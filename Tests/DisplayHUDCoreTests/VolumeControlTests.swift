import Foundation
import Testing
@testable import DisplayHUDCore

private actor TestVolumeBackend: VolumeBackend {
    private var state: AudioState

    init(state: AudioState) {
        self.state = state
    }

    func readAudioState() async throws -> AudioState { state }

    func setVolume(_ value: BasisPoints) async throws -> AudioState {
        state = AudioState(volume: value, isMuted: false, isSettable: true)
        return state
    }

    func setMuted(_ isMuted: Bool) async throws -> AudioState {
        state = AudioState(volume: state.volume, isMuted: isMuted, isSettable: true)
        return state
    }

    func forceState(_ newState: AudioState) {
        state = newState
    }
}

private actor SlowVolumeBackend: VolumeBackend {
    private var state: AudioState
    private(set) var writes: [BasisPoints] = []

    init(volume: BasisPoints) {
        state = AudioState(volume: volume, isMuted: false, isSettable: true)
    }

    func readAudioState() async throws -> AudioState { state }

    func setVolume(_ value: BasisPoints) async throws -> AudioState {
        writes.append(value)
        try await Task.sleep(for: .milliseconds(20))
        state = AudioState(volume: value, isMuted: false, isSettable: true)
        return state
    }

    func setMuted(_ isMuted: Bool) async throws -> AudioState {
        state = AudioState(volume: state.volume, isMuted: isMuted, isSettable: true)
        return state
    }
}

@Test("Volume up snaps an externally changed value onto the half-percent grid")
func volumeUpSnapsCurrentValueOntoGrid() async throws {
    let backend = TestVolumeBackend(
        state: AudioState(volume: BasisPoints(percent: 80), isMuted: false, isSettable: true)
    )
    let engine = ControlEngine(
        brightnessBackend: UnavailableBrightnessBackend(),
        volumeBackend: backend
    )
    _ = try await engine.adjustVolume(by: .decrease)
    try await engine.waitUntilIdle(timeout: .seconds(1))
    await backend.forceState(
        AudioState(volume: BasisPoints(percent: 64.3), isMuted: false, isSettable: true)
    )

    _ = try await engine.beginVolumePress()
    let desired = try await engine.adjustVolume(by: .increase)

    #expect(desired.percent == 64.5)
}

@Test("Volume down snaps an externally changed value onto the half-percent grid")
func volumeDownSnapsCurrentValueOntoGrid() async throws {
    let backend = TestVolumeBackend(
        state: AudioState(volume: BasisPoints(percent: 64.3), isMuted: false, isSettable: true)
    )
    let engine = ControlEngine(
        brightnessBackend: UnavailableBrightnessBackend(),
        volumeBackend: backend
    )

    _ = try await engine.beginVolumePress()
    let desired = try await engine.adjustVolume(by: .decrease)

    #expect(desired.percent == 64.0)
}

@Test("Volume changes by exactly one half percent without integer rounding")
func volumeUsesHalfPercentFixedPointSteps() async throws {
    let backend = TestVolumeBackend(
        state: AudioState(
            volume: BasisPoints(percent: 72.0),
            isMuted: false,
            isSettable: true
        )
    )
    let engine = ControlEngine(
        brightnessBackend: UnavailableBrightnessBackend(),
        volumeBackend: backend
    )

    let desired = try await engine.adjustVolume(by: .increase)

    #expect(desired.percent == 72.5)
    try await engine.waitUntilIdle(timeout: .seconds(1))
    #expect(try await backend.readAudioState().volume.percent == 72.5)
}

@Test("Seven rapid on-grid volume presses retain the full 3.5 percent")
func sevenRapidVolumePressesAreNotDropped() async throws {
    let backend = SlowVolumeBackend(volume: BasisPoints(percent: 64.0))
    let engine = ControlEngine(
        brightnessBackend: UnavailableBrightnessBackend(),
        volumeBackend: backend
    )

    var desired = BasisPoints(percent: 64.0)
    for _ in 0..<7 {
        desired = try await engine.adjustVolume(by: .increase)
    }

    #expect(desired.percent == 67.5)
    try await engine.waitUntilIdle(timeout: .seconds(1))
    #expect(try await backend.readAudioState().volume.percent == 67.5)
    let writes = await backend.writes
    #expect(writes.last?.percent == 67.5)
    #expect(writes.count <= 2)
}

@Test("Mute toggles the current system mute state without changing volume")
func muteTogglesWithoutChangingVolume() async throws {
    let backend = TestVolumeBackend(
        state: AudioState(
            volume: BasisPoints(percent: 63.5),
            isMuted: false,
            isSettable: true
        )
    )
    let engine = ControlEngine(
        brightnessBackend: UnavailableBrightnessBackend(),
        volumeBackend: backend
    )

    let muted = try await engine.toggleMute()

    #expect(muted.isMuted)
    #expect(muted.volume.percent == 63.5)
}
