//
//  Color+Theme.swift
//  mixbridge
//
//  Theme colors that adapt to light and dark mode
//

import SwiftUI
    
extension Color {
    // MARK: - Background Colors
    static let adaptiveBackground = Color(uiColor: .systemBackground)
    static let adaptiveSecondaryBackground = Color(uiColor: .secondarySystemBackground)
    static let adaptiveTertiaryBackground = Color(uiColor: .tertiarySystemBackground)
    static let adaptiveGroupedBackground = Color(uiColor: .systemGroupedBackground)

    // MARK: - Text Colors
    static let adaptiveText = Color(uiColor: .label)
    static let adaptiveSecondaryText = Color(uiColor: .secondaryLabel)
    static let adaptiveTertiaryText = Color(uiColor: .tertiaryLabel)

    // MARK: - Brand Colors
    static let brandPrimary = Color("BrandPrimary")
    static let brandSecondary = Color("BrandSecondary")
    static let brandAccent = Color("BrandAccent")

    // MARK: - Card Colors
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardBorder = Color(uiColor: .separator)

    // MARK: - Album Artwork Gradient
    static func albumGradient(light: Color = .blue, dark: Color = .indigo) -> LinearGradient {
        LinearGradient(
            colors: [light, dark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Glass Effect Colors
    static func glassOverlay(opacity: Double = 0.3) -> Color {
        Color.white.opacity(opacity)
    }

    static func glassBorder(lightOpacity: Double = 0.3, darkOpacity: Double = 0.2) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(lightOpacity),
                Color.white.opacity(darkOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - UI Color Extensions
extension UIColor {
    // Custom brand colors that adapt to dark mode
    static let brandBlue = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)  // Lighter blue for dark mode
            : UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0) // Standard blue for light mode
    }

    static let brandPink = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.4, blue: 0.7, alpha: 1.0)  // Lighter pink for dark mode
            : UIColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0) // Standard pink for light mode
    }
}
