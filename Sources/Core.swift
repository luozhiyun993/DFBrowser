import AppKit
import Foundation

struct BrowserCandidate: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let applicationURL: URL
    var id: String { bundleID }
}

struct CandidateRanking {
    static func preference(for url: URL) -> Int {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/System/Applications/") || path.hasPrefix("/Applications/") { return 0 }
        if path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/") { return 1 }
        return 2
    }

    static func deduplicate(_ candidates: [BrowserCandidate], excluding ownID: String) -> [BrowserCandidate] {
        var byID: [String: BrowserCandidate] = [:]
        for candidate in candidates where candidate.bundleID != ownID {
            guard !candidate.bundleID.isEmpty,
                  candidate.applicationURL.pathExtension.lowercased() == "app" else { continue }
            if let existing = byID[candidate.bundleID] {
                let oldRank = preference(for: existing.applicationURL)
                let newRank = preference(for: candidate.applicationURL)
                if newRank < oldRank || (newRank == oldRank && candidate.applicationURL.path < existing.applicationURL.path) {
                    byID[candidate.bundleID] = candidate
                }
            } else {
                byID[candidate.bundleID] = candidate
            }
        }
        return byID.values.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.bundleID < $1.bundleID : comparison == .orderedAscending
        }
    }
}

enum BrowserDiscovery {
    static let ownBundleID = "local.DFBrowser"
    // Launch Services is the primary source. This fallback also discovers browsers
    // that have not yet registered their HTTP/HTTPS handlers.
    private static let knownIDs = [
        "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.beta",
        "com.google.Chrome.dev", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.brave.Browser", "com.brave.Browser.beta", "company.thebrowser.Browser",
        "company.thebrowser.dia", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS", "app.zen-browser.zen", "com.duckduckgo.macos.browser"
    ]

    static func discover() -> [BrowserCandidate] {
        let workspace = NSWorkspace.shared
        var applicationURLs: Set<URL> = []
        for string in ["https://example.com", "http://example.com"] {
            if let url = URL(string: string) {
                applicationURLs.formUnion(workspace.urlsForApplications(toOpen: url))
            }
        }
        for identifier in knownIDs {
            if let url = workspace.urlForApplication(withBundleIdentifier: identifier) {
                applicationURLs.insert(url)
            }
        }
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in roots {
            scanApplications(in: root, depth: 2, into: &applicationURLs)
        }

        let candidates = applicationURLs.compactMap { url -> BrowserCandidate? in
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: resolved.path),
                  let bundle = Bundle(url: resolved),
                  let identifier = bundle.bundleIdentifier,
                  identifier != ownBundleID,
                  !resolved.path.contains(".app/Contents/"),
                  !resolved.path.contains("/Library/Caches/"),
                  !resolved.path.contains("/Library/Application Support/"),
                  isBrowser(bundle) else { return nil }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? resolved.deletingPathExtension().lastPathComponent
            return BrowserCandidate(bundleID: identifier, name: name, applicationURL: resolved)
        }
        return CandidateRanking.deduplicate(candidates, excluding: ownBundleID)
    }

    private static func supportsWebURLs(_ bundle: Bundle) -> Bool {
        guard let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else { return false }
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.map { $0.lowercased() }
        return schemes.contains("http") && schemes.contains("https")
    }

    private static func isBrowser(_ bundle: Bundle) -> Bool {
        if let id = bundle.bundleIdentifier, knownIDs.contains(id) { return true }
        guard supportsWebURLs(bundle),
              let types = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] else { return false }
        // A URL handler is not necessarily a browser (terminal and desktop apps
        // can declare HTTP). Require web documents and exclude terminal shells.
        if types.contains(where: { ($0["CFBundleTypeRole"] as? String) == "Shell" }) { return false }
        return types.contains { type in
            let contentTypes = type["LSItemContentTypes"] as? [String] ?? []
            let extensions = type["CFBundleTypeExtensions"] as? [String] ?? []
            return contentTypes.contains("public.html") || contentTypes.contains("public.xhtml")
                || extensions.contains("html") || extensions.contains("htm")
        }
    }

    private static func scanApplications(in directory: URL, depth: Int, into result: inout Set<URL>) {
        guard depth >= 0,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
              ) else { return }
        for entry in entries {
            if entry.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: entry), isBrowser(bundle) else { continue }
                result.insert(entry)
            } else if depth > 0, (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                scanApplications(in: entry, depth: depth - 1, into: &result)
            }
        }
    }
}

enum LinkValidation {
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return false }
        // Do not route malformed URL strings or control characters into applications.
        return !url.absoluteString.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    static func uniqueWebURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { isWebURL($0) && seen.insert($0.absoluteString).inserted }
    }

    static func displayHost(_ url: URL) -> String {
        let host = url.host ?? "网页链接"
        return url.port.map { "\(host):\($0)" } ?? host
    }

    static func displayURL(_ url: URL) -> String {
        // Credentials are never rendered, but the actual URL is passed intact.
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return displayHost(url) }
        components.user = nil
        components.password = nil
        return components.string ?? displayHost(url)
    }
}

struct LinkRequest: Identifiable, Equatable {
    let id: UUID
    let urls: [URL]
    init(urls: [URL]) {
        self.id = UUID()
        self.urls = urls
    }
}

struct RequestQueue {
    private(set) var requests: [LinkRequest] = []
    var current: LinkRequest? { requests.first }
    var count: Int { requests.count }

    mutating func append(_ urls: [URL]) -> Bool {
        let valid = LinkValidation.uniqueWebURLs(urls)
        guard !valid.isEmpty else { return false }
        requests.append(LinkRequest(urls: valid))
        return true
    }

    mutating func remove(_ id: UUID) {
        requests.removeAll { $0.id == id }
    }
}
