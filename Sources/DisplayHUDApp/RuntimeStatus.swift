import DisplayHUDCore
import DisplayHUDPlatform
import Foundation

struct RuntimeStatusSnapshot: Sendable {
    let enabled: Bool
    let eventTapHealth: EventTapHealth
    let brightnessAvailable: Bool
    let betterDisplayDetail: String
    let selectedDisplay: String
    let volumeSettable: Bool
    let muteSettable: Bool
    let audioDetail: String
    let lastConfirmed: String
}

final class RuntimeStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private var eventTapHealth: EventTapHealth = .stopped
    private var brightnessAvailable = false
    private var betterDisplayDetail = "Not checked"
    private var selectedDisplay = "None"
    private var volumeSettable = false
    private var muteSettable = false
    private var audioDetail = "Not checked"
    private var lastConfirmed = "No confirmed action yet"

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func canHandle(_ key: MediaKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // Fail open while the low-level input path is not verified. The event
        // tap may still receive a transition-time event, but it must not swallow
        // that event until its actual enabled state has been confirmed.
        guard enabled, eventTapHealth == .running else { return false }
        switch key {
        case .brightnessUp, .brightnessDown:
            return brightnessAvailable
        case .volumeUp, .volumeDown:
            return volumeSettable
        case .mute:
            return muteSettable
        }
    }

    func snapshot() -> RuntimeStatusSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return RuntimeStatusSnapshot(
            enabled: enabled,
            eventTapHealth: eventTapHealth,
            brightnessAvailable: brightnessAvailable,
            betterDisplayDetail: betterDisplayDetail,
            selectedDisplay: selectedDisplay,
            volumeSettable: volumeSettable,
            muteSettable: muteSettable,
            audioDetail: audioDetail,
            lastConfirmed: lastConfirmed
        )
    }

    func setEnabled(_ value: Bool) {
        mutate { enabled = value }
    }

    func setEventTapHealth(_ value: EventTapHealth) {
        mutate { eventTapHealth = value }
    }

    func setBrightness(available: Bool, detail: String) {
        mutate {
            brightnessAvailable = available
            betterDisplayDetail = detail
        }
    }

    func setSelectedDisplay(_ value: String) {
        mutate { selectedDisplay = value }
    }

    func setAudio(
        volumeSettable: Bool,
        muteSettable: Bool,
        detail: String
    ) {
        mutate {
            self.volumeSettable = volumeSettable
            self.muteSettable = muteSettable
            audioDetail = detail
        }
    }

    func setLastConfirmed(_ value: String) {
        mutate { lastConfirmed = value }
    }

    private func mutate(_ body: () -> Void) {
        lock.lock()
        body()
        lock.unlock()
    }
}
