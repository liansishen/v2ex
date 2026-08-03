import SwiftUI
import UIKit

/// Selectable colour schemes. The neutral ink/surface ramp is shared; each
/// palette owns the accent, the secondary signal and the canvas temperature.
enum ThemePalette: String, CaseIterable, Identifiable {
    case emerald, ocean, crimson, amber, violet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emerald: return "翡翠绿"
        case .ocean: return "海洋蓝"
        case .crimson: return "绯红"
        case .amber: return "琥珀橙"
        case .violet: return "紫罗兰"
        }
    }

    // MARK: Accent — the one saturated colour per scheme.

    var accent: Color { Theme.dynamic(light: accentPair.l, dark: accentPair.d) }
    var accentDeep: Color { Theme.dynamic(light: accentDeepPair.l, dark: accentDeepPair.d) }
    var accentSoft: Color { Theme.dynamicA(light: (accentPair.l, 0.10), dark: (accentPair.d, 0.16)) }
    var accentWash: Color { Theme.dynamicA(light: (accentPair.l, 0.05), dark: (accentPair.d, 0.09)) }

    /// Secondary signal — coins, offline markers, favourites.
    var secondary: Color { Theme.dynamic(light: secondaryPair.l, dark: secondaryPair.d) }
    var secondarySoft: Color { Theme.dynamicA(light: (secondaryPair.l, 0.14), dark: (secondaryPair.d, 0.18)) }

    /// Canvas temperature follows the accent so each scheme reads as one piece.
    var canvas: Color { Theme.dynamic(light: canvasLight, dark: 0x0A0A0B) }

    // MARK: Colour tables

    private var accentPair: (l: UInt32, d: UInt32) {
        switch self {
        case .emerald: return (0x00734C, 0x2FBF8F)
        case .ocean:   return (0x0F64B0, 0x4AA3E8)
        case .crimson: return (0xA63D2E, 0xE86A5A)
        case .amber:   return (0xB4550A, 0xEFA85C)
        case .violet:  return (0x5A4B8C, 0xA898DD)
        }
    }

    private var accentDeepPair: (l: UInt32, d: UInt32) {
        switch self {
        case .emerald: return (0x00543A, 0x1E9C72)
        case .ocean:   return (0x0A4A85, 0x2F87C8)
        case .crimson: return (0x7E2A20, 0xD14A3A)
        case .amber:   return (0x8A3D00, 0xD97C34)
        case .violet:  return (0x433665, 0x8A78C6)
        }
    }

    private var secondaryPair: (l: UInt32, d: UInt32) {
        switch self {
        // Amber stays the default secondary; the amber scheme flips it to blue
        // so the accent and secondary never collide.
        case .emerald, .crimson, .violet: return (0xA85C00, 0xE8A33C)
        case .ocean:   return (0xB06A00, 0xE8A33C)
        case .amber:   return (0x1E5AA8, 0x4AA3E8)
        }
    }

    private var canvasLight: UInt32 {
        switch self {
        case .emerald: return 0xF2F2F7
        case .ocean:   return 0xF0F3F7
        case .crimson: return 0xF7F2F1
        case .amber:   return 0xF7F3EC
        case .violet:  return 0xF3F1F8
        }
    }
}

/// "Ink on paper" — the visual system.
///
/// Three deliberate choices, each fixing something the earlier grey system got
/// wrong:
///
/// 1. **Neutral canvas.** A grey sheet under neutral text; the canvas
///    temperature follows the selected palette so each scheme reads whole.
/// 2. **Real ink for titles.** Hierarchy comes from weight and size, not from
///    six shades of grey. Titles are near-black; everything secondary drops
///    hard to a single muted tone. Two levels, not five.
/// 3. **One signal colour.** The palette's accent is the only saturated colour,
///    used for interactive elements and node identity. The secondary is
///    reserved for coins, favourites and offline state. Everything else is
///    neutral.
enum Theme {

    /// The active palette, read straight from UserDefaults so any redraw after
    /// a switch in 外观 picks up the new colours without a restart.
    static var current: ThemePalette {
        ThemePalette(rawValue: UserDefaults.standard.string(forKey: "palette") ?? "") ?? .emerald
    }

    // MARK: Signal

    /// The one saturated colour in the app.
    static var accent: Color { current.accent }
    static var accentDeep: Color { current.accentDeep }
    static var accentSoft: Color { current.accentSoft }
    static var accentWash: Color { current.accentWash }

    /// Secondary signal — coins, offline markers, favourites.
    static var amber: Color { current.secondary }
    static var amberSoft: Color { current.secondarySoft }

    // MARK: Surfaces

    /// Canvas temperature follows the palette.
    static var canvas: Color { current.canvas }
    /// Cards sit crisply on the paper — no shadow needed at this contrast.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x161618)
    /// Fills inside a card: search fields, code blocks, stat tiles.
    static let inset = dynamic(light: 0xECECEF, dark: 0x1E1E21)
    /// Unselected chips, resting on the canvas.
    static let chipFill = dynamic(light: 0xFFFFFF, dark: 0x222225)

    // MARK: Ink

    /// Titles. Near-black, neutral to match the grey canvas.
    static let ink = dynamic(light: 0x141416, dark: 0xF2F2F4)
    /// Running text.
    static let body = dynamic(light: 0x2C2C2E, dark: 0xD1D1D6)
    /// Everything secondary collapses to this single tone.
    static let muted = dynamic(light: 0x86868B, dark: 0x8E8E93)
    /// Dividers, disabled glyphs, zero-value counts.
    static let faint = dynamic(light: 0xAEAEB2, dark: 0x4A4A4F)

    static let separator = dynamicA(light: (0x141416, 0.07), dark: (0xF2F2F4, 0.10))
    /// Fill flashed under a row while pressed.
    static let rowHighlight = dynamicA(light: (0x141416, 0.045), dark: (0xF2F2F4, 0.07))

    static let unreadDot = dynamic(light: 0xD8422C, dark: 0xFF6B54)
    static let searchHighlight = dynamicA(light: (0xE8A33C, 0.34), dark: (0xE8A33C, 0.28))

    // MARK: Node identity

    /// Nodes used to carry one of six colours so a feed could be scannable by
    /// source — in practice a screen of random hues read as noise. Identity
    /// now borrows the single accent: avatar placeholders and node labels
    /// share one signal colour, and source is read from the node name itself.
    static func nodeColor(for key: String) -> Color {
        Theme.accent
    }

    // MARK: Metrics

    enum Metric {
        static let cardRadius: CGFloat = 24
        static let screenPadding: CGFloat = 16
        static let cardPadding: CGFloat = 18
        static let headerPadding: CGFloat = 30
        static let rowHeight: CGFloat = 54
        static let hairline: CGFloat = 0.5
    }

    // MARK: Dynamic colour helpers

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(hex: dark, alpha: 1) : UIColor(hex: light, alpha: 1) })
    }

    static func dynamicA(light: (UInt32, CGFloat), dark: (UInt32, CGFloat)) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(hex: dark.0, alpha: dark.1) : UIColor(hex: light.0, alpha: light.1) })
    }
}

// MARK: - Typography

/// Type ramp. Numerals get their own face — see `number`.
enum Type {

    /// Screen titles.
    static func display(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .bold)
    }

    /// Topic titles in a list.
    static func title(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// Lead/featured titles.
    static func headline(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size)
    }

    /// Meta lines: node, author, timestamp.
    static func meta(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium)
    }

    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// **Numerals.** Rounded SF with tabular figures: distinctive enough to read
    /// as a deliberate choice, and tabular so counts line up in a column
    /// instead of jittering row to row — which is half of why the old list
    /// looked untidy.
    static func number(_ size: CGFloat = 13, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(UIColor(hex: hex, alpha: alpha))
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
