//
//  ExpandedPlayerMixSheet.swift
//  mixbridge
//

import SwiftUI
import UIKit

struct ExpandedPlayerMixSheet: View {
    @Environment(PlayerState.self) private var playerState
    @Binding var isVisible: Bool
    @Binding var expansion: CGFloat

    let currentTrack: Track
    let nextTrack: Track?
    let isDJEnabled: Bool
    let handleTopPadding: CGFloat
    let handleBottomPadding: CGFloat
    let listTopInset: CGFloat
    let sectionVisualLift: CGFloat
    let topFadeHeight: CGFloat

    @State private var dragStart: CGFloat = 0
    @State private var lightHaptic = UIImpactFeedbackGenerator(style: .light)
    @State private var mediumHaptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        @Bindable var playerState = playerState
        let mixControls = playerState.mixControls

        VStack(spacing: 0) {
            // Drag handle area
            VStack(spacing: 8) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 60, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, handleTopPadding)
            .padding(.bottom, handleBottomPadding)
            .background(Color.clear)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if dragStart == 0 {
                            dragStart = expansion
                        }
                        let drag = -value.translation.height
                        let newExpansion = max(0, min(300, dragStart + drag))

                        let oldThreshold = Int(expansion / 50)
                        let newThreshold = Int(newExpansion / 50)
                        if newThreshold != oldThreshold {
                            lightHaptic.impactOccurred(intensity: 0.5)
                        }

                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.8)) {
                            expansion = newExpansion
                        }
                    }
                    .onEnded { value in
                        dragStart = 0
                        let velocity = value.velocity.height

                        if value.translation.height > 100 && expansion < 100 {
                            mediumHaptic.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isVisible = false
                                expansion = 0
                            }
                        } else if value.translation.height < -30 && velocity < -300 {
                            mediumHaptic.impactOccurred()
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                                isVisible = false
                                expansion = 0
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                expansion = expansion > 100 ? 200 : 0
                            }
                        }
                    }
            )

            List {

                Section {
                    SwapControlRow(
                        title: "Bass Swap",
                        percentage: Int(mixControls.bassSwapDepth * 100),
                        selection: bassSelection,
                        tint: .blue
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))

                    SwapControlRow(
                        title: "Mids Swap",
                        percentage: Int(mixControls.midsSwapDepth * 100),
                        selection: midsSelection,
                        tint: .blue
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))

                    SwapControlRow(
                        title: "Highs Swap",
                        percentage: Int(mixControls.highsSwapDepth * 100),
                        selection: highsSelection,
                        tint: .blue
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Blend Length")
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.1fs", mixControls.blendLengthSeconds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        BorderedTickPicker(
                            count: 36,
                            config: TickConfig(
                                tickWidth: 2,
                                tickHeight: 24,
                                inActiveHeightProgress: 0.45,
                                activeTint: .blue,
                                inActiveTint: .secondary,
                                alignment: .center
                            ),
                            selection: blendLengthSelection
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .disabled(!isDJEnabled)

                if !isDJEnabled {
                    Section {
                        Text("DJ Mode required for these controls")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .listSectionSpacing(8)
            .contentMargins(.top, listTopInset + 10, for: .scrollContent)
            .contentMargins(.bottom, 10, for: .scrollContent)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: topFadeHeight)
                    Color.black
                }
            )
        }
        .onAppear {
            lightHaptic.prepare()
            mediumHaptic.prepare()
        }
        .frame(height: 360 + expansion)
        .offset(y: -expansion - sectionVisualLift)
        .layoutPriority(1)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: expansion)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var bassSelection: Binding<Int> {
        depthSelection(for: \MixControlsSettings.bassSwapDepth)
    }

    private var midsSelection: Binding<Int> {
        depthSelection(for: \MixControlsSettings.midsSwapDepth)
    }

    private var highsSelection: Binding<Int> {
        depthSelection(for: \MixControlsSettings.highsSwapDepth)
    }

    private var blendLengthSelection: Binding<Int> {
        Binding(
            get: {
                let clamped = max(2.0, min(20.0, playerState.mixControls.blendLengthSeconds))
                return Int((clamped - 2.0) / 0.5)
            },
            set: { index in
                let safeIndex = max(0, min(36, index))
                playerState.mixControls.blendLengthSeconds = 2.0 + Double(safeIndex) * 0.5
            }
        )
    }

    private func depthSelection(for keyPath: WritableKeyPath<MixControlsSettings, Double>) -> Binding<Int> {
        Binding(
            get: {
                let value = playerState.mixControls[keyPath: keyPath]
                return max(0, min(100, Int(value * 100)))
            },
            set: { index in
                let safeIndex = max(0, min(100, index))
                playerState.mixControls[keyPath: keyPath] = Double(safeIndex) / 100.0
            }
        )
    }
}

private struct MixTrackBadge: View {
    let title: String
    let artwork: String?

    var body: some View {
        VStack(spacing: 6) {
            ArtworkView(
                artwork: artwork ?? "",
                size: 46,
                cornerRadius: 10
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )

            Text(title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 90)
        }
    }
}

private struct SwapControlRow: View {
    let title: String
    let percentage: Int
    @Binding var selection: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(percentage)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            BorderedTickPicker(
                count: 100,
                config: TickConfig(
                    tickWidth: 2,
                    tickHeight: 24,
                    inActiveHeightProgress: 0.45,
                    activeTint: tint,
                    inActiveTint: .secondary,
                    alignment: .center
                ),
                selection: $selection
            )
        }
    }
}

private struct BorderedTickPicker: View {
    let count: Int
    let config: TickConfig
    @Binding var selection: Int

    var body: some View {
        TickPicker(
            count: count,
            config: config,
            selection: $selection
        )
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}
