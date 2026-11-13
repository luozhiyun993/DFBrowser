# DFBrowser

A lightweight native macOS browser picker. When another app opens a web link through the system, DFBrowser lets you choose which browser should open it.

一个原生 macOS 浏览器选择器：其他软件通过系统打开网页链接时，先显示选择浮窗，点击浏览器后再打开。

## Download / 下载

Download the Apple Silicon app ZIP from the [v0.1.2 preview release](https://github.com/luozhiyun993/DFBrowser/releases/tag/v0.1.2).

从 [Releases](https://github.com/luozhiyun993/DFBrowser/releases) 下载 `DFBrowser-0.1.2-macOS-arm64.zip`。它包含带蓝色分流图标的 `DFBrowser.app`。

**Requirements:** Apple Silicon Mac; minimum deployment target macOS 13. Tested on macOS 15. Intel and older macOS versions have not been validated.

**This is an early preview, not a notarized production release.** The app uses ad-hoc signing, without Developer ID notarization. Complete end-to-end manual verification remains pending; see [TESTING.md](TESTING.md).

## Features / 功能

- SwiftUI + AppKit native app with no third-party runtime dependencies.
- Discover installed browsers, show their icons and names, and refresh the list.
- Choose a browser for each request. No remembered automatic destination.
- Cancel with Esc; keyboard shortcuts 1–9; queued requests do not overwrite the current request.
- No URL history storage, page fetching, analytics, or URL uploads.
- Explicit registration as a browser candidate; default browser selection is performed by the user in System Settings.
- Status checks both HTTP/HTTPS preferences and actual URL resolution to avoid reporting partial setup as success.

The app does **not** promise to intercept navigation inside browsers, in-app web views, or proprietary deep links. Browser profiles and incognito mode are not supported in this version. Tab/window behavior is controlled by the destination browser.

## Installation / 安装

1. Quit any older DFBrowser instance from its menu bar icon.
2. Unzip the release and move `DFBrowser.app` to **Applications**. Keep just one installed app to avoid duplicate browser entries.
3. Launch DFBrowser. Use **注册到系统浏览器列表** to register it; this does not change the default browser or reset the system database.
4. Close and reopen **System Settings → Desktop & Dock → Default web browser**, then choose **DFBrowser**. The in-app **在系统设置中选择…** button can open that pane after confirmation.
5. Open a normal HTTP/HTTPS link from another app. Select a browser in the floating chooser.

**预览选择浮窗** uses example.com and does not change your default browser. Only selecting a browser opens the preview link.

If macOS blocks opening this unsigned-distribution preview, use the system's explicit **Privacy & Security → Open Anyway** flow. Do not disable Gatekeeper globally.

To undo setup, change the default browser back to Safari, Chrome, or another browser **before** removing DFBrowser.

## Build / 构建

Requires Xcode or Apple Command Line Tools, with Swift 6.1.2 or newer (the project uses Swift 5 language mode).

```sh
bash build.sh
bash test.sh
```

Outputs: `dist/DFBrowser-<version>.app` and a versioned ZIP for the current CPU architecture. Build scripts do not install the app or change your default browser. An Intel build must be built on an Intel Mac and is currently unverified.

```sh
# Read-only diagnostics from an installed app
/Applications/DFBrowser.app/Contents/MacOS/DFBrowser --list-browsers
/Applications/DFBrowser.app/Contents/MacOS/DFBrowser --diagnose

# Explicitly send a test URL without changing the default browser
open -a /Applications/DFBrowser.app "https://example.com"
```

### Avoid duplicate app entries

Development `.app` bundles may be indexed by macOS and appear alongside the installed app. Keep the installed `/Applications/DFBrowser.app`; archive development builds as ZIPs when no longer needed. If cleaning a duplicate bundle, unregister that **specific path** with Launch Services before moving it to Trash. Do not reset the global Launch Services database or remove system caches.

## Architecture

`Info.plist` declares HTTP/HTTPS handling. `NSApplicationDelegate.application(_:open:)` receives links, and `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)` names the destination application explicitly, avoiding a loop back to the system default.

Browser discovery combines Launch Services, known browser bundle identifiers, and Applications directories. It filters non-browser handlers, embedded helpers and testing caches, then deduplicates by bundle identifier.

The app has no persistent link history. Pending URLs live in memory until opened, cancelled or the app exits. Browser registration uses `LSRegisterURL` only for the current app. A deprecated, read-only `LSCopyDefaultHandlerForURLScheme` cross-check is intentionally retained for compatibility diagnostics.

## Version history

- **0.1.2**: new app icon and packaged local installation.
- **0.1.1**: explicit browser registration, improved setup state, user-driven system default selection.
- **0.1.0**: initial browser discovery, chooser and link routing preview.

The icon was AI-generated and converted to multi-resolution ICNS; it is a raster asset, not a vector logo or a registered trademark.

Domain terms: [GLOSSARY.md](GLOSSARY.md). Design decision: [ADR](docs/adr/0001-default-browser-router.md). Test scope and limitations: [TESTING.md](TESTING.md).

## License

[MIT](LICENSE). No warranty. Brand names of detected browsers remain the property of their respective owners.
