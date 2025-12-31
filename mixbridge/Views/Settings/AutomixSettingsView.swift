//
//  AutomixSettingsView.swift
//  mixbridge
//
//  Settings page for configuring automix/crossfade behavior.
//

import SwiftUI

struct AutomixSettingsView: View {
    @Bindable var playerState = PlayerState.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Automix Toggle
            Section {
                Toggle(isOn: $playerState.mixEnabled) {
                    Label("Automix", systemImage: "waveform.path")
                }
                .tint(.blue)
            }

            // Duration Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Slider(value: $playerState.crossfadeSeconds, in: 0...12, step: 0.5) {
                        Text("Duration")
                    } minimumValueLabel: {
                        Text("0s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("12s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tint(.blue)
                }
                .glassEffect(.regular)
            } header: {
                Text("Duration")
            }

            // Curve Section - Native Picker with liquid glass
            Section {
                Picker("Fade Curve", selection: $playerState.fadeCurve) {
                    ForEach(FadeCurve.allCases, id: \.self) { curve in
                        Label {
                            Text(curve.displayName)
                        } icon: {
                            Image(systemName: curve.icon)
                        }
                        .tag(curve)
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: playerState.fadeCurve) { _, _ in
                    HapticManager.selection()
                }
            } header: {
                Text("Fade Curve")
            }

            // Advanced Section
            Section {
                HStack {
                    Text("Prewarm Time")
                    Spacer()
                    Text("\(Int(playerState.prewarmSeconds))s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $playerState.prewarmSeconds, in: 5...60, step: 5) {
                    Text("Prewarm")
                }
                .tint(.blue)
            } header: {
                Text("Advanced")
            }
        }
        .listStyle(InsetGroupedListStyle())
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
        if seconds == 0 {
            return "Off"
        } else if seconds == floor(seconds) {
            return "\(Int(seconds))s"
        } else {
            return String(format: "%.1fs", seconds)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AutomixSettingsView()
    }
}
