import Testing
@testable import DisplayHUDCore

@Test("Only supported auxiliary media events are decoded")
func decodesSupportedAuxiliaryMediaEvents() {
    let brightnessDown = MediaKeyEventDecoder.decode(
        subtype: 8,
        data1: Int64((3 << 16) | (10 << 8))
    )
    let brightnessUpRelease = MediaKeyEventDecoder.decode(
        subtype: 8,
        data1: Int64((2 << 16) | (11 << 8))
    )

    #expect(brightnessDown == MediaKeyEvent(key: .brightnessDown, phase: .down, isRepeat: false))
    #expect(brightnessUpRelease == MediaKeyEvent(key: .brightnessUp, phase: .up, isRepeat: false))
    #expect(MediaKeyEventDecoder.decode(subtype: 7, data1: 0) == nil)
    #expect(MediaKeyEventDecoder.decode(subtype: 8, data1: Int64((16 << 16) | (10 << 8))) == nil)
}

@Test("All five media keys and repeat encoding decode without raw F-key capture")
func decodesAllSupportedMediaKeys() {
    let expected: [(Int, MediaKey)] = [
        (0, .volumeUp),
        (1, .volumeDown),
        (2, .brightnessUp),
        (3, .brightnessDown),
        (7, .mute),
    ]
    for (raw, key) in expected {
        let event = MediaKeyEventDecoder.decode(
            subtype: 8,
            data1: Int64((raw << 16) | (10 << 8) | 1)
        )
        #expect(event == MediaKeyEvent(key: key, phase: .down, isRepeat: true))
    }
}
