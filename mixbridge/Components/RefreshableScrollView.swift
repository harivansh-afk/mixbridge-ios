//
//  RefreshableScrollView.swift
//  mixbridge
//
//  Custom pull-to-refresh for ScrollView that works reliably
//  Based on onScrollPhaseChange + onScrollGeometryChange approach
//

import SwiftUI

struct RefreshableScrollView<Content: View>: View {
    @Binding var isRefreshing: Bool
    let refreshThreshold: CGFloat
    let onRefresh: () async -> Void
    @ViewBuilder let content: () -> Content

    @State private var contentInsetDifference: CGFloat = 0.0
    private let indicatorHeight: CGFloat = 42.0

    private let displayIndicatorThreshold: CGFloat = 0.5

    init(
        isRefreshing: Binding<Bool>,
        refreshThreshold: CGFloat = 80.0,
        onRefresh: @escaping () async -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isRefreshing = isRefreshing
        self.refreshThreshold = refreshThreshold
        self.onRefresh = onRefresh
        self.content = content
    }

    private var pullProgress: CGFloat {
        contentInsetDifference / -refreshThreshold
    }

    private var shouldShowIndicator: Bool {
        pullProgress > displayIndicatorThreshold || isRefreshing
    }

    private var scaleFactor: CGFloat {
        if isRefreshing { return 1.5 }
        guard displayIndicatorThreshold < 1 else { return 1.5 }
        let factor = 1 / (1 - displayIndicatorThreshold) * pullProgress + (1 - 1 / (1 - displayIndicatorThreshold))
        return min(max(factor, 0), 1.0) * 1.5
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if shouldShowIndicator {
                    refreshIndicator
                        .frame(height: indicatorHeight)
                        .padding(.top, -100) // nudge upward toward the nav/title
                }
                content()
            }
            .scrollTargetLayout()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            contentInsetDifference = newValue
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            guard oldPhase == .interacting, newPhase != .interacting else { return }

            let geometry = context.geometry
            let offset = geometry.contentOffset.y + geometry.contentInsets.top

            if offset < -refreshThreshold {
                isRefreshing = true
                HapticManager.light()
            }
        }
        .onChange(of: isRefreshing) { _, newValue in
            guard newValue else { return }
            Task {
                await onRefresh()
                await MainActor.run {
                    isRefreshing = false
                }
            }
        }
        .animation(.default, value: isRefreshing)
    }

    private var refreshIndicator: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.regular)
            .tint(.secondary)
            .scaleEffect(scaleFactor)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var isRefreshing = false
        @State private var items = Array(1...20)

        var body: some View {
            NavigationStack {
                RefreshableScrollView(isRefreshing: $isRefreshing) {
                    try? await Task.sleep(for: .seconds(2))
                    items.shuffle()
                } content: {
                    LazyVStack(spacing: 0) {
                        ForEach(items, id: \.self) { item in
                            Text("Item \(item)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                            Divider()
                        }
                    }
                }
                .navigationTitle("Refreshable")
            }
        }
    }
    return PreviewWrapper()
}
