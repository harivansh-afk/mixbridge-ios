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
                    Text("Automix")
                }
                .tint(.blue)
            }

            // Duration Section
            Section {
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
            } header: {
                Text("Duration")
            }

            // Prewarm Time Section
            Section {
                Slider(value: $playerState.prewarmSeconds, in: 5...60, step: 5) {
                    Text("Prewarm Time")
                } minimumValueLabel: {
                    Text("5s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("60s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(.blue)
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
        }
        .listStyle(InsetGroupedListStyle())
        .listSectionSpacing(12)
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
}

// MARK: - Fade Curve Picker

struct FadeCurvePicker: View {
    @Binding var selection: FadeCurve
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(FadeCurve.allCases, id: \.self) { curve in
                Button {
                    selection = curve
                    HapticManager.selection()
                    dismiss()
                } label: {
                    HStack {
                        Text(curve.displayName)
                        Spacer()
                        if curve == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .scrollContentBackground(.hidden)
        .background(.clear)
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
}
