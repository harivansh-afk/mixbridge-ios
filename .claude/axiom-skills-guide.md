# Axiom Skills Reference Guide

This guide lists all available Axiom skills for iOS/Swift development. Use this to quickly find the right skill for your task.

## How to Use Axiom Skills

1. **Check this guide** when starting iOS/Swift work
2. **Invoke the skill** using `/skill axiom:<skill-name>` or just describe your problem
3. **Router skills** (axiom-ios-*) automatically route to specialized skills

## Quick Decision Tree

| Situation | Start With |
|-----------|------------|
| Build failing | `axiom-ios-build` |
| App is slow | `axiom-ios-performance` |
| Memory leak | `axiom-memory-debugging` |
| SwiftUI issues | `axiom-ios-ui` |
| Navigation problems | `axiom-swiftui-nav-diag` |
| Concurrency errors | `axiom-ios-concurrency` |
| Database/persistence | `axiom-ios-data` |
| iOS 26 design | `axiom-liquid-glass` |
| Code quality check | Run audit commands |

---

## Router Skills (Start Here)

These route to the appropriate specialized skill based on your problem.

| Skill | Description |
|-------|-------------|
| **axiom-ios-accessibility** | VoiceOver, Dynamic Type, color contrast, touch targets, WCAG compliance |
| **axiom-ios-ai** | Apple Intelligence, Foundation Models, @Generable, LanguageModelSession, Tool protocol |
| **axiom-ios-build** | Build failures, compilation errors, dependency conflicts, simulator problems |
| **axiom-ios-concurrency** | Swift 6 concurrency, @MainActor, Sendable, data races, async/await |
| **axiom-ios-data** | SwiftData, Core Data, GRDB, SQLite, CloudKit sync, file storage, migrations |
| **axiom-ios-graphics** | Metal, OpenGL migration, shaders, frame rate, ProMotion, render loops |
| **axiom-ios-integration** | Siri, Shortcuts, widgets, IAP, camera, photo library, audio, haptics |
| **axiom-ios-ml** | CoreML, model compression, MLTensor, speech-to-text, on-device ML |
| **axiom-ios-networking** | URLSession, Network.framework, NetworkConnection, connection diagnostics |
| **axiom-ios-performance** | Memory leaks, profiling, Instruments, retain cycles, optimization |
| **axiom-ios-testing** | Unit tests, UI tests, Swift Testing, async testing, test architecture |
| **axiom-ios-ui** | SwiftUI, UIKit, layout, navigation, animations, design guidelines |
| **axiom-ios-vision** | Image analysis, object detection, pose detection, person segmentation |

---

## Debugging and Diagnostics

### Environment and Build

| Skill | Description |
|-------|-------------|
| **axiom-xcode-debugging** | BUILD FAILED, simulator hangs, zombie processes, stale builds, SPM issues |
| **axiom-build-debugging** | Dependency conflicts, CocoaPods/SPM failures, "Multiple commands produce" |
| **axiom-build-performance** | Slow builds, Build Timeline analysis, compilation caching, incremental builds |
| **axiom-auto-layout-debugging** | "Unable to simultaneously satisfy constraints", layout conflicts |

### Memory and Performance

| Skill | Description |
|-------|-------------|
| **axiom-memory-debugging** | Memory growth, retain cycles, leak diagnosis with Instruments |
| **axiom-performance-profiling** | Decision trees for Instruments (Time Profiler, Allocations, Energy) |
| **axiom-objc-block-retain-cycles** | Objective-C block memory leaks, weak-strong pattern |
| **axiom-concurrency-profiling** | Async/await profiling, actor contention, thread pool exhaustion |
| **axiom-swift-performance** | COW, ARC overhead, generics specialization, collection optimization |

### UI Debugging

| Skill | Description |
|-------|-------------|
| **axiom-swiftui-debugging** | View update issues, struct mutation, binding identity, view recreation |
| **axiom-swiftui-debugging-diag** | Systematic SwiftUI investigation with Instruments integration |
| **axiom-swiftui-performance** | SwiftUI Instrument (iOS 26), long view bodies, Cause & Effect Graph |
| **axiom-uikit-animation-debugging** | CAAnimation completion, spring physics, gesture+animation jank |
| **axiom-display-performance** | Frame rate issues, ProMotion, MTKView, CADisplayLink, frame pacing |

### Diagnostic Skills (-diag suffix)

| Skill | Description |
|-------|-------------|
| **axiom-accessibility-diag** | VoiceOver issues, Dynamic Type violations, WCAG compliance, App Store prep |
| **axiom-background-processing-diag** | Task never runs, terminates early, works in dev not prod |
| **axiom-camera-capture-diag** | Camera freezes, preview rotated, session interrupted, black preview |
| **axiom-cloud-sync-diag** | File not syncing, CloudKit errors, sync conflicts, iCloud upload failed |
| **axiom-core-data-diag** | Migration crashes, thread-confinement errors, N+1 queries |
| **axiom-core-location-diag** | No location updates, background broken, authorization denied, geofence issues |
| **axiom-energy-diag** | App at top of battery settings, phone gets hot, background drain |
| **axiom-foundation-models-diag** | Context exceeded, guardrails, slow generation, availability issues |
| **axiom-metal-migration-diag** | Black screen, rendering artifacts, shader errors, GPU crashes |
| **axiom-networking-diag** | Connection timeouts, TLS failures, data not arriving, proxy issues |
| **axiom-storage-diag** | Files disappeared, data missing after restart, backup too large |
| **axiom-swiftdata-migration-diag** | Migrations crash, relationships lost, works in simulator fails on device |
| **axiom-swiftui-nav-diag** | Navigation not responding, unexpected pops, deep link failures |
| **axiom-vision-diag** | Subject not detected, hand pose missing, low confidence, VisionKit errors |

---

## UI and Design

### Liquid Glass (iOS 26+)

| Skill | Description |
|-------|-------------|
| **axiom-liquid-glass** | Implementation, Regular vs Clear variants, design review defense |
| **axiom-liquid-glass-ref** | Complete app-wide adoption guide (icons, controls, navigation, windows) |

### SwiftUI Layout and Navigation

| Skill | Description |
|-------|-------------|
| **axiom-swiftui-layout** | ViewThatFits vs AnyLayout vs onGeometryChange, iOS 26 free-form windows |
| **axiom-swiftui-layout-ref** | Complete layout API reference |
| **axiom-swiftui-nav** | NavigationStack vs NavigationSplitView, deep links, coordinator patterns |
| **axiom-swiftui-nav-ref** | Comprehensive navigation API reference |
| **axiom-swiftui-containers-ref** | Stacks, grids, outlines, scroll enhancements through iOS 26 |

### SwiftUI Architecture and Animation

| Skill | Description |
|-------|-------------|
| **axiom-swiftui-architecture** | MVVM vs TCA vs vanilla, separating logic from views, refactoring |
| **axiom-swiftui-animation-ref** | VectorArithmetic, @Animatable, zoom transitions, spring vs timing |
| **axiom-swiftui-gestures** | Tap, drag, long press, magnification, rotation, gesture composition |
| **axiom-swiftui-26-ref** | iOS 26 features - 3D layout, WebView, AttributedString, drag/drop |

### Design Guidelines

| Skill | Description |
|-------|-------------|
| **axiom-hig** | Quick design decisions, color/background/typography choices, HIG checklists |
| **axiom-hig-ref** | Comprehensive Human Interface Guidelines with code examples |
| **axiom-typography-ref** | San Francisco fonts, text styles, Dynamic Type, tracking, leading |

---

## Data Persistence

### Frameworks

| Skill | Description |
|-------|-------------|
| **axiom-swiftdata** | @Model, @Query, @Relationship, CloudKit, iOS 26 features, Swift 6 |
| **axiom-sqlitedata** | Point-Free SQLiteData, @Table, FTS5, CTEs, JSON aggregation |
| **axiom-sqlitedata-ref** | Advanced patterns, @Selection, recursive CTEs, database views |
| **axiom-grdb** | Raw SQL, complex joins, ValueObservation, DatabaseMigrator, performance |
| **axiom-core-data** | Core Data vs SwiftData, stack setup, relationships, concurrency |
| **axiom-codable** | JSON encoding/decoding, CodingKeys, enum serialization, date strategies |

### Migrations

| Skill | Description |
|-------|-------------|
| **axiom-database-migration** | Safe schema evolution for SQLite/GRDB, additive migrations |
| **axiom-swiftdata-migration** | VersionedSchema, SchemaMigrationPlan, relationship preservation |
| **axiom-sqlitedata-migration** | SwiftData to SQLiteData decision guide, pattern equivalents |
| **axiom-realm-migration-ref** | Realm to SwiftData migration (Realm sunset Sept 2025) |

### Storage and Sync

| Skill | Description |
|-------|-------------|
| **axiom-storage** | Decision framework - SwiftData vs files, CloudKit vs iCloud Drive |
| **axiom-storage-management-ref** | Purge files, storage pressure, isExcludedFromBackup |
| **axiom-cloud-sync** | CloudKit vs iCloud Drive, offline-first patterns, sync architecture |
| **axiom-cloudkit-ref** | CKSyncEngine, CKRecord, shared/public database, conflict resolution |
| **axiom-icloud-drive-ref** | Ubiquitous container, NSFileCoordinator, NSFilePresenter |
| **axiom-file-protection-ref** | NSFileProtection, file encryption, data protection APIs |

---

## Concurrency

| Skill | Description |
|-------|-------------|
| **axiom-swift-concurrency** | Swift 6 strict concurrency, actor isolation, Sendable, data races |
| **axiom-synchronization** | Mutex (iOS 18+), OSAllocatedUnfairLock, Atomic types, locks vs actors |
| **axiom-assume-isolated** | MainActor.assumeIsolated, @preconcurrency, synchronous actor access |
| **axiom-ownership-conventions** | Borrowing, consuming, ~Copyable types, ARC optimization |

---

## Networking

| Skill | Description |
|-------|-------------|
| **axiom-networking** | Network.framework, NetworkConnection (iOS 26), structured concurrency |
| **axiom-network-framework-ref** | Complete API reference, TLV framing, Coder protocol, Wi-Fi Aware |

---

## Apple Intelligence and ML

### Foundation Models (iOS 26+)

| Skill | Description |
|-------|-------------|
| **axiom-foundation-models** | On-device AI, LanguageModelSession, @Generable, streaming, tool calling |
| **axiom-foundation-models-ref** | Complete API reference with all WWDC 2025 examples |

### Vision Framework

| Skill | Description |
|-------|-------------|
| **axiom-vision** | Subject segmentation, VNGenerateForegroundInstanceMaskRequest, OCR |
| **axiom-vision-ref** | Hand/body pose, face detection, VNImageRequestHandler, DataScanner |

---

## System Integration

### App Intents and Shortcuts

| Skill | Description |
|-------|-------------|
| **axiom-app-intents-ref** | Siri, Apple Intelligence, Shortcuts, Spotlight integration |
| **axiom-app-shortcuts-ref** | AppShortcutsProvider, suggested phrases, instant Siri availability |
| **axiom-app-discoverability** | 6-step strategy for Spotlight, Siri suggestions, system experiences |
| **axiom-core-spotlight-ref** | CSSearchableItem, IndexedEntity, NSUserActivity |

### Extensions and Widgets

| Skill | Description |
|-------|-------------|
| **axiom-extensions-widgets** | Widgets, Live Activities, Control Center controls |
| **axiom-extensions-widgets-ref** | WidgetKit, ActivityKit, App Groups, extension lifecycle |

### In-App Purchases

| Skill | Description |
|-------|-------------|
| **axiom-in-app-purchases** | StoreKit 2, subscriptions, transaction handling, testing |
| **axiom-storekit-ref** | Product, Transaction, SubscriptionStatus, StoreKit Views |

### Media

| Skill | Description |
|-------|-------------|
| **axiom-avfoundation-ref** | Audio APIs, AVAudioSession, AVAudioEngine, bit-perfect DAC, spatial audio |
| **axiom-camera-capture** | AVCaptureSession, photo/video capture, RotationCoordinator |
| **axiom-camera-capture-ref** | AVCapturePhotoSettings, AVCapturePhotoOutput, session presets |
| **axiom-photo-library** | PHPicker, PhotosPicker, limited library access, save to camera roll |
| **axiom-photo-library-ref** | PHPickerViewController, PhotosPickerItem, Transferable |
| **axiom-now-playing** | Lock Screen metadata, remote commands, artwork, playback state |
| **axiom-haptics** | Core Haptics, UIFeedbackGenerator, CHHapticEngine, AHAP patterns |

### Location and Background

| Skill | Description |
|-------|-------------|
| **axiom-core-location** | Authorization strategy, monitoring, accuracy selection, background |
| **axiom-core-location-ref** | CLLocationUpdate, CLMonitor, CLServiceSession |
| **axiom-background-processing** | BGTaskScheduler, task lifecycle, expiration handling, Swift 6 patterns |
| **axiom-background-processing-ref** | BGAppRefreshTask, BGProcessingTask, BGContinuedProcessingTask (iOS 26) |

### Energy

| Skill | Description |
|-------|-------------|
| **axiom-energy** | Power Profiler diagnosis, subsystem identification, anti-pattern fixes |
| **axiom-energy-ref** | Power Profiler workflows, MetricKit monitoring, timer/network/location APIs |

---

## Testing

| Skill | Description |
|-------|-------------|
| **axiom-swift-testing** | @Test/@Suite macros, #expect/#require, parameterized tests, traits |
| **axiom-testing-async** | Confirmation for callbacks, @MainActor tests, timeout control |
| **axiom-ui-testing** | Recording UI Automation (WWDC 2025), condition-based waiting, accessibility-first |

---

## Other

| Skill | Description |
|-------|-------------|
| **axiom-localization** | String Catalogs, plurals, RTL layouts, locale-aware formatting |
| **axiom-privacy-ux** | Privacy manifests, permission requests, App Tracking Transparency |
| **axiom-app-composition** | App entry points, authentication flows, @main structure, scene lifecycle |
| **axiom-textkit-ref** | TextKit 2 architecture, Writing Tools, SwiftUI TextEditor |
| **axiom-deep-link-debugging** | Debug-only deep links, simulator navigation, automated testing |
| **axiom-apple-docs-research** | Techniques for retrieving Apple docs, WWDC transcripts, code samples |
| **axiom-getting-started** | Interactive onboarding, skill recommendations based on project |
| **axiom-using-axiom** | How to find and use Axiom skills, router skill workflow |

---

## Audit Commands (Quick Scans)

Run these for automated code quality checks:

| Command | What It Finds |
|---------|---------------|
| `/axiom:audit-accessibility` | VoiceOver labels, Dynamic Type, contrast, touch targets |
| `/axiom:audit-concurrency` | Swift 6 violations, unsafe tasks, missing @MainActor |
| `/axiom:audit-memory` | Timer leaks, observer leaks, closure captures, delegate cycles |
| `/axiom:audit-core-data` | Migration risks, thread violations, N+1 queries |
| `/axiom:audit-networking` | Deprecated APIs (SCNetworkReachability, CFSocket), anti-patterns |
| `/axiom:audit-liquid-glass` | Glass adoption opportunities, toolbar improvements |

---

## Skill Naming Conventions

- **No suffix**: Discipline skills with step-by-step workflows
- **-diag suffix**: Diagnostic skills for systematic troubleshooting
- **-ref suffix**: Reference skills with comprehensive API guides

---

**Total**: 100+ skills covering the complete iOS development lifecycle
