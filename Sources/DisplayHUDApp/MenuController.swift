import AppKit
import DisplayHUDPlatform
import ServiceManagement

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let status: RuntimeStatus
    private let testHUD: () -> Void

    init(status: RuntimeStatus, testHUD: @escaping () -> Void) {
        self.status = status
        self.testHUD = testHUD
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "display.2",
            accessibilityDescription: "Display HUD"
        )
        statusItem.button?.toolTip = "Display HUD"
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        let snapshot = status.snapshot()

        let enabled = item(
            snapshot.enabled ? "Enabled" : "Disabled",
            action: #selector(toggleEnabled)
        )
        enabled.state = snapshot.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(.separator())

        menu.addItem(informational("Input permission: \(permissionText(snapshot.eventTapHealth))"))
        menu.addItem(informational("Event tap: \(eventTapText(snapshot.eventTapHealth))"))
        menu.addItem(informational("BetterDisplay: \(snapshot.betterDisplayDetail)"))
        menu.addItem(informational("Selected display: \(snapshot.selectedDisplay)"))
        menu.addItem(informational("Audio: \(snapshot.audioDetail)"))
        menu.addItem(informational("Last confirmed: \(snapshot.lastConfirmed)"))
        menu.addItem(.separator())

        let loginStatus = SMAppService.mainApp.status
        let loginTitle = loginStatus == .requiresApproval
            ? "Launch at Login (approval required)"
            : "Launch at Login"
        let login = item(loginTitle, action: #selector(toggleLaunchAtLogin))
        login.state = loginStatus == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Test HUD (no value change)", action: #selector(runHUDTest)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Display HUD", action: #selector(quit)))
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: "")
        value.target = self
        return value
    }

    private func informational(_ title: String) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        value.isEnabled = false
        return value
    }

    @objc private func toggleEnabled() {
        let next = !status.snapshot().enabled
        status.setEnabled(next)
        UserDefaults.standard.set(next, forKey: "DisplayHUDEnabled")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            status.setLastConfirmed("Launch at Login failed: \(error)")
        }
    }

    @objc private func runHUDTest() {
        testHUD()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func permissionText(_ health: EventTapHealth) -> String {
        health == .permissionRequired ? "Required" : "Granted"
    }

    private func eventTapText(_ health: EventTapHealth) -> String {
        switch health {
        case .stopped: "Stopped"
        case .permissionRequired: "Waiting for Accessibility"
        case .running: "Healthy"
        case .creationFailed: "Creation failed"
        case .disabled: "Disabled"
        }
    }
}
