//
//  ExpandedPlayerQueueSheet.swift
//  mixbridge
//

import SwiftUI
import UIKit

struct ExpandedPlayerQueueSheet: View {
    @Binding var isVisible: Bool
    @Binding var expansion: CGFloat

    let queueRows: [IndexedRow<QueueItem>]
    let queueTopFadeHeight: CGFloat
    let queueListTopInset: CGFloat
    let queueHandleTopPadding: CGFloat
    let queueHandleBottomPadding: CGFloat
    let queueSectionVisualLift: CGFloat

    let onMove: (IndexSet, Int) -> Void
    let onRemove: (QueueItem) -> Void

    @State private var dragStart: CGFloat = 0
    @State private var lightHaptic = UIImpactFeedbackGenerator(style: .light)
    @State private var mediumHaptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle area - larger hit target
            VStack(spacing: 8) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 60, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, queueHandleTopPadding)
            .padding(.bottom, queueHandleBottomPadding)
            .background(Color.clear)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        // Capture start position on first drag movement
                        if dragStart == 0 {
                            dragStart = expansion
                        }

                        // Negative translation = dragging up = expand
                        let drag = -value.translation.height
                        let newExpansion = max(0, min(300, dragStart + drag))

                        // Haptic at thresholds
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

                        // Swipe down to close
                        if value.translation.height > 100 && expansion < 100 {
                            mediumHaptic.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isVisible = false
                                expansion = 0
                            }
                        }
                        // Swipe UP and release: fling up then gravity pulls it down to hide
                        else if value.translation.height < -30 && velocity < -300 {
                            mediumHaptic.impactOccurred()
                            // Gravity-like fall: slightly longer response, lower damping for natural drop
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                                isVisible = false
                                expansion = 0
                            }
                        } else {
                            // Snap to expanded or collapsed based on position
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                expansion = expansion > 100 ? 200 : 0
                            }
                        }
                    }
            )

            List {
                ForEach(queueRows) { row in
                    TrackRow(
                        row.item.track,
                        number: row.index + 1,
                        showCover: true,
                        isQueueContext: true,
                        onRemoveFromQueue: {
                            onRemove(row.item)
                        }
                    )
                    .listRowSeparator(.hidden)
                }
                .onMove(perform: onMove)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Keep the original top fade, but start rows slightly below it so the first row
            // doesn't look "cut off" when the queue is lifted closer to the controls.
            .contentMargins(.top, queueListTopInset, for: .scrollContent)
            .contentMargins(.bottom, 60, for: .scrollContent)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: queueTopFadeHeight)
                    Color.black
                }
            )
        }
        .onAppear {
            lightHaptic.prepare()
            mediumHaptic.prepare()
        }
        .frame(height: 280 + expansion)
        .offset(y: -expansion - queueSectionVisualLift)
        .layoutPriority(1)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: expansion)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

