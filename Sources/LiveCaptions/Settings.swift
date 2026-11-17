import AppKit
import Observation

enum DisplayMode: String {
    /// A bar under the menu bar that pushes other windows down.
    case docked
    /// A bar that floats above all other windows.
    case floating
}

/// User preferences, persisted in UserDefaults.
@Observable
final class Settings {
    private let defaults = UserDefaults.standard

    var mode: DisplayMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    var includeMicrophone: Bool { didSet { defaults.set(includeMicrophone, forKey: "includeMicrophone") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    var lines: Int { didSet { defaults.set(lines, forKey: "lines") } }
    var opacity: Double { didSet { defaults.set(opacity, forKey: "opacity") } }
    /// The display the bar shows on, by its UUID. Nil means the main display (the one with the menu bar).
    var display: String? { didSet { defaults.set(display, forKey: "display") } }
    /// The floating bar's frame, relative to its display's bottom-left corner.
    var floatingFrame: NSRect? {
        didSet { defaults.set(floatingFrame.map { NSStringFromRect($0) }, forKey: "floatingFrame") }
    }

    init() {
        defaults.register(defaults: [
            "mode": DisplayMode.docked.rawValue,
            "includeMicrophone": false,
            "fontSize": 22.0,
            "lines": 2,
            "opacity": 0.9,
        ])
        mode = DisplayMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .docked
        includeMicrophone = defaults.bool(forKey: "includeMicrophone")
        fontSize = defaults.double(forKey: "fontSize")
        lines = min(max(defaults.integer(forKey: "lines"), Self.lineRange.lowerBound), Self.lineRange.upperBound)
        opacity = defaults.double(forKey: "opacity")
        display = defaults.string(forKey: "display")
        floatingFrame = defaults.string(forKey: "floatingFrame").map { NSRectFromString($0) }
    }

    static let fontSizes: [(String, Double)] = [("Small", 16), ("Medium", 19), ("Large", 22), ("Extra large", 28)]
    static let opacities: [Double] = [0.6, 0.75, 0.9, 1.0]
    static let lineRange = 1...10
    /// Caption text is kept to a centered column, like subtitles, for easy reading.
    static let maxTextWidth = 1000.0

    var font: NSFont { .systemFont(ofSize: fontSize, weight: .medium) }
    var lineSpacing: Double { 4 }
    var verticalPadding: Double { 10 }

    /// Height of the caption bar that shows exactly `lines` lines of text.
    var barHeight: Double {
        (lineHeight * Double(lines)).rounded(.up) + verticalPadding * 2
    }

    var lineHeight: Double {
        NSLayoutManager().defaultLineHeight(for: font) + lineSpacing
    }
}
