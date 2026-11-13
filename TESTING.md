# Testing / 验收范围

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
