import Foundation
import Testing
@testable import DisplayHUDCore

private actor SlowBrightnessBackend: BrightnessBackend {
    private var current: BasisPoints
    private(set) var writes: [BasisPoints] = []

    init(current: BasisPoints) {
        self.current = current
    }

    func readBrightness(for display: DisplayIdentifier) async throws -> BasisPoints {
        current
    }

    func setBrightness(
        _ value: BasisPoints,
        for display: DisplayIdentifier
    ) async throws -> BasisPoints {
        writes.append(value)
        try await Task.sleep(for: .milliseconds(20))
        current = value
        return current
    }

    func forceCurrent(_ value: BasisPoints) {
        current = value
    }
}

@Test("Brightness up snaps an externally changed value onto the half-percent grid")
func brightnessUpSnapsStaleValueOntoGrid() async throws {
    let backend = SlowBrightnessBackend(current: BasisPoints(percent: 50.0))
    let engine = ControlEngine(brightnessBackend: backend)
    let display = DisplayIdentifier(rawValue: 4)

    _ = try await engine.adjustBrightness(on: display, by: .increase)
    try await engine.waitUntilIdle(timeout: .seconds(1))
    await backend.forceCurrent(BasisPoints(percent: 37.3))

    _ = try await engine.beginBrightnessPress(on: display)
    let desired = try await engine.adjustBrightness(on: display, by: .increase)

    #expect(desired.percent == 37.5)
}

@Test("Brightness down snaps an externally changed value onto the half-percent grid")
func brightnessDownSnapsStaleValueOntoGrid() async throws {
    let backend = SlowBrightnessBackend(current: BasisPoints(percent: 37.3))
    let engine = ControlEngine(brightnessBackend: backend)
    let display = DisplayIdentifier(rawValue: 4)

    _ = try await engine.beginBrightnessPress(on: display)
    let desired = try await engine.adjustBrightness(on: display, by: .decrease)

    #expect(desired.percent == 37.0)
}

@Test("Seven rapid on-grid brightness presses retain the full 3.5 percent")
func sevenRapidBrightnessPressesAreNotDropped() async throws {
    let backend = SlowBrightnessBackend(current: BasisPoints(percent: 37.5))
    let engine = ControlEngine(brightnessBackend: backend)
    let display = DisplayIdentifier(rawValue: 4)

    var desired = BasisPoints(percent: 37.5)
    for _ in 0..<7 {
        desired = try await engine.adjustBrightness(on: display, by: .increase)
    }

    #expect(desired.percent == 41.0)
    try await engine.waitUntilIdle(timeout: .seconds(1))
    #expect(try await backend.readBrightness(for: display).percent == 41.0)
    let writes = await backend.writes
    #expect(writes.last?.percent == 41.0)
    #expect(writes.count <= 2)
}

private actor QuantizingBrightnessBackend: BrightnessBackend {
    private(set) var writes: [BasisPoints] = []

    func readBrightness(for display: DisplayIdentifier) async throws -> BasisPoints {
        BasisPoints(percent: 37.3)
    }

    func setBrightness(
        _ value: BasisPoints,
        for display: DisplayIdentifier
    ) async throws -> BasisPoints {
        writes.append(value)
        return BasisPoints(percent: 38.0)
    }
}

@Test("A quantized readback reconciles once without duplicate retries")
func quantizedReadbackDoesNotRetryBlindly() async throws {
    let backend = QuantizingBrightnessBackend()
    let engine = ControlEngine(brightnessBackend: backend)
    let display = DisplayIdentifier(rawValue: 4)

    _ = try await engine.adjustBrightness(on: display, by: .increase)
    try await engine.waitUntilIdle(timeout: .seconds(1))

    #expect(await backend.writes.count == 1)
    #expect(await backend.writes.first?.percent == 37.5)
    #expect(await engine.brightnessSnapshot(for: display)?.confirmed.percent == 38.0)
}
