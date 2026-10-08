import Foundation

/// Retries a transient availability probe according to a finite schedule.
/// The first attempt is immediate; each delay precedes one additional attempt.
public struct BoundedAvailabilityRecovery: Sendable {
    private let retryDelays: [Duration]

    public init(retryDelays: [Duration]) {
        self.retryDelays = retryDelays
    }

    public func run(
        _ probe: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        if await probe() {
            return true
        }

        for delay in retryDelays {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return false
            }
            if await probe() {
                return true
            }
        }
        return false
    }
}

/// Fixed-point percentage storage. One raw unit is 0.01 percentage points.
public struct BasisPoints: Equatable, Comparable, Hashable, Sendable {
    public static let minimum = BasisPoints(rawValue: 0)
    public static let maximum = BasisPoints(rawValue: 10_000)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = min(max(rawValue, 0), 10_000)
    }

    public init(percent: Double) {
        self.init(rawValue: Int((percent * 100).rounded()))
    }

    public init(scalar: Double) {
        self.init(rawValue: Int((scalar * 10_000).rounded()))
    }

    public var percent: Double { Double(rawValue) / 100 }
    public var scalar: Double { Double(rawValue) / 10_000 }

    public func stepped(by delta: Int) -> BasisPoints {
        BasisPoints(rawValue: rawValue + delta)
    }

    /// Advances in the requested direction to the next value on the 0.5% grid.
    /// An off-grid value moves by no more than one half-percent and never moves
    /// opposite the user's keypress.
    public func nextHalfPercent(in direction: StepDirection) -> BasisPoints {
        let step = 50
        let remainder = rawValue % step

        switch direction {
        case .increase:
            return stepped(by: remainder == 0 ? step : step - remainder)
        case .decrease:
            return stepped(by: remainder == 0 ? -step : -remainder)
        }
    }

    public static func < (lhs: BasisPoints, rhs: BasisPoints) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct DisplayIdentifier: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

public enum StepDirection: Sendable {
    case increase
    case decrease
}

public enum MediaKey: Equatable, Hashable, Sendable {
    case brightnessUp
    case brightnessDown
    case volumeUp
    case volumeDown
    case mute
}

public enum MediaKeyRoutingDecision: Equatable, Sendable {
    case passThrough
    case consumeAndDispatch
    case consumeWithoutDispatch
}

/// Pairs swallowed key-down events with their key-up event and otherwise fails open.
public struct MediaKeyCaptureSession: Sendable {
    private var captured: Set<MediaKey> = []

    public init() {}

    /// Ends every in-progress capture after an input-delivery interruption.
    ///
    /// A session lock, secure-input transition, disabled event tap, or display
    /// reconfiguration can prevent the matching key-up event from reaching the
    /// app. Keeping that stale key-down would make every later press of the same
    /// media key look like a duplicate and silently swallow it forever.
    public mutating func reset() {
        captured.removeAll(keepingCapacity: true)
    }

    public mutating func route(
        _ event: MediaKeyEvent,
        backendAvailable: Bool
    ) -> MediaKeyRoutingDecision {
        switch event.phase {
        case .down:
            if captured.contains(event.key) {
                return .consumeWithoutDispatch
            }
            guard backendAvailable else { return .passThrough }
            captured.insert(event.key)
            return .consumeAndDispatch

        case .up:
            guard captured.remove(event.key) != nil else { return .passThrough }
            return .consumeAndDispatch
        }
    }
}

public enum KeyPhase: Equatable, Sendable {
    case down
    case up
}

public struct MediaKeyEvent: Equatable, Sendable {
    public let key: MediaKey
    public let phase: KeyPhase
    public let isRepeat: Bool

    public init(key: MediaKey, phase: KeyPhase, isRepeat: Bool) {
        self.key = key
        self.phase = phase
        self.isRepeat = isRepeat
    }
}

public enum MediaKeyEventDecoder {
    /// Decodes `NX_SUBTYPE_AUX_CONTROL_BUTTONS` event data without depending on AppKit.
    public static func decode(subtype: Int64, data1: Int64) -> MediaKeyEvent? {
        guard subtype == 8 else { return nil }
        let bits = UInt32(truncatingIfNeeded: data1)
        let rawKey = Int((bits >> 16) & 0xffff)
        let state = Int((bits >> 8) & 0xff)

        let key: MediaKey
        switch rawKey {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        case 7: key = .mute
        default: return nil
        }

        let phase: KeyPhase
        switch state {
        case 10: phase = .down
        case 11: phase = .up
        default: return nil
        }

        return MediaKeyEvent(
            key: key,
            phase: phase,
            isRepeat: (bits & 0x1) == 1
        )
    }
}

/// Converts one physical key-down/key-up pair into deterministic hold repetition.
public actor HoldRepeater {
    public typealias Action = @Sendable (MediaKey) async -> Void

    private let initialDelay: Duration
    private let repeatInterval: Duration
    private let action: Action
    private var activeKey: MediaKey?
    private var repeatTask: Task<Void, Never>?

    public init(
        initialDelay: Duration = .milliseconds(250),
        repeatInterval: Duration = .milliseconds(60),
        action: @escaping Action
    ) {
        self.initialDelay = initialDelay
        self.repeatInterval = repeatInterval
        self.action = action
    }

    public func keyDown(_ key: MediaKey, isSystemRepeat: Bool) async {
        guard !isSystemRepeat else { return }
        repeatTask?.cancel()
        activeKey = key
        await action(key)
        guard activeKey == key else { return }

        let delay = initialDelay
        let interval = repeatInterval
        repeatTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                while !Task.isCancelled {
                    guard let self, await self.isActive(key) else { return }
                    await self.fire(key)
                    try await Task.sleep(for: interval)
                }
            } catch {
                // Cancellation is the normal key-up path.
            }
        }
    }

    public func keyUp(_ key: MediaKey) {
        guard activeKey == key else { return }
        activeKey = nil
        repeatTask?.cancel()
        repeatTask = nil
    }

    public func cancel() {
        activeKey = nil
        repeatTask?.cancel()
        repeatTask = nil
    }

    private func isActive(_ key: MediaKey) -> Bool {
        activeKey == key
    }

    private func fire(_ key: MediaKey) async {
        guard activeKey == key else { return }
        await action(key)
    }
}

public protocol BrightnessBackend: Sendable {
    func readBrightness(for display: DisplayIdentifier) async throws -> BasisPoints
    func setBrightness(
        _ value: BasisPoints,
        for display: DisplayIdentifier
    ) async throws -> BasisPoints
}

public struct AudioState: Equatable, Sendable {
    public var volume: BasisPoints
    public var isMuted: Bool
    public var isSettable: Bool

    public init(volume: BasisPoints, isMuted: Bool, isSettable: Bool) {
        self.volume = volume
        self.isMuted = isMuted
        self.isSettable = isSettable
    }
}

public protocol VolumeBackend: Sendable {
    func readAudioState() async throws -> AudioState
    func setVolume(_ value: BasisPoints) async throws -> AudioState
    func setMuted(_ isMuted: Bool) async throws -> AudioState
}

public enum ControlBackendError: Error, Equatable {
    case unavailable
    case unsupported
}

public struct UnavailableBrightnessBackend: BrightnessBackend {
    public init() {}

    public func readBrightness(for display: DisplayIdentifier) async throws -> BasisPoints {
        throw ControlBackendError.unavailable
    }

    public func setBrightness(
        _ value: BasisPoints,
        for display: DisplayIdentifier
    ) async throws -> BasisPoints {
        throw ControlBackendError.unavailable
    }
}

public enum ControlEngineError: Error, Equatable {
    case timedOutWaitingForIdle
}

public struct ValueSnapshot: Equatable, Sendable {
    public let desired: BasisPoints
    public let confirmed: BasisPoints
    public let isRunning: Bool

    public init(desired: BasisPoints, confirmed: BasisPoints, isRunning: Bool) {
        self.desired = desired
        self.confirmed = confirmed
        self.isRunning = isRunning
    }
}

/// Owns absolute desired values and serializes writes independently per display.
public actor ControlEngine {
    private struct BrightnessLane {
        var confirmed: BasisPoints
        var desired: BasisPoints
        var generation: UInt64 = 0
        var isRunning = false
    }

    private let brightnessBackend: any BrightnessBackend
    private let volumeBackend: (any VolumeBackend)?
    private var brightnessLanes: [DisplayIdentifier: BrightnessLane] = [:]
    private var volumeLane: BrightnessLane?

    public init(
        brightnessBackend: any BrightnessBackend,
        volumeBackend: (any VolumeBackend)? = nil
    ) {
        self.brightnessBackend = brightnessBackend
        self.volumeBackend = volumeBackend
    }

    @discardableResult
    public func beginBrightnessPress(
        on display: DisplayIdentifier
    ) async throws -> BasisPoints {
        if let lane = brightnessLanes[display], lane.isRunning {
            return lane.desired
        }
        let current = try await brightnessBackend.readBrightness(for: display)
        brightnessLanes[display] = BrightnessLane(
            confirmed: current,
            desired: current
        )
        return current
    }

    @discardableResult
    public func beginVolumePress() async throws -> AudioState {
        guard let volumeBackend else { throw ControlBackendError.unavailable }
        if let lane = volumeLane, lane.isRunning {
            return AudioState(
                volume: lane.desired,
                isMuted: false,
                isSettable: true
            )
        }
        let state = try await volumeBackend.readAudioState()
        guard state.isSettable else { throw ControlBackendError.unsupported }
        volumeLane = BrightnessLane(
            confirmed: state.volume,
            desired: state.volume
        )
        return state
    }

    @discardableResult
    public func adjustBrightness(
        on display: DisplayIdentifier,
        by direction: StepDirection
    ) async throws -> BasisPoints {
        if brightnessLanes[display] == nil {
            let current = try await brightnessBackend.readBrightness(for: display)
            if brightnessLanes[display] == nil {
                brightnessLanes[display] = BrightnessLane(
                    confirmed: current,
                    desired: current
                )
            }
        }

        var lane = brightnessLanes[display]!
        lane.desired = lane.desired.nextHalfPercent(in: direction)
        lane.generation &+= 1
        let desired = lane.desired
        let shouldStart = !lane.isRunning
        if shouldStart {
            lane.isRunning = true
        }
        brightnessLanes[display] = lane

        if shouldStart {
            Task { await self.drainBrightnessLane(for: display) }
        }

        return desired
    }

    @discardableResult
    public func adjustVolume(by direction: StepDirection) async throws -> BasisPoints {
        guard let volumeBackend else { throw ControlBackendError.unavailable }
        if volumeLane == nil {
            let state = try await volumeBackend.readAudioState()
            guard state.isSettable else { throw ControlBackendError.unsupported }
            if volumeLane == nil {
                volumeLane = BrightnessLane(
                    confirmed: state.volume,
                    desired: state.volume
                )
            }
        }

        var lane = volumeLane!
        lane.desired = lane.desired.nextHalfPercent(in: direction)
        lane.generation &+= 1
        let desired = lane.desired
        let shouldStart = !lane.isRunning
        if shouldStart {
            lane.isRunning = true
        }
        volumeLane = lane

        if shouldStart {
            Task { await self.drainVolumeLane() }
        }

        return desired
    }

    public func toggleMute() async throws -> AudioState {
        guard let volumeBackend else { throw ControlBackendError.unavailable }
        while volumeLane?.isRunning == true {
            try await Task.sleep(for: .milliseconds(1))
        }

        let current = try await volumeBackend.readAudioState()
        guard current.isSettable else { throw ControlBackendError.unsupported }
        let confirmed = try await volumeBackend.setMuted(!current.isMuted)
        volumeLane = BrightnessLane(
            confirmed: confirmed.volume,
            desired: confirmed.volume
        )
        return confirmed
    }

    public func brightnessSnapshot(for display: DisplayIdentifier) -> ValueSnapshot? {
        brightnessLanes[display].map {
            ValueSnapshot(
                desired: $0.desired,
                confirmed: $0.confirmed,
                isRunning: $0.isRunning
            )
        }
    }

    public func volumeSnapshot() -> ValueSnapshot? {
        volumeLane.map {
            ValueSnapshot(
                desired: $0.desired,
                confirmed: $0.confirmed,
                isRunning: $0.isRunning
            )
        }
    }

    public func waitUntilIdle(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while brightnessLanes.values.contains(where: \.isRunning)
            || volumeLane?.isRunning == true
        {
            guard clock.now < deadline else {
                throw ControlEngineError.timedOutWaitingForIdle
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private func drainBrightnessLane(for display: DisplayIdentifier) async {
        while let lane = brightnessLanes[display], lane.isRunning {
            let target = lane.desired
            let requestGeneration = lane.generation

            do {
                let confirmed = try await brightnessBackend.setBrightness(target, for: display)
                guard var current = brightnessLanes[display] else { return }
                current.confirmed = confirmed

                if current.generation == requestGeneration {
                    // Reconcile an adapter-quantized readback without blindly retrying.
                    current.desired = confirmed
                    current.isRunning = false
                    brightnessLanes[display] = current
                    return
                }

                brightnessLanes[display] = current
            } catch {
                brightnessLanes.removeValue(forKey: display)
                return
            }
        }
    }

    private func drainVolumeLane() async {
        guard let volumeBackend else { return }

        while let lane = volumeLane, lane.isRunning {
            let target = lane.desired
            let requestGeneration = lane.generation

            do {
                let state = try await volumeBackend.setVolume(target)
                guard var current = volumeLane else { return }
                current.confirmed = state.volume

                if current.generation == requestGeneration {
                    current.desired = state.volume
                    current.isRunning = false
                    volumeLane = current
                    return
                }

                volumeLane = current
            } catch {
                volumeLane = nil
                return
            }
        }
    }
}
