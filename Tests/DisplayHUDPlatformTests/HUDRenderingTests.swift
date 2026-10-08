import AppKit
import Testing
@testable import DisplayHUDPlatform

// Tests that order real HUD panels on screen are opt-in: they briefly show
// passive windows and must never run as part of a default headless test pass.
private let windowTestsEnabled = ProcessInfo.processInfo.environment["DISPLAY_HUD_WINDOW_TESTS"] == "1"

@MainActor
@Test("The HUD is 318 by 88 points with fully transparent outer corners")
func hudHasTransparentOuterCorners() throws {
    let view = HUDContentView(frame: NSRect(x: 0, y: 0, width: 318, height: 88))
    view.model = HUDModel(
        kind: .brightness,
        value: BasisPoints(percent: 47.5),
        isMuted: false
    )
    view.layoutSubtreeIfNeeded()

    #expect(view.bounds.size == NSSize(width: 318, height: 88))
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)

    let corners = [
        (0, 0),
        (representation.pixelsWide - 1, 0),
        (0, representation.pixelsHigh - 1),
        (representation.pixelsWide - 1, representation.pixelsHigh - 1),
    ]
    for (x, y) in corners {
        #expect((representation.colorAt(x: x, y: y)?.alphaComponent ?? 1) == 0)
    }
}

@MainActor
@Test(arguments: [
    HUDModel(kind: .brightness, value: BasisPoints(percent: 47.5), isMuted: false),
    HUDModel(kind: .volume, value: BasisPoints(percent: 72.5), isMuted: false),
    HUDModel(kind: .mute, value: BasisPoints(percent: 72.5), isMuted: true),
])
func everyHUDModeKeepsTransparentCorners(model: HUDModel) throws {
    let view = HUDContentView(frame: NSRect(origin: .zero, size: HUDContentView.preferredSize))
    view.model = model
    view.layoutSubtreeIfNeeded()
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)

    #expect((representation.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) == 0)
    #expect((representation.colorAt(
        x: representation.pixelsWide - 1,
        y: representation.pixelsHigh - 1
    )?.alphaComponent ?? 1) == 0)

    if let captureDirectory = ProcessInfo.processInfo.environment["DISPLAY_HUD_CAPTURE_DIR"],
       let data = representation.representation(using: .png, properties: [:])
    {
        try FileManager.default.createDirectory(
            atPath: captureDirectory,
            withIntermediateDirectories: true
        )
        let name: String
        switch model.kind {
        case .brightness: name = "brightness"
        case .volume: name = "volume"
        case .mute: name = "mute"
        }
        try data.write(to: URL(fileURLWithPath: captureDirectory).appendingPathComponent("\(name).png"))
    }
}

@MainActor
@Test("A replacement HUD remains visible after the previous fade completes")
func replacementHUDSurvivesPreviousFadeCompletion() async throws {
    guard windowTestsEnabled else { return }
    let presenter = HUDPresenter()
    let screen = try #require(NSScreen.main)
    let first = HUDModel(
        kind: .brightness,
        value: BasisPoints(percent: 47.5),
        isMuted: false
    )
    let replacement = HUDModel(
        kind: .volume,
        value: BasisPoints(percent: 67.5),
        isMuted: false
    )

    presenter.show(first, on: screen)
    try await Task.sleep(for: .milliseconds(1_000))
    presenter.show(replacement, on: screen)
    try await Task.sleep(for: .milliseconds(180))

    let visibleHUD = presenter.panelForTesting.isVisible
        && presenter.panelForTesting.alphaValue > 0.99
    presenter.hide()

    #expect(visibleHUD)
}

@MainActor
@Test("Ordinary HUD sessions reuse the prewarmed panel")
func ordinarySessionsReusePrewarmedPanel() throws {
    guard windowTestsEnabled else { return }
    let presenter = HUDPresenter()
    let screen = try #require(NSScreen.main)
    let model = HUDModel(
        kind: .volume,
        value: BasisPoints(percent: 61.5),
        isMuted: false
    )

    presenter.show(model, on: screen)
    let firstPanel = presenter.panelForTesting
    #expect(firstPanel.isVisible)
    presenter.hide()

    presenter.show(model, on: screen)
    let secondPanel = presenter.panelForTesting
    #expect(secondPanel.isVisible)
    presenter.hide()

    #expect(secondPanel === firstPanel)
}

@MainActor
@Test("Lifecycle invalidation replaces stale WindowServer panel state")
func lifecycleInvalidationReplacesPanel() throws {
    guard windowTestsEnabled else { return }
    let presenter = HUDPresenter()
    let screen = try #require(NSScreen.main)
    let model = HUDModel(
        kind: .brightness,
        value: BasisPoints(percent: 43.5),
        isMuted: false
    )

    presenter.show(model, on: screen)
    let firstPanel = presenter.panelForTesting
    #expect(firstPanel.isVisible)

    presenter.invalidateForLifecycleTransition()
    #expect(!firstPanel.isVisible)

    presenter.show(model, on: screen)
    let replacement = presenter.panelForTesting
    #expect(replacement.isVisible)
    presenter.hide()

    #expect(replacement !== firstPanel)
}
