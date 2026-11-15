# DFBrowser v0.1.4 — URL rules preview

## Changes

- **URL rules (网址规则)**: map host patterns to browsers. Matching links open directly in that browser without the chooser; everything else still shows the chooser.
  - `*.google.com` matches `google.com` and all subdomains; `docs.example.com` matches only that host; `*` anywhere matches any characters (e.g. `*.openai.*`, `git*.com`, a final `*` catch-all).
  - Rules are checked top to bottom; first match wins. Reorder with the arrows in the editor.
- Rule editor in the menu-bar → **网址规则…** and from settings → **编辑规则…**.
- Chooser checkbox **以后 … 都直接用所选浏览器打开** saves an exact-host rule.
- **导入… / 导出…** rules as hand-editable JSON; `browser` accepts a bundle ID or browser name. Import can merge or replace.
- Hold **Option** while clicking a link to bypass rules. If the rule's browser is missing or fails, the chooser appears instead.
- Text fields support Cmd+C / V / X / A / Z.
- Routed links no longer open the settings panel.

## Downloads

- `DFBrowser-0.1.4-macOS-arm64.zip`: Apple Silicon app containing `DFBrowser.app`.
- `DFBrowser-0.1.4-source.zip`: source, icon assets, MIT license and build/test scripts.
- `SHA256SUMS.txt`: SHA-256 checksums of both ZIPs.

Quit the old app, unzip this build and replace the app in Applications. Keep only one installed copy. Existing settings, including the default-browser association, are kept.

## Verified

- 101 automatic assertions passed.
- Signature / plist validation and installed executable match passed.
- Actual startup: accessory activation policy, menu bar present, no chooser, no foreground activation.
- Rule-matched link opened directly in the configured browser on the installed app.

## Known limitations

Rules match the host only: paths, ports and schemes are not distinguished; non-ASCII (IDN) host patterns are not supported. Login-startup remains experimental (see v0.1.3).

This is a prerelease: arm64 only, minimum deployment target macOS 13, tested on macOS 15. The app is ad-hoc signed and not Developer ID notarized.

0.1.4 新增“网址规则”：按域名自动分流到指定浏览器，支持通配符、选择浮窗中“记住此网站”、JSON 导入导出、按住 Option 临时跳过规则；输入框支持复制粘贴快捷键。
