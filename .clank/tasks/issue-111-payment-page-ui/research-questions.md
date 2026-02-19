# Research Questions

## 1. StoreKit 2 & Payment Infrastructure

1. What StoreKit 2 APIs are available in iOS 26 for managing subscriptions and one-time purchases?
2. What is the recommended pattern for a StoreKit 2 `Store` service using async/await and `Product.SubscriptionInfo`?
3. How should transaction verification and entitlement checking work with `Transaction.currentEntitlements`?
4. What App Store Server Notifications v2 considerations apply for subscription lifecycle events?

## 2. Product & Subscription Model

5. What tier structure fits a music streaming app — single premium tier, or multiple tiers (e.g., Free / Pro / Pro+)?
6. What features should be gated behind the paywall (offline downloads, high-quality audio, unlimited playlists, no ads)?
7. Should the app support both monthly and annual billing cycles? Free trial periods?
8. How does the existing `FeatureFlags.swift` map to premium feature gating?

## 3. SwiftUI 26 UI Primitives & Patterns

9. What new SwiftUI 26 primitives (e.g., updated `SubscriptionStoreView`, mesh gradients, new scroll APIs) should be used for the payment page?
10. Should the payment page use Apple's native `SubscriptionStoreView` / `StoreView` or a fully custom UI?
11. What `PresentationDetent` and sheet styles best fit a payment flow — full screen cover, bottom sheet, or pushed navigation?
12. How should the payment page handle dark mode, dynamic type, and accessibility (VoiceOver, reduced motion)?

## 4. Visual Design & Layout

13. What visual style matches the existing app aesthetic (dark theme, `.ultraThinMaterial`, `InstrumentSerif` font, gradient accents)?
14. What hero/header content should the payment page display — feature comparison grid, promotional artwork, testimonial cards?
15. How should plan selection work — horizontal carousel of cards, vertical stacked list, or segmented toggle?
16. What call-to-action placement and styling drives conversion (sticky bottom CTA, inline buttons)?

## 5. Navigation & Integration

17. Where in the app should the payment page be triggered — AccountBottomSheet, onboarding flow, feature-locked tap, settings?
18. How should the payment page integrate with `AuthManager` and the existing environment-based DI pattern?
19. What ViewModel pattern should be used — `@Observable PaymentViewModel` wrapping a `PaymentService`?
20. How should successful purchase confirmation be presented (animation, haptic feedback, navigation transition)?

## 6. State Management & Error Handling

21. How should purchase-in-progress, success, failure, and restore states be modeled?
22. What error states need UI treatment — network failure, payment declined, sandbox vs production, parental controls?
23. How should the app persist and verify entitlement state across launches (Keychain, UserDefaults, server validation)?
24. How should the "Restore Purchases" flow work and where should it be placed?

## 7. Existing Codebase Patterns

25. What patterns from `PlaylistDetailView`, `CreatePlaylistSheet`, and `AccountBottomSheet` should be reused for consistency?
26. How does the existing `CachedAsyncImage` and asset pipeline apply to payment page artwork?
27. What animation patterns (matched geometry, transitions) from the existing codebase apply to the payment flow?
28. How should the payment page use the existing `HapticManager` for purchase confirmation feedback?
