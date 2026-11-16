//
//  Color+Hex.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import SwiftUI
import SwiftData

extension Color {
    /// Initialize a Color from a hex string (e.g., "#FF5733" or "FF5733")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255) // Default to system blue
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Convert Color to hex string (iOS 17+)
    @available(iOS 17.0, *)
    func toHex(in environment: EnvironmentValues = EnvironmentValues()) -> String {
        let resolved = self.resolve(in: environment)
        return String(
            format: "#%02X%02X%02X",
            Int(resolved.red * 255),
            Int(resolved.green * 255),
            Int(resolved.blue * 255)
        )
    }
}

// MARK: - Theme Colors

extension Color {
    /// Dark grey background for dim theme (darker than components)
    static let dimBackground = Color(white: 0.07)

    /// Secondary dark grey for dim theme (for grouped backgrounds)
    static let dimSecondaryBackground = Color(white: 0.11)
}

// MARK: - Dim Theme Background Modifier

struct DimThemeBackground: ViewModifier {
    @Query private var preferences: [UserPreferences]
    let isScrollView: Bool

    private var isDimTheme: Bool {
        preferences.first?.theme == .dim
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isScrollView {
            // For ScrollView - just apply background
            content
                .background(isDimTheme ? Color.dimBackground : Color(.systemGroupedBackground))
        } else {
            // For List/Form - hide scroll content background and apply custom
            content
                .scrollContentBackground(isDimTheme ? .hidden : .automatic)
                .background(isDimTheme ? Color.dimBackground : Color.clear)
        }
    }
}

extension View {
    /// Apply dim theme background if active (for List/Form)
    func dimThemeBackground() -> some View {
        modifier(DimThemeBackground(isScrollView: false))
    }

    /// Apply dim theme background if active (for ScrollView)
    func dimThemeScrollBackground() -> some View {
        modifier(DimThemeBackground(isScrollView: true))
    }
}

// MARK: - Predefined Habit Colors

extension Color {
    /// Predefined color palette for habits
    static let habitColors: [Color] = [
        Color(hex: "#007AFF"), // Blue
        Color(hex: "#34C759"), // Green
        Color(hex: "#FF3B30"), // Red
        Color(hex: "#FF9500"), // Orange
        Color(hex: "#AF52DE"), // Purple
        Color(hex: "#FF2D55"), // Pink
        Color(hex: "#5856D6"), // Indigo
        Color(hex: "#00C7BE"), // Teal
        Color(hex: "#FFD60A"), // Yellow
        Color(hex: "#8E8E93"), // Gray
    ]

    /// Hex strings for the predefined habit colors
    static let habitColorHexes: [String] = [
        "#007AFF",
        "#34C759",
        "#FF3B30",
        "#FF9500",
        "#AF52DE",
        "#FF2D55",
        "#5856D6",
        "#00C7BE",
        "#FFD60A",
        "#8E8E93",
    ]
}
