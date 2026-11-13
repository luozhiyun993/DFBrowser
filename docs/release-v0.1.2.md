# v0.1.2 — Native macOS browser picker preview

DFBrowser intercepts web links handled by the system default browser and lets you choose the destination browser in a floating window.

## Included

- Native SwiftUI / AppKit browser chooser.
- Installed-browser discovery with duplicate and helper filtering.
- Explicit selection for each request, keyboard shortcuts 1–9, cancellation and queued requests.
- Browser candidate registration and user-driven default browser selection in System Settings.
- Blue split-arrow app icon.

## Downloads

- `DFBrowser-0.1.2-macOS-arm64.zip`: Apple Silicon macOS app, containing `DFBrowser.app`.
- `DFBrowser-0.1.2-source.zip`: source code, MIT license, resources and build scripts.
- `SHA256SUMS.txt`: SHA-256 checksums of the two downloadable ZIPs.

Move the app to Applications, launch it, register the browser candidate and choose DFBrowser under System Settings → Desktop & Dock → Default web browser.

## Important limitations

- Early preview, ad-hoc signed and **not Developer ID notarized**.
- Minimum deployment target macOS 13; tested on macOS 15 / Apple Silicon. Intel and older macOS versions are unverified.
- 42 automated assertions pass; the full GUI routing sequence has not been conclusively verified end-to-end.
- Browser profiles, incognito mode, in-browser navigation and in-app web views are not covered.
- No stored URL history, page fetching or analytics.

请只保留一个已安装的 DFBrowser.app，避免开发副本在系统浏览器列表里重复出现。此版本是早期试用版，未公证；完整端到端体验仍需人工验收。
