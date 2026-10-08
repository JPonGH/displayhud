import Foundation
import Testing
@testable import DisplayHUDCore

private actor ActionCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

@Test("A held key repeats and key-up stops it immediately")
func holdRepeatsUntilMatchingKeyUp() async throws {
    let counter = ActionCounter()
    let repeater = HoldRepeater(
        initialDelay: .milliseconds(250),
        repeatInterval: .milliseconds(60)
    ) { _ in
        await counter.increment()
    }

    await repeater.keyDown(.brightnessUp, isSystemRepeat: false)
    try await Task.sleep(for: .milliseconds(330))
    let beforeRelease = await counter.count
    #expect(beforeRelease >= 2)

    await repeater.keyUp(.brightnessUp)
    let afterRelease = await counter.count
    try await Task.sleep(for: .milliseconds(120))
    #expect(await counter.count == afterRelease)
}

@Test("System-generated repeat-down events do not create duplicate hold loops")
func systemRepeatDownIsIgnored() async throws {
    let counter = ActionCounter()
    let repeater = HoldRepeater { _ in await counter.increment() }

    await repeater.keyDown(.volumeDown, isSystemRepeat: false)
    await repeater.keyDown(.volumeDown, isSystemRepeat: true)
    try await Task.sleep(for: .milliseconds(20))
    await repeater.cancel()

    #expect(await counter.count == 1)
}
