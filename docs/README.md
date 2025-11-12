# SwiftUI & iOS Documentation

Comprehensive reference documentation for SwiftUI development with iOS 18/19.

## Documentation Structure

### 📱 [SwiftUI Best Practices](./swiftui/BEST_PRACTICES_2025.md)
- Modern architecture patterns (MVVM + Clean + Feature Modules)
- State management with @Observable
- Navigation patterns
- Performance optimization
- Testing strategies
- Common pitfalls to avoid

### 🧩 [Native Components](./components/NATIVE_COMPONENTS.md)
- Complete reference of SwiftUI components
- Layout containers (VStack, HStack, ZStack, Grid)
- Navigation components (NavigationStack, TabView)
- Lists and collections
- Forms and inputs
- Buttons and controls
- Images and media
- Sheets, alerts, and dialogs

### 🆕 [iOS 18/19 Features](./ios/IOS_18_19_FEATURES.md)
- iOS 18 features (Mesh Gradients, Zoom Transitions, Enhanced Tabs)
- iOS 19 features (NavigationStack 2.0, Advanced Animations)
- Migration guides
- Feature comparison tables
- Backwards compatibility

### 📖 [SwiftUI Syntax & Patterns](./syntax/SWIFT_UI_SYNTAX.md)
- Property wrappers (@State, @Binding, @Observable)
- ViewBuilder and control flow
- Async/await patterns
- Gestures and animations
- Custom modifiers
- Common design patterns (MVVM, Repository)

## Quick Start

### Modern View Structure (2025)

```swift
import SwiftUI

struct MyView: View {
    @State private var viewModel = ViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("My View")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
        } else if viewModel.items.isEmpty {
            ContentUnavailableView("No Items", systemImage: "tray")
        } else {
            List(viewModel.items) { item in
                ItemRow(item: item)
            }
        }
    }
}

@Observable
class ViewModel {
    var items: [Item] = []
    var isLoading = false

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }
        // Load data
    }
}
```

### Key Principles

1. **Use @Observable** instead of ObservableObject (iOS 17+)
2. **NavigationStack** over NavigationView
3. **Extract subviews** for better code organization
4. **Unidirectional data flow** - State down, actions up
5. **Async/await** for asynchronous operations
6. **ContentUnavailableView** for empty states (iOS 17+)

## Architecture Overview

### Recommended Structure

```
App
├── Views/               # SwiftUI views
├── ViewModels/          # @Observable view models
├── Models/              # Data models
├── Services/            # Network, persistence, etc.
├── Repositories/        # Data access layer
└── Utilities/           # Helpers and extensions
```

### Data Flow

```
View → ViewModel → Repository → Service
         ↓
     @Observable
         ↓
    View Updates
```

## Common Components Quick Reference

| Component | Use Case | Example |
|-----------|----------|---------|
| VStack | Vertical layout | `VStack { Text("1"); Text("2") }` |
| HStack | Horizontal layout | `HStack { Text("Left"); Text("Right") }` |
| List | Scrollable list | `List(items) { item in Text(item.name) }` |
| NavigationStack | Navigation | `NavigationStack { content }` |
| TabView | Tab navigation | `TabView { Tab("Home", systemImage: "house") { } }` |
| Form | Input forms | `Form { TextField("Name", text: $name) }` |
| Button | Actions | `Button("Tap") { action() }` |
| TextField | Text input | `TextField("Enter", text: $text)` |
| Toggle | On/off switch | `Toggle("Enable", isOn: $isOn)` |
| AsyncImage | Load images | `AsyncImage(url: url)` |

## Property Wrappers Quick Reference

| Wrapper | Purpose | Example |
|---------|---------|---------|
| @State | Local view state | `@State private var count = 0` |
| @Binding | Two-way binding | `@Binding var text: String` |
| @Observable | Observable state | `@Observable class ViewModel { }` |
| @Environment | Environment values | `@Environment(\.dismiss) var dismiss` |

## Modern vs Legacy Patterns

### State Management

**Legacy (Avoid):**
```swift
class ViewModel: ObservableObject {
    @Published var items: [Item] = []
}

@StateObject private var viewModel = ViewModel()
```

**Modern (Use):**
```swift
@Observable
class ViewModel {
    var items: [Item] = []
}

@State private var viewModel = ViewModel()
```

### Navigation

**Legacy (Avoid):**
```swift
NavigationView {
    List { }
}
```

**Modern (Use):**
```swift
NavigationStack {
    List { }
}
```

## Resources

### Official Apple Documentation
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [WWDC Sessions](https://developer.apple.com/videos/)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

### Community Resources
- [Hacking with Swift](https://www.hackingwithswift.com/)
- [Swift with Majid](https://swiftwithmajid.com/)
- [SwiftLee](https://www.avanderlee.com/)

### Tools
- Xcode 15+
- SF Symbols App
- Simulator

## Version Requirements

- **iOS 17+**: @Observable, ContentUnavailableView
- **iOS 18+**: Mesh Gradients, Enhanced Tabs, Zoom Transitions
- **iOS 19+**: NavigationStack 2.0, Advanced Animations

## Getting Help

When encountering issues:
1. Check the relevant documentation section
2. Review code examples
3. Check iOS version requirements
4. Look for migration guides if updating from older iOS versions

## Contributing

This documentation is living and should be updated as SwiftUI evolves. Key areas to watch:
- New WWDC announcements
- iOS beta releases
- Community best practices
- Performance improvements

---

Last Updated: November 2025
iOS Versions Covered: iOS 17, iOS 18, iOS 19
