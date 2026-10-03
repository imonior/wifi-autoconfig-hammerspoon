#!/bin/bash
#
# build-release.sh - Package an offline install archive + generate the release page
#
# Produces, under dist/:
#   wifi-autoconfig-hammerspoon-vX.Y.Z.zip   self-contained offline install bundle
# and at the project root:
#   release.html                             standalone release page (dark theme, bilingual EN/简体中文, English default)
#   RELEASE.md                               GitHub release notes (bilingual, English first)
#
# The bundle contains every file needed to install WITHOUT network access:
#   src/  scripts/  config.example.json  LICENSE  README.md  README.zh-CN.md
#   CHANGELOG.md  CHANGELOG.zh-CN.md
#
# Requires only `zip` (and `sed`); no network.
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# ---- Read version from the single source of truth (install.sh) -------------
VERSION="$(grep -E '^MODULE_VERSION=' scripts/install.sh | head -1 | sed 's/.*="//; s/"$//')"
if [ -z "$VERSION" ]; then
    echo "ERROR: could not read MODULE_VERSION from scripts/install.sh" >&2
    exit 1
fi

PKG_NAME="wifi-autoconfig-hammerspoon"
PKG_DIR="$PKG_NAME"
DIST_DIR="$PROJECT_ROOT/dist"
STAGE="$DIST_DIR/staging/$PKG_DIR"
ZIP="$DIST_DIR/${PKG_NAME}-v${VERSION}.zip"

echo "Building release package v${VERSION}..."

# ---- Stage files -----------------------------------------------------------
rm -rf "$DIST_DIR"
mkdir -p "$STAGE"

cp -R src        "$STAGE/src"
cp -R scripts    "$STAGE/scripts"
cp config.example.json "$STAGE/"
cp LICENSE       "$STAGE/"
cp README.md README.zh-CN.md CHANGELOG.md CHANGELOG.zh-CN.md "$STAGE/"

chmod +x "$STAGE/scripts/"*.sh

# ---- Sanity: the bundle must be installable offline ------------------------
if [ ! -f "$STAGE/src/init.lua" ] || [ ! -f "$STAGE/scripts/install.sh" ]; then
    echo "ERROR: staged bundle is missing required files" >&2
    exit 1
fi

# ---- Zip -------------------------------------------------------------------
( cd "$DIST_DIR/staging" && zip -rq "$ZIP" "$PKG_DIR" )
echo "  -> $ZIP ($(du -h "$ZIP" | cut -f1))"

# ---- Generate release.html (standalone, dark theme, bilingual EN/简体中文) --
RELEASE_HTML="$PROJECT_ROOT/release.html"
cat > "$RELEASE_HTML" <<'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Wi-Fi AutoConfig for Hammerspoon — Release @@VERSION@@</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
    background: #0d1117; color: #e6edf3; line-height: 1.6;
  }
  .wrap { max-width: 880px; margin: 0 auto; padding: 48px 24px 72px; }
  header { border-bottom: 1px solid #21262d; padding-bottom: 24px; margin-bottom: 32px;
           display: flex; flex-wrap: wrap; align-items: flex-end; justify-content: space-between; gap: 16px; }
  h1 { font-size: 28px; margin: 0 0 8px; }
  h2 { font-size: 20px; margin: 40px 0 12px; border-left: 3px solid #58a6ff; padding-left: 10px; }
  .badge {
    display: inline-block; background: #1f6feb; color: #fff; font-weight: 600;
    border-radius: 999px; padding: 3px 12px; font-size: 13px; margin-bottom: 12px;
  }
  .sub { color: #8b949e; font-size: 14px; }
  .download {
    display: inline-block; margin: 20px 0; padding: 14px 28px;
    background: #238636; color: #fff; text-decoration: none; font-weight: 600;
    border-radius: 8px; font-size: 16px;
  }
  .download:hover { background: #2ea043; }
  pre {
    background: #161b22; border: 1px solid #21262d; border-radius: 8px;
    padding: 14px 16px; overflow-x: auto; font-size: 13px; color: #c9d1d9;
  }
  code { font-family: "SF Mono", Menlo, Consolas, monospace; }
  table { width: 100%; border-collapse: collapse; margin: 12px 0; font-size: 14px; }
  th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #21262d; }
  th { color: #8b949e; font-weight: 600; }
  .note { background: #161b22; border: 1px solid #21262d; border-radius: 8px; padding: 12px 16px; font-size: 14px; color: #8b949e; }
  a { color: #58a6ff; }
  footer { margin-top: 48px; padding-top: 20px; border-top: 1px solid #21262d; color: #8b949e; font-size: 13px; }
  .langswitch { display: flex; gap: 8px; }
  .langswitch button {
    background: #21262d; color: #e6edf3; border: 1px solid #30363d; border-radius: 6px;
    padding: 6px 12px; font-size: 13px; cursor: pointer;
  }
  .langswitch button.active { background: #1f6feb; border-color: #1f6feb; color: #fff; }
  /* Default (no .zh on <html>): show English, hide Chinese */
  html:not(.zh) .zh { display: none !important; }
  /* When .zh is present: hide English, show Chinese using its natural display */
  html.zh .en { display: none !important; }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div>
      <div class="badge">v@@VERSION@@</div>
      <h1>Wi-Fi AutoConfig for Hammerspoon</h1>
      <div class="sub en">A Hammerspoon-based macOS Wi-Fi network auto-switcher · Offline install bundle &amp; release page</div>
      <div class="sub zh">基于 Hammerspoon 的 macOS Wi-Fi 网络自动切换工具 · 离线安装包与发布页</div>
    </div>
    <div class="langswitch">
      <button id="btn-en" class="active" onclick="setLang('en')">English</button>
      <button id="btn-zh" onclick="setLang('zh')">简体中文</button>
    </div>
  </header>

  <div class="note">
    <span class="en">This archive bundles every script and source file — installation requires <b>no access to GitHub</b>. If a previous version is already installed (directories <code>~/.hammerspoon/wifi_ip_switcher</code> or <code>wifi_ip_controller</code>), use the legacy-upgrade script in the upgrade section instead.</span>
    <span class="zh">该归档已包含全部脚本与源文件，<b>无需访问 GitHub 即可安装</b>。若已安装旧版本（目录为 <code>~/.hammerspoon/wifi_ip_switcher</code> 或 <code>wifi_ip_controller</code>），请改用「旧版本升级」章节中的脚本。</span>
  </div>


  <h2 class="en">What's in the bundle</h2>
  <h2 class="zh">发布包内容</h2>
  <table>
    <tr>
      <th class="en">Path</th><th class="zh">路径</th>
      <th class="en">Description</th><th class="zh">说明</th>
    </tr>
    <tr>
      <td><code>src/</code></td>
      <td class="en">All Lua modules (init / core / config / utils / i18n / menu_builder / network_apply / panel / ui)</td>
      <td class="zh">全部 Lua 模块（init / core / config / utils / i18n / menu_builder / network_apply / panel / ui）</td>
    </tr>
    <tr>
      <td><code>scripts/</code></td>
      <td class="en">install.sh · uninstall.sh · legacy-install.sh · legacy-uninstall.sh</td>
      <td class="zh">install.sh · uninstall.sh · legacy-install.sh · legacy-uninstall.sh</td>
    </tr>
    <tr>
      <td><code>config.example.json</code></td>
      <td class="en">Configuration example (copied to config.json on install)</td>
      <td class="zh">配置示例（安装时复制为 config.json）</td>
    </tr>
    <tr>
      <td><code>LICENSE</code></td>
      <td class="en">License</td>
      <td class="zh">许可证</td>
    </tr>
    <tr>
      <td><code>README.md</code> / <code>README.zh-CN.md</code></td>
      <td class="en">Documentation (English / 简体中文)</td>
      <td class="zh">使用文档（英文 / 简体中文）</td>
    </tr>
    <tr>
      <td><code>CHANGELOG.md</code> / <code>CHANGELOG.zh-CN.md</code></td>
      <td class="en">Changelog (English / 简体中文)</td>
      <td class="zh">更新日志（英文 / 简体中文）</td>
    </tr>
  </table>

  <h2 class="en">Changes &amp; notes</h2>
  <h2 class="zh">变更与说明</h2>
  <p class="sub en">Full changelog: <a href="CHANGELOG.md">CHANGELOG.md</a> (English) and <a href="CHANGELOG.zh-CN.md">CHANGELOG.zh-CN.md</a> (简体中文).</p>
  <p class="sub zh">完整更新日志见 <a href="CHANGELOG.md">CHANGELOG.md</a>（英文）与 <a href="CHANGELOG.zh-CN.md">CHANGELOG.zh-CN.md</a>（简体中文）。</p>

  <h2 class="en">Online install (one command)</h2>
  <h2 class="zh">在线安装（一行命令）</h2>
  <pre><code>curl -fsSL https://raw.githubusercontent.com/imonior/wifi-autoconfig-hammerspoon/main/scripts/install.sh | bash</code></pre>

  <h2 class="en">Upgrade from a previous version (clean up old version, then install v@@VERSION@@)</h2>
  <h2 class="zh">旧版本升级（清理旧版后安装 v@@VERSION@@）</h2>
  <pre><code>bash scripts/legacy-install.sh        # interactive
bash scripts/legacy-install.sh --force  # skip confirmation</code></pre>

  <h2 class="en">Uninstall</h2>
  <h2 class="zh">卸载</h2>
  <pre><code>bash scripts/uninstall.sh             # interactive (backs up config.json first)
bash scripts/uninstall.sh --force     # skip confirmation</code></pre>
  <h2 class="en">Offline install steps</h2>
  <h2 class="zh">离线安装步骤</h2>
  <pre><code>unzip wifi-autoconfig-hammerspoon-v@@VERSION@@.zip
cd wifi-autoconfig-hammerspoon
bash scripts/install.sh</code></pre>
  <p class="sub en">The installer auto-detects the local files inside the archive and installs offline; Hammerspoon itself must be installed beforehand (the first run will try to download it if missing).</p>
  <p class="sub zh">安装器会自动识别压缩包内的本地文件并离线安装；Hammerspoon 本身需提前安装（首次安装若未装会尝试联网下载）。</p>

  <a class="download en" href="dist/wifi-autoconfig-hammerspoon-v@@VERSION@@.zip">⬇ Download offline installer (.zip)</a>
  <a class="download zh" href="dist/wifi-autoconfig-hammerspoon-v@@VERSION@@.zip">⬇ 下载离线安装包 (.zip)</a>

  <footer>
    <span class="en">Wi-Fi AutoConfig for Hammerspoon · v@@VERSION@@ · Offline installer generated by <code>scripts/build-release.sh</code></span>
    <span class="zh">Wi-Fi AutoConfig for Hammerspoon · v@@VERSION@@ · 离线安装包由 <code>scripts/build-release.sh</code> 生成</span>
  </footer>
</div>
<script>
  function setLang(l) {
    var zh = (l === 'zh');
    document.documentElement.classList.toggle('zh', zh);
    document.getElementById('btn-en').classList.toggle('active', !zh);
    document.getElementById('btn-zh').classList.toggle('active', zh);
    try { localStorage.setItem('rel-lang', l); } catch (e) {}
  }
  (function () {
    var s = null;
    try { s = localStorage.getItem('rel-lang'); } catch (e) {}
    if (s === 'zh') setLang('zh');
  })();
</script>
</body>
</html>
HTML_EOF

sed "s/@@VERSION@@/$VERSION/g" "$RELEASE_HTML" > "$RELEASE_HTML.tmp" && mv "$RELEASE_HTML.tmp" "$RELEASE_HTML"
echo "  -> $RELEASE_HTML"

# ---- Generate RELEASE.md (GitHub release notes, bilingual, English first) ---
RELEASE_MD="$PROJECT_ROOT/RELEASE.md"
cat > "$RELEASE_MD" <<MD_EOF
# Wi-Fi AutoConfig for Hammerspoon v$VERSION

A Hammerspoon-based macOS Wi-Fi network auto-switching tool. This release ships a
**self-contained offline install bundle** — download the zip, extract, and run
\`bash scripts/install.sh\` with no network access to GitHub required.

基于 Hammerspoon 的 macOS Wi-Fi 网络自动切换工具。本版本提供**自包含离线安装包**：
下载 zip、解压后运行 \`bash scripts/install.sh\` 即可，无需访问 GitHub。

## What's in the bundle / 发布包内容

- \`src/\` — all Lua modules (init / core / config / utils / i18n / menu_builder / network_apply / panel / ui)
- \`scripts/\` — install.sh · uninstall.sh · legacy-install.sh · legacy-uninstall.sh
- \`config.example.json\`, \`LICENSE\`, \`README.md\` / \`README.zh-CN.md\`, \`CHANGELOG.md\` / \`CHANGELOG.zh-CN.md\`

## Offline install / 离线安装

\`\`\`bash
unzip wifi-autoconfig-hammerspoon-v$VERSION.zip
cd wifi-autoconfig-hammerspoon
bash scripts/install.sh
\`\`\`

## Upgrading from a previous (pre-3.0) version / 旧版本升级

\`\`\`bash
bash scripts/legacy-install.sh --force
\`\`\`

See CHANGELOG.md (English) / CHANGELOG.zh-CN.md (简体中文) for the full history.
MD_EOF
echo "  -> $RELEASE_MD"

echo ""
echo "Release v$VERSION built successfully."
echo "  Archive : $ZIP"
echo "  Page    : $RELEASE_HTML"
echo "  Notes   : $RELEASE_MD"
