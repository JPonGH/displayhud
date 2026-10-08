import AppKit
import DisplayHUDCore

public enum HUDKind: Equatable, Sendable {
    case brightness
    case volume
    case mute
}

public struct HUDModel: Equatable, Sendable {
    public let kind: HUDKind
    public let value: BasisPoints
    public let isMuted: Bool

    public init(kind: HUDKind, value: BasisPoints, isMuted: Bool) {
        self.kind = kind
        self.value = value
        self.isMuted = isMuted
    }
}

@MainActor
public final class HUDContentView: NSView {
    public static let preferredSize = NSSize(width: 318, height: 88)

    public var model = HUDModel(kind: .brightness, value: .minimum, isMuted: false) {
        didSet { updateContent() }
    }

    private let materialView = NSVisualEffectView()
    private let iconView = NSImageView()
    private let valueLabel = NSTextField(labelWithString: "0.0%")
    private let titleLabel = NSTextField(labelWithString: "BRIGHTNESS")
    private let railView = NSView()
    private let fillView = NSView()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    public override var isOpaque: Bool { false }

    public override func layout() {
        super.layout()
        materialView.frame = bounds.insetBy(dx: 1, dy: 1)
        iconView.frame = NSRect(x: 23, y: 25, width: 38, height: 38)
        valueLabel.frame = NSRect(x: 76, y: 36, width: 122, height: 34)
        titleLabel.frame = NSRect(x: 78, y: 17, width: 118, height: 16)
        railView.frame = NSRect(x: 208, y: 39, width: 84, height: 7)
        fillView.frame = NSRect(
            x: 0,
            y: 0,
            width: railView.bounds.width * CGFloat(model.value.scalar),
            height: railView.bounds.height
        )
        materialView.layer?.cornerRadius = 22
        railView.layer?.cornerRadius = railView.bounds.height / 2
        fillView.layer?.cornerRadius = fillView.bounds.height / 2
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        materialView.wantsLayer = true
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.material = .hudWindow
        materialView.layer?.masksToBounds = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            materialView.material = .windowBackground
            materialView.layer?.backgroundColor = NSColor.windowBackgroundColor
                .withAlphaComponent(0.97).cgColor
        }
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            materialView.layer?.borderWidth = 1
            materialView.layer?.borderColor = NSColor.labelColor
                .withAlphaComponent(0.45).cgColor
        } else {
            materialView.layer?.borderWidth = 0.75
            materialView.layer?.borderColor = NSColor.white
                .withAlphaComponent(0.18).cgColor
        }
        addSubview(materialView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = NSColor.systemOrange
        materialView.addSubview(iconView)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .left
        valueLabel.lineBreakMode = .byClipping
        materialView.addSubview(valueLabel)

        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .left
        materialView.addSubview(titleLabel)

        railView.wantsLayer = true
        railView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
        railView.layer?.masksToBounds = true
        materialView.addSubview(railView)

        fillView.wantsLayer = true
        fillView.layer?.backgroundColor = NSColor.systemOrange.cgColor
        railView.addSubview(fillView)

        updateContent()
    }

    private func updateContent() {
        let accent: NSColor
        let symbolName: String
        let title: String

        switch model.kind {
        case .brightness:
            accent = .systemOrange
            symbolName = "sun.max.fill"
            title = "BRIGHTNESS"
        case .volume:
            accent = .systemBlue
            symbolName = model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
            title = model.isMuted ? "MUTED" : "VOLUME"
        case .mute:
            accent = .systemBlue
            symbolName = model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
            title = model.isMuted ? "MUTED" : "UNMUTED"
        }

        iconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title.capitalized
        )
        iconView.contentTintColor = accent
        valueLabel.stringValue = String(
            format: "%.1f%%",
            locale: Locale(identifier: "en_US_POSIX"),
            model.value.percent
        )
        titleLabel.stringValue = title
        fillView.layer?.backgroundColor = accent.cgColor
        needsLayout = true
    }
}
