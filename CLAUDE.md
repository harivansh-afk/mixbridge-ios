# MixBridge iOS - Claude Code Instructions

## Project Overview
MixBridge is an iOS app that bridges music platforms (Spotify and SoundCloud).

## Architecture Notes

### Authentication
- Main auth screen is `ConnectSoundCloudScreen.swift` (handles both Spotify and SoundCloud login)
- `SpotifyAuthManager.shared` - singleton for Spotify OAuth flow
- `AuthManager.shared` - singleton for SoundCloud OAuth flow
- Uses `ASWebAuthenticationSession` for SoundCloud with callback scheme `mixbridge`
- Spotify uses separate OAuth flow via `startOAuthFlow()`

### UI Patterns
- Glass effect styling: `.glassEffect(.regular, in: .capsule)` for buttons
- Custom font: "InstrumentSerif-Italic" for branding
- `GlassEffectText` component for styled text
- `HapticManager.heavy()` for button feedback

### Analytics
- `Analytics.shared.track()` for event tracking
- Login events: `spotify_login_tapped`, `soundcloud_login_tapped`
- Login results: `soundcloud_login_result` with latency_ms property

## Coding Conventions

### SwiftUI
- Use `@Environment` for shared managers (e.g., `AuthManager`)
- Use `@State` for local view state
- Prefer `GeometryReader` for responsive layouts

### Style
- No emojis in code or comments
- Use hyphens instead of em dashes
- Keep UI code clean - no hardcoded magic numbers without context

## Known Issues / Technical Debt

- `ConnectSoundCloudScreen.swift` name is misleading - it handles all auth, not just SoundCloud
  - Consider renaming to `AuthScreen.swift` or `LoginScreen.swift`
