import Foundation

/// Controls the inexpensive in-process check that keeps Display HUD's media
/// filter ahead of other login-item filters.
///
/// `NSWorkspace.didLaunchApplicationNotification` is not emitted reliably by
/// every accessory application. Inspecting Core Graphics' actual tap order is
/// therefore the only dependable way to detect an enabled-but-starved tap.
public struct TapPriorityPolicy: Sendable {
    public let monitorInterval: Duration

    public init(monitorInterval: Duration) {
        self.monitorInterval = monitorInterval
    }

    public static let displayHUD = TapPriorityPolicy(
        monitorInterval: .milliseconds(500)
    )
}
