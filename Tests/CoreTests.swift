import AppKit
import Foundation

var failures: [String] = []
var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    assertions += 1
    if !condition() { failures.append(name); print("FAIL: \(name)") }
}

@MainActor
final class MockLoginItemService: LoginItemServicing {
    var state: LoginItemState = .disabled
    var enableCalls = 0
    var disableCalls = 0
    var fail = false
    func enable() throws {
        enableCalls += 1
        if fail { throw NSError(domain: "Test", code: 1) }
        state = .enabled
    }
    func disable() throws {
        disableCalls += 1
        if fail { throw NSError(domain: "Test", code: 2) }
        state = .disabled
    }
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
        let testSuite = "DFBrowserTests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: testSuite)!
        let testStore = RoutingRuleStore(defaults: testDefaults)
        MainActor.assumeIsolated {
            let model = AppModel(ruleStore: testStore)
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
        routingTests(store: testStore)
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
        MainActor.assumeIsolated {
            let fake = MockLoginItemService()
            let controller = LoginItemController(service: fake)
            check(fake.enableCalls == 0, "creating login controller never auto-registers")
            controller.refresh()
            check(controller.state == .disabled, "login switch initial system state")
            controller.setEnabled(true)
            check(controller.state == .enabled && fake.enableCalls == 1, "explicit enabling calls service")
            controller.setEnabled(true)
            check(fake.enableCalls == 1, "idempotent enabling")
            controller.setEnabled(false)
            check(controller.state == .disabled && fake.disableCalls == 1, "disabling unregisters")
            controller.setEnabled(false)
            check(fake.disableCalls == 1, "idempotent disabling")
            fake.state = .requiresApproval
            controller.refresh()
            check(controller.state.toggleIsOn && controller.state != .enabled, "pending approval is not claimed as enabled")
            controller.setEnabled(false)
            check(controller.state == .disabled, "pending approval can be cancelled")
            fake.fail = true
            controller.setEnabled(true)
            check(controller.state == .disabled && controller.errorMessage != nil, "enable failure cannot optimistically turn switch on")
            fake.fail = false
            fake.state = .unavailable
            controller.refresh()
            check(!controller.state.toggleIsOn, "unavailable service is not enabled")
        }
        check(!AppLaunchPolicy.shouldShowChooser(hasPendingLink: false), "normal and login launch stay windowless")
        check(AppLaunchPolicy.shouldShowChooser(hasPendingLink: true), "cold URL launch still shows chooser")
        testDefaults.removePersistentDomain(forName: testSuite)
        print("\(assertions) assertions, \(failures.count) failures")
        if !failures.isEmpty { exit(1) }
    }
}

func routingTests(store: RoutingRuleStore) {
    check(HostPattern.normalize("  *.Google.COM ") == "*.google.com", "pattern normalized to lowercase")
    check(HostPattern.normalize("https://user@Docs.Example.com:8443/a?b#c") == "docs.example.com", "pasted URL reduced to host")
    check(HostPattern.normalize("") == nil && HostPattern.normalize("bad host") == nil && HostPattern.normalize("[::1]") == nil && HostPattern.normalize("例子.com") == nil, "invalid patterns rejected")
    check(HostPattern.matches("*.google.com", host: "google.com"), "wildcard covers bare domain")
    check(HostPattern.matches("*.google.com", host: "mail.google.com"), "wildcard covers subdomain")
    check(HostPattern.matches("*.google.com", host: "a.b.GOOGLE.com."), "wildcard covers nested subdomain, case and trailing dot")
    check(!HostPattern.matches("*.google.com", host: "notgoogle.com"), "wildcard does not match suffix lookalike")
    check(!HostPattern.matches("*.google.com", host: "google.com.evil.io"), "wildcard anchored at end")
    check(HostPattern.matches("docs.example.com", host: "docs.example.com") && !HostPattern.matches("docs.example.com", host: "x.docs.example.com"), "exact host")
    check(HostPattern.matches("*", host: "anything.io"), "catch-all")
    check(HostPattern.matches("*.openai.*", host: "openai.com"), "leading wildcard covers bare domain with wildcard TLD")
    check(HostPattern.matches("*.openai.*", host: "chat.openai.com") && HostPattern.matches("*.openai.*", host: "openai.co.uk"), "wildcard TLD with subdomain")
    check(!HostPattern.matches("*.openai.*", host: "notopenai.com"), "wildcard TLD does not match lookalike")
    let gpt = URL(string: "https://openai.com/index/introducing-gpt-6-cyber/")!
    let reported = [RoutingRule(pattern: "*.github.com", bundleID: "com.microsoft.edgemac", browserName: "Edge"),
                    RoutingRule(pattern: "*.openai.*", bundleID: "com.google.Chrome", browserName: "Chrome")]
    check(LinkRouter.bundleID(for: [gpt], rules: reported) == "com.google.Chrome", "reported openai link routed to Chrome")
    check(HostPattern.matches("git*.com", host: "gitlab.com") && !HostPattern.matches("git*.com", host: "gitlab.org"), "inner wildcard")

    let chrome = RoutingRule(pattern: "*.google.com", bundleID: "com.google.Chrome", browserName: "Chrome")
    let brave = RoutingRule(pattern: "*.byte.com", bundleID: "com.brave.Browser", browserName: "Brave")
    let catchAll = RoutingRule(pattern: "*", bundleID: "com.apple.Safari", browserName: "Safari")
    let selfRule = RoutingRule(pattern: "*.loop.com", bundleID: "local.DFBrowser", browserName: "DFBrowser")
    let broken = RoutingRule(pattern: "bad host", bundleID: "com.brave.Browser", browserName: "Brave")
    let rules = [broken, selfRule, chrome, brave, catchAll]
    let g = URL(string: "https://mail.google.com/x")!, b = URL(string: "https://www.byte.com")!, o = URL(string: "https://other.org")!
    check(LinkRouter.rule(for: g, in: rules)?.id == chrome.id, "google routed to Chrome")
    check(LinkRouter.rule(for: b, in: rules)?.id == brave.id, "byte routed to Brave")
    check(LinkRouter.rule(for: o, in: rules)?.id == catchAll.id, "first match wins, catch-all last")
    check(LinkRouter.rule(for: URL(string: "https://a.loop.com")!, in: rules)?.id == catchAll.id, "self-targeting rule skipped")
    check(LinkRouter.rule(for: o, in: [chrome, brave]) == nil, "unmatched link has no rule")
    check(LinkRouter.bundleID(for: [g, URL(string: "https://google.com")!], rules: rules) == "com.google.Chrome", "uniform batch routed")
    check(LinkRouter.bundleID(for: [g, b], rules: rules) == nil, "mixed batch goes to chooser")
    check(LinkRouter.bundleID(for: [g, o], rules: [chrome]) == nil, "partially matched batch goes to chooser")
    check(LinkRouter.bundleID(for: [], rules: rules) == nil, "empty batch not routed")

    let remembered = LinkRouter.remembering(hosts: ["Docs.Example.com"], bundleID: "com.brave.Browser", browserName: "Brave", in: [chrome])
    check(remembered.count == 2 && remembered[0].pattern == "docs.example.com" && remembered[1] == chrome, "remembered host prepended")
    let updated = LinkRouter.remembering(hosts: ["docs.example.com"], bundleID: "com.google.Chrome", browserName: "Chrome", in: remembered)
    check(updated.count == 2 && updated[0].bundleID == "com.google.Chrome", "remembering existing host updates instead of duplicating")

    transferTests(chrome: chrome, brave: brave)
    check(store.load().isEmpty, "empty store loads no rules")
    store.save([chrome, brave])
    check(store.load() == [chrome, brave], "rules persist with order")

    MainActor.assumeIsolated {
        store.save([chrome])
        let model = AppModel(ruleStore: store)
        check(model.rules == [chrome], "model loads stored rules")
        var launched: [([URL], URL)] = []
        var launchError: Error?
        model.applicationURLForBundleID = { $0 == "com.google.Chrome" ? URL(fileURLWithPath: "/Applications/Google Chrome.app") : nil }
        model.launcher = { urls, app, done in launched.append((urls, app)); done(launchError) }
        var presented = 0
        model.requestPresentation = { presented += 1 }
        model.receive([g])
        check(launched.count == 1 && launched[0].0 == [g] && model.currentRequest == nil && presented == 0, "matched link opens directly without chooser")
        model.receive([g], applyRules: false)
        check(launched.count == 1 && model.currentRequest != nil, "preview bypasses rules")
        model.cancelCurrent()
        model.receive([o])
        check(launched.count == 1 && model.currentRequest?.urls == [o], "unmatched link shows chooser")
        model.cancelCurrent()
        model.applicationURLForBundleID = { _ in nil }
        model.receive([g])
        check(launched.count == 1 && model.currentRequest?.urls == [g], "uninstalled rule browser falls back to chooser")
        model.cancelCurrent()
        model.applicationURLForBundleID = { _ in URL(fileURLWithPath: "/Applications/Google Chrome.app") }
        launchError = NSError(domain: "Test", code: 3)
        model.receive([g])
        check(model.currentRequest?.urls == [g] && model.errorMessage != nil, "failed rule launch falls back to chooser with error")
        launchError = nil
        model.rememberChoice = true
        let browser = BrowserCandidate(bundleID: "com.brave.Browser", name: "Brave", applicationURL: URL(fileURLWithPath: "/Applications/Brave Browser.app"))
        model.open(in: browser)
        check(model.currentRequest == nil && !model.rememberChoice, "remembered choice opens and resets checkbox")
        check(model.rules.first?.pattern == "mail.google.com" && model.rules.first?.bundleID == "com.brave.Browser", "remembered choice creates exact-host rule ahead of wildcard")
        check(store.load() == model.rules, "rule edits persisted")
        model.addRule()
        check(model.rules.count == 3, "add rule")
        let newID = model.rules.last!.id
        model.updateRule(newID) { $0.pattern = "*.byte.com" }
        model.moveRule(newID, by: -1)
        check(model.rules[1].id == newID, "move rule up")
        model.deleteRule(newID)
        check(model.rules.count == 2 && store.load().count == 2, "delete rule persisted")
    }
}

func transferTests(chrome: RoutingRule, brave: RoutingRule) {
    let installed = [
        BrowserCandidate(bundleID: "com.google.Chrome", name: "Google Chrome", applicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")),
        BrowserCandidate(bundleID: "com.brave.Browser", name: "Brave Browser", applicationURL: URL(fileURLWithPath: "/Applications/Brave Browser.app"))
    ]
    let exported = try! RuleTransfer.export([chrome, brave])
    let roundTrip = try! RuleTransfer.parse(exported, browsers: installed)
    check(roundTrip.skipped.isEmpty && roundTrip.rules.map(\.pattern) == ["*.google.com", "*.byte.com"]
          && roundTrip.rules.map(\.bundleID) == ["com.google.Chrome", "com.brave.Browser"], "export then import round trip")
    let handWritten = """
    {"rules": [
      {"pattern": "*.Google.com", "browser": "chrome"},
      {"pattern": "https://www.byte.com/x", "browser": "Brave Browser"},
      {"pattern": "bad host", "browser": "chrome"},
      {"pattern": "a.com", "browser": "Netscape"},
      {"pattern": "b.com", "browser": "org.example.NotInstalled"},
      {"pattern": "c.com", "browser": "local.DFBrowser"}
    ]}
    """
    let parsed = try! RuleTransfer.parse(Data(handWritten.utf8), browsers: installed)
    check(parsed.rules.map(\.pattern) == ["*.google.com", "www.byte.com", "b.com"], "hand-written file normalized")
    check(parsed.rules.map(\.bundleID) == ["com.google.Chrome", "com.brave.Browser", "org.example.NotInstalled"], "browser by partial name, full name or bundle ID")
    check(parsed.skipped.count == 3, "invalid pattern, unknown name and self target skipped")
    let bare = try? RuleTransfer.parse(Data(#"[{"pattern": "x.com", "browser": "com.brave.Browser"}]"#.utf8), browsers: installed)
    check(bare?.rules.count == 1, "bare array accepted")
    check((try? RuleTransfer.parse(Data("not json".utf8), browsers: installed)) == nil, "garbage rejected")
    let updatedChrome = RoutingRule(pattern: "*.GOOGLE.com", bundleID: "com.brave.Browser", browserName: "Brave")
    let extra = RoutingRule(pattern: "new.com", bundleID: "com.google.Chrome", browserName: "Chrome")
    let merged = RuleTransfer.merge([updatedChrome, extra], into: [chrome, brave])
    check(merged.count == 3 && merged[0].id == chrome.id && merged[0].bundleID == "com.brave.Browser" && merged[2].pattern == "new.com", "merge updates existing pattern in place and appends new")
}
