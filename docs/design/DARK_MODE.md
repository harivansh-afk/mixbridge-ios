# Dark Mode Implementation Guide

## Overview
Mixbridge fully supports iOS dark mode with adaptive colors and optimized UI elements that automatically adjust to the user's system appearance preference.

## Key Features

### ✅ Automatic Dark Mode Support
- All views automatically adapt to system appearance settings
- No manual theme switching required (uses system preference)
- Optimized contrast and readability in both modes

### ✅ Semantic Colors
The app uses SwiftUI's semantic colors that automatically adapt:
- `.primary` - Primary text color (black in light, white in dark)
- `.secondary` - Secondary text color (gray with appropriate opacity)
- `.background` - Background color (white in light, black in dark)
- `.systemBackground` - System-level background colors

### ✅ Custom Adaptive Colors
Enhanced with custom color extension (`Color+Theme.swift`):
- Adaptive backgrounds (primary, secondary, tertiary)
- Adaptive text colors (label, secondary label, tertiary label)
- Card colors with proper contrast
- Glass effect colors with mode-specific opacity

## Implementation Details

### 1. Color System

#### Semantic Colors (Built-in)
```swift
// Text colors
.foregroundStyle(.primary)      // Adapts automatically
.foregroundStyle(.secondary)    // Adapts automatically

// Backgrounds
.background(.background)        // Adapts automatically
```

#### Custom Adaptive Colors
```swift
// From Color+Theme.swift
Color.adaptiveBackground
Color.adaptiveSecondaryBackground
Color.adaptiveText
Color.cardBackground
```

#### Gradients
All gradients use adaptive system colors:
```swift
LinearGradient(
    colors: [.blue, .indigo],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```
These system colors (.blue, .indigo) automatically adjust their brightness in dark mode.

### 2. Component-Specific Adaptations

#### ProfileCircleView
- Uses blue-to-indigo gradient that adapts to dark mode
- White text on colored background maintains visibility

#### LiquidGlassProfileButton
- Glass effect opacity adjusts based on color scheme
- Border colors: lighter in light mode, subtler in dark mode
- Shadow: more prominent in dark mode for depth

```swift
@Environment(\.colorScheme) private var colorScheme

// Adaptive border
colors: colorScheme == .dark ? [
    .white.opacity(0.2),
    .white.opacity(0.05)
] : [
    .white.opacity(0.4),
    .white.opacity(0.1)
]
```

#### TrackRow
- Album artwork placeholders use consistent blue-indigo gradient
- Text colors use semantic `.primary` and `.secondary`
- Swipe actions use system colors (.pink, .blue) that adapt

#### AccountBottomSheet
- Uses `UIColor.secondarySystemGroupedBackground` for proper list styling
- Navigation elements use semantic colors

### 3. Preview Configuration

All views include both light and dark mode previews:
```swift
#Preview("Light Mode") {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ContentView()
        .preferredColorScheme(.dark)
}
```

## Best Practices

### ✅ DO:
1. **Use semantic colors** for text and backgrounds
   ```swift
   .foregroundStyle(.primary)
   .background(.background)
   ```

2. **Use system colors** for branded elements
   ```swift
   .tint(.blue)  // Automatically adapts
   .foregroundStyle(.green)  // Automatically adapts
   ```

3. **Test both modes** using Xcode previews
   ```swift
   #Preview("Dark Mode") {
       YourView()
           .preferredColorScheme(.dark)
   }
   ```

4. **Use @Environment(\.colorScheme)** when you need different logic
   ```swift
   @Environment(\.colorScheme) private var colorScheme

   var opacity: Double {
       colorScheme == .dark ? 0.2 : 0.4
   }
   ```

5. **Use adaptive system colors** from UIKit
   ```swift
   Color(uiColor: .systemBackground)
   Color(uiColor: .secondarySystemGroupedBackground)
   ```

### ❌ DON'T:
1. **Hardcode colors** like `Color.white` or `Color.black`
   - Exception: When deliberately needed (like white text on colored backgrounds)

2. **Use fixed opacity values** that don't consider the color scheme
   - Instead: Adjust opacity based on `colorScheme`

3. **Forget to test** in both light and dark modes
   - Always add preview configurations

4. **Override system appearance** unless specifically required
   - Let iOS handle the appearance automatically

## Testing Dark Mode

### In Xcode Previews:
1. Use `#Preview("Dark Mode")` with `.preferredColorScheme(.dark)`
2. View both modes side-by-side in the preview canvas

### In Simulator:
1. Settings → Developer → Dark Appearance (toggle)
2. Or use: Control Center → Appearance

### On Device:
1. Settings → Display & Brightness → Appearance
2. Toggle between Light and Dark

## Color Contrast Guidelines

### Contrast Ratios (WCAG AA):
- **Normal text**: 4.5:1 minimum
- **Large text**: 3:1 minimum
- **UI components**: 3:1 minimum

### Semantic Colors Meet These Standards:
- `.primary` vs `.background`: ✅ High contrast
- `.secondary` vs `.background`: ✅ Adequate contrast
- System colors (blue, green, red, etc.): ✅ Optimized by Apple

## Files Modified for Dark Mode

### New Files:
- `Extensions/Color+Theme.swift` - Custom adaptive color system

### Updated Files:
- `ContentView.swift` - Updated gradients, added previews
- `Components/TrackRow.swift` - Consistent gradients, semantic colors, previews
- `Components/ProfileCircleView.swift` - Adaptive glass effect, gradients, previews
- `Components/AccountBottomSheet.swift` - Added dark mode previews
- `Views/Home/HomeView.swift` - Added dark mode previews
- `Views/Library/LibraryView.swift` - Added dark mode previews
- `Views/Liked/LikedView.swift` - Added dark mode previews
- `Views/Search/SearchView.swift` - Added dark mode previews
- `Views/Profile/ProfileView.swift` - Added dark mode previews

## Future Enhancements

### Optional: Manual Theme Selection
If you want to add manual theme selection:

```swift
// Add to a Settings view
enum ColorSchemePreference: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

// In root view
@AppStorage("colorSchemePreference") private var colorSchemePreference = ColorSchemePreference.system

.preferredColorScheme(
    colorSchemePreference == .system ? nil :
    colorSchemePreference == .dark ? .dark : .light
)
```

### Optional: Custom Brand Colors
To add brand-specific colors in the asset catalog:

1. Open `Assets.xcassets`
2. Add new Color Sets: `BrandPrimary`, `BrandSecondary`, `BrandAccent`
3. Configure Appearances: Any/Light/Dark
4. Use in code:
   ```swift
   Color("BrandPrimary")  // Automatically adapts
   ```

## Summary

✅ **Dark mode is now fully supported** across the entire Mixbridge app!

**Key achievements:**
- All views use semantic and adaptive colors
- Components adapt intelligently to dark mode
- Consistent gradient system (blue-indigo)
- Proper contrast ratios maintained
- All views include dark mode previews for testing

**Result:** The app provides an excellent user experience in both light and dark modes, following Apple's Human Interface Guidelines and accessibility standards.

---

**Last Updated:** November 2025
**iOS Target:** 17.0+
**SwiftUI:** Latest features
