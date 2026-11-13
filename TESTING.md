# Testing / 验收范围

## v0.1.3 regression

- 54 automated assertions pass, including native-login state modeling with an injected fake service, enable/disable idempotence, approval handling, failure reporting and silent-startup policy.
- No actual login registration is performed by tests. Installation is verified; real enabling/disabling through SMAppService and next-login launch remain pending validation.
- `--verify-background` exercises actual AppKit startup without a settings/chooser panel or foreground activation. AppKit's menu-bar internal windows are not treated as application panels.
- `--verify-background` actual AppKit test passed: `accessory=true, menuBar=true, chooser=false, active=false`. Only NSStatusBarWindow internal windows were visible; no application panel or foreground activation.
- Actual login service read-only status in the development bundle was unavailable; do not claim real enabling or subsequent-login launch is verified until tested from the installed, signed app.
- The binary has `LSUIElement=true` and retains accessory activation policy. Incoming web links still invoke the chooser.
- Installed application has been updated to v0.1.3 at `/Applications/DFBrowser.app` after user authorization, with a v0.1.2 ZIP backup retained. The old process quit gracefully, the new executable matches the build, and signature verification passed. The update used background launching and preserved the HTTP/HTTPS default-browser association.
- Installed running-process verification passed: accessory activation policy (no Dock), `active=false`, and zero onscreen regular panels. No foreground window was opened during the update.
- Login startup was not enabled. A read-only diagnostic from the installed app still reports the ServiceManagement state as unavailable; real enabling/disabling and next-login launch remain unverified.
- The v0.1.3 release is an early preview. Menu-bar startup is verified; login startup remains experimental and unavailable on the tested installation. Existing v0.1.2 release assets are retained.

## Automated verification for v0.1.2

On macOS 15, Apple Silicon, using Swift 6.1.2 in Swift 5 language mode:

- 42 assertions passed, 0 failures.
- URL validation and rejection of unsupported schemes.
- Display credentials redacted while original URLs are preserved for routing.
- Batch deduplication, request order and identity, cancellation and in-flight cancellation protection.
- Missing target application error recovery and self-routing rejection.
- Browser discovery deduplication and filtering of non-browser handlers, embedded helpers and automated testing caches.
- Default-browser status checks for preference/resolution disagreement, partially configured schemes, case-insensitive identifiers and setup errors.
- Invalid bundles rejected before registration.
- `Info.plist` validation and ad-hoc code signature verification passed.
- Installed and packaged application executable and ICNS resources matched.

Run the regression tests:

```sh
bash test.sh
```

Browser-discovery tests require at least one supported browser installed. The diagnostic probe is read-only and optional.

## Manual observations

The chooser was observed displaying the incoming URL, browser icons, names, refresh and cancel controls. HTTP/HTTPS candidate registration was verified with system APIs. A single installed app was confirmed as the selected HTTP/HTTPS handler after user configuration; duplicate development bundles were subsequently unregistered and moved to Trash.

## Not yet fully verified

The complete GUI sequence of choosing a browser and confirming the resulting browser tab was not conclusively observed. Do **not** interpret the automated tests or a visible chooser as full end-to-end verification.

Still requiring manual validation:

1. Browser selection opens the exact requested URL and dismisses the chooser.
2. Esc cancellation does not open a tab.
3. Multiple incoming requests are handled one at a time through the real GUI.
4. Setup and removal are reliable on other Macs.
5. macOS 13/14 and Intel Macs; minimum deployment version is not proof of testing.

## Suggested acceptance steps

1. Install one `DFBrowser.app` in Applications, register it and select it in System Settings.
2. Use the preview action, choose a browser, and verify example.com.
3. Preview again and press Esc; confirm no new page opened.
4. Send two requests explicitly:

```sh
open -a /Applications/DFBrowser.app "https://example.com/?request=1"
open -a /Applications/DFBrowser.app "https://example.com/?request=2"
```

5. Verify the first request is not overwritten, and choose or cancel each request.
6. Click ordinary web links from another app that honors system defaults.
7. Restore another default browser and verify direct opening before uninstalling DFBrowser.

## Distribution limitations

- Current binary release is arm64 only.
- Ad-hoc signed, not Developer ID notarized.
- No browser profile/ incognito selection.
- In-browser navigation, in-app web views and proprietary deep links are outside the supported interception scope.
- The compatibility diagnostic uses deprecated read-only Launch Services APIs, which may produce compiler warnings.
