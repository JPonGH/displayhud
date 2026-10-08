import CoreGraphics
import AppKit
import Foundation
import Testing
@testable import DisplayHUDPlatform

@Test("Physical media keys are captured at the HID event point")
func physicalMediaKeysUseHIDEventTap() {
    #expect(MediaKeyEventTap.physicalMediaKeyTapLocation == .cghidEventTap)
}

@Test("Tap priority monitor checks often enough to heal late login items")
func tapPriorityMonitorIsResponsive() {
    let policy = TapPriorityPolicy.displayHUD
    #expect(policy.monitorInterval == .milliseconds(500))
}

@Test("Tap priority detects an enabled Display HUD tap that is starved behind another filter")
func tapPriorityDetectsHeadOwnership() {
    let displayHUDPID: pid_t = 101
    let competitorPID: pid_t = 202
    let mediaMask = CGEventMask(1) << 14
    let displayHUD = MediaKeyTapCandidate(
        tappingProcess: displayHUDPID,
        tapPoint: .cghidEventTap,
        options: .defaultTap,
        eventsOfInterest: mediaMask,
        enabled: true
    )
    let competitor = MediaKeyTapCandidate(
        tappingProcess: competitorPID,
        tapPoint: .cghidEventTap,
        options: .defaultTap,
        eventsOfInterest: mediaMask,
        enabled: true
    )
    let staleDisabledDisplayHUD = MediaKeyTapCandidate(
        tappingProcess: displayHUDPID,
        tapPoint: .cghidEventTap,
        options: .defaultTap,
        eventsOfInterest: mediaMask,
        enabled: false
    )
    let passiveListener = MediaKeyTapCandidate(
        tappingProcess: competitorPID,
        tapPoint: .cghidEventTap,
        options: .listenOnly,
        eventsOfInterest: mediaMask,
        enabled: true
    )

    #expect(
        MediaKeyTapPriorityEvaluator.evaluate(
            [displayHUD, competitor],
            processID: displayHUDPID
        ) == .first
    )
    #expect(
        MediaKeyTapPriorityEvaluator.evaluate(
            [competitor, displayHUD],
            processID: displayHUDPID
        ) == .behind
    )
    #expect(
        MediaKeyTapPriorityEvaluator.evaluate(
            [staleDisabledDisplayHUD, competitor, displayHUD],
            processID: displayHUDPID
        ) == .behind
    )
    #expect(
        MediaKeyTapPriorityEvaluator.evaluate(
            [passiveListener, displayHUD],
            processID: displayHUDPID
        ) == .first
    )
    #expect(
        MediaKeyTapPriorityEvaluator.evaluate(
            [competitor],
            processID: displayHUDPID
        ) == .missing
    )
}

private final class EventCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func read() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Test("A disabled event tap clears an interrupted physical key capture")
func disabledEventTapClearsInterruptedCapture() throws {
    let count = EventCount()
    let eventTap = MediaKeyEventTap(
        availability: { _ in true },
        handler: { _ in count.increment() },
        healthHandler: { _ in }
    )
    let down = try #require(auxiliaryMediaEvent(rawKey: 3, state: 10))

    #expect(eventTap.process(type: CGEventType(rawValue: 14)!, event: down))
    #expect(eventTap.process(type: CGEventType(rawValue: 14)!, event: down))
    #expect(count.read() == 1)

    let disabled = try #require(CGEvent(source: nil))
    #expect(!eventTap.process(type: .tapDisabledByTimeout, event: disabled))

    #expect(eventTap.process(type: CGEventType(rawValue: 14)!, event: down))
    #expect(count.read() == 2)
}

@Test("An unavailable boot-time backend fails open and requests recovery once")
func unavailableBackendRequestsRecovery() throws {
    let handled = EventCount()
    let recoveryRequests = EventCount()
    let eventTap = MediaKeyEventTap(
        availability: { _ in false },
        handler: { _ in handled.increment() },
        healthHandler: { _ in },
        availabilityMissHandler: { key in
            if key == .volumeUp {
                recoveryRequests.increment()
            }
        }
    )
    let down = try #require(auxiliaryMediaEvent(rawKey: 0, state: 10))
    let up = try #require(auxiliaryMediaEvent(rawKey: 0, state: 11))

    #expect(!eventTap.process(type: CGEventType(rawValue: 14)!, event: down))
    #expect(!eventTap.process(type: CGEventType(rawValue: 14)!, event: up))
    #expect(handled.read() == 0)
    #expect(recoveryRequests.read() == 1)
}

private func auxiliaryMediaEvent(rawKey: Int, state: Int) -> CGEvent? {
    let data1 = (rawKey << 16) | (state << 8)
    return NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        subtype: 8,
        data1: data1,
        data2: -1
    )?.cgEvent
}
