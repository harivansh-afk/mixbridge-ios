import SwiftUI

/// Bottom sheet shown when user attempts Spotify login but isn't registered in the beta
struct SpotifyBetaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var isSubmitting = false
    @State private var hasSubmitted = false
    @FocusState private var isEmailFocused: Bool

    private var isValidEmail: Bool {
        let emailRegex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        return email.wholeMatch(of: emailRegex) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                // Spotify icon
                Image("spotify")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .foregroundStyle(.primary.opacity(0.85))

                VStack(spacing: 14) {
                    Text(hasSubmitted ? "You're on the list" : "Join the waitlist")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(hasSubmitted
                         ? "I'll add your account within minutes. Try logging in again shortly."
                         : "Spotify integration is in private beta. Enter your Spotify email and we'll add you.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !hasSubmitted {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Approval typically takes 5-10 minutes", systemImage: "clock")
                        Label("You'll receive access automatically", systemImage: "checkmark.circle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                }

                if hasSubmitted {
                    Button {
                        dismiss()
                    } label: {
                        Text("Got it")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.blue)
                            .clipShape(Capsule())
                            .glassEffect(.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 12) {
                        // Email input
                        TextField("", text: $email, prompt: Text("hari@spotify.com").foregroundStyle(.secondary))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isEmailFocused)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .tint(.primary)
                            .padding(.horizontal, 20)
                            .frame(height: 50)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(Capsule())

                        // Submit button
                        Button {
                            Task {
                                await submitEmail()
                            }
                        } label: {
                            Group {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Join Waitlist")
                                        .font(.body.weight(.semibold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(isValidEmail ? .blue : .blue.opacity(0.4))
                            .clipShape(Capsule())
                            .glassEffect(.regular, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isValidEmail || isSubmitting)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            isEmailFocused = true
        }
    }

    private func submitEmail() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await SpotifyWaitlistService.shared.joinWaitlist(email: email)
            withAnimation {
                hasSubmitted = true
            }
        } catch {
            // Still show success - we don't want to block the user
            withAnimation {
                hasSubmitted = true
            }
        }
    }
}

// MARK: - Waitlist Service

final class SpotifyWaitlistService {
    static let shared = SpotifyWaitlistService()
    private let convexUrl = "https://avid-falcon-471.convex.cloud"

    private init() {}

    func joinWaitlist(email: String) async throws {
        let url = URL(string: "\(convexUrl)/api/mutation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "path": "spotifyWaitlist:joinWaitlist",
            "args": ["email": email],
            "format": "json"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

#Preview {
    Text("Background")
        .sheet(isPresented: .constant(true)) {
            SpotifyBetaSheet()
        }
}
