//
//  ToastView.swift
//  mixbridge
//

import SwiftUI

extension View {
    @ViewBuilder
    func dynamicIslandToast(isPresented: Binding<Bool>, value: Toast) -> some View {
        self
            .modifier(
                DynamicIslandToastViewModifier(
                    isPresented: isPresented,
                    value: value
                )
            )
    }
}

/// Helper View Modifier
struct DynamicIslandToastViewModifier: ViewModifier {
    @Binding var isPresented: Bool
    var value: Toast
    /// View Properties
    @State private var overlayWindow: PassThroughWindow?
    @State private var overlayController: CustomHostingView?
    func body(content: Content) -> some View {
        content
            .background(WindowExtractor { mainWindow in
                createOverlayWindow(mainWindow)
            })
            .onChange(of: isPresented, initial: true) { oldValue, newValue in
                guard let overlayWindow else { return }
                if newValue {
                    /// Setting Current Toast
                    overlayWindow.toast = value
                }

                overlayWindow.isPresented = newValue
                /// Updating Status Bar
                overlayController?.isStatusBarHidden = newValue
            }
            /// If the toast is closed outside we need to update the isPresented Property as well!
            .onChange(of: overlayWindow?.isPresented) { oldValue, newValue in
                if let newValue, newValue == false, isPresented == true {
                    isPresented = false
                }
            }
    }

    private func createOverlayWindow(_ mainWindow: UIWindow) {
        guard let windowScene = mainWindow.windowScene else { return }

        if let window = windowScene.windows.first(where: { $0.tag == 1009 }) as? PassThroughWindow {
            print("Using Already Exisiting Window!")
            self.overlayWindow = window
            self.overlayController = window.rootViewController as? CustomHostingView
        } else {
            let overlayWindow = PassThroughWindow(windowScene: windowScene)
            overlayWindow.backgroundColor = .clear
            overlayWindow.windowLevel = .statusBar + 1
            overlayWindow.isUserInteractionEnabled = true
            overlayWindow.tag = 1009
            createRootController(overlayWindow)
            overlayWindow.isHidden = false

            self.overlayWindow = overlayWindow
        }
    }

    private func createRootController(_ window: PassThroughWindow) {
        let hostingController = CustomHostingView(
            rootView: ToastView(window: window)
        )

        hostingController.view.backgroundColor = .clear
        window.rootViewController = hostingController

        self.overlayController = hostingController
    }
}

struct ToastView: View {
    var window: PassThroughWindow
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        GeometryReader {
            let safeArea = $0.safeAreaInsets
            let size = $0.size

            /// Dynamic Island
            let haveDynamicIsland: Bool = safeArea.top >= 59
            let dynamicIslandWidth: CGFloat = 120
            let dynamicIslandHeight: CGFloat = 36
            let topOffset: CGFloat = 11 + max((safeArea.top - 59), 0)

            /// Expanded Properties
            let expandedWidth = size.width - 30 
            let expandedHeight: CGFloat = haveDynamicIsland ? 76 : 60
            let scaleX: CGFloat = isExpanded ? 1 : (dynamicIslandWidth / expandedWidth)
            let scaleY: CGFloat = isExpanded ? 1 : (dynamicIslandHeight / expandedHeight)

            ZStack {
                ConcentricRectangle(corners: .concentric(minimum: .fixed(60)), isUniform: true)
                    .fill(.black)
                    .overlay {
                        ToastContent(haveDynamicIsland)
                            /// Keeping the exact expanded size and using the scale to shrink and fit
                            /// Avoids any text wraps and other such things!
                            .frame(width: expandedWidth, height: expandedHeight)
                            .scaleEffect(x: scaleX, y: scaleY)
                    }
                    .frame(
                        width: isExpanded ? expandedWidth : dynamicIslandWidth,
                        height: isExpanded ? expandedHeight : dynamicIslandHeight
                    )
                    .offset(
                        y: haveDynamicIsland ? topOffset : (isExpanded ? safeArea.top + 10 : -80)
                    )
                    /// For Non Dynamic Island Based Phones!
                    .opacity(haveDynamicIsland ? 1 : (isExpanded ? 1 : 0))
                    /// For Dynamic Island Based Phones!
                    /// Showing capsule when the effect is active and hiding it when it's not
                    .animation(.smooth(duration: 0.3).delay(isExpanded ? 0 : 0.35)) { content in
                        content
                            .opacity(haveDynamicIsland ? isExpanded ? 1 : 0 : 1)
                    }
                    .geometryGroup()
                    .contentShape(.rect)
                    .gesture(
                        DragGesture().onEnded { value in
                            if value.translation.height < 0 {
                                /// Dismiss
                                window.isPresented = false
                            }
                        }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .animation(.smooth(duration: 0.5), value: isExpanded)
            .onChange(of: isExpanded) { _, newValue in
                if newValue {
                    // Cancel any existing dismiss task
                    dismissTask?.cancel()
                    // Auto-dismiss after 1 second
                    dismissTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled {
                            window.isPresented = false
                        }
                    }
                } else {
                    dismissTask?.cancel()
                    dismissTask = nil
                }
            }
        }
    }

    /// Toast View Content
    @ViewBuilder
    func ToastContent(_ haveDynamicIsland: Bool) -> some View {
        if let toast = window.toast {
            HStack(spacing: 12) {
                Image(systemName: toast.symbol)
                    .font(toast.symbolFont)
                    .foregroundStyle(toast.symbolForegroundStyle.0, toast.symbolForegroundStyle.1)
                    .symbolEffect(.bounce, value: isExpanded)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(toast.message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .compositingGroup()
            .blur(radius: isExpanded ? 0 : 5)
            .opacity(isExpanded ? 1 : 0)
        }
    }

    var isExpanded: Bool {
        window.isPresented
    }
}
