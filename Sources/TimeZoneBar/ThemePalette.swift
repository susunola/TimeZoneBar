import SwiftUI

// MARK: - Theme palette

/// Visual tokens for each app theme. Centralised so every view (header,
/// rows, footer, settings preview) renders from one source of truth.
struct ThemePalette {
    let window: Color          // panel background
    let surface: Color         // row / card surface
    let surfaceAlt: Color      // alternate row surface (midnight: dimmed row)
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let hairline: Color
    let rowRadius: CGFloat
    let headerTimeSize: CGFloat
    let quoteIsSerif: Bool
    let quoteHasMarks: Bool
    let useCards: Bool         // rows as cards (glass) vs flat rows
    let useAccentBars: Bool    // 4px accent bar on rows (minimal / midnight)
    let detectIsSolid: Bool    // solid accent detect button (glass)
    let panelRadius: CGFloat

    static func palette(for theme: Theme) -> ThemePalette {
        switch theme {
        case .minimal:
            return ThemePalette(window: Color(hex: "#FFFFFF"),
                                surface: Color(hex: "#FFFFFF"),
                                surfaceAlt: Color(hex: "#F0F6FF"),
                                textPrimary: Color(hex: "#1D1D1F"),
                                textSecondary: Color(hex: "#86868B"),
                                textTertiary: Color(hex: "#B4B4BB"),
                                accent: Color(hex: "#0A84FF"),
                                hairline: Color(hex: "#E5E5EA"),
                                rowRadius: 8,
                                headerTimeSize: 40,
                                quoteIsSerif: true,
                                quoteHasMarks: false,
                                useCards: false,
                                useAccentBars: true,
                                detectIsSolid: false,
                                panelRadius: 16)
        case .glass:
            return ThemePalette(window: Color(hex: "#F5F7FA"),
                                surface: Color(hex: "#FFFFFF"),
                                surfaceAlt: Color(hex: "#FFFFFF"),
                                textPrimary: Color(hex: "#1D1D1F"),
                                textSecondary: Color(hex: "#5F6B76"),
                                textTertiary: Color(hex: "#8A94A0"),
                                accent: Color(hex: "#0A84FF"),
                                hairline: Color(hex: "#E0E6ED"),
                                rowRadius: 14,
                                headerTimeSize: 44,
                                quoteIsSerif: true,
                                quoteHasMarks: false,
                                useCards: true,
                                useAccentBars: false,
                                detectIsSolid: true,
                                panelRadius: 24)
        case .midnight:
            return ThemePalette(window: Color(hex: "#1C1C1E"),
                                surface: Color(hex: "#2C2C2E"),
                                surfaceAlt: Color(hex: "#242426"),
                                textPrimary: Color(hex: "#F5F5F7"),
                                textSecondary: Color(hex: "#98989D"),
                                textTertiary: Color(hex: "#7C7C80"),
                                accent: Color(hex: "#64D2FF"),
                                hairline: Color(hex: "#3A3A3C"),
                                rowRadius: 10,
                                headerTimeSize: 42,
                                quoteIsSerif: true,
                                quoteHasMarks: false,
                                useCards: false,
                                useAccentBars: true,
                                detectIsSolid: false,
                                panelRadius: 20)
        case .editorial:
            return ThemePalette(window: Color(hex: "#FAFAF8"),
                                surface: Color(hex: "#FAFAF8"),
                                surfaceAlt: Color(hex: "#F2F2ED"),
                                textPrimary: Color(hex: "#2E2A24"),
                                textSecondary: Color(hex: "#8B867A"),
                                textTertiary: Color(hex: "#B9B9B0"),
                                accent: Color(hex: "#C41E3A"),
                                hairline: Color(hex: "#E2E2DC"),
                                rowRadius: 4,
                                headerTimeSize: 52,
                                quoteIsSerif: true,
                                quoteHasMarks: true,
                                useCards: false,
                                useAccentBars: false,
                                detectIsSolid: false,
                                panelRadius: 4)
        }
    }
}
