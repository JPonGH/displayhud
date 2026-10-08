import ApplicationServices
import AppKit
import CoreGraphics
import DisplayHUDCore
import Foundation

public enum EventTapHealth: Equatable, Sendable {
    case stopped
    case permissionRequired
    case running
    case creationFailed
    case disabled
}

enum MediaKeyTapPriority: Equatable, Sendable {
    case first
    case behind
    case missing
}

struct MediaKeyTapCandidate {
    let tappingProcess: pid_t
    let tapPoint: CGEventTapLocation
    let options: CGEventTapOptions
    let eventsOfInterest: CGEventMask
    let enabled: Bool
}

enum MediaKeyTapPriorityEvaluator {
    private static let mediaMask = CGEventMask(1) << 14

    static func evaluate(
        _ candidates: [MediaKeyTapCandidate],
        processID: pid_t
    ) -> MediaKeyTapPriority {
        let consumingHIDMediaTaps = candidates.filter {
            $0.tapPoint == .cghidEventTap
                && $0.options == .defaultTap
                && $0.enabled
                && $0.eventsOfInterest & mediaMask != 0
        }
        guard let ownIndex = consumingHIDMediaTaps.firstIndex(where: {
            $0.tappingProcess == processID
        }) else {
            return .missing
        }
        return ownIndex == consumingHIDMediaTaps.startIndex ? .first : .behind
    }
}

public final class MediaKeyEventTap: @unchecked Sendable {
    public static let physicalMediaKeyTapLocation = CGEventTapLocation.cghidEventTap

    public typealias Availability = @Sendable (MediaKey) -> Bool
    public typealias Handler = @Sendable (MediaKeyEvent) -> Void
    public typealias HealthHandler = @Sendable (EventTapHealth) -> Void
    public typealias AvailabilityMissHandler = @Sendable (MediaKey) -> Void

    private let availability: Availability
    private let handler: Handler
    private let healthHandler: HealthHandler
    private let availabilityMissHandler: AvailabilityMissHandler
    private let lock = NSLock()
    private var captureSession = MediaKeyCaptureSession()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    @MainActor private var recoveryTask: Task<Void, Never>?

    public init(
        availability: @escaping Availability,
        handler: @escaping Handler,
        healthHandler: @escaping HealthHandler,
        availabilityMissHandler: @escaping AvailabilityMissHandler = { _ in }
    ) {
        self.availability = availability
        self.handler = handler
        self.healthHandler = healthHandler
        self.availabilityMissHandler = availabilityMissHandler
    }

    @MainActor
    @discardableResult
    public func start(promptForAccessibility: Bool = true) -> Bool {
        recoveryTask?.cancel()
        recoveryTask = nil

        if let tap {
            let enabled = CGEvent.tapIsEnabled(tap: tap)
            healthHandler(enabled ? .running : .disabled)
            if !enabled {
                scheduleVerifiedRecovery()
            }
            return enabled
        }

        let trusted: Bool
        if promptForAccessibility {
            trusted = AXIsProcessTrustedWithOptions([
                "AXTrustedCheckOptionPrompt": true,
            ] as CFDictionary)
        } else {
            trusted = AXIsProcessTrusted()
        }
        guard trusted else {
            healthHandler(.permissionRequired)
            return false
        }

        let systemDefined = CGEventType(rawValue: 14)!
        let mask = CGEventMask(1) << systemDefined.rawValue
        guard let newTap = CGEvent.tapCreate(
            tap: Self.physicalMediaKeyTapLocation,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: displayHUDEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            healthHandler(.creationFailed)
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        tap = newTap
        runLoopSource = source
        CGEvent.tapEnable(tap: newTap, enable: true)
        let enabled = CGEvent.tapIsEnabled(tap: newTap)
        healthHandler(enabled ? .running : .disabled)
        if !enabled {
            scheduleVerifiedRecovery()
        }
        return enabled
    }

    @MainActor
    public func stop() {
        recoveryTask?.cancel()
        recoveryTask = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
        resetCaptureSession()
        healthHandler(.stopped)
    }

    /// Removes and creates a new HID tap at `headInsertEventTap`.
    ///
    /// Merely enabling an existing tap does not change its ordering. Login
    /// items such as Supercharge can launch later and insert a consuming tap
    /// ahead of Display HUD, leaving this tap enabled but unable to receive the
    /// media event. Recreating the tap is the public Core Graphics mechanism
    /// that re-establishes head priority without restarting the application.
    @MainActor
    @discardableResult
    public func recreateAtHead() -> Bool {
        stop()
        return start(promptForAccessibility: false)
    }

    /// Clears state that may have lost its matching key-up before a session,
    /// screen, Space, or security-shield transition.
    @MainActor
    public func prepareForLifecycleTransition() {
        recoveryTask?.cancel()
        recoveryTask = nil
        resetCaptureSession()
        if tap != nil {
            healthHandler(.disabled)
        }
    }

    /// Verifies and, if needed, finitely re-enables the existing event tap.
    /// This never launches another process and never creates a recurring loop.
    @MainActor
    public func recoverAfterLifecycleTransition() {
        resetCaptureSession()
        guard tap != nil else {
            _ = start(promptForAccessibility: false)
            return
        }
        scheduleVerifiedRecovery()
    }

    @MainActor
    public func isActuallyEnabled() -> Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Returns whether this process owns the first enabled, consuming HID tap
    /// interested in media-key events. `nil` means Core Graphics could not
    /// provide a tap list, so callers should leave the existing tap untouched.
    public func hasHeadPriority(processID: pid_t = getpid()) -> Bool? {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return false }

        var taps = Array(repeating: CGEventTapInformation(), count: Int(count))
        let result = taps.withUnsafeMutableBufferPointer {
            CGGetEventTapList(count, $0.baseAddress, &count)
        }
        guard result == .success else { return nil }

        let candidates = taps.prefix(Int(count)).map {
            MediaKeyTapCandidate(
                tappingProcess: $0.tappingProcess,
                tapPoint: $0.tapPoint,
                options: $0.options,
                eventsOfInterest: $0.eventsOfInterest,
                enabled: $0.enabled
            )
        }
        return MediaKeyTapPriorityEvaluator.evaluate(
            candidates,
            processID: processID
        ) == .first
    }

    func process(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Disabled taps can lose the key-up that pairs with an earlier
            // swallowed key-down. Reset synchronously before any recovery.
            resetCaptureSession()
            healthHandler(.disabled)
            Task { @MainActor [weak self] in
                self?.scheduleVerifiedRecovery()
            }
            return false
        }

        let modifierMask: CGEventFlags = [
            .maskCommand,
            .maskControl,
            .maskAlternate,
            .maskShift,
        ]
        guard event.flags.intersection(modifierMask).isEmpty,
              let appKitEvent = NSEvent(cgEvent: event),
              let mediaEvent = MediaKeyEventDecoder.decode(
                subtype: Int64(appKitEvent.subtype.rawValue),
                data1: Int64(appKitEvent.data1)
              )
        else {
            return false
        }

        let backendAvailable = availability(mediaEvent.key)
        if mediaEvent.phase == .down,
           !mediaEvent.isRepeat,
           !backendAvailable
        {
            // A login-time probe can fail before a backend has finished
            // initializing without producing a later system notification.
            // Preserve fail-open behavior for this press, but ask the app to
            // refresh the stale capability instead of remaining inert forever.
            availabilityMissHandler(mediaEvent.key)
        }

        lock.lock()
        let decision = captureSession.route(
            mediaEvent,
            backendAvailable: backendAvailable
        )
        lock.unlock()

        switch decision {
        case .passThrough:
            return false
        case .consumeWithoutDispatch:
            return true
        case .consumeAndDispatch:
            handler(mediaEvent)
            return true
        }
    }

    private func resetCaptureSession() {
        lock.lock()
        captureSession.reset()
        lock.unlock()
    }

    @MainActor
    private func scheduleVerifiedRecovery() {
        guard tap != nil else { return }
        recoveryTask?.cancel()
        healthHandler(.disabled)
        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let delays: [Duration] = [
                .zero,
                .milliseconds(50),
                .milliseconds(150),
                .milliseconds(300),
                .milliseconds(750),
                .milliseconds(1_500),
                .seconds(3),
            ]

            for delay in delays {
                do {
                    if delay != .zero {
                        try await Task.sleep(for: delay)
                    }
                    try Task.checkCancellation()
                } catch {
                    return
                }

                guard let tap = self.tap else { return }
                CGEvent.tapEnable(tap: tap, enable: true)
                if CGEvent.tapIsEnabled(tap: tap) {
                    self.healthHandler(.running)
                    self.recoveryTask = nil
                    return
                }
            }

            self.healthHandler(.disabled)
            self.recoveryTask = nil
        }
    }
}

private func displayHUDEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let owner = Unmanaged<MediaKeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return owner.process(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
