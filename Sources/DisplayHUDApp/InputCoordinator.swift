import AppKit
import DisplayHUDCore
import DisplayHUDPlatform
import Foundation

@MainActor
final class InputCoordinator {
    private let engine: ControlEngine
    private let audioBackend: CoreAudioVolumeBackend
    private let presenter: HUDPresenter
    private let status: RuntimeStatus
    private let recoveryHandler: (MediaKey) -> Void
    private var activeKey: MediaKey?
    private var activeTarget: ScreenTarget?
    private var pressGeneration: UInt64 = 0

    private lazy var repeater = HoldRepeater { [weak self] key in
        guard let self else { return }
        await self.performStep(for: key)
    }

    init(
        engine: ControlEngine,
        audioBackend: CoreAudioVolumeBackend,
        presenter: HUDPresenter,
        status: RuntimeStatus,
        recoveryHandler: @escaping (MediaKey) -> Void = { _ in }
    ) {
        self.engine = engine
        self.audioBackend = audioBackend
        self.presenter = presenter
        self.status = status
        self.recoveryHandler = recoveryHandler
    }

    func handle(_ event: MediaKeyEvent) async {
        switch event.phase {
        case .down:
            await begin(event.key)
        case .up:
            await end(event.key)
        }
    }

    func showTestHUD() {
        guard let target = ScreenTargetLocator.underPointer() else { return }
        status.setSelectedDisplay(target.name)
        presenter.show(
            HUDModel(kind: .brightness, value: BasisPoints(percent: 50), isMuted: false),
            on: target.screen
        )
    }

    /// Cancels a possibly interrupted hold and discards stale presentation
    /// state before input resumes after lock, sleep, Space, display, or app-lock
    /// shield transitions.
    func resetForLifecycleTransition() async {
        pressGeneration &+= 1
        activeKey = nil
        activeTarget = nil
        presenter.invalidateForLifecycleTransition()
        await repeater.cancel()
    }

    private func begin(_ key: MediaKey) async {
        pressGeneration &+= 1
        let generation = pressGeneration
        activeKey = key
        let pressTarget = ScreenTargetLocator.underPointer()
        activeTarget = pressTarget
        if let pressTarget {
            status.setSelectedDisplay(pressTarget.name)
        }

        if key == .mute {
            await performMute()
            return
        }

        do {
            switch key {
            case .brightnessUp, .brightnessDown:
                guard let pressTarget else { return }
                _ = try await engine.beginBrightnessPress(on: pressTarget.display)
            case .volumeUp, .volumeDown:
                _ = try await engine.beginVolumePress()
            case .mute:
                return
            }
        } catch {
            recordFailure(for: key, error: error)
            return
        }

        if generation == pressGeneration, activeKey == key {
            await repeater.keyDown(key, isSystemRepeat: false)
        } else {
            // A very fast tap can release while the backend read is in flight.
            // Use this press's captured target instead of mutable global state so
            // neither an early release nor a newer press can erase the intent.
            await performStep(for: key, on: pressTarget)
            await finalize(key, target: pressTarget)
        }
    }

    private func end(_ key: MediaKey) async {
        if activeKey == key {
            activeKey = nil
        }
        let target = activeTarget
        await repeater.keyUp(key)
        await finalize(key, target: target)
        if activeKey == nil {
            activeTarget = nil
        }
    }

    private func performStep(for key: MediaKey) async {
        await performStep(for: key, on: activeTarget)
    }

    private func performStep(for key: MediaKey, on target: ScreenTarget?) async {
        guard let target else { return }
        do {
            switch key {
            case .brightnessUp:
                let desired = try await engine.adjustBrightness(on: target.display, by: .increase)
                presenter.show(HUDModel(kind: .brightness, value: desired, isMuted: false), on: target.screen)
            case .brightnessDown:
                let desired = try await engine.adjustBrightness(on: target.display, by: .decrease)
                presenter.show(HUDModel(kind: .brightness, value: desired, isMuted: false), on: target.screen)
            case .volumeUp:
                let desired = try await engine.adjustVolume(by: .increase)
                presenter.show(HUDModel(kind: .volume, value: desired, isMuted: false), on: target.screen)
            case .volumeDown:
                let desired = try await engine.adjustVolume(by: .decrease)
                presenter.show(HUDModel(kind: .volume, value: desired, isMuted: false), on: target.screen)
            case .mute:
                break
            }
        } catch {
            recordFailure(for: key, error: error)
        }
    }

    private func performMute() async {
        guard let target = activeTarget else { return }
        do {
            let state = try await engine.toggleMute()
            presenter.show(
                HUDModel(kind: .mute, value: state.volume, isMuted: state.isMuted),
                on: target.screen
            )
            status.setLastConfirmed(
                "Audio \(state.isMuted ? "muted" : "unmuted") • \(Self.timestamp())"
            )
        } catch {
            recordFailure(for: .mute, error: error)
        }
    }

    private func finalize(_ key: MediaKey, target: ScreenTarget?) async {
        do {
            try await engine.waitUntilIdle(timeout: .seconds(1))
            switch key {
            case .brightnessUp, .brightnessDown:
                guard let target,
                      let snapshot = await engine.brightnessSnapshot(for: target.display)
                else {
                    status.setBrightness(available: false, detail: "Last request failed")
                    return
                }
                status.setBrightness(available: true, detail: "Connected")
                status.setLastConfirmed(
                    String(
                        format: "Brightness %.1f%% on %@ • %@",
                        locale: Locale(identifier: "en_US_POSIX"),
                        snapshot.confirmed.percent,
                        target.name,
                        Self.timestamp()
                    )
                )
            case .volumeUp, .volumeDown:
                let state = try await audioBackend.readAudioState()
                status.setLastConfirmed(
                    String(
                        format: "Volume %.1f%% • %@",
                        locale: Locale(identifier: "en_US_POSIX"),
                        state.volume.percent,
                        Self.timestamp()
                    )
                )
            case .mute:
                break
            }
        } catch {
            recordFailure(for: key, error: error)
        }
    }

    private func recordFailure(for key: MediaKey, error: Error) {
        switch key {
        case .brightnessUp, .brightnessDown:
            status.setBrightness(available: false, detail: "Unavailable: \(error)")
        case .volumeUp, .volumeDown, .mute:
            status.setAudio(volumeSettable: false, muteSettable: false, detail: "Unavailable: \(error)")
        }
        status.setLastConfirmed("Action failed • \(Self.timestamp())")
        recoveryHandler(key)
    }

    private static func timestamp() -> String {
        Date.now.formatted(date: .omitted, time: .standard)
    }
}
