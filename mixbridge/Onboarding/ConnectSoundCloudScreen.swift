import SwiftUI
import AuthenticationServices

struct ConnectSoundCloudScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var authSession: ASWebAuthenticationSession?
    @State private var contextProvider = PresentationContextProvider()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // SoundCloud Logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.4, blue: 0.0), Color(red: 1.0, green: 0.5, blue: 0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 40)

                Image(systemName: "cloud.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.4, blue: 0.0), Color(red: 1.0, green: 0.5, blue: 0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(height: 180)

            // Title
            Text("Connect Your\nSoundCloud")
                .font(.system(size: 36, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Description
            Text("Sign in to access your music library, likes, and playlists")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            Spacer()

            // Connect Button
            Button {
                startAuthentication()
            } label: {
                HStack(spacing: 12) {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "cloud.fill")
                            .font(.title3)

                        Text("Connect SoundCloud")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundColor(.white)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.4, blue: 0.0), Color(red: 1.0, green: 0.5, blue: 0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
            }
            .disabled(authManager.isLoading)
            .padding(.horizontal, 40)

            // Error message
            if let error = authManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
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
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
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
