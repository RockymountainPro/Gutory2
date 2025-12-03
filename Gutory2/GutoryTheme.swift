//  GutoryTheme.swift
//  Gutory2
//
//  Created by Mac Mantei on 2025-11-24.
//

import SwiftUI

/// Central place to manage Gutory’s visual tokens.
/// Hook everything in the app to these instead of hard-coded colors.
enum GutoryTheme {

    // MARK: - Backgrounds

    /// Full-screen app background (behind scroll views, tab bars, etc.).
    /// Used mainly for dark mode or when you don't want the gradient.
    static let appBackground = Color("AppBackground")

    /// Very light gradient used for light-mode backgrounds.
    /// Backed by `BackgroundGradientStart` / `BackgroundGradientEnd` in Assets.
    static let backgroundGradientStart = Color("BackgroundGradientStart")
    static let backgroundGradientEnd   = Color("BackgroundGradientEnd")

    /// Card / surface background for sections, cells, cards.
    static let cardBackground = Color("CardBackground")

    /// Text input fields (TextField, TextEditor, search, etc.).
    static let inputBackground = Color("InputBackground")

    // MARK: - Text

    /// Primary, high-emphasis text (titles, key labels, values).
    static let primaryText = Color("PrimaryText")

    /// Secondary, supporting text (subtitles, hints, timestamps).
    static let secondaryText = Color("SecondaryText")

    // MARK: - Accent / Interactive

    /// Main app accent (teal / gutory green)
    static let accent = Color("AccentColor")

    /// TRUE purple for AI banner + special highlights
    static let accentPurple = Color("AccentPurple")

    /// Softer version for backgrounds / pills / subtle highlights
    static let accentPurpleSoft = Color("AccentPurple").opacity(0.15)

    // MARK: - Borders / Dividers

    /// Subtle separators, strokes, and outlines.
    static let divider = Color("DividerColor")

    // MARK: - Gradients

    /// Gradient used for hero banners & primary CTAs
    static let accentGradient = LinearGradient(
        colors: [accentPurple, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Very light background gradient (top → bottom) for light mode.
    static let backgroundGradient = LinearGradient(
        colors: [backgroundGradientStart, backgroundGradientEnd],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Convenience accessors

extension Color {

    // Backgrounds
    static var gutoryBackground: Color { GutoryTheme.appBackground }
    static var gutoryCard: Color { GutoryTheme.cardBackground }
    static var gutoryInput: Color { GutoryTheme.inputBackground }

    // Text
    static var gutoryPrimaryText: Color { GutoryTheme.primaryText }
    static var gutorySecondaryText: Color { GutoryTheme.secondaryText }

    // Accent / Interactive
    static var gutoryAccent: Color { GutoryTheme.accent }
    static var gutoryAccentPurple: Color { GutoryTheme.accentPurple }
    static var gutoryAccentPurpleSoft: Color { GutoryTheme.accentPurpleSoft }

    // Borders / Dividers
    static var gutoryDivider: Color { GutoryTheme.divider }
}

// MARK: - Gradient helpers

extension LinearGradient {

    /// Hero gradient specifically for the Gutory AI banner on the Reports tab.
    static var gutoryAIBanner: LinearGradient {
        GutoryTheme.accentGradient
    }

    /// Light-mode app background gradient.
    /// Use this in combination with `Color.gutoryBackground` + colorScheme.
    static var gutoryBackground: LinearGradient {
        GutoryTheme.backgroundGradient
    }
}
