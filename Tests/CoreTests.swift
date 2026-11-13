import AppKit
import Foundation

var failures: [String] = []
var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    assertions += 1
    if !condition() { failures.append(name); print("FAIL: \(name)") }
}

@main
struct CoreTests {
    static func main() {
        check(LinkValidation.isWebURL(URL(string: "https://example.com/path?a=1#part")!), "valid HTTPS URL")
        check(LinkValidation.isWebURL(URL(string: "http://localhost:8080")!), "localhost HTTP")
        check(!LinkValidation.isWebURL(URL(string: "file:///etc/passwd")!), "reject file")
        check(!LinkValidation.isWebURL(URL(string: "javascript:alert(1)")!), "reject javascript")
        check(!LinkValidation.isWebURL(URL(string: "mailto:test@example.com")!), "reject mailto")
        check(!LinkValidation.isWebURL(URL(string: "https:/missing-host")!), "reject missing host")
        check(!LinkValidation.isWebURL(URL(string: "example.com")!), "reject bare domain")
        let original = URL(string: "https://user:secret@example.com:8443/path?q=a%26b#hash")!
        check(LinkValidation.displayURL(original) == "https://example.com:8443/path?q=a%26b#hash", "redact credentials in display only")
        check(LinkValidation.displayHost(original) == "example.com:8443", "display host and port")
        check(original.absoluteString.contains("user:secret"), "preserve original credentials")
        let first = URL(string: "https://example.com/one")!
        let second = URL(string: "https://example.com/two?a=1&b=2#three")!
        check(LinkValidation.uniqueWebURLs([first, first, second]).count == 2, "deduplicate one batch")

        var queue = RequestQueue()
        check(!queue.append([URL(string: "file:///tmp/a")!]), "invalid batch not enqueued")
        check(queue.count == 0, "invalid batch leaves queue empty")
        check(queue.append([first, first, second]), "enqueue batch")
        check(queue.current?.urls == [first, second], "preserve batch order")
        let id = queue.current!.id
        check(queue.append([first]), "same URL in a later request requires fresh choice")
        check(queue.count == 2 && queue.current?.id == id, "later request does not overwrite first")
        queue.remove(id)
        check(queue.count == 1 && queue.current?.urls == [first], "cancel advances queue")
        queue.remove(UUID())
        check(queue.count == 1, "unknown completion cannot remove next request")
        queue.remove(queue.current!.id)
        check(queue.current == nil && queue.count == 0, "finish empties queue")

        let installed = BrowserCandidate(bundleID: "browser.test", name: "Test", applicationURL: URL(fileURLWithPath: "/Applications/Test.app"))
        let cache = BrowserCandidate(bundleID: "browser.test", name: "Test", applicationURL: URL(fileURLWithPath: "/Users/test/Library/Updater/Test.app"))
        let own = BrowserCandidate(bundleID: "local.DFBrowser", name: "DFBrowser", applicationURL: URL(fileURLWithPath: "/Applications/DFBrowser.app"))
        let results = CandidateRanking.deduplicate([cache, own, installed, installed], excluding: "local.DFBrowser")
        check(results == [installed], "exclude self and prefer installed copy over updater cache")
        let browsers = BrowserDiscovery.discover()
        check(!browsers.isEmpty, "discover installed browsers")
        check(Set(browsers.map(\.bundleID)).count == browsers.count, "real browser IDs unique")
        check(!browsers.contains { $0.bundleID == BrowserDiscovery.ownBundleID }, "real list excludes self")
        check(browsers.allSatisfy { FileManager.default.fileExists(atPath: $0.applicationURL.path) }, "real app paths exist")
        check(!browsers.contains { ["com.openai.codex", "com.googlecode.iterm2"].contains($0.bundleID) }, "exclude non-browser HTTP handlers")
        check(!browsers.contains { $0.applicationURL.path.contains(".app/Contents/") }, "exclude embedded helper browsers")
        check(!browsers.contains { $0.applicationURL.path.contains("/Library/Caches/") }, "exclude automated testing caches")
        MainActor.assumeIsolated {
            let model = AppModel()
            var dismissed = 0
            model.dismissPresentation = { dismissed += 1 }
            model.receive([first])
            let requestID = model.currentRequest!.id
            model.receive([second])
            check(model.currentRequest?.id == requestID && model.queuedCount == 2, "model retains current request on arrival")
            model.cancelCurrent()
            check(model.currentRequest?.urls == [second] && dismissed == 0, "model cancel preserves queued request")
            model.isOpening = true
            model.cancelCurrent()
            check(model.queuedCount == 1, "opening request cannot be cancelled in flight")
            model.isOpening = false
            let missing = BrowserCandidate(bundleID: "test.missing", name: "Missing", applicationURL: URL(fileURLWithPath: "/not-installed/Test.app"))
            model.open(in: missing)
            check(model.errorMessage != nil && !model.isOpening && model.queuedCount == 1, "missing browser reports error and retains request")
            model.open(in: own)
            check(model.queuedCount == 1 && !model.isOpening, "model refuses routing to itself")
            model.cancelCurrent()
            check(model.currentRequest == nil && dismissed == 1, "model dismisses final cancelled request")
            model.receive([URL(string: "mailto:test@example.com")!])
            check(model.currentRequest == nil && model.errorMessage != nil, "model rejects non-web request")
        }
        let ownID = "local.DFBrowser"
        let confirmed = DefaultBrowserSnapshot(preferredIDs: ["http": "LOCAL.DFBROWSER", "https": ownID], resolvedIDs: ["http": ownID, "https": ownID])
        check(confirmed.isConfirmedDefault(ownID), "default IDs compared case-insensitively")
        check(confirmed.status(for: ownID, setupError: "error") != "已设为默认链接处理应用", "setup error cannot coexist with success status")
        let disagrees = DefaultBrowserSnapshot(preferredIDs: ["http": "com.brave.Browser", "https": "com.brave.Browser"], resolvedIDs: ["http": ownID, "https": ownID])
        check(!disagrees.isConfirmedDefault(ownID), "workspace cache alone cannot declare success")
        let partial = DefaultBrowserSnapshot(preferredIDs: ["http": ownID, "https": "com.brave.Browser"], resolvedIDs: ["http": ownID, "https": "com.brave.Browser"])
        check(!partial.isConfirmedDefault(ownID), "partial HTTP HTTPS settings are not success")
        check(partial.status(for: ownID, setupError: nil).contains("不完整"), "partial state explained")
        let empty = DefaultBrowserSnapshot(preferredIDs: [:], resolvedIDs: [:])
        check(!empty.isConfirmedDefault(ownID), "missing scheme metadata cannot declare success")
        do {
            try BrowserRegistration.registerApplication(at: URL(fileURLWithPath: "/not-installed/DFBrowser.app"))
            check(false, "invalid registration must fail")
        } catch { check(true, "invalid bundle rejected before registration") }
        print("\(assertions) assertions, \(failures.count) failures")
        if !failures.isEmpty { exit(1) }
    }
}
