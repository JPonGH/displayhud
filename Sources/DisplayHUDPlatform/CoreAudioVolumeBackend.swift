import AudioToolbox
import CoreAudio
import DisplayHUDCore

public protocol AudioHardwareAccess: Sendable {
    func defaultOutputDevice() throws -> AudioObjectID
    func readVolume(device: AudioObjectID) throws -> Float32
    func writeVolume(_ value: Float32, device: AudioObjectID) throws
    func isVolumeSettable(device: AudioObjectID) -> Bool
    func readMute(device: AudioObjectID) throws -> Bool
    func writeMute(_ value: Bool, device: AudioObjectID) throws
    func isMuteSettable(device: AudioObjectID) -> Bool
}

public enum CoreAudioControlError: Error, Equatable {
    case status(OSStatus)
    case noDefaultOutput
    case volumeUnavailable
    case volumeNotSettable
    case muteUnavailable
    case muteNotSettable
}

public struct AudioCapabilities: Equatable, Sendable {
    public let device: AudioObjectID
    public let volumeSettable: Bool
    public let muteSettable: Bool

    public init(device: AudioObjectID, volumeSettable: Bool, muteSettable: Bool) {
        self.device = device
        self.volumeSettable = volumeSettable
        self.muteSettable = muteSettable
    }
}

public actor CoreAudioVolumeBackend: VolumeBackend {
    private let access: any AudioHardwareAccess

    public init(access: any AudioHardwareAccess = SystemAudioHardwareAccess()) {
        self.access = access
    }

    public func readAudioState() async throws -> AudioState {
        let device = try access.defaultOutputDevice()
        let scalar = try access.readVolume(device: device)
        let muted = (try? access.readMute(device: device)) ?? false
        return AudioState(
            volume: BasisPoints(scalar: Double(scalar)),
            isMuted: muted,
            isSettable: access.isVolumeSettable(device: device)
        )
    }

    public func setVolume(_ value: BasisPoints) async throws -> AudioState {
        let device = try access.defaultOutputDevice()
        guard access.isVolumeSettable(device: device) else {
            throw CoreAudioControlError.volumeNotSettable
        }

        if access.isMuteSettable(device: device),
           (try? access.readMute(device: device)) == true
        {
            try access.writeMute(false, device: device)
        }
        try access.writeVolume(Float32(value.scalar), device: device)
        return try await readAudioState()
    }

    public func setMuted(_ isMuted: Bool) async throws -> AudioState {
        let device = try access.defaultOutputDevice()
        guard access.isMuteSettable(device: device) else {
            throw CoreAudioControlError.muteNotSettable
        }
        try access.writeMute(isMuted, device: device)
        return try await readAudioState()
    }

    public func capabilities() throws -> AudioCapabilities {
        let device = try access.defaultOutputDevice()
        return AudioCapabilities(
            device: device,
            volumeSettable: access.isVolumeSettable(device: device),
            muteSettable: access.isMuteSettable(device: device)
        )
    }
}

public final class CoreAudioDefaultOutputMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jp.DisplayHUD.audio-monitor")
    private let handler: @Sendable () -> Void
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var block: AudioObjectPropertyListenerBlock?

    public init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        let callback: AudioObjectPropertyListenerBlock = { [handler] _, _ in handler() }
        block = callback
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            callback
        )
    }

    deinit {
        if let block {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                queue,
                block
            )
        }
    }
}

public struct SystemAudioHardwareAccess: AudioHardwareAccess {
    public init() {}

    public func defaultOutputDevice() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ))
        guard device != kAudioObjectUnknown else {
            throw CoreAudioControlError.noDefaultOutput
        }
        return device
    }

    public func readVolume(device: AudioObjectID) throws -> Float32 {
        var address = Self.volumeAddress
        guard AudioObjectHasProperty(device, &address) else {
            throw CoreAudioControlError.volumeUnavailable
        }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value))
        return value
    }

    public func writeVolume(_ value: Float32, device: AudioObjectID) throws {
        var address = Self.volumeAddress
        var mutable = value
        let size = UInt32(MemoryLayout<Float32>.size)
        try check(AudioObjectSetPropertyData(device, &address, 0, nil, size, &mutable))
    }

    public func isVolumeSettable(device: AudioObjectID) -> Bool {
        isSettable(device: device, address: Self.volumeAddress)
    }

    public func readMute(device: AudioObjectID) throws -> Bool {
        var address = Self.muteAddress
        guard AudioObjectHasProperty(device, &address) else {
            throw CoreAudioControlError.muteUnavailable
        }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value))
        return value != 0
    }

    public func writeMute(_ value: Bool, device: AudioObjectID) throws {
        var address = Self.muteAddress
        var mutable: UInt32 = value ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectSetPropertyData(device, &address, 0, nil, size, &mutable))
    }

    public func isMuteSettable(device: AudioObjectID) -> Bool {
        isSettable(device: device, address: Self.muteAddress)
    }

    private func isSettable(
        device: AudioObjectID,
        address original: AudioObjectPropertyAddress
    ) -> Bool {
        var address = original
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr
            && settable.boolValue
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw CoreAudioControlError.status(status) }
    }

    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
}
