//
//  iOS26Compatibility.swift
//  mixbridge
//
//  Compatibility layer for iOS 26-only APIs to support iOS 18+
//

import SwiftUI

// MARK: - Glass Effect Compatibility

extension View {
    /// Applies clear glass effect on iOS 26+, falls back to thin material on iOS 18
    @ViewBuilder
    func glassEffectIfAvailable<S: Shape>(_ style: GlassEffectStyleCompat = .regular, in shape: S) -> some View {
        if #available(iOS 26, *) {
            switch style {
            case .clear:
                self.glassEffect(.clear, in: shape)
            case .regular:
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.thinMaterial, in: shape)
        }
    }

    /// Applies glass effect on iOS 26+, falls back to thin material on iOS 18 (no shape)
    @ViewBuilder
    func glassEffectIfAvailable(_ style: GlassEffectStyleCompat = .regular) -> some View {
        if #available(iOS 26, *) {
            switch style {
            case .clear:
                self.glassEffect(.clear)
            case .regular:
                self.glassEffect(.regular)
            }
        } else {
            self.background(.thinMaterial)
        }
    }
}

/// Wrapper enum for GlassEffectStyle to avoid direct iOS 26 API reference
enum GlassEffectStyleCompat {
    case clear
    case regular
}

// MARK: - Glass Effect Container Compatibility

/// Container view for grouping glass effect union items
struct GlassEffectContainerCompat<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    /// Applies glass effect union on iOS 26+, no-op on iOS 18
    @ViewBuilder
    func glassEffectUnionIfAvailable(id: String, namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            self.glassEffectUnion(id: id, namespace: namespace)
        } else {
            self
        }
    }
}

// MARK: - Navigation Transition Compatibility

extension View {
    /// Applies zoom navigation transition on iOS 26+, no-op on iOS 18
    @ViewBuilder
    func navigationTransitionIfAvailable(sourceID: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    /// Applies matched transition source on iOS 26+, no-op on iOS 18
    @ViewBuilder
    func matchedTransitionSourceIfAvailable(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Content Margins Compatibility

extension View {
    /// Applies content margins on iOS 26+, padding fallback on iOS 18
    @ViewBuilder
    func contentMarginsIfAvailable(_ edges: Edge.Set = .all, _ length: CGFloat, for placement: ContentMarginsPlacementCompat = .scrollContent) -> some View {
        if #available(iOS 26, *) {
            self.contentMargins(edges, length, for: placement.toNative)
        } else {
            // Fallback: use padding for scroll content on iOS 18
            self
        }
    }
}

enum ContentMarginsPlacementCompat {
    case scrollContent
    case scrollIndicators
    case automatic

    @available(iOS 26, *)
    var toNative: ContentMarginPlacement {
        switch self {
        case .scrollContent: return .scrollContent
        case .scrollIndicators: return .scrollIndicators
        case .automatic: return .automatic
        }
    }
}

// MARK: - Scroll Phase Change Compatibility

extension View {
    /// Applies onScrollPhaseChange on iOS 26+, no-op on iOS 18
    @ViewBuilder
    func onScrollPhaseChangeIfAvailable(
        _ action: @escaping (_ oldPhase: ScrollPhaseCompat, _ newPhase: ScrollPhaseCompat, _ context: ScrollPhaseContextCompat) -> Void
    ) -> some View {
        if #available(iOS 26, *) {
            self.onScrollPhaseChange { oldPhase, newPhase, context in
                action(
                    ScrollPhaseCompat(from: oldPhase),
                    ScrollPhaseCompat(from: newPhase),
                    ScrollPhaseContextCompat(geometry: ScrollGeometryCompat(
                        contentOffset: context.geometry.contentOffset,
                        contentInsets: context.geometry.contentInsets
                    ))
                )
            }
        } else {
            self
        }
    }

    /// Simple version without context
    @ViewBuilder
    func onScrollPhaseChangeIfAvailable(
        _ action: @escaping (_ oldPhase: ScrollPhaseCompat, _ newPhase: ScrollPhaseCompat) -> Void
    ) -> some View {
        if #available(iOS 26, *) {
            self.onScrollPhaseChange { oldPhase, newPhase in
                action(
                    ScrollPhaseCompat(from: oldPhase),
                    ScrollPhaseCompat(from: newPhase)
                )
            }
        } else {
            self
        }
    }
}

/// Compatibility wrapper for ScrollPhase
enum ScrollPhaseCompat: Equatable {
    case idle
    case interacting
    case tracking
    case decelerating
    case animating

    @available(iOS 26, *)
    init(from phase: ScrollPhase) {
        switch phase {
        case .idle: self = .idle
        case .interacting: self = .interacting
        case .tracking: self = .tracking
        case .decelerating: self = .decelerating
        case .animating: self = .animating
        @unknown default: self = .idle
        }
    }
}

struct ScrollPhaseContextCompat {
    let geometry: ScrollGeometryCompat
}

struct ScrollGeometryCompat {
    let contentOffset: CGPoint
    let contentInsets: EdgeInsets
}

// MARK: - Scroll Geometry Change Compatibility

extension View {
    /// Applies onScrollGeometryChange on iOS 26+, no-op on iOS 18
    @ViewBuilder
    func onScrollGeometryChangeIfAvailable<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (ScrollGeometryCompat) -> T,
        action: @escaping (_ oldValue: T, _ newValue: T) -> Void
    ) -> some View {
        if #available(iOS 26, *) {
            self.onScrollGeometryChange(for: type) { proxy in
                transform(ScrollGeometryCompat(
                    contentOffset: proxy.contentOffset,
                    contentInsets: proxy.contentInsets
                ))
            } action: { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            self
        }
    }
}

// MARK: - Tab View Compatibility

extension View {
    /// Applies tabViewBottomAccessory on iOS 26+, no-op on iOS 18
    @ViewBuilder
    func tabViewBottomAccessoryIfAvailable<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26, *) {
            self.tabViewBottomAccessory {
                content()
            }
        } else {
            self
        }
    }

    /// Applies tabBarMinimizeBehavior on iOS 26+, no-op on iOS 18
    @ViewBuilder
    func tabBarMinimizeBehaviorIfAvailable() -> some View {
        if #available(iOS 26, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

// MARK: - Container Background Compatibility

extension View {
    /// Applies containerBackground on iOS 26+, no-op on iOS 18
    @ViewBuilder
    func containerBackgroundIfAvailable<S: ShapeStyle>(_ style: S, for container: ContainerBackgroundPlacementCompat) -> some View {
        if #available(iOS 26, *) {
            self.containerBackground(style, for: .navigation)
        } else {
            self
        }
    }
}

enum ContainerBackgroundPlacementCompat {
    case navigation
}

// MARK: - Toolbar Background Compatibility

extension View {
    /// Applies toolbarBackground on iOS 26+ with hidden visibility, no-op on iOS 18
    @ViewBuilder
    func toolbarBackgroundHiddenIfAvailable(for bars: ToolbarPlacement) -> some View {
        if #available(iOS 26, *) {
            self.toolbarBackground(.hidden, for: bars)
        } else {
            self
        }
    }
}

// MARK: - TabView iOS 18 Fallback

/// iOS 18 compatible TabView using traditional API
struct LegacyTabView<Content: View>: View {
    @Binding var selectedTab: Int
    let content: Content

    init(selectedTab: Binding<Int>, @ViewBuilder content: () -> Content) {
        self._selectedTab = selectedTab
        self.content = content()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            content
        }
        .tint(.primary)
    }
}
