import AppKit
import Foundation

let arguments = CommandLine.arguments
if arguments.contains("--list-browsers") {
    for browser in BrowserDiscovery.discover() {
        print("\(browser.name)\t\(browser.bundleID)\t\(browser.applicationURL.path)")
    }
} else if arguments.contains("--register-browser") {
    do {
        try BrowserRegistration.registerApplication(at: Bundle.main.bundleURL)
        print("browser candidate registered; default browser unchanged")
        print("candidate: \(BrowserRegistration.isRegisteredCandidate(bundleID: BrowserDiscovery.ownBundleID))")
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else if arguments.contains("--diagnose") {
    print("DFBrowser \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")")
    print("architecture: \(ProcessInfo.processInfo.machineArchitecture)")
    let snapshot = BrowserRegistration.snapshot()
    for value in ["http://example.com", "https://example.com"] {
        let url = URL(string: value)!
        let app = NSWorkspace.shared.urlForApplication(toOpen: url)
        print("\(url.scheme!): \(app?.path ?? "unavailable")")
        print("preferred \(url.scheme!): \(snapshot.preferredIDs[url.scheme!] ?? "none")")
    }
    print("default status: \(snapshot.status(for: BrowserDiscovery.ownBundleID, setupError: nil))")
    print("registered candidate: \(BrowserRegistration.isRegisteredCandidate(bundleID: BrowserDiscovery.ownBundleID))")
    print("browsers: \(BrowserDiscovery.discover().count)")
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
