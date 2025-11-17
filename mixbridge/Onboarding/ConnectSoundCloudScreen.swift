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
                    .grayscale(0.7)
                    .blur(radius: 5, opaque: true)

                VStack(spacing: -11) {
                    Spacer()

                    // Title
                    Text("Welcome to")
                        .font(.custom("InstrumentSerif-Regular", size:30))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text("Mixbridge")
                        .font(.custom("InstrumentSerif-Italic", size: 46))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

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
                                if authManager.isLoading {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Image(systemName: "cloud.fill")
                                        .foregroundColor(.white)
                                    Text("Login with SoundCloud")
                                        .foregroundColor(.white)
                                        .font(.callout)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        
                        .controlSize(.large)
                        .disabled(authManager.isLoading)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20) + 20)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func startAuthentication() {
        print("🎯 startAuthentication called")

        guard let authURL = authManager.getAuthorizationURL() else {
            print("❌ Failed to generate auth URL")
            authManager.errorMessage = "Failed to generate auth URL"
            return
        }

        print("🌐 Creating ASWebAuthenticationSession with URL: \(authURL.absoluteString)")
        print("🔗 Callback scheme: mixbridge")

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "mixbridge"
        ) { callbackURL, error in
            print("📞 Session completion handler called")

            if let error = error {
                let nsError = error as NSError
                print("❌ Error occurred:")
                print("   Domain: \(nsError.domain)")
                print("   Code: \(nsError.code)")
                print("   Description: \(error.localizedDescription)")
                print("   User Info: \(nsError.userInfo)")

                if case ASWebAuthenticationSessionError.canceledLogin = error {
                    print("ℹ️ User cancelled login")
                    authManager.isLoading = false
                    return
                }

                authManager.errorMessage = error.localizedDescription
                authManager.isLoading = false
                return
            }

            guard let callbackURL = callbackURL else {
                print("❌ No callback URL received")
                authManager.errorMessage = "No callback URL received"
                authManager.isLoading = false
                return
            }

            print("✅ Received callback URL: \(callbackURL.absoluteString)")

            // Handle the callback
            Task {
                await authManager.handleCallback(url: callbackURL)
            }
        }

        // Set presentation context provider BEFORE storing session
        session.presentationContextProvider = contextProvider
        print("🎭 Presentation context provider set")

        // Store session to prevent deallocation
        self.authSession = session
        print("💾 Session stored in @State variable")

        session.prefersEphemeralWebBrowserSession = false
        print("🔧 prefersEphemeralWebBrowserSession set to false")

        print("🚀 Starting session...")
        let started = session.start()
        print("📊 Session start result: \(started)")

        if !started {
            print("⚠️ Session failed to start!")
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
            return UIWindow(windowScene: windowScene)
        }

        // Last resort fallback
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first ?? UIWindow(frame: .zero)
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
