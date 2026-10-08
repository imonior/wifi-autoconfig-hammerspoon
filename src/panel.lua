-- ~/.hammerspoon/wifi_autoconfig/panel.lua
--
-- The status menu is drawn as a borderless WKWebView panel instead of an
-- NSMenu.  Reasons, all verified against Hammerspoon's own sources:
--   * hs.menubar exposes nothing to paint the menu surface (libmenubar.m has no
--     background/appearance handling at all), so the surface is always the
--     macOS material -- a light grey sheet in light appearance, which is what
--     washed out the amber and the green;
--   * a read-only row can only be stopped from highlighting on hover by
--     "disabled", and macOS redraws disabled titles in grey, throwing the
--     colours away (an informational row has no way to be both inert and
--     correctly coloured in an NSMenu);
--   * with our own surface we can pin a single palette for light and dark.
-- Owning the surface also means owning the dismissal logic -- see the click
-- tap below.

local webview = require("hs.webview")
local usercontent = require("hs.webview.usercontent")
local drawing = require("hs.drawing")
local eventtap = require("hs.eventtap")
local screen = require("hs.screen")
local mouse = require("hs.mouse")
local json = require("hs.json")
local timer = require("hs.timer")
local utils = require("wifi_autoconfig.utils")

local M = {}

-- Geometry. The row heights are mirrored exactly by the CSS below so the
-- window can be sized without a round-trip to the renderer.
local ROW_H = 20
local ACTION_H = 22
local SEP_H = 13
local PAD_V = 7
local BORDER = 2

-- Width is only a starting frame: the CSS makes the panel hug its content and
-- the load handler reports the real width back, so this just has to be a sane
-- first guess (slightly wider than the longest row, e.g. the VPN header).
local WIDTH_DEFAULT = 320
local WIDTH_MIN = 260
local WIDTH_MAX = 420
local GAP = 4 -- gap between the menu bar item and the panel
local EDGE = 8 -- keep the panel this far from the screen edges

-- One palette for both appearances: the panel paints its own dark surface, so
-- the colours no longer have to survive a light-grey macOS backdrop. The
-- green is the pure traffic-light green; on this surface it is legible.
local THEME = {
    bg = "#1F1F1F",
    border = "#3A3A3A",
    head = "#FFD34E", -- warning amber for the section titles
    label = "#5AA9FF", -- the 🟦 blue, lifted for a dark surface
    value = "#FFFFFF",
    muted = "#C9C9C9",
    ok = "#00FF00",
    bad = "#FF0000"
}

local panel, controller, tap
local rows, actions = {}, {}
local visible = false
local menuBarItemRef = nil
local currentWidth = WIDTH_DEFAULT

local function esc(value)
    return utils.escapeHTML(tostring(value == nil and "" or value))
end

local function css(scrollable)
    local rules = {
        "* { box-sizing: border-box; }",
        "html, body { margin:0; padding:0; background:transparent; overflow:hidden; }",
        "body { font:13px/" .. ROW_H .. "px -apple-system, 'SF Pro Text', 'PingFang SC', 'Helvetica Neue', sans-serif;",
        "  color:" .. THEME.value .. "; -webkit-user-select:none; cursor:default; }",
        "#panel { display:block; width:max-content; min-width:260px; max-width:" .. WIDTH_MAX .. "px;",
        "  background:" .. THEME.bg .. "; border:1px solid " .. THEME.border .. ";",
        "  border-radius:10px; padding:" .. PAD_V .. "px 0; overflow:hidden; }",
        ".row { padding:0 14px; line-height:" .. ROW_H .. "px; white-space:nowrap; overflow:hidden; }",
        ".head { color:" .. THEME.head .. "; font-weight:600; }",
        -- Informational rows never react to the pointer: no hover, no cursor
        -- change, no highlight. This is the whole point of the custom panel.
        ".info { pointer-events:none; }",
        ".i1 { padding-left:26px; }",
        ".i2 { padding-left:40px; }",
        ".lb { color:" .. THEME.label .. "; }",
        ".label { color:" .. THEME.label .. "; }",
        ".vl { color:" .. THEME.value .. "; }",
        ".muted { color:" .. THEME.muted .. "; font-size:12px; }",
        ".dot { display:inline-block; width:8px; height:8px; border-radius:50%; margin-right:6px; }",
        ".ok { color:" .. THEME.ok .. "; }",
        ".ok .dot { background:" .. THEME.ok .. "; }",
        ".bad { color:" .. THEME.bad .. "; }",
        ".bad .dot { background:" .. THEME.bad .. "; }",
        ".sep { height:1px; background:" .. THEME.border .. "; margin:6px 12px; }",
        -- Only the action rows are interactive, so only they get a hover state.
        -- :hover is a fallback; the real highlight is the .hov class toggled
        -- from Lua (see the note above PANEL_JS for why :hover alone is dead).
        ".action { cursor:pointer; padding:0 14px; line-height:" .. ACTION_H .. "px; }",
        ".action:hover, .action.hov { background:rgba(255,255,255,0.16); }",
        ".action:active { background:rgba(255,255,255,0.24); }",
    }
    -- A menu taller than the screen gets a card that fills the window and scrolls the
    -- rest, which has to come last so it overrides the plain overflow:hidden above.
    -- The scroller itself stays invisible: the window width is measured from this
    -- element's own box and a layout scrollbar would take those pixels off the row text.
    -- The clipped row at the bottom edge is itself the cue that there is more to see.
    if scrollable then
        rules[#rules + 1] = "#panel { max-height:100vh; overflow-y:auto; }"
        rules[#rules + 1] = "#panel::-webkit-scrollbar { width:0; height:0; }"
    end
    return table.concat(rules, "\n")
end

local function bodyFor(rows)
    local out = {}
    for _, r in ipairs(rows) do
        local pad = r.indent and (" i" .. r.indent) or ""
        if r.kind == "sep" then
            out[#out + 1] = '<div class="sep"></div>'
        elseif r.kind == "head" then
            out[#out + 1] = '<div class="row head">' .. esc(r.text) .. '</div>'
        elseif r.kind == "kv" then
            out[#out + 1] = '<div class="row info' .. pad .. '"><span class="lb">' .. esc(r.label) ..
                '</span> <span class="vl">' .. esc(r.value) .. '</span></div>'
        elseif r.kind == "label" then
            out[#out + 1] = '<div class="row info label' .. pad .. '">' .. esc(r.text) .. '</div>'
        elseif r.kind == "muted" then
            out[#out + 1] = '<div class="row info muted' .. pad .. '">' .. esc(r.text) .. '</div>'
        elseif r.kind == "status" then
            local cls = (r.state == "ok") and "ok" or "bad"
            out[#out + 1] = '<div class="row info ' .. cls .. pad .. '"><span class="dot"></span>' .. esc(r.text) .. '</div>'
        elseif r.kind == "action" then
            out[#out + 1] = '<div class="row action" data-id="' .. esc(r.id) .. '">' .. esc(r.text) .. '</div>'
        end
    end
    return table.concat(out, "\n")
end

-- Why hover is driven from Lua instead of CSS :hover: libwebview.m never sets
-- acceptsMouseMovedEvents, and a borderless NSWindow ships with it disabled --
-- so WebKit never sees mouse-moved events and :hover never fires, while
-- mouseDown still works.
--
-- Why the highlight is polled by a timer, never by a mouseMoved event tap: a
-- CGEventTap that listens to mouseMoved stalls the whole system's pointer on
-- some setups (it shipped once and froze the cursor machine-wide). Instead the
-- 0.05s timer reads the cursor position with the pure getter
-- hs.mouse.getAbsolutePosition() -- no event tap, so it cannot freeze anything
-- -- and dispatches JavaScript only when the pointer actually moved. The renderer
-- decides which row that is, since a scrolled card moved the answer out of Lua's reach.
local PANEL_JS = [[
(function () {
  var bridge = (window.webkit && window.webkit.messageHandlers) ?
      window.webkit.messageHandlers.wifiPanel : null;
  function post(payload) {
    if (!bridge) { return; }
    try { bridge.postMessage(JSON.stringify(payload)); } catch (e) {}
  }
  document.addEventListener('click', function (ev) {
    var el = ev.target && ev.target.closest ? ev.target.closest('.action') : null;
    if (el) { post({ type: 'action', id: el.getAttribute('data-id') }); }
  });
  document.addEventListener('contextmenu', function (ev) { ev.preventDefault(); });
  var hovered = null;
  var lastX = -1, lastY = -1;
  function resolveHover() {
    var el = (lastX < 0 || lastY < 0) ? null : document.elementFromPoint(lastX, lastY);
    var row = el && el.closest ? el.closest('.action') : null;
    if (row === hovered) { return; }
    if (hovered) { hovered.classList.remove('hov'); }
    if (row) { row.classList.add('hov'); }
    hovered = row || null;
  }
  // The pointer arrives in window coordinates rather than as a row number, because once
  // the card scrolls the row under it is no longer something Lua can work out from the
  // model: elementFromPoint already accounts for the scroll offset, for the width the CSS
  // actually chose, and for the informational rows that ignore the pointer.
  window.__wifiPanelHoverAt = function (x, y) {
    lastX = x; lastY = y;
    resolveHover();
  };
  window.__wifiPanelHoverReset = function () {
    lastX = -1; lastY = -1;
    if (hovered) { hovered.classList.remove('hov'); hovered = null; }
  };
  var card = document.getElementById('panel');
  if (card) { card.addEventListener('scroll', resolveHover); }
  window.addEventListener('load', function () {
    var p = document.getElementById('panel');
    if (p) { post({ type: 'size', w: Math.ceil(p.getBoundingClientRect().width) }); }
  });
})();
]]

-- Exported so the layout can be rendered and inspected outside Hammerspoon.
function M.renderHTML(rowList, scrollable)
    return table.concat({
        '<!DOCTYPE html><html><head><meta charset="utf-8"><style>',
        css(scrollable),
        '</style></head><body><div id="panel">',
        bodyFor(rowList),
        '</div><script>',
        PANEL_JS,
        '</script></body></html>'
    }, "\n")
end

local function measure(rowList)
    local h = PAD_V * 2 + BORDER
    for _, r in ipairs(rowList) do
        if r.kind == "sep" then
            h = h + SEP_H
        elseif r.kind == "action" then
            h = h + ACTION_H
        else
            h = h + ROW_H
        end
    end
    return math.floor(h)
end

local function tryCall(object, method, ...)
    if not object then return nil end
    local fn = object[method]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, object, ...)
    if not ok then return nil end
    return result
end

-- The screen the given point (e.g. the menu bar icon) lives on -- not the
-- main screen: with more than one display the icon can sit on a screen whose
-- origin is negative, and clamping against the wrong frame drags the panel
-- all the way to the wrong screen's edge. Returns the screen itself as well as
-- its frame, because the usable bottom needs a second query on that screen.
local function screenContaining(x, y, fallbackFrame)
    for _, s in ipairs(screen.allScreens()) do
        local f = s:fullFrame()
        if x >= f.x and x <= f.x + f.w and y >= f.y and y <= f.y + f.h then
            return s, f
        end
    end
    return nil, fallbackFrame
end

-- The lowest row of pixels the panel may occupy. fullFrame reaches under the Dock, so
-- a menu that ends there would have its action rows behind it; visibleFrame stops short
-- of the Dock and of the menu bar, which is the area a window can really be read in.
local function usableBottom(s, frame)
    local vf = s and tryCall(s, "visibleFrame")
    if vf and vf.y + vf.h <= frame.y + frame.h then return vf.y + vf.h end
    return frame.y + frame.h
end

-- The height a panel can occupy hanging under the menu bar item. Returning nil means the
-- geometry is unknown (no icon frame yet), and the caller then takes the content height
-- as it is rather than guessing a limit.
local function availableHeightFor(item)
    local f = item and tryCall(item, "frame")
    if not f then return nil end
    local s, sf = screenContaining(f.x + f.w / 2, f.y + f.h / 2, screen.mainScreen():fullFrame())
    return math.floor(usableBottom(s, sf) - EDGE - (f.y + f.h + GAP))
end

local function positionFor(item, height, width)
    local f = item and tryCall(item, "frame")

    if not f then
        -- No menu bar frame (icon not in the bar yet): fall back to the pointer.
        local p = mouse.getAbsolutePosition()
        return { x = math.floor(p.x - width), y = math.floor(p.y + 12), w = width, h = height }
    end

    local s, sf = screenContaining(f.x + f.w / 2, f.y + f.h / 2, screen.mainScreen():fullFrame())

    -- Right-align the panel under the icon, like a real NSMenu does.
    local x = f.x + f.w - width
    local y = f.y + f.h + GAP

    if x + width > sf.x + sf.w - EDGE then x = sf.x + sf.w - EDGE - width end
    if x < sf.x + EDGE then x = sf.x + EDGE end
    -- The bottom is kept inside the usable area, but the top is never pushed above the
    -- icon it hangs from: moving the whole panel up was how an over-tall menu used to
    -- escape off the top of the screen and lose its first rows. A panel that still does
    -- not fit is capped by the caller and scrolls.
    local bottom = usableBottom(s, sf) - EDGE
    if y + height > bottom then y = math.max(f.y + f.h + GAP, bottom - height) end
    if y < sf.y + EDGE then y = sf.y + EDGE end

    return { x = math.floor(x), y = math.floor(y), w = width, h = height }
end

local function pointIn(p, r)
    if not p or not r then return false end
    return p.x >= r.x and p.x <= (r.x + r.w) and p.y >= r.y and p.y <= (r.y + r.h)
end

local function stopTap()
    if tap then pcall(function() tap:stop() end) end
end

-- Dismiss on any click outside the panel. AppKit focus events are not enough
-- on their own (a borderless panel is not guaranteed to become the key window),
-- so the click tap is the primary mechanism and the focus change is a backup.
-- The tap listens ONLY to mouse-down events (never mouseMoved): a mouseMoved
-- tap froze the whole system pointer on this machine, so hover tracking is
-- done by polling hs.mouse.getAbsolutePosition() on hoverTimer instead.
local lastPointer = nil
local hoverTimer = nil

local function stopHoverTimer()
    if hoverTimer then
        pcall(function() hoverTimer:stop() end)
        hoverTimer = nil
    end
    lastPointer = nil
end

-- Which row carries the highlight is now the renderer's decision, not arithmetic on the
-- model: a scrolled card no longer has its first row at the top of the window, so the
-- only thing Lua can offer is where the pointer sits inside it. The JS resolves that to a
-- row, and resolves it again on every scroll with the same last position.
local function ensureHoverTimer()
    if hoverTimer then return end
    hoverTimer = timer.doEvery(0.05, function()
        if not visible or not panel then return end
        -- Poll the cursor position directly instead of installing a system-wide
        -- mouseMoved event tap: a CGEventTap listening to mouseMoved stalls the
        -- pointer machine-wide on some setups (it shipped once and froze the
        -- cursor). Reading the position is a pure getter and never taps events.
        local p = mouse.getAbsolutePosition()
        if not p then return end
        if lastPointer and lastPointer.x == p.x and lastPointer.y == p.y then return end
        lastPointer = { x = p.x, y = p.y }

        local f = tryCall(panel, "frame")
        if not f or not pointIn(p, f) then
            tryCall(panel, "evaluateJavaScript", "__wifiPanelHoverReset && __wifiPanelHoverReset()")
            return
        end
        tryCall(panel, "evaluateJavaScript",
            string.format("__wifiPanelHoverAt(%d, %d)", math.floor(p.x - f.x), math.floor(p.y - f.y)))
    end)
end

local function startTap()
    if not tap then
        local ok, created = pcall(eventtap.new,
            { eventtap.event.types.leftMouseDown, eventtap.event.types.rightMouseDown },
            function(event)
                if not visible then return false end

                -- A click inside the panel is handled by the webview's own click
                -- listener; a click on the menu bar item toggles the panel there.
                -- Only an outside click dismisses the panel here. No mouseMoved
                -- type -- a mouseMoved tap froze the system pointer before.
                local p = event:location()
                if panel and pointIn(p, tryCall(panel, "frame")) then return false end
                if menuBarItemRef and pointIn(p, tryCall(menuBarItemRef, "frame")) then return false end
                M.hide()
                return false
            end)
        if ok then tap = created end
    end
    if tap then pcall(function() tap:start() end) end
end

local function ensurePanel()
    if panel then return panel end

    local ok, err = pcall(function()
        controller = usercontent.new("wifiPanel")
        controller:setCallback(function(message)
            local payload = message and message.body
            local data = payload
            if type(payload) == "string" then
                local decoded, parsed = pcall(json.decode, payload)
                if decoded and type(parsed) == "table" then data = parsed end
            end
            if type(data) ~= "table" then return end

            if data.type == "action" then
                local id = tostring(data.id or "")
                local fn = actions[id]
                M.hide()
                if fn then
                    utils.wait(0.05, fn)
                end
            elseif data.type == "size" then
                local w = tonumber(data.w)
                if w then
                    w = math.max(WIDTH_MIN, math.min(WIDTH_MAX, w + 4))
                    if panel and math.abs(w - currentWidth) > 2 then
                        local f = tryCall(panel, "frame")
                        currentWidth = w
                        if f then
                            tryCall(panel, "frame", { x = f.x + f.w - w, y = f.y, w = w, h = f.h })
                        end
                    end
                end
            end
        end)

        panel = webview.new({ x = 0, y = 0, w = WIDTH_DEFAULT, h = 200 }, {
            javaScriptEnabled = true,
            developerExtrasEnabled = false,
            suppressesIncrementalRendering = true
        }, controller)

        tryCall(panel, "windowStyle", { "borderless" })
        -- Without this the window paints its default white background behind
        -- the rounded corners of #panel -- it read as a white border.
        tryCall(panel, "transparent", true)
        tryCall(panel, "behaviorAsLabels", { "canJoinAllSpaces", "moveToActiveSpace" })
        tryCall(panel, "level", drawing.windowLevels.popUpMenu)
        tryCall(panel, "deleteOnClose", false)
        tryCall(panel, "allowTextEntry", false)
        tryCall(panel, "shadow", true)
        tryCall(panel, "windowCallback", function(action, _, state)
            if action == "focusChange" and state == false and visible then
                M.hide()
            end
        end)
    end)

    if not ok or not panel then
        utils.log("panel: could not create the webview: " .. tostring(err))
        panel = nil
        return nil
    end

    return panel
end

function M.hide()
    visible = false
    stopHoverTimer()
    if panel then pcall(function() panel:hide() end) end
    stopTap()
end

function M.show(model)
    rows = (model and model.rows) or {}
    actions = (model and model.actions) or {}

    local wv = ensurePanel()
    if not wv then return end

    -- The window is sized from the row model, so content taller than the screen used to
    -- simply hang off the bottom out of reach. Now the window takes what the screen
    -- offers and the card inside it scrolls; the height is capped rather than the
    -- content, because a menu cannot drop rows and stay readable.
    local contentHeight = measure(rows)
    local available = availableHeightFor(menuBarItemRef)
    local scrollable = available ~= nil and contentHeight > available
    local height = scrollable and available or contentHeight

    currentWidth = WIDTH_DEFAULT
    tryCall(wv, "frame", positionFor(menuBarItemRef, height, currentWidth))
    wv:html(M.renderHTML(rows, scrollable))
    wv:show()

    visible = true
    startTap()
    ensureHoverTimer()
end

-- Wires the menu bar item to the panel: opening rebuilds the model so the
-- panel always shows live data, exactly like the dynamic NSMenu did.
-- A second click on the icon within DOUBLE_CLICK_NS closes the panel and opens
-- the settings editor instead, so the icon has both a quick look (one click)
-- and a quick edit (two).
-- Returns false when the panel could not be created, so the caller can fall
-- back to the native menu instead of leaving the item dead.
local DOUBLE_CLICK_NS = 400000000 -- 0.4s

function M.attach(item, builder, onDoubleClick)
    if not ensurePanel() then
        utils.log("panel: webview unavailable, keeping the native menu")
        return false
    end

    menuBarItemRef = item

    -- hs.menubar's click callback reports only the modifier keys (see its docs for
    -- 1.1.1), so a double-click has to be recognised from the gap between the two
    -- callbacks rather than from an event click count.
    local lastClickAt = 0
    item:setClickCallback(function()
        local now = timer.absoluteTime()
        local isDoubleClick = (now - lastClickAt) < DOUBLE_CLICK_NS
        lastClickAt = now

        if isDoubleClick then
            -- Reset so a third click in a row is not read as another double-click.
            lastClickAt = 0
            if visible then M.hide() end
            if onDoubleClick then onDoubleClick() end
            return
        end

        if visible then
            M.hide()
            return
        end

        local ok, model = pcall(builder)
        if not ok or type(model) ~= "table" then
            utils.log("panel: could not build the menu model: " .. tostring(model))
            return
        end

        M.show(model)
    end)

    return true
end

function M.destroy()
    M.hide()
    if panel then
        pcall(function() panel:delete() end)
        panel = nil
    end
    controller = nil
end

return M
