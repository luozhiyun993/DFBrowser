import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var browsers: [BrowserCandidate] = []
    @Published var currentRequest: LinkRequest?
    @Published var queuedCount = 0
    @Published var isOpening = false
    @Published var errorMessage: String?
    @Published var defaultStatus = ""
    @Published var registrationMessage: String?
    @Published var rules: [RoutingRule] { didSet { ruleStore.save(rules) } }
    /// Chooser checkbox: turn this choice into exact-host rules.
    @Published var rememberChoice = false
    @Published var ruleTransferMessage: String?
    let loginItem = LoginItemController(service: SystemLoginItemService())
    private let ruleStore: RoutingRuleStore
    private var setupError: String?
    private var queue = RequestQueue()
    var requestPresentation: (() -> Void)?
    var dismissPresentation: (() -> Void)?
    var requestRulesPresentation: (() -> Void)?
    /// Injectable for tests; production resolves installed apps through Launch Services.
    var applicationURLForBundleID: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    var launcher: ([URL], URL, @escaping (Error?) -> Void) -> Void = { urls, appURL, completion in
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Always name the destination application. The default opener would loop
        // back into DFBrowser once it becomes the system default browser.
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    init(ruleStore: RoutingRuleStore = RoutingRuleStore()) {
        self.ruleStore = ruleStore
        self.rules = ruleStore.load()
    }

    func refreshBrowsers() {
        browsers = BrowserDiscovery.discover()
        refreshDefaultStatus()
    }

    func refreshDefaultStatus() {
        defaultStatus = BrowserRegistration.snapshot().status(for: BrowserDiscovery.ownBundleID, setupError: setupError)
    }

    /// Links matching a routing rule open directly; holding Option forces the chooser.
    func receive(_ urls: [URL], applyRules: Bool = true) {
        let valid = LinkValidation.uniqueWebURLs(urls)
        if applyRules, !NSEvent.modifierFlags.contains(.option),
           let bundleID = LinkRouter.bundleID(for: valid, rules: rules),
           let appURL = applicationURLForBundleID(bundleID) {
            launcher(valid, appURL) { [weak self] error in
                guard let self, let error else { return }
                // Fall back to the chooser so the link is never silently lost.
                self.receive(valid, applyRules: false)
                self.errorMessage = "规则指定的浏览器无法打开链接：\(error.localizedDescription)"
            }
            return
        }
        guard queue.append(urls) else {
            errorMessage = "仅支持有效的 HTTP / HTTPS 网页链接。"
            requestPresentation?()
            return
        }
        synchronizeQueue()
        if !isOpening { errorMessage = nil }
        refreshBrowsers()
        requestPresentation?()
    }

    func cancelCurrent() {
        guard !isOpening else { return }
        if let request = currentRequest { queue.remove(request.id) }
        errorMessage = nil
        rememberChoice = false
        synchronizeQueue()
        if currentRequest == nil { dismissPresentation?() }
    }

    func open(in browser: BrowserCandidate) {
        guard !isOpening, let request = currentRequest,
              browser.bundleID != BrowserDiscovery.ownBundleID else { return }
        guard FileManager.default.fileExists(atPath: browser.applicationURL.path) else {
            errorMessage = "找不到 \(browser.name)，请刷新浏览器列表后重试。"
            return
        }
        isOpening = true
        errorMessage = nil
        let remember = rememberChoice
        launcher(request.urls, browser.applicationURL) { [weak self] error in
            guard let self else { return }
            self.isOpening = false
            if let error {
                self.errorMessage = "无法用 \(browser.name) 打开链接：\(error.localizedDescription)"
            } else {
                if remember {
                    self.rules = LinkRouter.remembering(hosts: request.urls.compactMap(\.host), bundleID: browser.bundleID,
                                                        browserName: browser.name, in: self.rules)
                }
                self.rememberChoice = false
                self.queue.remove(request.id)
                self.synchronizeQueue()
                if self.currentRequest == nil {
                    self.dismissPresentation?()
                } else {
                    self.requestPresentation?()
                }
            }
        }
    }

    func addRule() {
        let browser = browsers.first
        rules.append(RoutingRule(pattern: "", bundleID: browser?.bundleID ?? "", browserName: browser?.name ?? ""))
    }

    func updateRule(_ id: UUID, _ change: (inout RoutingRule) -> Void) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        change(&rules[index])
    }

    func exportRules() {
        let panel = NSSavePanel()
        panel.title = "导出网址规则"
        panel.nameFieldStringValue = "DFBrowser-rules.json"
        panel.allowedContentTypes = [.json]
        presentFilePanel(panel) { [weak self] in
            guard let self, let url = panel.url else { return }
            do {
                try RuleTransfer.export(self.rules).write(to: url, options: .atomic)
                self.ruleTransferMessage = "已导出 \(self.rules.count) 条规则到 \(url.lastPathComponent)。"
            } catch {
                self.ruleTransferMessage = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    func importRules() {
        let panel = NSOpenPanel()
        panel.title = "导入网址规则"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        presentFilePanel(panel) { [weak self] in
            guard let self, let url = panel.url else { return }
            self.refreshBrowsers()
            let result: RuleImportResult
            do {
                result = try RuleTransfer.parse(Data(contentsOf: url), browsers: self.browsers)
            } catch {
                self.ruleTransferMessage = "导入失败：\(error.localizedDescription)"
                return
            }
            guard !result.rules.isEmpty else {
                self.ruleTransferMessage = "文件中没有可导入的规则。" + Self.skippedSummary(result.skipped)
                return
            }
            var replace = false
            if !self.rules.isEmpty {
                let alert = NSAlert()
                alert.messageText = "导入 \(result.rules.count) 条规则"
                alert.informativeText = "合并：同名域名更新浏览器，新规则追加到末尾。替换：清空现有 \(self.rules.count) 条规则后导入。"
                alert.addButton(withTitle: "合并")
                alert.addButton(withTitle: "替换")
                alert.addButton(withTitle: "取消")
                switch alert.runModal() {
                case .alertFirstButtonReturn: replace = false
                case .alertSecondButtonReturn: replace = true
                default: return
                }
            }
            self.rules = replace ? result.rules : RuleTransfer.merge(result.rules, into: self.rules)
            self.ruleTransferMessage = "已导入 \(result.rules.count) 条规则。" + Self.skippedSummary(result.skipped)
        }
    }

    private static func skippedSummary(_ skipped: [String]) -> String {
        guard !skipped.isEmpty else { return "" }
        let shown = skipped.prefix(5).joined(separator: "、")
        return "跳过 \(skipped.count) 条：\(shown)\(skipped.count > 5 ? " 等" : "")"
    }

    /// Attach to the (floating) rules window as a sheet so the panel is never hidden behind it.
    private func presentFilePanel(_ panel: NSSavePanel, onOK: @escaping () -> Void) {
        ruleTransferMessage = nil
        if let window = NSApplication.shared.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK { onOK() }
            }
        } else if panel.runModal() == .OK {
            onOK()
        }
    }

    func deleteRule(_ id: UUID) { rules.removeAll { $0.id == id } }

    func moveRule(_ id: UUID, by offset: Int) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard rules.indices.contains(target) else { return }
        rules.swapAt(index, target)
    }

    func registerBrowserCandidate() {
        setupError = nil
        errorMessage = nil
        registrationMessage = nil
        do {
            try BrowserRegistration.registerApplication(at: Bundle.main.bundleURL)
            if BrowserRegistration.isRegisteredCandidate(bundleID: BrowserDiscovery.ownBundleID) {
                registrationMessage = "已注册浏览器候选，未更改默认浏览器。请重新打开系统设置，在默认网页浏览器中选择 DFBrowser。"
            } else {
                registrationMessage = "注册请求已提交。请将应用放入“应用程序”，退出旧版后启动新版，再重新打开系统设置。"
            }
        } catch {
            setupError = error.localizedDescription
            errorMessage = "无法注册浏览器候选：\(error.localizedDescription)"
        }
        refreshDefaultStatus()
    }

    func requestDefaultBrowser() {
        guard currentRequest == nil else { return }
        let alert = NSAlert()
        alert.messageText = "在系统设置中选择 DFBrowser"
        alert.informativeText = "将先注册 DFBrowser 为浏览器候选，再打开“桌面与程序坞”。请在“默认网页浏览器”列表中选择 DFBrowser。此操作不会自行更改默认浏览器。建议先退出旧版，将新版应用放入“应用程序”。"
        alert.addButton(withTitle: "注册并打开设置")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        registerBrowserCandidate()
        guard setupError == nil else { return }
        // Let System Settings update the complete default browser association.
        // Sequential per-scheme setters can report errors or leave partial state.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension"),
              NSWorkspace.shared.open(url) else {
            setupError = "无法自动打开系统设置"
            errorMessage = "浏览器候选已注册，但无法自动打开系统设置。请手动打开“系统设置 → 桌面与程序坞 → 默认网页浏览器”。"
            refreshDefaultStatus()
            return
        }
    }

    private func synchronizeQueue() {
        currentRequest = queue.current
        queuedCount = queue.count
    }
}

struct BrowserChooserView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            linkCard
            browserList
            if let request = model.currentRequest {
                Toggle(rememberLabel(request), isOn: $model.rememberChoice)
                    .toggleStyle(.checkbox).font(.system(size: 12)).disabled(model.isOpening)
            }
            if let message = model.errorMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.currentRequest == nil, let message = model.registrationMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.currentRequest == nil {
                rulesCard
                LoginItemSettingsView(controller: model.loginItem)
            }
            Divider()
            footer
        }
        .padding(22)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func rememberLabel(_ request: LinkRequest) -> String {
        var seen = Set<String>()
        let hosts = request.urls.compactMap(\.host).filter { seen.insert($0.lowercased()).inserted }
        let subject = hosts.count == 1 ? hosts[0] : "这 \(hosts.count) 个网站"
        return "以后 \(subject) 都直接用所选浏览器打开"
    }

    private var rulesCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("网址规则").font(.system(size: 13, weight: .medium))
                Text(model.rules.isEmpty ? "未设置；所有链接都会弹出选择。" : "\(model.rules.count) 条规则，匹配的链接将直接打开。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("编辑规则…") { model.requestRulesPresentation?() }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(model.currentRequest == nil ? "DFBrowser" : "用哪个浏览器打开？")
                    .font(.system(size: 20, weight: .semibold))
                Text(model.currentRequest == nil ? "按网址规则分流，其余链接由你选择浏览器。" : "点击浏览器打开 · Esc 取消")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.refreshBrowsers() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("刷新已安装的浏览器")
                .accessibilityLabel("刷新浏览器").disabled(model.isOpening)
        }
    }

    @ViewBuilder private var linkCard: some View {
        if let request = model.currentRequest, let url = request.urls.first {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    Text(LinkValidation.displayHost(url)).font(.system(size: 14, weight: .medium))
                    Spacer()
                    if request.urls.count > 1 {
                        Text("\(request.urls.count) 个链接").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(LinkValidation.displayURL(url))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
                if request.urls.count > 1 {
                    Text("这批链接将全部交给你选中的浏览器。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.defaultStatus, systemImage: "info.circle")
                    .font(.system(size: 13, weight: .medium))
                Text("设为默认浏览器后，其他软件交给系统的网页链接会先来到这里；选好浏览器后才会打开。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var browserList: some View {
        VStack(spacing: 12) {
            HStack {
                Text("已安装的浏览器").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.browsers.count) 个").font(.caption).foregroundStyle(.secondary)
            }
            if model.browsers.isEmpty {
                Text("未发现可用浏览器。请安装并启动一次浏览器，再点击刷新。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(model.browsers.enumerated()), id: \.element.id) { index, browser in
                            browserButton(browser, index: index)
                        }
                    }.padding(.vertical, 1)
                }
                .frame(height: CGFloat(min(model.browsers.count, 5)) * 60)
            }
        }
    }

    @ViewBuilder private func browserButton(_ browser: BrowserCandidate, index: Int) -> some View {
        if index < 9 {
            BrowserRow(browser: browser, number: index + 1, selectable: model.currentRequest != nil) {
                model.open(in: browser)
            }
            .disabled(model.isOpening || model.currentRequest == nil)
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
        } else {
            BrowserRow(browser: browser, number: index + 1, selectable: model.currentRequest != nil) {
                model.open(in: browser)
            }
            .disabled(model.isOpening || model.currentRequest == nil)
        }
    }

    @ViewBuilder private var footer: some View {
        if model.currentRequest != nil {
            HStack {
                if model.isOpening {
                    ProgressView().controlSize(.small)
                    Text("正在打开…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(model.queuedCount > 1 ? "另有 \(model.queuedCount - 1) 个请求等待选择" : "按住 Option 点链接可跳过规则 · 不记录历史")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { model.cancelCurrent() }
                    .keyboardShortcut(.cancelAction).disabled(model.isOpening)
            }
        } else {
            HStack {
                Button("注册到系统浏览器列表") { model.registerBrowserCandidate() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("在系统设置中选择…") { model.requestDefaultBrowser() }
                    .buttonStyle(.borderedProminent)
            }
            Button("预览选择浮窗") { model.receive([URL(string: "https://example.com")!], applyRules: false) }
                .buttonStyle(.borderless)
            Text("注册不会更改默认浏览器；预览链接由你选好浏览器后打开。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct LoginItemSettingsView: View {
    @ObservedObject var controller: LoginItemController
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("登录时自动启动", isOn: Binding(
                get: { controller.state.toggleIsOn },
                set: { controller.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            Text(controller.state.description).font(.caption).foregroundStyle(.secondary)
            if controller.state == .requiresApproval {
                Button("打开系统登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.borderless)
            }
            if let error = controller.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct BrowserRow: View {
    let browser: BrowserCandidate
    let number: Int
    let selectable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: browser.applicationURL.path))
                    .resizable()
                    .frame(width: 34, height: 34)
                Text(browser.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if selectable && number <= 9 {
                    Text("\(number)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color(nsColor: .separatorColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
                if selectable { Image(systemName: "arrow.up.right").foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectable ? "用 \(browser.name) 打开" : browser.name)
    }
}

final class ChooserPanel: NSPanel {
    var cancelHandler: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { cancelHandler?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelHandler?() }
        else { super.keyDown(with: event) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model = AppModel()
    private var panel: ChooserPanel?
    private var rulesWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        configureStatusItem()
        model.requestPresentation = { [weak self] in self?.presentPanel() }
        model.dismissPresentation = { [weak self] in self?.panel?.orderOut(nil) }
        model.requestRulesPresentation = { [weak self] in self?.showRules() }
        model.refreshBrowsers()
        model.loginItem.refresh()
        if AppLaunchPolicy.shouldShowChooser(hasPendingLink: model.currentRequest != nil) { presentPanel() }
        if CommandLine.arguments.contains("--verify-background") {
            DispatchQueue.main.async {
                let app = NSApplication.shared
                let hasChooser = self.panel != nil
                let passed = app.activationPolicy() == .accessory && self.statusItem != nil && !hasChooser && !app.isActive
                print("background launch: \(passed ? "PASS" : "FAIL"); accessory=\(app.activationPolicy() == .accessory), menuBar=\(self.statusItem != nil), chooser=\(hasChooser), active=\(app.isActive)")
                // AppKit owns internal status-bar windows. They are not app panels.
                for window in app.windows { print("AppKit window: \(type(of: window)), visible=\(window.isVisible)") }
                fflush(stdout)
                if !passed { exit(1) }
                app.terminate(nil)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // receive() presents the chooser itself when a choice is needed (or an
        // error must be shown). Links routed by a rule must not open any window.
        model.receive(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshDefaultStatus()
        model.loginItem.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.isOpening { return false }
        model.cancelCurrent()
        if model.currentRequest == nil { panel?.orderOut(nil) }
        return false
    }

    /// Accessory apps show no menu bar, but AppKit still routes Cmd+X/C/V/A/Z
    /// through the main menu's key equivalents. Without it, text fields can't paste.
    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "DFBrowser")
        item.button?.toolTip = "DFBrowser · 网页链接浏览器选择器"
        let menu = NSMenu()
        menu.delegate = self
        let settings = NSMenuItem(title: "查看浏览器与设置", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let rulesItem = NSMenuItem(title: "网址规则…", action: #selector(showRules), keyEquivalent: "")
        rulesItem.target = self
        menu.addItem(rulesItem)
        let preview = NSMenuItem(title: "预览选择浮窗", action: #selector(showPreview), keyEquivalent: "")
        preview.target = self
        menu.addItem(preview)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "登录时自动启动", action: #selector(toggleLoginAtStartup), keyEquivalent: "")
        login.target = self
        login.tag = 100
        menu.addItem(login)
        let approval = NSMenuItem(title: "打开系统登录项设置", action: #selector(openLoginSettings), keyEquivalent: "")
        approval.target = self
        approval.tag = 101
        approval.isHidden = true
        menu.addItem(approval)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 DFBrowser", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.loginItem.refresh()
        let state = model.loginItem.state
        menu.item(withTag: 100)?.state = state == .enabled ? .on : state == .requiresApproval ? .mixed : .off
        menu.item(withTag: 100)?.title = state == .requiresApproval ? "登录时自动启动（待批准）" : "登录时自动启动"
        menu.item(withTag: 101)?.isHidden = state != .requiresApproval
    }

    @objc private func toggleLoginAtStartup() {
        model.loginItem.refresh()
        model.loginItem.setEnabled(!model.loginItem.state.toggleIsOn)
        if model.loginItem.errorMessage != nil { showSettings() }
    }

    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    @objc private func showSettings() {
        model.refreshBrowsers()
        model.loginItem.refresh()
        presentPanel()
    }

    @objc private func showRules() {
        model.refreshBrowsers()
        // The settings panel floats; hide it so it does not cover the editor.
        if model.currentRequest == nil { panel?.orderOut(nil) }
        if rulesWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 460),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "网址规则"
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentMinSize = NSSize(width: 520, height: 320)
            window.contentView = NSHostingView(rootView: RoutingRulesView(model: model))
            window.center()
            rulesWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        rulesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showPreview() {
        model.receive([URL(string: "https://example.com")!], applyRules: false)
    }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }

    private func presentPanel() {
        if panel == nil {
            let panel = ChooserPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
                                     styleMask: [.titled, .closable],
                                     backing: .buffered, defer: false)
            panel.title = "DFBrowser"
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.delegate = self
            panel.cancelHandler = { [weak self] in self?.model.cancelCurrent() }
            let hosting = NSHostingView(rootView: BrowserChooserView(model: model))
            panel.contentView = hosting
            self.panel = panel
        }
        guard let panel, let contentView = panel.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let fitting = contentView.fittingSize
        if fitting.height > 0 { panel.setContentSize(NSSize(width: 480, height: fitting.height)) }
        // Center on the screen containing the mouse, not always the main display.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        } else { panel.center() }
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

struct RoutingRulesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("网址规则").font(.system(size: 18, weight: .semibold))
                Text("匹配规则的链接会直接用指定浏览器打开，不再弹出选择；从上到下取第一条匹配。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(verbatim: "例：*.google.com 匹配 google.com 及其所有子域名；docs.example.com 只匹配该域名；* 匹配全部链接。点链接时按住 Option 可临时弹出选择。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.rules.isEmpty {
                Text("还没有规则。点击“添加规则”，或在选择浮窗中勾选“以后都直接用所选浏览器打开”。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(model.rules.enumerated()), id: \.element.id) { index, rule in
                            RoutingRuleRow(model: model, rule: rule, isFirst: index == 0,
                                           isLast: index == model.rules.count - 1)
                        }
                    }.padding(.vertical, 1)
                }
                .frame(maxHeight: .infinity)
            }
            if let message = model.ruleTransferMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button { model.addRule() } label: { Label("添加规则", systemImage: "plus") }
                    .disabled(model.browsers.isEmpty)
                Button { model.importRules() } label: { Label("导入…", systemImage: "square.and.arrow.down") }
                Button { model.exportRules() } label: { Label("导出…", systemImage: "square.and.arrow.up") }
                    .disabled(model.rules.isEmpty)
                Spacer()
                Button { model.refreshBrowsers() } label: { Label("刷新浏览器", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct RoutingRuleRow: View {
    @ObservedObject var model: AppModel
    let rule: RoutingRule
    let isFirst: Bool
    let isLast: Bool

    private var isValid: Bool { HostPattern.normalize(rule.pattern) != nil }
    private var isInstalled: Bool { model.browsers.contains { $0.bundleID == rule.bundleID } }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("*.example.com", text: Binding(
                    get: { rule.pattern },
                    set: { value in model.updateRule(rule.id) { $0.pattern = value } }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                if !isValid {
                    Text(rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty ? "请输入域名" : "格式无效，规则不会生效")
                        .font(.caption2).foregroundStyle(.red)
                }
            }
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { rule.bundleID },
                set: { id in
                    let name = model.browsers.first { $0.bundleID == id }?.name ?? id
                    model.updateRule(rule.id) { $0.bundleID = id; $0.browserName = name }
                }
            )) {
                ForEach(model.browsers) { browser in
                    Text(browser.name).tag(browser.bundleID)
                }
                if !isInstalled {
                    Text("\(rule.browserName.isEmpty ? rule.bundleID : rule.browserName)（未安装）").tag(rule.bundleID)
                }
            }
            .labelsHidden()
            .frame(width: 170)
            Button { model.moveRule(rule.id, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(isFirst).help("上移（优先匹配）")
            Button { model.moveRule(rule.id, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(isLast).help("下移")
            Button { model.deleteRule(rule.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("删除规则")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
