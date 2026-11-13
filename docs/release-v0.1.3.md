# DFBrowser v0.1.3 — Menu-bar-only preview

## Changes

- Run only in the menu bar, without a Dock or Cmd-Tab entry.
- Ordinary launch is silent: no settings panel or foreground activation.
- Incoming HTTP/HTTPS links still show the browser chooser.
- Add **登录时自动启动** in the menu and settings, using `SMAppService.mainApp`.
- Display pending system approval and errors instead of optimistically reporting success.

## Downloads

- `DFBrowser-0.1.3-macOS-arm64.zip`: Apple Silicon app containing `DFBrowser.app`.
- `DFBrowser-0.1.3-source.zip`: source, icon assets, MIT license and build/test scripts.
- `SHA256SUMS.txt`: SHA-256 checksums of both ZIPs.

Quit the old app, unzip this build and replace the app in Applications. Keep only one installed copy. Launch it and use the menu-bar icon → **查看浏览器与设置**.

## Verified

- 54 automatic assertions passed.
- Signature / plist validation and installed executable match passed.
- Actual startup: accessory activation policy, menu bar present, no chooser, no foreground activation.
- Installed process: no Dock appearance, no visible regular panel, not active in the foreground.

## Known limitations

**Login-startup is experimental and not verified working.** The tested, installed ad-hoc-signed app returned an unavailable ServiceManagement status. The switch does not automatically enable itself; actual registration, approval and next-login launch still need verification. Do not treat its presence as proof that startup works.

This is a prerelease: arm64 only, minimum deployment target macOS 13, tested on macOS 15. The app is ad-hoc signed and not Developer ID notarized. Complete GUI browser-routing end-to-end verification remains pending. Browser profiles, incognito, in-browser navigation and in-app web views are not covered.

0.1.3 已验证菜单栏运行、无 Dock、启动不弹窗；“登录时自动启动”开关已加入，但测试机器的系统状态为暂不可用，真实开启及下次登录启动尚未验证。发布为早期试用版，保留 0.1.2 版本供回退。
