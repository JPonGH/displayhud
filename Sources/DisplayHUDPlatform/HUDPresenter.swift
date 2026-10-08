import AppKit
import DisplayHUDCore

@MainActor
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

public struct ScreenTarget: @unchecked Sendable {
    public let display: DisplayIdentifier
    public let screen: NSScreen
    public let name: String

    public init(display: DisplayIdentifier, screen: NSScreen, name: String) {
        self.display = display
        self.screen = screen
        self.name = name
    }
}

@MainActor
public enum ScreenTargetLocator {
    public static func underPointer() -> ScreenTarget? {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main
        guard let screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber
        else {
            return nil
        }
        return ScreenTarget(
            display: DisplayIdentifier(rawValue: number.uint32Value),
            screen: screen,
            name: screen.localizedName
        )
    }
}

@MainActor
public final class HUDPresenter {
    private struct PanelSession {
        let panel: HUDPanel
        let contentView: HUDContentView
    }

    private var session: PanelSession
    private var dismissalTask: Task<Void, Never>?

    var panelForTesting: NSPanel { session.panel }

    public init() {
        session = Self.makePanelSession()
        Self.prewarm(session)
    }

    private static func makePanelSession() -> PanelSession {
        let size = HUDContentView.preferredSize
        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let contentView = HUDContentView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = contentView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.alphaValue = 0
        return PanelSession(panel: panel, contentView: contentView)
    }

    private static func prewarm(_ session: PanelSession) {
        // Allocate the WindowServer surface while fully transparent so the
        // first physical keypress does not pay the panel creation cost.
        session.panel.alphaValue = 0
        session.panel.orderFrontRegardless()
        session.panel.displayIfNeeded()
        session.panel.orderOut(nil)
    }

    @discardableResult
    public func show(_ model: HUDModel, on screen: NSScreen) -> Duration {
        let clock = ContinuousClock()
        let started = clock.now
        dismissalTask?.cancel()

        let activeSession = session
        activeSession.contentView.model = model
        activeSession.contentView.layoutSubtreeIfNeeded()

        let size = HUDContentView.preferredSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        activeSession.panel.setFrame(frame, display: false)
        activeSession.panel.alphaValue = 1
        activeSession.panel.orderFrontRegardless()
        activeSession.panel.displayIfNeeded()

        dismissalTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(900))
                try Task.checkCancellation()
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    activeSession.panel.orderOut(nil)
                    activeSession.panel.alphaValue = 0
                    return
                }

                // A cancellable manual fade prevents an earlier animation's
                // completion handler from hiding a replacement HUD.
                for step in 1...6 {
                    try Task.checkCancellation()
                    activeSession.panel.alphaValue = 1 - CGFloat(step) / 6
                    try await Task.sleep(for: .milliseconds(20))
                }
                try Task.checkCancellation()
                activeSession.panel.orderOut(nil)
                activeSession.panel.alphaValue = 0
            } catch {
                // Cancellation means a newer value replaced this dismissal.
            }
        }
        return started.duration(to: clock.now)
    }

    public func hide() {
        dismissalTask?.cancel()
        dismissalTask = nil
        session.panel.orderOut(nil)
        session.panel.alphaValue = 0
    }

    /// Discards all WindowServer-backed presentation state after a session,
    /// Space, screen, or security-shield transition.
    ///
    /// Reusing a hidden panel after one of those transitions can leave AppKit
    /// waiting on a stale render fence. The replacement is still passive and
    /// does not activate the app or steal focus.
    public func invalidateForLifecycleTransition() {
        dismissalTask?.cancel()
        dismissalTask = nil
        session.panel.orderOut(nil)
        session.panel.alphaValue = 0
        session = Self.makePanelSession()
        Self.prewarm(session)
    }
}
