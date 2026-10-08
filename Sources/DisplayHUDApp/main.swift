import AppKit
import ServiceManagement

@MainActor
private func runDisplayHUD() {
    if ProcessInfo.processInfo.arguments.contains("--print-login-item-status") {
        let value: String
        switch SMAppService.mainApp.status {
        case .notRegistered: value = "not-registered"
        case .enabled: value = "enabled"
        case .requiresApproval: value = "requires-approval"
        case .notFound: value = "not-found"
        @unknown default: value = "unknown"
        }
        print("DISPLAY_HUD_LOGIN_ITEM_STATUS=\(value)")
        return
    }

    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}

runDisplayHUD()
