//
//  HapticManager.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/16/25.
//

import UIKit
import SwiftUI

/// Centralized haptic feedback management
/// Provides consistent haptics across the app
struct HapticManager {

    /// Light impact - for subtle interactions
    static func light() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    /// Medium impact - for standard button taps and selections
    static func medium() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    /// Heavy impact - for significant actions
    static func heavy() {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
    }

    /// Selection feedback - for navigation and tab changes
    static func selection() {
        let selection = UISelectionFeedbackGenerator()
        selection.selectionChanged()
    }

    /// Success notification - for successful operations
    static func success() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
    }

    /// Warning notification - for destructive actions
    static func warning() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.warning)
    }

    /// Error notification - for failed operations
    static func error() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.error)
    }
}

/// ViewModifier to add haptic feedback to any view interaction
struct HapticFeedback: ViewModifier {
    let style: HapticStyle

    enum HapticStyle {
        case light, medium, heavy, selection, success, warning, error
    }

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    switch style {
                    case .light: HapticManager.light()
                    case .medium: HapticManager.medium()
                    case .heavy: HapticManager.heavy()
                    case .selection: HapticManager.selection()
                    case .success: HapticManager.success()
                    case .warning: HapticManager.warning()
                    case .error: HapticManager.error()
                    }
                }
            )
    }
}

extension View {
    /// Add haptic feedback to any tappable view
    func haptic(_ style: HapticFeedback.HapticStyle = .light) -> some View {
        modifier(HapticFeedback(style: style))
    }
}
