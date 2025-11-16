import SwiftUI

struct OnboardingView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ConnectSoundCloudScreen()
            .ignoresSafeArea()
    }
}

#Preview {
    OnboardingView()
        .environment(AuthManager.shared)
}
