import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

enum LineSpacingPreference: String, CaseIterable, Identifiable {
    case tight, standard, relaxed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tight: return "紧凑"
        case .standard: return "标准"
        case .relaxed: return "宽松"
        }
    }

    /// Multiplier applied to the body font size to get line height.
    var multiplier: CGFloat {
        switch self {
        case .tight: return 1.38
        case .standard: return 1.52
        case .relaxed: return 1.68
        }
    }
}

enum MonoFontPreference: String, CaseIterable, Identifiable {
    case sfMono, menlo, courier
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sfMono: return "SF Mono"
        case .menlo: return "Menlo"
        case .courier: return "Courier"
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .sfMono: return .system(size: size, design: .monospaced)
        case .menlo: return .custom("Menlo", size: size)
        case .courier: return .custom("Courier", size: size)
        }
    }
}

/// Everything screen 09 (外观) controls, plus the reading state it implies.
@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("theme") var theme: ThemePreference = .system
    @AppStorage("palette") var palette: ThemePalette = .emerald
    @AppStorage("bodyFontSize") var bodyFontSize: Double = 14
    @AppStorage("lineSpacing") var lineSpacing: LineSpacingPreference = .relaxed
    @AppStorage("monoFont") var monoFont: MonoFontPreference = .sfMono
    @AppStorage("rememberReadingPosition") var rememberReadingPosition = true
    @AppStorage("autoOfflineFollowedNodes") var autoOfflineFollowedNodes = true
    @AppStorage("autoSyncFollowedNodes") var autoSyncFollowedNodes = true
    @AppStorage("offlineOnWiFiOnly") var offlineOnWiFiOnly = true
    @AppStorage("dimReadTopics") var dimReadTopics = false

    var bodyFont: Font { .system(size: bodyFontSize) }
    var bodyLineSpacing: CGFloat { bodyFontSize * (lineSpacing.multiplier - 1) }
    func codeFont(size: CGFloat) -> Font { monoFont.font(size: size) }
}
