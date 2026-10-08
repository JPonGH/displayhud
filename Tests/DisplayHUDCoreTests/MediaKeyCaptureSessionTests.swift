import Testing
@testable import DisplayHUDCore

@Test("Unavailable backends fail open while handled key-up remains paired")
func mediaKeyCaptureFailsOpenSafely() {
    var session = MediaKeyCaptureSession()

    #expect(session.route(
        MediaKeyEvent(key: .brightnessUp, phase: .down, isRepeat: false),
        backendAvailable: false
    ) == .passThrough)
    #expect(session.route(
        MediaKeyEvent(key: .brightnessUp, phase: .up, isRepeat: false),
        backendAvailable: false
    ) == .passThrough)

    #expect(session.route(
        MediaKeyEvent(key: .volumeUp, phase: .down, isRepeat: false),
        backendAvailable: true
    ) == .consumeAndDispatch)
    #expect(session.route(
        MediaKeyEvent(key: .volumeUp, phase: .up, isRepeat: false),
        backendAvailable: false
    ) == .consumeAndDispatch)
}

@Test("Interrupted delivery clears a stranded media-key down")
func mediaKeyCaptureResetClearsStrandedDown() {
    var session = MediaKeyCaptureSession()
    let down = MediaKeyEvent(key: .brightnessDown, phase: .down, isRepeat: false)

    #expect(session.route(down, backendAvailable: true) == .consumeAndDispatch)
    #expect(session.route(down, backendAvailable: true) == .consumeWithoutDispatch)

    session.reset()

    #expect(session.route(down, backendAvailable: true) == .consumeAndDispatch)
}
