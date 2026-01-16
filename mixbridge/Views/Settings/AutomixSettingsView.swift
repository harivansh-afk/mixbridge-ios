//
//  AutomixSettingsView.swift
//  mixbridge
//
//  Settings page for configuring automix/crossfade behavior.
//

import SwiftUI

struct AutomixSettingsView: View {
    @Environment(PlayerState.self) private var playerState
    @Environment(\.dismiss) private var dismiss

    // Binding to convert crossfadeSeconds (Double 1-20, step 0.5) to Int selection (0-38)
    private var crossfadeSelection: Binding<Int> {
        Binding(
            get: { Int((playerState.crossfadeSeconds - 1) / 0.5) },
            set: { playerState.crossfadeSeconds = 1 + Double($0) * 0.5 }
        )
    }

    // Binding to convert prewarmSeconds (Double 5-60, step 1) to Int selection (0-55)
    private var prewarmSelection: Binding<Int> {
        Binding(
            get: { Int(playerState.prewarmSeconds - 5) },
            set: { playerState.prewarmSeconds = 5 + Double($0) }
        )
    }

    var body: some View {
        @Bindable var playerState = playerState

        List {
            // Automix Toggle
            Section {
                Toggle(isOn: $playerState.mixEnabled) {
                    Text("Automix")
                }
                .tint(.blue)

                Toggle(isOn: $playerState.djEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DJ Mode (Downloaded-only)")
                        Text("Beat/tempo mixing requires offline downloads. Streaming uses normal crossfade.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.purple)
            }

            // Duration Section
            Section {
                VStack(spacing: 8) {
                    TickPicker(
                        count: 38,
                        config: TickConfig(
                            tickWidth: 2,
                            tickHeight: 30,
                            inActiveHeightProgress: 0.43,
                            activeTint: .blue,
                            inActiveTint: .secondary,
                            alignment: .center
                        ),
                        selection: crossfadeSelection
                    )

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(formatDuration(playerState.crossfadeSeconds))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text("s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            } header: {
                Text("Duration")
            }

            // Prewarm Time Section
            Section {
                VStack(spacing: 8) {
                    TickPicker(
                        count: 55,
                        config: TickConfig(
                            tickWidth: 2,
                            tickHeight: 30,
                            inActiveHeightProgress: 0.43,
                            activeTint: .blue,
                            inActiveTint: .secondary,
                            alignment: .center
                        ),
                        selection: prewarmSelection
                    )

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(playerState.prewarmSeconds))")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text("s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            } header: {
                Text("Prewarm Time")
            }

            // Fade Curve Section
            Section {
                NavigationLink {
                    FadeCurvePicker(selection: $playerState.fadeCurve)
                } label: {
                    Text(playerState.fadeCurve.displayName)
                }
            } header: {
                Text("Fade Curve")
            }

            // DJ Download Prep
            Section {
                Toggle(isOn: $playerState.djStrictMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Force DJ backend (no fallback)")
                        Text("For testing: if a track isn’t downloaded or DJ can’t start, playback will error instead of using normal crossfade.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!playerState.djEnabled)

                Toggle(isOn: $playerState.djAutoDownloadAhead) {
                    Text("Auto-download upcoming tracks")
                }
                .disabled(!playerState.djEnabled)

                Stepper(value: $playerState.djDownloadAheadCount, in: 1...5) {
                    Text("Download ahead: \(playerState.djDownloadAheadCount)")
                }
                .disabled(!playerState.djEnabled || !playerState.djAutoDownloadAhead)
            } header: {
                Text("DJ Prep")
            }
        }
        .listStyle(InsetGroupedListStyle())
        .listSectionSpacing(23)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .contentMargins(.top, 5, for: .scrollContent)
        .toolbarBackground(.hidden, for: .navigationBar)
        .containerBackground(.clear, for: .navigation)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds == seconds.rounded() {
            return "\(Int(seconds))"
        } else {
            return String(format: "%.1f", seconds)
        }
    }
}

// MARK: - Fade Curve Picker

struct FadeCurvePicker: View {
    @Binding var selection: FadeCurve
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Selection rows
            Section {
                ForEach(FadeCurve.allCases, id: \.self) { curve in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = curve
                        }
                        HapticManager.selection()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(curve.displayName)
                                    .font(.body)
                                Text(curve.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if curve == selection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .foregroundStyle(.primary)
                }
            }
            
            // Large curve preview
            Section {
                FadeCurveShape.FadeCurvePreview(curve: selection)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            } header: {
                Text("Preview")
            }
        }
        .listStyle(InsetGroupedListStyle())
        .listSectionSpacing(23)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .contentMargins(.top, 5, for: .scrollContent)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AutomixSettingsView()
    }
    .environment(PlayerState.shared)
}
