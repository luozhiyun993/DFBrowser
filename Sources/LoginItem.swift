import Foundation
import ServiceManagement

enum LoginItemState: Equatable {
    case disabled, enabled, requiresApproval, unavailable
    var toggleIsOn: Bool { self == .enabled || self == .requiresApproval }
    var description: String {
        switch self {
        case .disabled: return "已关闭"
        case .enabled: return "已启用，下次登录后在菜单栏运行"
        case .requiresApproval: return "等待系统批准，请到系统登录项中允许 DFBrowser"
        case .unavailable: return "系统暂不可用，请从“应用程序”中的 DFBrowser 启动"
        }
    }
}

@MainActor
protocol LoginItemServicing {
    var state: LoginItemState { get }
    func enable() throws
    func disable() throws
}

@MainActor
final class SystemLoginItemService: LoginItemServicing {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
    func enable() throws { try SMAppService.mainApp.register() }
    func disable() throws { try SMAppService.mainApp.unregister() }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var state: LoginItemState = .disabled
    @Published private(set) var errorMessage: String?
    private let service: LoginItemServicing
    init(service: LoginItemServicing) { self.service = service }
    func refresh() { state = service.state }
    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        refresh()
        do {
            if enabled && !state.toggleIsOn { try service.enable() }
            if !enabled && state.toggleIsOn { try service.disable() }
        } catch {
            errorMessage = "登录启动设置未完成：\(error.localizedDescription)"
        }
        // System state, not a stored preference or optimistic UI, is authoritative.
        refresh()
    }
}

enum AppLaunchPolicy {
    static func shouldShowChooser(hasPendingLink: Bool) -> Bool { hasPendingLink }
}
