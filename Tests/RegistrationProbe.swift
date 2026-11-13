import AppKit
import CoreServices
import Foundation

@main
struct RegistrationProbe {
    static func main() {
        for scheme in ["http", "https"] {
            let preferred = LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() as String?
            let handlers = LSCopyAllHandlersForURLScheme(scheme as CFString)?.takeRetainedValue() as? [String] ?? []
            print("\(scheme): preferred=\(preferred ?? "none"), DFBrowser-candidate=\(handlers.contains { $0.lowercased() == "local.dfbrowser" })")
            let url = URL(string: "\(scheme)://example.com")!
            print("workspace candidates: \(NSWorkspace.shared.urlsForApplications(toOpen: url).filter { Bundle(url: $0)?.bundleIdentifier?.lowercased() == "local.dfbrowser" }.map(\.path))")
        }
        for (name, role) in [("all", LSRolesMask.all), ("viewer", .viewer), ("editor", .editor)] {
            let apps = LSCopyAllRoleHandlersForContentType("com.apple.default-app.web-browser" as CFString, role)?.takeRetainedValue() as? [String] ?? []
            print("browser role \(name): \(apps)")
        }
        let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidateURLs = [URL(fileURLWithPath: "/Applications/DFBrowser.app"), projectURL.appendingPathComponent("dist/DFBrowser-0.1.2.app")]
        for url in candidateURLs {
            print("\(url.path): exists=\(FileManager.default.fileExists(atPath: url.path)), bundle=\(Bundle(url: url)?.bundleIdentifier ?? "none")")
        }
    }
}
