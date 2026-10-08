import CoreAudio
import Testing
@testable import DisplayHUDPlatform

private final class FakeAudioHardwareAccess: @unchecked Sendable, AudioHardwareAccess {
    var device: AudioObjectID = 1
    var volumes: [AudioObjectID: Float32] = [1: 0.723, 2: 0.410]
    var muted: [AudioObjectID: Bool] = [1: true, 2: false]
    var volumeSettable = true
    var muteSettable = true

    func defaultOutputDevice() throws -> AudioObjectID { device }
    func readVolume(device: AudioObjectID) throws -> Float32 { volumes[device] ?? 0 }
    func writeVolume(_ value: Float32, device: AudioObjectID) throws { volumes[device] = value }
    func isVolumeSettable(device: AudioObjectID) -> Bool { volumeSettable }
    func readMute(device: AudioObjectID) throws -> Bool { muted[device] ?? false }
    func writeMute(_ value: Bool, device: AudioObjectID) throws { muted[device] = value }
    func isMuteSettable(device: AudioObjectID) -> Bool { muteSettable }
}

@Test("CoreAudio writes half-percent volume to the current output device")
func coreAudioUsesCurrentDeviceAndFractionalVolume() async throws {
    let access = FakeAudioHardwareAccess()
    let backend = CoreAudioVolumeBackend(access: access)

    access.device = 2
    let state = try await backend.setVolume(BasisPoints(percent: 41.5))

    #expect(state.volume.percent == 41.5)
    #expect(access.volumes[1] == 0.723)
    #expect(access.volumes[2] == 0.415)
    #expect(access.muted[2] == false)
}
