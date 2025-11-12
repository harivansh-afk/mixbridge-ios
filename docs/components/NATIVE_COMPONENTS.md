# SwiftUI Native Components Reference

## Layout Containers

### VStack
Vertical stack of views.

```swift
VStack(alignment: .leading, spacing: 16) {
    Text("Title")
    Text("Subtitle")
}
```

**Parameters:**
- `alignment: HorizontalAlignment` - .leading, .center, .trailing
- `spacing: CGFloat?` - Space between views

### HStack
Horizontal stack of views.

```swift
HStack(alignment: .center, spacing: 8) {
    Image(systemName: "star")
    Text("Featured")
}
```

**Parameters:**
- `alignment: VerticalAlignment` - .top, .center, .bottom
- `spacing: CGFloat?` - Space between views

### ZStack
Overlay views on top of each other.

```swift
ZStack(alignment: .topLeading) {
    Image("background")
    Text("Overlay")
}
```

### LazyVStack / LazyHStack
Lazy-loading stacks for performance with large data sets.

```swift
ScrollView {
    LazyVStack(spacing: 10) {
        ForEach(items) { item in
            ItemRow(item: item)
        }
    }
}
```

### Grid (iOS 16+)
Two-dimensional grid layout.

```swift
Grid {
    GridRow {
        Text("A1")
        Text("B1")
    }
    GridRow {
        Text("A2")
        Text("B2")
    }
}
```

## Navigation

### NavigationStack (iOS 16+)
Recommended for stack-based navigation.

```swift
NavigationStack {
    List(items) { item in
        NavigationLink(value: item) {
            Text(item.name)
        }
    }
    .navigationTitle("Items")
    .navigationDestination(for: Item.self) { item in
        DetailView(item: item)
    }
}
```

**Key Modifiers:**
- `.navigationTitle(_:)` - Set navigation bar title
- `.navigationBarTitleDisplayMode(_:)` - .large, .inline, .automatic
- `.navigationDestination(for:destination:)` - Define destination for navigation

### NavigationLink
Creates a navigation link to another view.

```swift
NavigationLink(value: item) {
    Label("Details", systemImage: "chevron.right")
}
```

### NavigationSplitView (iOS 16+)
Multi-column navigation for iPad/Mac.

```swift
NavigationSplitView {
    List(categories) { category in
        Text(category.name)
    }
} detail: {
    Text("Select a category")
}
```

### TabView
Tab-based navigation.

```swift
TabView {
    Tab("Home", systemImage: "house") {
        HomeView()
    }
    Tab("Profile", systemImage: "person") {
        ProfileView()
    }
    Tab(role: .search) {
        SearchView()
    }
}
```

## Lists and Collections

### List
Scrollable list of rows.

```swift
List {
    Section("Header") {
        ForEach(items) { item in
            Text(item.name)
        }
    }
}
```

**Styles:**
- `.listStyle(.plain)`
- `.listStyle(.inset)`
- `.listStyle(.insetGrouped)`
- `.listStyle(.sidebar)`

### Section
Groups items in a List.

```swift
Section("Settings") {
    Toggle("Enable", isOn: $isEnabled)
    Picker("Option", selection: $option) {
        Text("A").tag(0)
        Text("B").tag(1)
    }
}
```

### ForEach
Loop over collections.

```swift
ForEach(items) { item in
    ItemRow(item: item)
}
```

### ScrollView
Scrollable container.

```swift
ScrollView(.vertical, showsIndicators: true) {
    VStack {
        ForEach(items) { item in
            ItemCard(item: item)
        }
    }
}
```

## Text and Input

### Text
Display text.

```swift
Text("Hello, World!")
    .font(.largeTitle)
    .foregroundStyle(.primary)
    .bold()
```

**Common Modifiers:**
- `.font(_:)` - .largeTitle, .title, .headline, .body, .caption
- `.foregroundStyle(_:)` - .primary, .secondary, custom colors
- `.bold()`, `.italic()`, `.underline()`
- `.lineLimit(_:)`
- `.multilineTextAlignment(_:)`

### TextField
Single-line text input.

```swift
TextField("Enter name", text: $name)
    .textFieldStyle(.roundedBorder)
```

### TextEditor
Multi-line text input.

```swift
TextEditor(text: $notes)
    .frame(height: 200)
```

### SecureField
Password input field.

```swift
SecureField("Password", text: $password)
```

### Label
Combines text and image.

```swift
Label("Settings", systemImage: "gear")
```

## Buttons and Controls

### Button
Interactive button.

```swift
Button("Save") {
    saveData()
}
.buttonStyle(.borderedProminent)
```

**Button Styles:**
- `.buttonStyle(.plain)`
- `.buttonStyle(.bordered)`
- `.buttonStyle(.borderedProminent)`
- `.buttonStyle(.borderless)`

### Toggle
On/off switch.

```swift
Toggle("Enable notifications", isOn: $isEnabled)
    .toggleStyle(.switch)
```

### Picker
Selection control.

```swift
Picker("Color", selection: $selectedColor) {
    Text("Red").tag(Color.red)
    Text("Blue").tag(Color.blue)
    Text("Green").tag(Color.green)
}
.pickerStyle(.menu)
```

**Picker Styles:**
- `.pickerStyle(.menu)`
- `.pickerStyle(.segmented)`
- `.pickerStyle(.wheel)`

### Slider
Value selection with slider.

```swift
Slider(value: $volume, in: 0...100, step: 1)
```

### Stepper
Increment/decrement control.

```swift
Stepper("Quantity: \(quantity)", value: $quantity, in: 0...10)
```

### DatePicker
Date and time selection.

```swift
DatePicker("Select date", selection: $date, displayedComponents: .date)
```

### ColorPicker (iOS 14+)
Color selection.

```swift
ColorPicker("Choose color", selection: $selectedColor)
```

## Images and Media

### Image
Display images.

```swift
Image(systemName: "star.fill")
    .resizable()
    .scaledToFit()
    .frame(width: 50, height: 50)
    .foregroundStyle(.yellow)
```

**System Images:**
- SF Symbols: 5000+ icons
- `Image(systemName: "icon.name")`

### AsyncImage (iOS 15+)
Load images from URLs.

```swift
AsyncImage(url: URL(string: imageURL)) { phase in
    switch phase {
    case .empty:
        ProgressView()
    case .success(let image):
        image
            .resizable()
            .scaledToFit()
    case .failure:
        Image(systemName: "exclamationmark.triangle")
    @unknown default:
        EmptyView()
    }
}
```

### VideoPlayer (iOS 14+)
Play video content.

```swift
import AVKit

VideoPlayer(player: AVPlayer(url: videoURL))
```

## Progress and Status

### ProgressView
Loading indicator or progress bar.

```swift
// Indeterminate
ProgressView("Loading...")

// Determinate
ProgressView(value: progress, total: 100)
```

### ContentUnavailableView (iOS 17+)
Empty state view.

```swift
ContentUnavailableView(
    "No Results",
    systemImage: "magnifyingglass",
    description: Text("Try a different search term")
)
```

## Forms and Input Groups

### Form
Grouped input controls.

```swift
Form {
    Section("Profile") {
        TextField("Name", text: $name)
        TextField("Email", text: $email)
    }

    Section("Preferences") {
        Toggle("Notifications", isOn: $notifications)
        Picker("Theme", selection: $theme) {
            Text("Light").tag(0)
            Text("Dark").tag(1)
        }
    }
}
```

### GroupBox
Visual grouping container.

```swift
GroupBox("Stats") {
    HStack {
        Text("Count:")
        Spacer()
        Text("\(count)")
    }
}
```

## Sheets and Alerts

### Sheet
Modal presentation.

```swift
.sheet(isPresented: $showingSheet) {
    SheetView()
}
```

### Alert
Alert dialog.

```swift
.alert("Title", isPresented: $showingAlert) {
    Button("OK") { }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("Alert message")
}
```

### ConfirmationDialog
Action sheet.

```swift
.confirmationDialog("Choose", isPresented: $showingDialog) {
    Button("Option 1") { }
    Button("Option 2") { }
    Button("Cancel", role: .cancel) { }
}
```

## Shapes and Drawing

### Rectangle, Circle, RoundedRectangle
Basic shapes.

```swift
Circle()
    .fill(.blue)
    .frame(width: 50, height: 50)

RoundedRectangle(cornerRadius: 10)
    .stroke(.gray, lineWidth: 2)
```

### Path
Custom drawing.

```swift
Path { path in
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: 100, y: 100))
}
.stroke(.blue, lineWidth: 2)
```

### Canvas (iOS 15+)
High-performance drawing.

```swift
Canvas { context, size in
    context.fill(
        Path(ellipseIn: CGRect(origin: .zero, size: size)),
        with: .color(.blue)
    )
}
```

## Search

### Searchable (iOS 15+)
Add search functionality.

```swift
.searchable(text: $searchText, prompt: "Search items")
```

## Toolbars

### Toolbar
Add toolbar items.

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button("Add") {
            addItem()
        }
    }
}
```

**Common Placements:**
- `.topBarLeading`
- `.topBarTrailing`
- `.bottomBar`
- `.navigation`

## Advanced Components (iOS 18+)

### MeshGradient
Colorful mesh gradients.

```swift
MeshGradient(
    width: 3,
    height: 3,
    points: points,
    colors: colors
)
```

### Custom Container Views
Create custom containers with ForEach subview iteration.

```swift
@ViewBuilder
var content: some View {
    ForEach(subviewOf: someView) { subview in
        subview
    }
}
```
