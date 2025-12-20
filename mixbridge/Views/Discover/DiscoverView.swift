//
//  DiscoverView.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 12/19/25.
//

import SwiftUI

struct DiscoverView: View {
    @Binding var isPresented: Bool
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content area
                ScrollView {
                    VStack(spacing: 24) {
                        // Placeholder content
                        ContentUnavailableView(
                            "Coming Soon",
                            systemImage: "sparkles",
                            description: Text("Discover new music and explore curated content")
                        )
                        .padding(.top, 100)
                    }
                    .padding(.horizontal, 16)
                }

                // AnimatedBottomBar at the bottom
                VStack {
                    Spacer()

                    AnimatedBottomBar(
                        hint: "Search for music...",
                        tint: .green,
                        text: $searchText,
                        isFocused: $isSearchFocused
                    ) {
                        // Leading actions
                        Button {
                            HapticManager.light()
                        } label: {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(Color.primary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.secondary.opacity(0.2), in: .circle)
                        }
                    } trailingAction: {
                        // Trailing action
                        Button {
                            HapticManager.light()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(Color.primary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.secondary.opacity(0.2), in: .circle)
                        }
                    } mainAction: {
                        // Main action
                        Button {
                            HapticManager.light()
                            // Perform search
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticManager.light()
                        isPresented = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .onTapGesture {
                // Dismiss keyboard when tapping outside
                isSearchFocused = false
            }
        }
    }
}

#Preview("Light Mode") {
    DiscoverView(isPresented: .constant(true))
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    DiscoverView(isPresented: .constant(true))
        .preferredColorScheme(.dark)
}
