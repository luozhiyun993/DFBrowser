import AppKit
import CoreServices
import Foundation

struct DefaultBrowserSnapshot {
    let preferredIDs: [String: String]
    let resolvedIDs: [String: String]

    func isConfirmedDefault(_ bundleID: String) -> Bool {
        let own = bundleID.lowercased()
        return ["http", "https"].allSatisfy { scheme in
            preferredIDs[scheme]?.lowercased() == own && resolvedIDs[scheme]?.lowercased() == own
        }
    }

    func status(for bundleID: String, setupError: String?) -> String {
        if setupError != nil { return "设置未完成，请在系统设置中确认" }
        if isConfirmedDefault(bundleID) { return "已设为默认链接处理应用" }
        let own = bundleID.lowercased()
        if preferredIDs.values.contains(where: { $0.lowercased() == own }) || resolvedIDs.values.contains(where: { $0.lowercased() == own }) {
            return "默认链接设置不完整，请在系统设置中重新选择"
        }
        return "尚未设为默认浏览器"
    }
}

enum BrowserRegistration {
    static func snapshot() -> DefaultBrowserSnapshot {
        var preferred: [String: String] = [:]
        var resolved: [String: String] = [:]
        for scheme in ["http", "https"] {
            // Deliberate compatibility cross-check: NSWorkspace URL resolution
            // alone can disagree with stored Launch Services scheme preferences.
            if let identifier = LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() as String? {
                preferred[scheme] = identifier
            }
            if let url = URL(string: "\(scheme)://example.com"),
               let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url),
               let identifier = Bundle(url: applicationURL)?.bundleIdentifier {
                resolved[scheme] = identifier
            }
        }
        return DefaultBrowserSnapshot(preferredIDs: preferred, resolvedIDs: resolved)
    }

    static func registerApplication(at url: URL) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              bundle.bundleIdentifier?.lowercased() == BrowserDiscovery.ownBundleID.lowercased(),
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw NSError(domain: "DFBrowser.Registration", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "未找到有效的 DFBrowser 应用包，请从 .app 启动。"])
        }
        // Register only this bundle. Never reset or rebuild the global database.
        let status = LSRegisterURL(url as CFURL, true)
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "系统浏览器候选注册失败（\(status)）。"])
        }
    }

    static func isRegisteredCandidate(bundleID: String) -> Bool {
        ["http", "https"].allSatisfy { scheme in
            guard let url = URL(string: "\(scheme)://example.com") else { return false }
            return NSWorkspace.shared.urlsForApplications(toOpen: url).contains {
                Bundle(url: $0)?.bundleIdentifier?.lowercased() == bundleID.lowercased()
            }
        }
    }
}
