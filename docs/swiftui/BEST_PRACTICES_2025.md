# SwiftUI Best Practices 2025

## Architecture Evolution

### Modern MVVM in 2025

Classic MVVM is evolving. SwiftUI 2025 features like `@Observable`, `@Bindable`, Swift macros, and SwiftData have transformed how we structure apps.

**Key Changes:**
- No more `@Published` spam with `@Observable` macro
- ViewModels are leaner and more focused
- Unidirectional data flow is preferred over layered separation

### Recommended Architecture: MVVM + Clean + Feature Modules

```
NetworkService → Handles HTTP calls
Repository → Bridges network & business logic
ViewModel → Owns state & async logic (@Observable)
View → Binds to ViewModel for rendering
```

**Benefits:**
- Testability
- Modularity
- Clean separation of concerns
- Scalable for large apps

## Core Principles

### 1. Use @Observable Instead of ObservableObject

**Old Way (Avoid):**
```swift
class ViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
}
```

**Modern Way (2025):**
```swift
@Observable
class ViewModel {
    var items: [Item] = []
    var isLoading = false
}
```

### 2. Unidirectional Data Flow

- State flows down through views
- Actions flow up through bindings or callbacks
- Side effects handled via async/await or middleware

### 3. Use @Binding Wisely

- Keep `@State` local to views when possible
- Use `@Binding` for child views that need to mutate parent state
- Process data locally before propagating changes

### 4. Modular Design

- Break views into smaller, reusable components
- Use `NavigationStack` with proper scoping
- Keep `@Observable` scopes appropriate to their usage

### 5. Separate Side Effects

- Use async/await for asynchronous operations
- Leverage `.task` modifier for view lifecycle management
- Keep business logic out of views

## View Structure Best Practices

### Keep Views Simple

```swift
struct ContentView: View {
    @State private var viewModel = ViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Title")
        }
    }

    private var content: some View {
        List {
            ForEach(viewModel.items) { item in
                ItemRow(item: item)
            }
        }
    }
}
```

### Extract Subviews

When a view gets complex, extract reusable components:

```swift
struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack {
            Text(item.title)
            Spacer()
            Image(systemName: item.icon)
        }
    }
}
```

### Use ViewBuilder for Conditional Content

```swift
@ViewBuilder
private var statusView: some View {
    if isLoading {
        ProgressView()
    } else if items.isEmpty {
        ContentUnavailableView("No Items", systemImage: "tray")
    } else {
        itemsList
    }
}
```

## State Management

### Local State

Use `@State` for view-local data:

```swift
@State private var searchText = ""
@State private var isShowingDetail = false
```

### Shared State

Use `@Observable` objects for shared state:

```swift
@Observable
class AppState {
    var user: User?
    var settings: Settings
}
```

### Environment

Pass shared objects through environment:

```swift
struct MyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
```

## Navigation Patterns

### NavigationStack (iOS 16+)

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

### Programmatic Navigation

```swift
@State private var path = NavigationPath()

NavigationStack(path: $path) {
    List(items) { item in
        Button(item.name) {
            path.append(item)
        }
    }
    .navigationDestination(for: Item.self) { item in
        DetailView(item: item)
    }
}
```

## Performance Best Practices

### 1. Avoid Unnecessary View Updates

```swift
// Use Equatable to prevent unnecessary redraws
struct ItemView: View, Equatable {
    let item: Item

    static func == (lhs: ItemView, rhs: ItemView) -> Bool {
        lhs.item.id == rhs.item.id
    }

    var body: some View {
        // ...
    }
}
```

### 2. Use LazyStacks for Large Lists

```swift
ScrollView {
    LazyVStack {
        ForEach(items) { item in
            ItemRow(item: item)
        }
    }
}
```

### 3. Optimize Images

```swift
AsyncImage(url: url) { image in
    image
        .resizable()
        .scaledToFit()
} placeholder: {
    ProgressView()
}
```

## Accessibility

### Always Add Accessibility Labels

```swift
Button {
    // action
} label: {
    Image(systemName: "plus")
}
.accessibilityLabel("Add Item")
```

### Use Semantic Colors

```swift
.foregroundStyle(.primary)
.foregroundStyle(.secondary)
.background(.background)
```

## Testing Best Practices

### Separate Business Logic

```swift
// Testable ViewModel
@Observable
class ViewModel {
    private let repository: Repository
    var items: [Item] = []

    init(repository: Repository = .shared) {
        self.repository = repository
    }

    func loadItems() async {
        items = await repository.fetchItems()
    }
}

// Easy to test with mock repository
let mockRepo = MockRepository()
let viewModel = ViewModel(repository: mockRepo)
```

## Common Pitfalls to Avoid

1. **Don't overuse `@State`** - Use local state only when needed
2. **Avoid massive ViewModels** - Break into focused, single-responsibility objects
3. **Don't put business logic in views** - Keep views focused on presentation
4. **Avoid force unwrapping** - Use optional binding or default values
5. **Don't ignore memory management** - Be mindful of retain cycles with closures

## Modern SwiftUI Features (iOS 18+)

### Mesh Gradients

```swift
MeshGradient(
    width: 3,
    height: 3,
    points: points,
    colors: colors
)
```

### Zoom Transitions

```swift
.matchedTransitionSource(id: item.id, in: namespace)
```

### Enhanced Tab View

```swift
TabView {
    Tab("Home", systemImage: "house") {
        HomeView()
    }
    Tab("Search", systemImage: "magnifyingglass") {
        SearchView()
    }
}
```

## Resources

- Apple Developer Documentation: https://developer.apple.com/documentation/swiftui
- WWDC SwiftUI Sessions
- Community: Hacking with Swift, Swift with Majid
