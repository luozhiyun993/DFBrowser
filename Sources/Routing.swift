import Foundation

/// A user-defined rule: links whose host matches `pattern` open directly in `bundleID`.
struct RoutingRule: Codable, Identifiable, Equatable {
    var id: UUID
    var pattern: String
    var bundleID: String
    /// Remembered so the rule stays readable if the browser is later uninstalled.
    var browserName: String

    init(id: UUID = UUID(), pattern: String, bundleID: String, browserName: String) {
        self.id = id
        self.pattern = pattern
        self.bundleID = bundleID
        self.browserName = browserName
    }
}

enum HostPattern {
    /// Normalizes user input into a lowercase host pattern. Accepts pasted URLs
    /// (`https://a.com/x` → `a.com`) and drops ports. Returns nil when invalid.
    static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = value.range(of: "://") { value = String(value[range.upperBound...]) }
        if let end = value.firstIndex(where: { "/?#".contains($0) }) { value = String(value[..<end]) }
        if let at = value.lastIndex(of: "@") { value = String(value[value.index(after: at)...]) }
        if let colon = value.lastIndex(of: ":") { value = String(value[..<colon]) }
        while value.hasSuffix(".") { value.removeLast() }
        guard !value.isEmpty,
              value.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || "-_.*".contains($0) }) else { return nil }
        return value
    }

    /// `*` matches any run of characters (including dots). A leading `*.` also
    /// matches the bare domain, so `*.google.com` covers `google.com` too.
    static func matches(_ pattern: String, host rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }
        if pattern.hasPrefix("*."), glob(Array(pattern.dropFirst(2)), Array(host)) { return true }
        return glob(Array(pattern), Array(host))
    }

    private static func glob(_ pattern: [Character], _ text: [Character]) -> Bool {
        var p = 0, t = 0, star = -1, mark = 0
        while t < text.count {
            if p < pattern.count, pattern[p] != "*", pattern[p] == text[t] {
                p += 1; t += 1
            } else if p < pattern.count, pattern[p] == "*" {
                star = p; mark = t; p += 1
            } else if star >= 0 {
                p = star + 1; mark += 1; t = mark
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }
}

enum LinkRouter {
    /// First matching rule wins; invalid or self-targeting rules are skipped.
    static func rule(for url: URL, in rules: [RoutingRule], excluding ownID: String = BrowserDiscovery.ownBundleID) -> RoutingRule? {
        guard let host = url.host else { return nil }
        return rules.first { rule in
            guard !rule.bundleID.isEmpty, rule.bundleID != ownID,
                  let pattern = HostPattern.normalize(rule.pattern) else { return false }
            return HostPattern.matches(pattern, host: host)
        }
    }

    /// A batch is routed automatically only when every link resolves to the same browser.
    static func bundleID(for urls: [URL], rules: [RoutingRule], excluding ownID: String = BrowserDiscovery.ownBundleID) -> String? {
        let ids = urls.map { rule(for: $0, in: rules, excluding: ownID)?.bundleID }
        guard let first = ids.first, let id = first, ids.allSatisfy({ $0 == id }) else { return nil }
        return id
    }

    /// Adds or updates exact-host rules (placed first, so they win over wildcards).
    static func remembering(hosts: [String], bundleID: String, browserName: String, in rules: [RoutingRule]) -> [RoutingRule] {
        var result = rules
        for host in hosts.reversed() {
            guard let pattern = HostPattern.normalize(host) else { continue }
            if let index = result.firstIndex(where: { HostPattern.normalize($0.pattern) == pattern }) {
                var rule = result.remove(at: index)
                rule.bundleID = bundleID
                rule.browserName = browserName
                result.insert(rule, at: 0)
            } else {
                result.insert(RoutingRule(pattern: pattern, bundleID: bundleID, browserName: browserName), at: 0)
            }
        }
        return result
    }
}

struct RoutingRuleStore {
    var defaults: UserDefaults = .standard
    var key = "routingRules"

    func load() -> [RoutingRule] {
        guard let data = defaults.data(forKey: key),
              let rules = try? JSONDecoder().decode([RoutingRule].self, from: data) else { return [] }
        return rules
    }

    func save(_ rules: [RoutingRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Hand-editable rule file. `browser` may be a bundle ID or a browser name.
struct RuleFile: Codable {
    struct Entry: Codable {
        var pattern: String
        var browser: String
        var browserName: String?
    }
    var version: Int? = 1
    var rules: [Entry]
}

struct RuleImportResult: Equatable {
    var rules: [RoutingRule]
    var skipped: [String]
}

enum RuleTransferError: LocalizedError {
    case unreadable(String)
    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): return "文件不是有效的规则文件：\(detail)"
        }
    }
}

enum RuleTransfer {
    static func export(_ rules: [RoutingRule]) throws -> Data {
        let file = RuleFile(rules: rules.map { .init(pattern: $0.pattern, browser: $0.bundleID, browserName: $0.browserName) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    /// Accepts `{"rules": [...]}` or a bare array of entries. Browser names are
    /// matched case-insensitively against installed browsers (exact, then partial);
    /// unknown values containing a dot are kept as bundle IDs.
    static func parse(_ data: Data, browsers: [BrowserCandidate], excluding ownID: String = BrowserDiscovery.ownBundleID) throws -> RuleImportResult {
        let decoder = JSONDecoder()
        let entries: [RuleFile.Entry]
        do {
            if let file = try? decoder.decode(RuleFile.self, from: data) {
                entries = file.rules
            } else {
                entries = try decoder.decode([RuleFile.Entry].self, from: data)
            }
        } catch {
            throw RuleTransferError.unreadable("需要 {\"rules\": [{\"pattern\": …, \"browser\": …}]} 格式")
        }
        var result = RuleImportResult(rules: [], skipped: [])
        for entry in entries {
            guard let pattern = HostPattern.normalize(entry.pattern) else {
                result.skipped.append("\(entry.pattern)（域名格式无效）"); continue
            }
            guard let (bundleID, name) = resolve(entry, browsers: browsers), bundleID.lowercased() != ownID.lowercased() else {
                result.skipped.append("\(entry.pattern)（找不到浏览器 \(entry.browser)）"); continue
            }
            result.rules.append(RoutingRule(pattern: pattern, bundleID: bundleID, browserName: name))
        }
        return result
    }

    private static func resolve(_ entry: RuleFile.Entry, browsers: [BrowserCandidate]) -> (String, String)? {
        let key = entry.browser.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let lower = key.lowercased()
        if let match = browsers.first(where: { $0.bundleID.lowercased() == lower })
            ?? browsers.first(where: { $0.name.lowercased() == lower })
            ?? browsers.first(where: { $0.name.lowercased().contains(lower) }) {
            return (match.bundleID, match.name)
        }
        guard key.contains(".") else { return nil }
        return (key, entry.browserName ?? key)
    }

    /// Imported rules with an existing pattern update it in place; new ones append.
    static func merge(_ imported: [RoutingRule], into existing: [RoutingRule]) -> [RoutingRule] {
        var result = existing
        for rule in imported {
            if let index = result.firstIndex(where: { HostPattern.normalize($0.pattern) == HostPattern.normalize(rule.pattern) }) {
                result[index].bundleID = rule.bundleID
                result[index].browserName = rule.browserName
            } else {
                result.append(rule)
            }
        }
        return result
    }
}
