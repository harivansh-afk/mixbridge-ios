//
//  HapticManager.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 11/16/25.
//

import UIKit
import SwiftUI

@MainActor
private enum CachedHaptics {
    static let light = UIImpactFeedbackGenerator(style: .light)
    static let medium = UIImpactFeedbackGenerator(style: .medium)
    static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    static let selection = UISelectionFeedbackGenerator()
    static let notification = UINotificationFeedbackGenerator()

    static func impact(_ generator: UIImpactFeedbackGenerator) {
        generator.prepare()
        generator.impactOccurred()
    }
}

/// Centralized haptic feedback management
/// Provides consistent haptics across the app
struct HapticManager {

    /// Light impact - for subtle interactions
    static func light() {
        if Thread.isMainThread {
            CachedHaptics.impact(CachedHaptics.light)
        } else {
            DispatchQueue.main.async { CachedHaptics.impact(CachedHaptics.light) }
        }
    }

    /// Medium impact - for standard button taps and selections
    static func medium() {
        if Thread.isMainThread {
            CachedHaptics.impact(CachedHaptics.medium)
        } else {
            DispatchQueue.main.async { CachedHaptics.impact(CachedHaptics.medium) }
        }
    }

    /// Heavy impact - for significant actions
    static func heavy() {
        if Thread.isMainThread {
            CachedHaptics.impact(CachedHaptics.heavy)
        } else {
            DispatchQueue.main.async { CachedHaptics.impact(CachedHaptics.heavy) }
        }
    }

    /// Selection feedback - for navigation and tab changes
    static func selection() {
        if Thread.isMainThread {
            CachedHaptics.selection.prepare()
            CachedHaptics.selection.selectionChanged()
        } else {
            DispatchQueue.main.async {
                CachedHaptics.selection.prepare()
                CachedHaptics.selection.selectionChanged()
            }
        }
    }

    /// Success notification - for successful operations
    static func success() {
        if Thread.isMainThread {
            CachedHaptics.notification.prepare()
            CachedHaptics.notification.notificationOccurred(.success)
        } else {
            DispatchQueue.main.async {
                CachedHaptics.notification.prepare()
                CachedHaptics.notification.notificationOccurred(.success)
            }
        }
    }

    /// Warning notification - for destructive actions
    static func warning() {
        if Thread.isMainThread {
            CachedHaptics.notification.prepare()
            CachedHaptics.notification.notificationOccurred(.warning)
        } else {
            DispatchQueue.main.async {
                CachedHaptics.notification.prepare()
                CachedHaptics.notification.notificationOccurred(.warning)
            }
        }
    }

    /// Error notification - for failed operations
    static func error() {
        if Thread.isMainThread {
            CachedHaptics.notification.prepare()
            CachedHaptics.notification.notificationOccurred(.error)
        } else {
            DispatchQueue.main.async {
                CachedHaptics.notification.prepare()
                CachedHaptics.notification.notificationOccurred(.error)
            }
        }
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
