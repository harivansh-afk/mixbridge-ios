# Mixbridge Project Structure

## Overview

Mixbridge is a SwiftUI application for transferring playlists between music services. The project follows modern SwiftUI best practices with a clean, organized structure.

## Directory Structure

```
mixbridge/
├── docs/                          # Comprehensive SwiftUI & iOS documentation
│   ├── README.md                  # Documentation index
│   ├── swiftui/
│   │   └── BEST_PRACTICES_2025.md # Modern SwiftUI patterns & architecture
│   ├── components/
│   │   └── NATIVE_COMPONENTS.md   # Complete SwiftUI component reference
│   ├── ios/
│   │   └── IOS_18_19_FEATURES.md  # Latest iOS features
│   └── syntax/
│       └── SWIFT_UI_SYNTAX.md     # SwiftUI syntax guide
│
├── mixbridge/
│   ├── mixbridgeApp.swift         # App entry point
│   ├── ContentView.swift          # Main tab navigation
│   │
│   └── Views/                     # All SwiftUI views
│       ├── Home/
│       │   └── HomeView.swift     # Home screen
│       ├── Search/
│       │   └── SearchView.swift   # Search functionality
│       ├── Library/
│       │   └── LibraryView.swift  # Library/history view
│       ├── Liked/
│       │   └── LikedView.swift    # Liked songs view
│       ├── Profile/
│       │   └── ProfileView.swift  # Profile & settings
│       └── Transfer/
│           ├── TransferView.swift       # Transfer container
│           └── TransferDetailView.swift # Transfer detail screen
│
└── PROJECT_STRUCTURE.md           # This file
```

## Architecture

### Current Pattern: View-Based (Simple)

The app currently uses a simple view-based architecture suitable for its current scope:

```
ContentView (TabView)
    ├── HomeView
    ├── SearchView
    ├── LibraryView
    ├── LikedView
    └── ProfileView
```

### Future Scaling: MVVM + Clean Architecture

As the app grows, consider implementing:

```
View → ViewModel (@Observable) → Repository → Service
                ↓
            State updates
                ↓
            View re-renders
```

**Benefits:**
- Testable business logic
- Separation of concerns
- Easier to maintain and scale

## Code Organization Best Practices

### 1. File Structure

Each view follows this pattern:
```swift
// Header comments
import statements

struct ViewName: View {
    // State properties

    var body: some View {
        // Main content reference
    }

    // Private computed properties for subviews
    @ViewBuilder
    private var content: some View {
        // Implementation
    }

    private var section1: some View {
        // Section implementation
    }
}

// MARK: - Supporting Components
// Any view-specific components

// MARK: - Preview
#Preview {
    ViewName()
}
```

### 2. View Composition

Views are broken into smaller, reusable components:

**Example from ProfileView:**
```swift
struct ProfileView: View {
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Profile")
        }
    }

    // Extracted sections
    private var connectedServicesSection: some View { }
    private var settingsSection: some View { }
}

// Reusable component
struct ServiceRow: View { }
```

**Benefits:**
- Easier to read and understand
- Testable components
- Reusable across views
- Better performance (SwiftUI can optimize smaller views)

### 3. State Management

Current approach (simple, local state):
```swift
@State private var searchText = ""
@State private var isLoading = false
```

For future scaling with shared state:
```swift
@Observable
class AppState {
    var user: User?
    var settings: Settings
}

// In view
@Environment(AppState.self) private var appState
```

### 4. Navigation

Using modern NavigationStack (iOS 16+):
```swift
NavigationStack {
    List(items) { item in
        NavigationLink(value: item) {
            ItemRow(item: item)
        }
    }
    .navigationDestination(for: Item.self) { item in
        DetailView(item: item)
    }
}
```

## Key SwiftUI Patterns Used

### 1. ViewBuilder
Enables declarative syntax with multiple views:
```swift
@ViewBuilder
private var content: some View {
    if isLoading {
        ProgressView()
    } else {
        dataView
    }
}
```

### 2. ContentUnavailableView (iOS 17+)
Modern empty states:
```swift
ContentUnavailableView(
    "No Liked Songs",
    systemImage: "heart",
    description: Text("Your liked songs will appear here")
)
```

### 3. Computed Properties for Subviews
Clean view hierarchy:
```swift
private var header: some View {
    VStack {
        Text("Title")
        Text("Subtitle")
    }
}
```

### 4. Extracted Components
Reusable UI elements:
```swift
struct ServiceRow: View {
    let name: String
    let icon: String
    let iconColor: Color
    let status: String

    var body: some View { }
}
```

## View Details

### ContentView
- **Purpose**: Main app container with tab navigation
- **Pattern**: TabView with modern Tab syntax
- **Tabs**: Home, Library, Liked, Search (role-based)
- **Location**: `/mixbridge/ContentView.swift`

### HomeView
- **Purpose**: Landing screen, welcome message
- **Features**: ContentUnavailableView for empty state
- **Navigation**: Wrapped in NavigationStack
- **Location**: `/mixbridge/Views/Home/HomeView.swift`

### SearchView
- **Purpose**: Search playlists across services
- **Features**:
  - Searchable modifier
  - Empty state when no query
  - Results list when searching
- **State**: `@State private var searchText`
- **Location**: `/mixbridge/Views/Search/SearchView.swift`

### LibraryView
- **Purpose**: Show transfer history and saved playlists
- **Structure**: List with sections
- **Sections**: Recent Transfers, Saved Playlists
- **Location**: `/mixbridge/Views/Library/LibraryView.swift`

### LikedView
- **Purpose**: Display user's liked songs
- **Features**: ContentUnavailableView for empty state
- **Location**: `/mixbridge/Views/Liked/LikedView.swift`

### ProfileView
- **Purpose**: User profile and app settings
- **Features**:
  - Connected services status
  - Navigation to Preferences and About
  - Reusable ServiceRow component
- **Location**: `/mixbridge/Views/Profile/ProfileView.swift`

### TransferView & TransferDetailView
- **Purpose**: Playlist transfer functionality
- **Structure**: Container + Detail views
- **Location**: `/mixbridge/Views/Transfer/`

## Naming Conventions

### Files
- Use PascalCase: `HomeView.swift`
- Descriptive names: `TransferDetailView.swift`
- Group related files in folders

### Views
- Suffix with `View`: `HomeView`, `SearchView`
- Components without suffix: `ServiceRow`

### Properties
- camelCase for variables: `searchText`, `isLoading`
- Descriptive names: `connectedServicesSection`

### State
- Prefix with `@State`, `@Binding`, etc.
- Use `private` for local state: `@State private var`

## Performance Considerations

### Current Implementation
- Views are lightweight with extracted components
- ContentUnavailableView for efficient empty states
- NavigationStack for modern, performant navigation

### Future Optimizations
When dealing with large data sets:
1. Use `LazyVStack`/`LazyHStack` for lists
2. Implement view model layer for business logic
3. Use `@Observable` instead of `ObservableObject`
4. Cache expensive computations
5. Optimize image loading with AsyncImage

## Testing Strategy

### Current State
- Preview providers for visual testing
- Manual testing in simulator

### Recommended Approach
When implementing business logic:
```swift
@Observable
class HomeViewModel {
    var playlists: [Playlist] = []

    func loadPlaylists() async {
        // Testable business logic
    }
}

// Easy to unit test
let viewModel = HomeViewModel()
await viewModel.loadPlaylists()
XCTAssertFalse(viewModel.playlists.isEmpty)
```

## Accessibility

All views include:
- Semantic colors (`.primary`, `.secondary`)
- SF Symbols for icons
- Descriptive text
- Native SwiftUI components (built-in accessibility)

Future additions:
- Accessibility labels
- Accessibility hints
- VoiceOver testing

## iOS Version Requirements

- **Minimum**: iOS 17.0 (for ContentUnavailableView)
- **Target**: iOS 18.0+ (for latest SwiftUI features)
- **Recommended**: iOS 19.0+ (for newest patterns)

## Documentation

Comprehensive SwiftUI documentation is available in the `docs/` folder:

1. **[docs/README.md](./docs/README.md)** - Start here for quick references
2. **[docs/swiftui/BEST_PRACTICES_2025.md](./docs/swiftui/BEST_PRACTICES_2025.md)** - Architecture patterns
3. **[docs/components/NATIVE_COMPONENTS.md](./docs/components/NATIVE_COMPONENTS.md)** - Component reference
4. **[docs/ios/IOS_18_19_FEATURES.md](./docs/ios/IOS_18_19_FEATURES.md)** - Latest iOS features
5. **[docs/syntax/SWIFT_UI_SYNTAX.md](./docs/syntax/SWIFT_UI_SYNTAX.md)** - Syntax guide

## Future Enhancements

### Architecture
- [ ] Implement ViewModels with `@Observable`
- [ ] Add Repository pattern for data access
- [ ] Create Service layer for API calls
- [ ] Add dependency injection

### Features
- [ ] Implement actual music service integrations
- [ ] Add playlist transfer logic
- [ ] Implement search functionality
- [ ] Add user authentication
- [ ] Persist data with SwiftData

### Code Quality
- [ ] Add unit tests
- [ ] Add UI tests
- [ ] Implement error handling
- [ ] Add logging
- [ ] Performance profiling

### UI/UX
- [ ] Custom themes
- [ ] Animations and transitions
- [ ] Pull to refresh
- [ ] Loading states
- [ ] Error states

## Getting Started

### Running the App
1. Open `mixbridge.xcodeproj` in Xcode 15+
2. Select a simulator or device (iOS 17+)
3. Press Cmd+R to build and run

### Adding a New View
1. Create folder in `Views/` (e.g., `Views/NewFeature/`)
2. Create `NewFeatureView.swift`
3. Follow the view structure pattern (see above)
4. Add to navigation in `ContentView.swift`

### Code Style
- Follow SwiftUI best practices (see `docs/`)
- Use `@ViewBuilder` for complex views
- Extract subviews for readability
- Add `#Preview` for all views
- Use semantic colors and SF Symbols

## Resources

- [Apple SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [SF Symbols](https://developer.apple.com/sf-symbols/)
- Project docs: `docs/` folder

---

**Last Updated**: November 2025
**SwiftUI Version**: iOS 17-19
**Xcode Version**: 15+
