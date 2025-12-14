import SwiftUI
import AuthenticationServices

struct ConnectSoundCloudScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var authSession: ASWebAuthenticationSession?
    @State private var contextProvider = PresentationContextProvider()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background Image
                Image("background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()
                    .blur(radius: 5, opaque: true)

                VStack(spacing: -11) {
                    Spacer()
                GlassEffectText(
                        text: "Mixbridge",
                        font: UIFont(name: "InstrumentSerif-Italic", size: 46) ?? .systemFont(ofSize: 46)
                    )
                    .frame(height: 60)

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
                }
            }
        }
        .ignoresSafeArea()
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
            if let error = error {
                if case ASWebAuthenticationSessionError.canceledLogin = error {
                    authManager.isLoading = false
                    return
                }

                authManager.errorMessage = error.localizedDescription
                authManager.isLoading = false
                return
            }

            guard let callbackURL = callbackURL else {
                authManager.errorMessage = "No callback URL received"
                authManager.isLoading = false
                return
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
