//
//  AnimatedBottomBar.swift
//  mixbridge
//
//  Created by Harivansh Rathi on 12/19/25.
//

import SwiftUI

struct AnimatedBottomBar<LeadingAction: View, TrailingAction: View, MainAction: View>: View {
    var hint: String
    var tint: Color = .green
    var highlightWhenEmpty: Bool = true
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @ViewBuilder var leadingAction: () -> LeadingAction
    @ViewBuilder var trailingAction: () -> TrailingAction
    @ViewBuilder var mainAction: () -> MainAction

    @State private var isHighligting: Bool = false

    var body: some View {
        let mainLayout = isFocused ? AnyLayout(ZStackLayout(alignment: .bottomTrailing)) :
            AnyLayout(HStackLayout(alignment: .bottom, spacing: 10))
        let shape = RoundedRectangle(cornerRadius: isFocused ? 25 : 30)

        ZStack {
            mainLayout {
                let subLayout = isFocused ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 20)) : AnyLayout(ZStackLayout(alignment: .trailing))

                subLayout {
                    TextField(hint, text: $text, axis: .vertical)
                        .lineLimit(isFocused ? 5 : 1)
                        .focused(_isFocused)
                        .mask {
                            Rectangle()
                                .padding(.trailing, isFocused ? 0 : 40)
                        }

                    /// Trailing & Leading Action View
                    HStack(spacing: 10) {
                        /// Leading Actions
                        HStack(spacing: 10) {
                            ForEach(subviews: leadingAction()) { subview in
                                /// Each button max size is 35
                                subview
                                    .frame(width: 35, height: 35)
                                    .contentShape(.rect)
                            }
                        }
                        .compositingGroup()
                        /// Disabling interaction and hiding when not focused
                        .allowsHitTesting(isFocused)
                        .blur(radius: isFocused ? 0 : 6)
                        .opacity(isFocused ? 1 : 0)

                        Spacer(minLength: 0)

                        /// Trailing Action
                        /// Trailing Action contains of only one button!
                        trailingAction()
                            .frame(width: 35, height: 35)
                            .contentShape(.rect)
                    }
                }
                .frame(height: isFocused ? nil : 55)
                .padding(.leading, 15)
                .padding(.trailing, isFocused ? 15 : 10)
                .padding(.bottom, isFocused ? 10 : 0)
                .padding(.top, isFocused ? 20 : 0)
                .background {
                    shape
                        .fill(.bar)
                        /// Applying Shadows for more visibility
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
                        .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: -5)
                }
                .background {
                    HighlightingBackgroundView(shape: shape)
                }

                /// Main Action Button
                /// Main Action is also a single button view with a matching size of 50
                mainAction()
                    .frame(width: 50, height: 50)
                    .clipShape(.circle)
                    .background {
                        Circle()
                            .fill(.bar)
                            /// Applying Shadows for more visibility
                            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
                            .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: -5)
                    }
                    .visualEffect { [isFocused] content, proxy in
                        content
                            .offset(x: isFocused ? (proxy.size.width + 30) : 0)
                    }
            }
        }
        .geometryGroup()
        .animation(.linear(duration: animationDuration), value: isFocused)
    }

    var animationDuration: CGFloat {
        /// iOS 26 keyboard appears more faster than the older ones!
        if #available(iOS 26, *) {
            return 0.22
        } else {
            return 0.33
        }
    }

    @ViewBuilder
    private func HighlightingBackgroundView(shape: RoundedRectangle) -> some View {
        ZStack {
            if !isFocused && text.isEmpty && highlightWhenEmpty {
                shape
                    .stroke(
                        tint.gradient,
                        style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .mask {
                        /// Increase the count of this to increase the gradient style masking effect
                        /// on the highlighting effect!
                        let clearColors: [Color] = Array(repeating: .clear, count: 3)

                        shape
                            .fill(AngularGradient(
                                colors: clearColors + [Color.white] + clearColors,
                                center: .center,
                                angle: .init(degrees: isHighligting ? 360 : 0)
                            ))
                    }
                    .padding(-2)
                    .blur(radius: 2)
                    .onAppear {
                        /// Infinite Looping Effect
                        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                            isHighligting = true
                        }
                    }
                    .onDisappear {
                        /// Disabling the effect
                        isHighligting = false
                    }
                    .transition(.blurReplace)
            }
        }
    }
}

#Preview {
    AnimatedBottomBarPreview()
}

struct AnimatedBottomBarPreview: View {
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.1).ignoresSafeArea()

            VStack {
                Spacer()

                AnimatedBottomBar(
                    hint: "Type here...",
                    tint: .green,
                    text: $text,
                    isFocused: $isFocused
                ) {
                    Button {
                    } label: {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.secondary.opacity(0.2), in: .circle)
                    }

                    Button {
                    } label: {
                        Image(systemName: "photo")
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.secondary.opacity(0.2), in: .circle)
                    }
                } trailingAction: {
                    Button {
                    } label: {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.secondary.opacity(0.2), in: .circle)
                    }
                } mainAction: {
                    Button {
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.body)
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.bottom, 10)
            }
        }
    }
}
