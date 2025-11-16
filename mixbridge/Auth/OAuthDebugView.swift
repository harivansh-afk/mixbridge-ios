import SwiftUI

/// Debug view to test OAuth URL generation - REMOVE IN PRODUCTION
struct OAuthDebugView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var generatedURL: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Generated OAuth URL") {
                    if !generatedURL.isEmpty {
                        Text(generatedURL)
                            .font(.caption)
                            .textSelection(.enabled)
                    } else {
                        Text("Tap button below to generate")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Actions") {
                    Button("Generate URL") {
                        if let url = authManager.getAuthorizationURL() {
                            generatedURL = url.absoluteString
                            print("🔐 Full URL:\n\(url.absoluteString)")
                        } else {
                            generatedURL = "Failed to generate URL"
                        }
                    }

                    Button("Copy URL") {
                        UIPasteboard.general.string = generatedURL
                    }
                    .disabled(generatedURL.isEmpty)

                    Button("Open in Safari") {
                        if let url = URL(string: generatedURL) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .disabled(generatedURL.isEmpty)
                }

                Section("Instructions") {
                    Text("""
                    1. Generate URL
                    2. Copy it
                    3. Paste in browser
                    4. Login to SoundCloud
                    5. See what error you get

                    This helps diagnose if the issue is:
                    - URL formation ❌
                    - Redirect URI not whitelisted ❌
                    - Something else ❌
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("OAuth Debug")
        }
    }
}

#Preview {
    OAuthDebugView()
        .environment(AuthManager.shared)
}
