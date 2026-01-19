import SwiftUI
import AuthenticationServices
import Foundation

struct ConnectSoundCloudScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var authSession: ASWebAuthenticationSession?
    @State private var contextProvider = PresentationContextProvider()
    @State private var loginStartTime: Date?
    @State private var peelProgress: Double = 0
    @State private var contentOpacity: Double = 0

    private let staticHoldProgress: Double = 0.67
    private let fadeInDuration: Double = 0.45
    private let screenBufferDelay: Double = 0.3

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer(size: geometry.size)
                    .grayscale(1.0)
                    .blur(radius: 5, opaque: true)

                VStack(spacing: -11) {
                    Spacer()
                    GlassEffectText(
                        text: "Mixbridge",
                        font: UIFont(name: "InstrumentSerif-Italic", size: 46) ?? .systemFont(ofSize: 46)
                    )
                    .frame(height: 60)
                    .opacity(contentOpacity)

                    Spacer()

                    VStack(spacing: 16) {
                        // Error message
                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        // Connect Button
                        Button {
                            HapticManager.heavy()
                            loginStartTime = Date()
                            Analytics.shared.track("soundcloud_login_tapped")
                            startAuthentication()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "cloud.fill")
                                Text("Login with SoundCloud")
                                    .font(.callout)
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .glassEffect(.regular, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20) + 20)
                    .opacity(contentOpacity)
                }
            }
            .onAppear {
                peelProgress = 0
                contentOpacity = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + screenBufferDelay) {
                    peelProgress = staticHoldProgress
                    withAnimation(.easeOut(duration: fadeInDuration)) {
                        contentOpacity = 1
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            Analytics.shared.track("onboarding_viewed")
        }
    }

    private func startAuthentication() {
        guard let authURL = authManager.getAuthorizationURL() else {
            authManager.errorMessage = "Failed to generate auth URL"
            return
        }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "mixbridge"
        ) { callbackURL, error in
            let startTime = loginStartTime ?? Date()
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            func trackLoginResult(_ result: String) {
                Task { @MainActor in
                    Analytics.shared.track(
                        "soundcloud_login_result",
                        properties: ["result": result, "latency_ms": latencyMs]
                    )
                }
            }

            if let error = error {
                if case ASWebAuthenticationSessionError.canceledLogin = error {
                    authManager.isLoading = false
                    trackLoginResult("cancel")
                    return
                }

                authManager.errorMessage = error.localizedDescription
                authManager.isLoading = false
                trackLoginResult("fail")
                return
            }

            guard let callbackURL = callbackURL else {
                authManager.errorMessage = "No callback URL received"
                authManager.isLoading = false
                trackLoginResult("fail")
                return
            }

            if callbackURL.host == "auth-success" {
                trackLoginResult("success")
            } else {
                trackLoginResult("fail")
            }

            Task {
                await authManager.handleCallback(url: callbackURL)
            }
        }

        session.presentationContextProvider = contextProvider
        self.authSession = session
        session.prefersEphemeralWebBrowserSession = false

        let started = session.start()
        if !started {
            authManager.errorMessage = "Authentication session failed to start"
        }
    }

    @ViewBuilder
    private func backgroundLayer(size: CGSize) -> some View {
        if PeelMetalView.isMetalAvailable {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                PeelMetalView(
                    bottomImageName: "background",
                    topImageName: nil,
                    progress: peelProgress,
                    size: size,
                    amplitude: 0.06,
                    frequency: 2.2
                )
                .frame(width: size.width, height: size.height)
                .clipped()
                .ignoresSafeArea()
            }
        } else {
            Image("background")
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .ignoresSafeArea()
        }
    }

}

// MARK: - Presentation Context Provider

class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the key window
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        // Fallback: return first window or create new window with scene
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            // Try to return existing window first
            if let existingWindow = windowScene.windows.first {
                return existingWindow
            }
            // Create new window with scene if no existing window
            return UIWindow(windowScene: windowScene)
        }

        // Last resort fallback - return any existing window
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first ?? {
                // If no window exists, create one with first available scene
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    return UIWindow(windowScene: scene)
                }
                fatalError("No window scene available")
            }()
    }
}

// MARK: - Presentation Anchor Type

#if os(iOS)
typealias PresentationAnchor = UIWindow
#elseif os(macOS)
typealias PresentationAnchor = NSWindow
#endif


#Preview {
    ConnectSoundCloudScreen()
        .environment(AuthManager.shared)
}
