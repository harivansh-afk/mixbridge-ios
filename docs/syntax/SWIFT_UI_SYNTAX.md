# SwiftUI Syntax & Patterns Guide

## Core Syntax

### View Protocol

All SwiftUI views must conform to the `View` protocol.

```swift
struct MyView: View {
    var body: some View {
        Text("Hello, World!")
    }
}
```

**Key Points:**
- `body` is a computed property
- Must return `some View`
- Can only contain one root view (use stacks to combine multiple views)

### View Modifiers

Modifiers transform views and return new views.

```swift
Text("Hello")
    .font(.title)
    .foregroundStyle(.blue)
    .padding()
    .background(.gray.opacity(0.2))
    .cornerRadius(8)
```

**Modifier Order Matters:**
```swift
// Padding THEN background
Text("Hello")
    .padding()           // Adds padding
    .background(.blue)   // Background around padded area

// Background THEN padding
Text("Hello")
    .background(.blue)   // Background only around text
    .padding()           // Padding outside background
```

## Property Wrappers

### @State
Local view state that SwiftUI manages.

```swift
@State private var count = 0
@State private var isOn = false
@State private var name = ""
```

**Rules:**
- Use `private` to encapsulate state
- Only for value types (struct, enum, basic types)
- SwiftUI manages the storage
- Changes trigger view updates

### @Binding
Two-way connection to state owned by parent view.

```swift
struct ChildView: View {
    @Binding var text: String

    var body: some View {
        TextField("Enter text", text: $text)
    }
}

struct ParentView: View {
    @State private var text = ""

    var body: some View {
        ChildView(text: $text)
    }
}
```

**Access Bindings:**
- Use `$` prefix to pass binding: `$text`
- Child can read and write parent's state

### @Observable (iOS 17+)
Modern replacement for ObservableObject.

```swift
@Observable
class ViewModel {
    var items: [Item] = []
    var isLoading = false

    func loadData() {
        // Load data
    }
}

struct MyView: View {
    @State private var viewModel = ViewModel()

    var body: some View {
        List(viewModel.items) { item in
            Text(item.name)
        }
        .onAppear {
            viewModel.loadData()
        }
    }
}
```

### @Environment
Access values from the environment.

```swift
@Environment(\.colorScheme) var colorScheme
@Environment(\.dismiss) var dismiss
@Environment(\.modelContext) var modelContext

var body: some View {
    Button("Close") {
        dismiss()
    }
}
```

**Common Environment Values:**
- `.colorScheme` - Current color scheme (light/dark)
- `.dismiss` - Dismiss current view
- `.horizontalSizeClass` - Horizontal size class
- `.scenePhase` - App lifecycle phase

### @EnvironmentObject (Legacy)
Inject observable objects through environment.

```swift
class AppSettings: ObservableObject {
    @Published var isDarkMode = false
}

struct ParentView: View {
    @StateObject private var settings = AppSettings()

    var body: some View {
        ChildView()
            .environmentObject(settings)
    }
}

struct ChildView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Toggle("Dark Mode", isOn: $settings.isDarkMode)
    }
}
```

**Note:** Prefer `@Observable` with `.environment()` modifier in iOS 17+

### @StateObject (Legacy)
Create and own observable objects.

```swift
@StateObject private var viewModel = ViewModel()
```

**Rules:**
- View owns the object lifecycle
- Created once per view lifetime
- Use for ObservableObject classes

### @ObservedObject (Legacy)
Reference observable objects owned elsewhere.

```swift
@ObservedObject var viewModel: ViewModel
```

## ViewBuilder

Enable declarative syntax with multiple views.

```swift
@ViewBuilder
func headerView() -> some View {
    Text("Title")
        .font(.largeTitle)
    Text("Subtitle")
        .font(.caption)
}

// Use in body
var body: some View {
    VStack {
        headerView()
    }
}
```

**Conditional Views:**
```swift
@ViewBuilder
var statusView: some View {
    if isLoading {
        ProgressView()
    } else if items.isEmpty {
        Text("No items")
    } else {
        itemsList
    }
}
```

## Control Flow

### If-Else

```swift
var body: some View {
    VStack {
        if showDetail {
            DetailView()
        } else {
            SummaryView()
        }
    }
}
```

### Switch

```swift
var body: some View {
    switch status {
    case .loading:
        ProgressView()
    case .success(let data):
        DataView(data: data)
    case .failure(let error):
        ErrorView(error: error)
    }
}
```

### Optional Chaining

```swift
if let user = user {
    UserView(user: user)
}

// Or use optional
user.map { UserView(user: $0) }
```

## ForEach

Iterate over collections.

```swift
ForEach(items) { item in
    ItemRow(item: item)
}

// With index
ForEach(Array(items.enumerated()), id: \.offset) { index, item in
    Text("\(index): \(item.name)")
}

// With range
ForEach(0..<10) { number in
    Text("Number \(number)")
}
```

**Requirements:**
- Collection must be `RandomAccessCollection`
- Items must be `Identifiable` or provide `id` parameter

## Async/Await with SwiftUI

### Task Modifier

```swift
.task {
    await loadData()
}

// With cancellation
.task(id: searchText) {
    await searchItems(query: searchText)
}
```

### Async Functions in ViewModel

```swift
@Observable
class ViewModel {
    var items: [Item] = []

    func loadItems() async {
        items = await api.fetchItems()
    }
}

// In view
.task {
    await viewModel.loadItems()
}
```

### MainActor

Ensure UI updates on main thread.

```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var items: [Item] = []

    func loadItems() async {
        let fetchedItems = await api.fetchItems()
        items = fetchedItems // Automatically on main thread
    }
}
```

## Gestures

### Tap Gesture

```swift
Text("Tap me")
    .onTapGesture {
        handleTap()
    }

// Double tap
    .onTapGesture(count: 2) {
        handleDoubleTap()
    }
```

### Long Press

```swift
Text("Press and hold")
    .onLongPressGesture(minimumDuration: 1.0) {
        handleLongPress()
    }
```

### Drag Gesture

```swift
@State private var offset = CGSize.zero

Circle()
    .offset(offset)
    .gesture(
        DragGesture()
            .onChanged { value in
                offset = value.translation
            }
            .onEnded { _ in
                offset = .zero
            }
    )
```

## Animations

### Implicit Animations

```swift
@State private var scale = 1.0

Circle()
    .scaleEffect(scale)
    .animation(.spring, value: scale)

Button("Animate") {
    scale = scale == 1.0 ? 1.5 : 1.0
}
```

### Explicit Animations

```swift
Button("Animate") {
    withAnimation(.spring) {
        scale = scale == 1.0 ? 1.5 : 1.0
    }
}
```

### Custom Animations

```swift
.animation(.easeInOut(duration: 0.5), value: isExpanded)
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: position)
```

### Transitions

```swift
if showDetail {
    DetailView()
        .transition(.slide)
}

// Custom transition
    .transition(.asymmetric(
        insertion: .slide,
        removal: .opacity
    ))
```

## Preferences

Pass data up the view hierarchy.

```swift
struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Set preference
Text("Content")
    .background(
        GeometryReader { geometry in
            Color.clear
                .preference(key: HeightPreferenceKey.self, value: geometry.size.height)
        }
    )

// Read preference
.onPreferenceChange(HeightPreferenceKey.self) { height in
    print("Height: \(height)")
}
```

## Type Erasure

### AnyView

Erase view type for heterogeneous collections.

```swift
let views: [AnyView] = [
    AnyView(Text("Hello")),
    AnyView(Image(systemName: "star")),
    AnyView(Button("Tap") { })
]
```

**Note:** Avoid overusing - impacts performance. Prefer `@ViewBuilder` instead.

## Custom View Modifiers

Create reusable modifiers.

```swift
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.white)
            .cornerRadius(10)
            .shadow(radius: 5)
    }
}

// Extension for convenience
extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}

// Usage
Text("Card content")
    .cardStyle()
```

## Common Patterns

### MVVM Pattern

```swift
// Model
struct Item: Identifiable {
    let id = UUID()
    var name: String
}

// ViewModel
@Observable
class ItemViewModel {
    var items: [Item] = []

    func addItem(_ name: String) {
        items.append(Item(name: name))
    }
}

// View
struct ItemListView: View {
    @State private var viewModel = ItemViewModel()

    var body: some View {
        List(viewModel.items) { item in
            Text(item.name)
        }
    }
}
```

### Repository Pattern

```swift
protocol ItemRepository {
    func fetchItems() async -> [Item]
    func saveItem(_ item: Item) async
}

class NetworkItemRepository: ItemRepository {
    func fetchItems() async -> [Item] {
        // Network call
    }

    func saveItem(_ item: Item) async {
        // Save to network
    }
}

// ViewModel uses repository
@Observable
class ViewModel {
    private let repository: ItemRepository
    var items: [Item] = []

    init(repository: ItemRepository) {
        self.repository = repository
    }

    func loadItems() async {
        items = await repository.fetchItems()
    }
}
```

### Dependency Injection

```swift
// Using initializers
struct MyView: View {
    let viewModel: ViewModel

    init(viewModel: ViewModel = ViewModel()) {
        self.viewModel = viewModel
    }
}

// Using environment
struct MyView: View {
    @Environment(\.database) var database

    var body: some View {
        // Use database
    }
}
```

## Best Practices

1. **Keep views simple** - Extract complex logic to ViewModels
2. **Use private for @State** - Encapsulate local state
3. **Prefer @Observable over ObservableObject** - Modern, cleaner syntax (iOS 17+)
4. **Extract subviews** - Break large views into smaller components
5. **Use meaningful names** - Make code self-documenting
6. **Avoid force unwrapping** - Use optional binding or default values
7. **Use @ViewBuilder** - For conditional view logic
8. **Test ViewModels** - Separate testable logic from views
9. **Mind the modifier order** - Order affects the final appearance
10. **Use task for async work** - Proper lifecycle management
