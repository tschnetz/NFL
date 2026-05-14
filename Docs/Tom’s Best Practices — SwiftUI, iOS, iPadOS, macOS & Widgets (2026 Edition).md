# Tom’s Best Practices — SwiftUI, iOS, iPadOS, macOS & Widgets (2026 Edition)

**Scope:** Architecture · State · Navigation · Liquid Glass · Styling · Colors · Typography · Layout · Animation · Accessibility · Performance · Testing · Widgets · Menubar Apps · AI Features · Security · Project Conventions  
**Last updated:** April 29, 2026  
**Baseline:** Xcode 26+, Swift 6.2+, iOS/iPadOS 26+, macOS Tahoe 26+  
**Minimum targets:** iOS 18 (broad adoption); iOS 26 for Liquid Glass. macOS 15 Sequoia; macOS Tahoe for Liquid Glass. Use compatibility shims when supporting older OS versions.  
**Sources:** WWDC 2025 sessions (219, 278, 310, 323, 334), Apple Developer Documentation, post-ship developer experience, and community feedback.

---

## Table of Contents

1. [Guiding Principles](#1-guiding-principles)
2. [Tooling Baseline](#2-tooling-baseline)
3. [Project Structure](#3-project-structure)
4. [App Architecture](#4-app-architecture)
5. [State Management](#5-state-management)
6. [Flow and Screen Design](#6-flow-and-screen-design)
7. [Navigation](#7-navigation)
8. [Platform-Specific Layout](#8-platform-specific-layout)
9. [Liquid Glass & Apple Design Language](#9-liquid-glass--apple-design-language)
10. [Color System](#10-color-system)
11. [Typography](#11-typography)
12. [Layout](#12-layout)
13. [Styling and Design System](#13-styling-and-design-system)
14. [Motion & Animation](#14-motion--animation)
15. [Icons and Imagery](#15-icons-and-imagery)
16. [Components and Controls](#16-components-and-controls)
17. [Lists & Data Display](#17-lists--data-display)
18. [Forms & Controls](#18-forms--controls)
19. [Toolbars, Menus, and Commands](#19-toolbars-menus-and-commands)
20. [Accessibility](#20-accessibility)
21. [Performance](#21-performance)
22. [Data, Persistence, and Networking](#22-data-persistence-and-networking)
23. [Error Handling](#23-error-handling)
24. [iOS-Specific Best Practices](#24-ios-specific-best-practices)
25. [iPadOS-Specific Best Practices](#25-ipados-specific-best-practices)
26. [macOS-Specific Best Practices](#26-macos-specific-best-practices)
27. [macOS Menubar Apps](#27-macos-menubar-apps)
28. [Widgets (WidgetKit)](#28-widgets-widgetkit)
29. [Previews](#29-previews)
30. [Testing](#30-testing)
31. [AI Features in Apps](#31-ai-features-in-apps)
32. [Security and Privacy](#32-security-and-privacy)
33. [Code Style](#33-code-style)
34. [Quick Reference Checklists](#34-quick-reference-checklists)
35. [Design Checklist](#35-design-checklist)
36. [Practical Defaults for New Apps](#36-practical-defaults-for-new-apps)
37. [Common Mistakes to Avoid](#37-common-mistakes-to-avoid)
38. [Source Links](#38-source-links)
39. [Recommended Team Rule](#39-recommended-team-rule)

---

## 1. Guiding Principles

### Build native first

SwiftUI is at its best when you let the platform do the work:

- Prefer native SwiftUI controls before custom controls.
- Use system typography, spacing, materials, symbols, gestures, focus, and accessibility behaviors.
- Make iOS feel like iOS and macOS feel like macOS instead of forcing one shared layout everywhere.
- Share models, business logic, state containers, services, formatters, and view models; specialize view composition per platform.
- Keep business logic in a platform-agnostic Swift package. Views should be thin wrappers over ViewModels.

### Optimize for clarity, not visual cleverness

The Apple Human Interface Guidelines emphasize familiar structure, clear hierarchy, legible typography, adaptive color, accessibility, and consistent platform conventions. Treat custom visual styling as seasoning, not architecture.

### Design for adaptability

A modern SwiftUI interface should adapt to:

- iPhone portrait and landscape
- iPad compact, regular, split-screen, and Stage Manager layouts
- macOS resizable windows
- keyboard, mouse, pointer, touch, trackpad, and VoiceOver
- light, dark, high contrast, reduced transparency, reduced motion, and Dynamic Type
- localization and longer text
- offline/error/loading states

### The 2026 two-layer mental model

Everything in iOS 26 / macOS Tahoe flows from this principle:

- **Content layer** — the floor: lists, tables, media, data
- **Navigation layer** — floats above: tab bars, toolbars, menus, controls, chrome

Liquid Glass is exclusively for the navigation layer. Never apply it to content.

### Favor composable screens

Avoid "god views." A screen should be assembled from small, named sections:

```swift
struct PortfolioView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                SummarySection()
                HoldingsSection()
                ActivitySection()
            }
            .scenePadding()
        }
        .navigationTitle("Portfolio")
    }
}
```

---

## 2. Tooling Baseline

### Use the current Apple-native stack

| Need | Preferred tool in 2026 |
|---|---|
| UI | SwiftUI |
| State observation | Observation framework: `@Observable`, `@State`, `@Bindable`, `@Environment` |
| Persistence | SwiftData for app-local model persistence; CloudKit when sync is needed |
| Concurrency | Swift concurrency: `async`/`await`, `@MainActor`, actors, structured tasks, `TaskGroup` |
| Navigation | `NavigationStack`, `NavigationSplitView`, typed route values |
| Testing | Swift Testing for unit and logic tests; XCTest/UI tests where still appropriate |
| Performance | Instruments with the SwiftUI template, memory graph, signposts |
| AI-assisted development | Xcode 26 Coding Tools/agent integrations — but review generated code carefully |
| On-device AI features | Foundation Models framework for private, on-device summarization, extraction, classification, or generation |

### Enable Swift 6 strict concurrency

Enable Swift 6 strict concurrency in all targets. Every actor-isolated state must be explicitly declared; default to `@MainActor` for ViewModels. No `DispatchQueue.main` calls.

```swift
@MainActor
final class ItemViewModel: ObservableObject {
    @Published var items: [Item] = []
    func load() async { items = await service.fetchItems() }
}
```

> ⚠️ Avoid `Task { }` inside view body. Prefer `.task { }` modifier, which cancels on disappear automatically.

### What you get for free by recompiling with Xcode 26

Just recompile with Xcode 26 and these adopt Liquid Glass automatically — no code changes needed:

- **iOS/iPadOS:** NavigationBar, TabBar, Toolbar, Sheets, Popovers, Menus, Alerts, Search bars
- **macOS:** Toolbar, Sidebar, Menu bar, Dock, Window controls, NSPopover, Sheets

### Avoid legacy defaults

- `NavigationView` — use `NavigationStack` or `NavigationSplitView`
- Global singleton view models
- Heavy `ObservableObject`/Combine pipelines when `@Observable` and async sequences are simpler
- Manual light/dark color switching where semantic colors or asset catalog variants work
- UIKit/AppKit wrappers unless SwiftUI lacks the needed capability
- Fixed pixel sizes and fixed text sizes
- Business logic embedded directly in views
- `DispatchQueue.main.async` — use `@MainActor` or `.receive(on:)`
- `UIScreen.main.bounds` — use `GeometryReader` or `containerRelativeFrame`
- `AnyView` type erasure — use generic views or conditional compilation
- `UIDevice.current` device checks — use horizontal size class instead

---

## 3. Project Structure

### Recommended layout

A practical SwiftUI project structure:

```text
App/
  MyApp.swift
  AppEnvironment.swift
  AppRouter.swift

Features/
  Dashboard/
    DashboardView.swift
    DashboardModel.swift
    DashboardRoute.swift
    Components/
  Settings/
  Detail/

Shared/
  DesignSystem/
    Colors.swift
    Typography.swift
    Spacing.swift
    Components/
  Models/
  Services/
  Persistence/
  Networking/
  Utilities/

Resources/
  Assets.xcassets
  Localizable.xcstrings

Tests/
  Unit/
  UI/
```

Alternatively, use Swift Package Manager for all internal modules:

```text
MyApp/
  App/          <- MyApp target (iOS + macOS shared)
  iOS/          <- iOS-only entry point, AppDelegate if needed
  macOS/        <- macOS MenuBarExtra, NSWindowDelegate
  Packages/     <- local SPM packages (Features, DesignSystem, Services)
  Resources/    <- Assets.xcassets, Localizable.xcstrings
```

Separate platform-specific entry points while sharing a core target.

---

## 4. App Architecture

### Keep views declarative

Views should describe UI. They should not own networking, persistence coordination, or complex transformation logic.

Good:

```swift
struct GameSummaryView: View {
    let summary: GameSummary

    var body: some View {
        LabeledContent("Score", value: summary.scoreText)
    }
}
```

Avoid:

```swift
struct GameSummaryView: View {
    var body: some View {
        Text(fetchAndParseScoreFromNetwork())
    }
}
```

### Recommended MVVM pattern

For hobbyist to mid-sized production apps, use a pragmatic MVVM with a service layer:

```
View  ->  ViewModel (@Observable)  ->  Service (protocol)  ->  Repository / API
```

| Layer | Responsibility |
|---|---|
| View | Render state, dispatch user intents, zero business logic |
| ViewModel | Transform model data for display, handle async tasks |
| Service / UseCase | Business rules, coordination, error handling |
| Repository | Data access abstraction (network, DB, cache) |
| Model | Plain Swift value types or `@Model` classes |

### MVVM vs. flat state

- Use flat `@State` for simple views with no non-trivial logic
- Use `@Observable` ViewModels when logic gets non-trivial
- SwiftUI's struct-based Views and `@Observable` reduce the need for separate ViewModels in simple cases — don't add ceremony that isn't earning its keep

### Use feature-level state

For a nontrivial feature, prefer a small observable model per feature:

```swift
@Observable
final class PortfolioScreenModel {
    var holdings: [Holding] = []
    var isLoading = false
    var errorMessage: String?

    private let service: PortfolioService

    init(service: PortfolioService) {
        self.service = service
    }

    @MainActor
    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            holdings = try await service.fetchHoldings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

Use `@State` to own a screen model:

```swift
struct PortfolioScreen: View {
    @State private var model: PortfolioScreenModel

    init(service: PortfolioService) {
        _model = State(initialValue: PortfolioScreenModel(service: service))
    }

    var body: some View {
        PortfolioContent(model: model)
            .task { await model.load() }
    }
}
```

### Use dependency injection without making it ceremonial

For personal/hobby apps, keep it simple:

```swift
struct AppEnvironment {
    var portfolioService: PortfolioService
    var settingsStore: SettingsStore
}
```

Inject through the SwiftUI environment:

```swift
private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppEnvironment.live
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
```

For more complex apps, use `@Environment` with custom `EnvironmentKey` for lightweight DI across the view tree. Avoid singletons.

```swift
private struct ItemServiceKey: EnvironmentKey {
    static let defaultValue: any ItemServiceProtocol = ItemService()
}

extension EnvironmentValues {
    var itemService: any ItemServiceProtocol {
        get { self[ItemServiceKey.self] }
        set { self[ItemServiceKey.self] = newValue }
    }
}

// Inject at root or in tests:
ContentView().environment(\.itemService, MockItemService())
```

---

## 5. State Management

### Use the right SwiftUI property wrapper

| Wrapper | Use for |
|---|---|
| `@State` | Local view-owned state and view-owned observable models |
| `@Binding` | Two-way value passed from parent to child |
| `@Bindable` | Bindable properties on an `@Observable` model |
| `@Environment` | Shared app dependencies and system values |
| `@Query` | SwiftData fetches directly tied to a view |
| `@SceneStorage` | Scene-specific UI restoration |
| `@AppStorage` | Lightweight user defaults settings |

### `@Observable` is the new baseline

`ObservableObject` / `@Published` is effectively legacy. The modern pattern:

```swift
@Observable
class ContentViewModel {
    var items: [Item] = []
    var isLoading = false

    func load() async { ... }
}

struct ContentView: View {
    @State private var model = ContentViewModel()
}
```

Fine-grained dependency tracking means only views that read a specific property re-render when it changes — not the whole object.

### Keep state close to where it changes

```swift
struct ExpandableCard: View {
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Details", isExpanded: $isExpanded) {
            Text("More information")
        }
    }
}
```

Avoid storing every toggle, sheet, filter, and sort option in a global object unless multiple distant views genuinely need it.

### Prefer derived values over duplicated state

Avoid:

```swift
var holdings: [Holding]
var totalValue: Decimal  // duplicated, can go stale
```

Prefer:

```swift
var totalValue: Decimal {
    holdings.reduce(0) { $0 + $1.marketValue }
}
```

### Use `@MainActor` for UI-facing models

Anything that mutates state displayed by SwiftUI should be main-actor isolated.

```swift
@MainActor
@Observable
final class SearchModel {
    var query = ""
    var results: [SearchResult] = []
}
```

---

## 6. Flow and Screen Design

### Every screen should have explicit states

A production-quality screen needs at least:

- Loading
- Empty
- Content
- Error
- Refreshing or stale data, when relevant

```swift
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(String)
}
```

Use this to prevent fragile UI built from scattered booleans.

### Design one primary action per screen

Each screen should make the next useful action obvious:

- Detail screen: edit, save, share, or open
- List screen: search, filter, add, or select
- Settings screen: change preferences
- Empty state: create/import/connect

### Use progressive disclosure

Do not overload a first screen with every metric, filter, and secondary action. Use:

- Summary cards for top-level information
- Detail drill-ins for dense data
- Sheets for focused creation/editing
- Popovers on macOS/iPadOS for lightweight contextual controls
- Disclosure groups for optional advanced settings

### Prefer stable layouts over animated rearrangement

Animation should reinforce cause and effect, not hide structure changes. Always respect Reduce Motion.

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

.animation(reduceMotion ? nil : .snappy, value: isExpanded)
```

---

## 7. Navigation

### Use `NavigationStack` for drill-down flows

`NavigationStack` is the correct navigation primitive for all new iOS and macOS apps. `NavigationView` is deprecated.

Use a typed route enum rather than scattering booleans and optional selected items:

```swift
enum AppRoute: Hashable {
    case holdingDetail(Holding.ID)
    case transactionDetail(Transaction.ID)
    case settings
}

struct RootView: View {
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            DashboardView(path: $path)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .holdingDetail(let id):
                        HoldingDetailView(id: id)
                    case .transactionDetail(let id):
                        TransactionDetailView(id: id)
                    case .settings:
                        SettingsView()
                    }
                }
        }
    }
}
```

### Use `NavigationSplitView` for iPad & Mac

Use `NavigationSplitView` for column-based layouts on iPad and macOS. It automatically collapses to stack navigation on compact horizontal size classes.

```swift
NavigationSplitView(columnVisibility: $visibility) {
    SidebarView()
} content: {
    ContentListView()
} detail: {
    DetailView()
}
.navigationSplitViewStyle(.balanced)
```

> Don't nest `NavigationSplitView` inside `NavigationStack` — they operate as sibling systems.

### Tab bar navigation

Use `TabView` with the tab label API introduced in iOS 18, and adopt the new iOS 26 behaviors:

```swift
TabView(selection: $selectedTab) {
    Tab("Home", systemImage: "house", value: Tab.home) {
        HomeView()
    }
    Tab("Favorites", systemImage: "star", value: Tab.favorites) {
        FavoritesView()
    }
    Tab("Search", systemImage: "magnifyingglass", value: Tab.search, role: .search) {
        NavigationStack { SearchView(searchText: $searchText) }
    }
}
.searchable(text: $searchText)
.tabBarMinimizeBehavior(.onScrollDown)
.tabViewBottomAccessory {
    NowPlayingView()
}
```

**Key iOS 26 tab bar behaviors:**
- The tab bar is now a floating glass panel that lifts off the bottom edge — content scrolls beneath it
- `.tabBarMinimizeBehavior(.onScrollDown)` collapses to just the active tab icon on scroll down, expands on scroll up
- The `.search` tab role creates a floating search button at bottom-right; activating it replaces the tab bar with a full-width search bar
- `.tabViewBottomAccessory` is the official shelf for mini players or global status — avoid stacking multiple strips ("glass sandwich")

| TabView Style | Effect |
|---|---|
| `.automatic` | Platform-appropriate (tab bar on iPhone, sidebar on Mac/iPad) |
| `.tabBarOnly` | Always renders as a bottom tab bar |
| `.sidebarAdaptable` | Sidebar on iPad/Mac, tab bar on iPhone (iOS 18+) |

**Tab bar rules:**
- Tabs are for top-level navigation between sections, not actions
- The classic large button pinned above the tab bar doesn't work with Liquid Glass — use a `ZStack` + floating glass button instead
- Avoid stacking: banner above tab bar + accessory + floating button all at once

### Floating action button (FAB) for Liquid Glass

```swift
ZStack(alignment: .bottomTrailing) {
    // content
    Button(action: { ... }) {
        Label("Add", systemImage: "plus")
            .labelStyle(.iconOnly)
            .padding()
    }
    .glassEffect(.regular.interactive())
    .padding([.bottom, .trailing], 12)
}
```

### Sheets, popovers & covers

```swift
.sheet(item: $editItem) { item in
    EditView(item: item)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

| Presentation | Use When |
|---|---|
| `.sheet` | Modal task that can be dismissed; partial content below |
| `.fullScreenCover` | Camera, immersive experience, login flow |
| `.popover` | Mac-style contextual info; adapts to sheet on iPhone |
| `.confirmationDialog` | Destructive or branching actions |
| `.alert` | Critical informational messages requiring acknowledgment |

### Deep links and state restoration

Use `.onOpenURL` and `NavigationPath` serialization. Keep route parsing separate from views.

```swift
.onOpenURL { url in
    guard let item = Item(url: url) else { return }
    path.append(item)
}
```

### iOS navigation guidance

Use: `TabView` for 2–5 top-level areas, `NavigationStack` inside each tab, sheets for short tasks, full-screen covers only for immersive flows, `.searchable` instead of custom search bars.

Avoid: deep modal chains, hamburger menus as primary navigation, replacing standard back behavior without a strong reason, hiding navigation in gestures only.

### macOS navigation guidance

Use: `NavigationSplitView` with sidebar/detail, menus and keyboard shortcuts, toolbars for high-frequency actions, inspector panels for metadata, resizable windows as a first-class constraint.

Avoid: iPhone-style tab bars as the main macOS structure, touch-sized spacing, hiding app commands only inside buttons, assuming one-window usage.

---

## 8. Platform-Specific Layout

### Shared adaptive pattern

```swift
struct AppRoot: View {
    var body: some View {
        #if os(macOS)
        MacRootView()
        #else
        IOSRootView()
        #endif
    }
}
```

Platform-specific root views usually produce a better app and cleaner code than extreme conditional layout inside every component.

### Use size classes carefully

Size classes are useful, but not sufficient alone. Also consider: `horizontalSizeClass`, `dynamicTypeSize`, window width on macOS, user-selected sidebar visibility, device idiom, input method, and content density.

```swift
@Environment(\.horizontalSizeClass) private var hSizeClass

var body: some View {
    if hSizeClass == .compact {
        CompactLayout()
    } else {
        WideLayout()
    }
}
```

> On iPhone landscape and iPad split view, horizontal size class can be `.compact` even on a large device. Always design for size class, not device model.

### Let content define layout

```swift
ViewThatFits {
    HStack { SummaryCard(); ChartCard() }
    VStack { SummaryCard(); ChartCard() }
}
```

### Safe area & geometry

Never hardcode status bar or bottom bar heights. Use safe area insets.

```swift
@Environment(\.safeAreaInsets) private var safeArea
Color.blue.ignoresSafeArea(.all, edges: .top)
```

---

## 9. Liquid Glass & Apple Design Language

### What is Liquid Glass

Introduced in iOS 26 / macOS Tahoe, Liquid Glass is Apple's most significant visual redesign since iOS 7 in 2013. It is a unified design language across iOS 26, iPadOS 26, macOS Tahoe, watchOS 26, tvOS 26, and visionOS 26.

Key characteristics:
- **Translucent, fluid materials** — UI chrome adopts a dynamic glass-like appearance that refracts and blends with content behind it
- **Depth-aware layering** — elements feel physically stacked, not painted flat
- **Adaptive tinting** — controls subtly absorb color from underlying content
- **Lensing** — bends and concentrates light in real-time, rather than the traditional blur that scatters it

**Core rule:** Liquid Glass is exclusively for the navigation layer. Never apply it to content (lists, tables, dense text, numbers).

### Adapting pre-iOS 26 apps

```swift
if #available(iOS 26, *) {
    view.glassEffect(.regular, in: .capsule)
} else {
    view.background(.thinMaterial, in: .capsule)
}
```

Every `.glassEffect()` call needs an `#available(iOS 26, *)` guard. The system automatically adopts Liquid Glass for standard controls — your main job is not fighting it by overriding backgrounds unnecessarily.

### The `.glassEffect()` modifier

```swift
// Common variants
.glassEffect()                          // default capsule, .regular
.glassEffect(.regular, in: .circle)
.glassEffect(.regular.tint(.accentColor))
.glassEffect(.regular.interactive())    // adds scale/bounce/shimmer on tap
.glassEffect(.clear)                    // transparent glass — use over images/video
.glassEffect(.identity)                 // no effect — use as accessibility fallback
```

**Apply `.glassEffect()` last** in your modifier chain.

### `GlassEffectContainer` — critical pattern

Glass cannot sample other glass. Always wrap co-located glass controls in a container:

```swift
GlassEffectContainer(spacing: 12) {   // spacing = merge threshold in points
    HStack {
        Button("Action 1") { }
            .glassEffect(.regular.interactive())
        Button("Action 2") { }
            .glassEffect(.regular.interactive())
    }
}
```

When elements are closer than `spacing`, they visually blend and morph together.

### Morphing with `@Namespace` + `glassEffectID`

The most native-feeling expanding/collapsing interaction pattern:

```swift
@State private var expanded = false
@Namespace private var ns

GlassEffectContainer(spacing: 18) {
    Button {
        withAnimation(.bouncy(duration: 0.35)) { expanded.toggle() }
    } label: {
        Image(systemName: expanded ? "xmark" : "plus")
            .frame(width: 56, height: 56)
    }
    .buttonStyle(.glassProminent)
    .glassEffectID("toggle", in: ns)

    if expanded {
        Button("Action") { }
            .buttonStyle(.glass)
            .glassEffectID("action", in: ns)
            .glassEffectTransition(.materialize)
    }
}
```

### `glassEffectUnion`

Visually group glass elements that are spatially far apart (e.g. Maps-style zoom controls):

```swift
@Namespace private var ns
GlassEffectContainer {
    Button("Edit") { }
        .buttonStyle(.glass)
        .glassEffectUnion(id: "tools", namespace: ns)
    Spacer().frame(height: 80)
    Button("Delete") { }
        .buttonStyle(.glass)
        .glassEffectUnion(id: "tools", namespace: ns)
}
```

### When to use (and not use) glass

Use Liquid Glass/system materials for: floating controls, toolbars, navigation/tab/sidebar chrome, overlays that need background awareness, contextual controls that should feel layered above content.

Avoid Liquid Glass/material effects for: dense text containers, tables full of numbers, long-form reading surfaces, critical alerts where contrast matters, and custom glass effects that fight system behavior.

Several professional apps have intentionally opted out of Liquid Glass on their data surfaces — heavy glass on tables and data grids looks wrong on macOS. Apply glass to panel chrome and controls; leave data content clean.

**Practical rule: content should stay calm; controls can be expressive.**

### Accessibility fallbacks for glass

```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency
@Environment(\.accessibilityReduceMotion) var reduceMotion

.glassEffect(reduceTransparency ? .identity : .regular)
withAnimation(reduceMotion ? .none : .bouncy) { ... }
```

### Progressive blurs

`List`, `Navigation`, and other components in iOS 26 now automatically have a soft blur effect at safe areas. This is system-level behavior — do not apply manually.

### Materials reference (pre-iOS 26 fallback)

| Material | Appropriate Use |
|---|---|
| `.ultraThinMaterial` | Floating overlays, tooltips, peek cards |
| `.thinMaterial` | Sheet backgrounds, sidebar fills |
| `.regularMaterial` | Navigation bar background (pre-iOS 26) |
| `.thickMaterial` | Popovers, menus on complex backgrounds |
| `.ultraThickMaterial` | Modal-weight surfaces needing full separation |

---

## 10. Color System

### Semantic color first

Always use semantic system colors before reaching for custom hex values.

| Category | Preferred Token | Never Do |
|---|---|---|
| Primary text | `.primary` | `Color(hex: "#000000")` |
| Secondary text | `.secondary` | `Color.gray` |
| Accent / tint | `.accentColor` / `.tint` | `Color.blue` (static) |
| Background | `.background` | `Color.white` |
| Fill | `.fill`, `.secondaryFill` | `Color(white: 0.9)` |
| Grouped bg | `.groupedBackground` | `Color(hex: "#F2F2F7")` |

### Custom colors in asset catalog

Define **all** custom colors in `Assets.xcassets` with Light / Dark / Increased Contrast variants. Never define custom colors in code.

```swift
// Correct
Color("BrandPrimary")
Color("BrandPrimary", bundle: .module)

// Wrong
Color(red: 0.1, green: 0.44, blue: 0.75)
Color(hex: "#1A70C0")
```

Set the 'High Contrast' variant for every custom color. WCAG AA requires 4.5:1 contrast ratio for normal text.

### Use semantic style names

```swift
extension ShapeStyle where Self == Color {
    static var appPositive: Color { Color("Positive") }
    static var appNegative: Color { Color("Negative") }
    static var appWarning: Color { Color("Warning") }
}
```

Semantic names survive redesigns, dark mode, contrast changes, and branding updates. Do not encode state with color alone.

### Dynamic color & scheme

```swift
@Environment(\.colorScheme) private var colorScheme

var iconColor: Color {
    colorScheme == .dark ? .white : .black
}
```

Avoid `.preferredColorScheme()` on individual views — set it at the app root only if forcing a scheme per user preference.

### Tint & accent

Set a single app-wide tint in the root view or Scene. Avoid setting `.tint()` per-component except to override for a specific section.

```swift
ContentView().tint(Color("BrandPrimary"))
```

---

## 11. Typography

### Always use Dynamic Type text styles

Never hardcode font sizes with `.font(.system(size: 17))`.

| Style | Recommended Use |
|---|---|
| `.largeTitle` | Screen-level page titles |
| `.title` / `.title2` / `.title3` | Section headers, card titles |
| `.headline` | List row primary label (semibold) |
| `.body` | Default body copy |
| `.callout` | Supporting body, captions in context |
| `.subheadline` | Metadata, secondary labels |
| `.footnote` | Timestamps, disclaimers |
| `.caption` / `.caption2` | Smallest supporting text |
| `.monospacedDigit()` | Numbers where alignment matters |

Use fixed sizes only for highly controlled decorative cases, never for core UI.

### iOS 26 typography changes

- Alert text and onboarding sheets: now **left-aligned** (better readability)
- List section headers: now **sentence case** (was ALL CAPS), increased text size
- Navigation bars: subtitle support + left-aligned title option

Update designs and test any custom alert or section header styles you have.

### macOS density

Mac users expect higher information density than iOS:
- Body text: `.callout` or `.body`
- Secondary text: `.caption`
- Section headers: `.caption2` + `.secondary`, sentence case
- Use `Divider()` generously between logical groups

### Custom fonts with scaling

```swift
Text("Hello")
    .font(.custom("SourceSerif4-Regular", size: 17, relativeTo: .body))
```

Register custom fonts in `Info.plist` under `UIAppFonts` (iOS) or `ATSApplicationFontsPath` (macOS).

### Text over glass

When rendering text on Liquid Glass surfaces:
- Increase font weight to medium or bold
- Use high-contrast color (white or `.primary`)
- Use white text with opacity variations for hierarchy, not color variations

### Line limits & truncation

```swift
Text(description)
    .lineLimit(3)
    .truncationMode(.tail)
    .fixedSize(horizontal: false, vertical: false)
```

Use `.lineLimit(nil)` only in scroll views. Test at accessibility text sizes and use vertical layouts when text grows.

---

## 12. Layout

### Layout primitives

| Container | Best For |
|---|---|
| `VStack` / `HStack` / `ZStack` | Simple linear or layered compositions |
| `LazyVStack` / `LazyHStack` | Long lists inside `ScrollView` — loads on demand |
| `Grid` / `LazyVGrid` | Multi-column item grids |
| `ViewThatFits` | Adapting layout to available space (iOS 16+) |
| `Layout` protocol | Fully custom reusable layout algorithms (iOS 16+) |

### Spacing & padding

Use semantic spacing constants (see [Section 13](#13-styling-and-design-system)). Default `VStack`/`HStack` spacing is 8pt — always set spacing explicitly to avoid surprises when system defaults change.

### Safe area

Never hardcode status bar or bottom bar heights. Use safe area insets and `ignoresSafeArea` deliberately.

---

## 13. Styling and Design System

### Create a small design system

```swift
extension DesignSystem {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 18
    }
}
```

Build on SwiftUI's native APIs rather than inventing non-native modifiers. Keep colors semantic — don't hardcode hex values inline.

### Keep reusable components boring

```swift
struct MetricCard<Content: View>: View {
    let title: LocalizedStringKey
    let value: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            content
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.large))
    }
}
```

### Prefer modifiers over inheritance-like abstractions

```swift
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.large))
    }
}

extension View {
    func appCard() -> some View { modifier(CardStyle()) }
}
```

---

## 14. Motion & Animation

### Spring physics are the house style in 2026

```swift
withAnimation(.bouncy(duration: 0.35)) { ... }
withAnimation(.smooth(duration: 1, extraBounce: 0)) { ... }
```

### Hero transitions

```swift
navigationTransitionStyle(.zoom(sourceID: item.id, in: namespace))
```

Anchor point matters — get it wrong and the view flies off-screen. Test on real hardware.

### SF Symbols 7

- 500+ new symbols
- "Draw on" animations are polished — use for checkboxes, confirmation states, progress indicators
- Prefer SF Symbol animations over custom Lottie animations for state transitions

### Always respect Reduce Motion

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

.animation(reduceMotion ? nil : .bouncy, value: isExpanded)
withAnimation(reduceMotion ? .none : .bouncy) { ... }
```

Any animation involving large movement, rotation, or zoom must be gated behind Reduce Motion.

---

## 15. Icons and Imagery

### Use SF Symbols first

```swift
Label("Settings", systemImage: "gearshape")
```

Best practices:
- Pair icons with labels unless the action is universally understood
- Use consistent symbol weights across the app
- Do not use symbols as decoration when they imply interactivity
- Provide accessibility labels for icon-only buttons

### macOS menu item icons

macOS 26 brings icons to menu items. Use `Label` instead of `Text`:

```swift
Button { refresh() } label: {
    Label("Refresh", systemImage: "arrow.clockwise")
}
```

Only add an icon to the first of a group of related items.

### App icons

Prepare layered/icon variants for the current platform. Make sure the icon works in light, dark, tinted, and clear/glass contexts. Avoid tiny text; test at small sizes.

### Image handling

```swift
AsyncImage(url: url) { phase in
    switch phase {
    case .success(let image): image.resizable().scaledToFill()
    case .failure:            Image(systemName: "photo")
    case .empty:              ProgressView()
    @unknown default:         EmptyView()
    }
}
```

For production apps, use a caching library (Nuke, Kingfisher via SPM) instead of `AsyncImage` for disk caching and priority management.

---

## 16. Components and Controls

### Lists vs. ScrollView+LazyVStack

Use `List` when you want platform behavior: selection, swipe actions, keyboard navigation, edit mode, context menus, and accessibility.

Use `ScrollView` + `LazyVStack` when you need custom card layouts and don't need full table/list behavior.

`LazyVStack` does NOT provide swipe actions, selection, or reordering. Do not recreate them manually — use `List` instead.

### Tables on macOS

For dense structured data on macOS, prefer `Table`. Users expect sortable columns, selection, keyboard navigation, and efficient scanning.

### Forms

```swift
Form {
    Section("Display") {
        Toggle("Show market value", isOn: $showMarketValue)
        Picker("Currency", selection: $currency) {
            Text("USD").tag("USD")
            Text("EUR").tag("EUR")
        }
    }
}
```

### Confirmation dialogs

```swift
.confirmationDialog("Delete holding?", isPresented: $showDeleteDialog) {
    Button("Delete", role: .destructive) { delete() }
    Button("Cancel", role: .cancel) {}
}
```

### Alerts and sheets

Use alerts for important information requiring acknowledgement — not for routine success messages. Use sheets for focused tasks; keep them short and dismissible. On macOS, consider whether a popover, inspector, or separate window is more appropriate.

---

## 17. Lists & Data Display

```swift
List(items, id: \.id) { item in
    ItemRow(item: item)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(item) }
                label: { Label("Delete", systemImage: "trash") }
        }
}
.listStyle(.insetGrouped)
```

| List Style | Platform / Use |
|---|---|
| `.automatic` | Default; platform-appropriate |
| `.insetGrouped` | iOS settings-style grouped sections |
| `.sidebar` | macOS / iPad sidebar navigation lists |
| `.plain` | Minimal list; no separators by default on macOS |
| `.grouped` | Legacy iOS style; prefer `.insetGrouped` for new code |

### Pagination

```swift
List(items) { item in
    ItemRow(item: item)
        .onAppear {
            if item == items.last { Task { await viewModel.loadMore() } }
        }
}
```

Add a loading row at the end during pagination rather than a spinner overlay — it preserves scroll position.

---

## 18. Forms & Controls

### Focus & keyboard

```swift
@FocusState private var focusedField: Field?

TextField("Email", text: $email)
    .focused($focusedField, equals: .email)
    .submitLabel(.next)
    .onSubmit { focusedField = .password }
```

Always handle keyboard avoidance with `.scrollDismissesKeyboard(.interactively)` on scroll views in forms.

### Haptics

```swift
Button("Submit") { submit() }
    .sensoryFeedback(.success, trigger: submitted)
```

| Feedback Type | Use |
|---|---|
| `.impact(.light)` | Subtle selection, small item pick |
| `.impact(.medium)` | Button taps, toggles |
| `.impact(.heavy)` | Destructive actions, snapping |
| `.selection` | Picker/slider value changes |
| `.success` / `.warning` / `.error` | Completion states |

---

## 19. Toolbars, Menus, and Commands

### Toolbar rules

Use toolbars for contextual, high-value actions. Avoid overcrowding — move secondary actions into menus. Design around symbols first; the system surfaces symbols over text labels in toolbars.

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button("Add", systemImage: "plus") { showAddSheet = true }
    }
}
```

### `ToolbarSpacer` (iOS 26+)

No more hacking spacing with invisible items:

```swift
.toolbar {
    ToolbarItemGroup(placement: .primaryAction) {
        UpButton()
        DownButton()
    }
    ToolbarSpacer(.fixed, placement: .primaryAction)
    ToolbarItem(placement: .primaryAction) {
        SettingsButton()
    }
}
```

### Menus

```swift
Menu("More", systemImage: "ellipsis.circle") {
    Button("Export", systemImage: "square.and.arrow.up") { export() }
    Button("Duplicate", systemImage: "plus.square.on.square") { duplicate() }
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) { delete() }
}
```

### macOS commands

```swift
.commands {
    CommandGroup(after: .newItem) {
        Button("Import…") { importFile() }
            .keyboardShortcut("i", modifiers: [.command, .shift])
    }
}
```

---

## 20. Accessibility

### Accessibility is not optional polish

Build accessibility into the first version of each component.

Minimum checklist:
- VoiceOver labels for custom controls
- Correct traits for buttons, toggles, links, and adjustable values
- Dynamic Type support
- Sufficient contrast (normal text: 4.5:1 WCAG AA; large text / interactive elements: 3:1)
- Dark mode support
- Reduced Motion support (see [Section 14](#14-motion--animation))
- Reduced Transparency support — use `.glassEffect(.identity)` as fallback
- Differentiate Without Color support
- Keyboard navigation on macOS/iPadOS
- Focus order that matches visual order
- Hit targets large enough for touch

### Label custom controls

```swift
Button { toggleFavorite() } label: {
    Image(systemName: isFavorite ? "star.fill" : "star")
}
.accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
```

### Combine accessibility elements for cards

```swift
VStack(alignment: .leading) {
    Text(holding.name)
    Text(holding.valueText)
    Text(holding.changeText)
}
.accessibilityElement(children: .combine)
```

### Do not rely on color alone

```swift
Label("Down 2.4%", systemImage: "arrow.down.right")
    .foregroundStyle(.appNegative)
```

### Testing accessibility

- Test all screens at Accessibility Extra Extra Extra Large text size
- Never clip text — allow views to grow or scroll
- Use `ViewThatFits` to reflow layouts at large text sizes
- Use Xcode Accessibility Inspector and the Color Contrast Calculator

---

## 21. Performance

### Understand SwiftUI identity

```swift
// Structural identity — always the same branch
if condition { ViewA() } else { ViewB() }

// Explicit identity — stable across list rearranges
ForEach(items, id: \.id) { ItemRow(item: $0) }

// Avoid unstable IDs
ForEach(holdings, id: \.self) { holding in ... }
```

### Avoid expensive work in `body`

```swift
// Avoid
var body: some View { Text(expensiveFormatter.string(from: value)) }

// Prefer — pre-compute before body
let formattedValue: String
var body: some View { Text(formattedValue) }
```

### Avoiding unnecessary re-renders

- Extract sub-views to let SwiftUI scope re-renders
- Mark pure views with `.equatable()` if they conform to `Equatable`
- Prefer `@Observable` over `ObservableObject` — it tracks property access, not the whole object

### `@IncrementalState` + `.incrementalID()` (iOS 26+)

For large lists with frequently changing items, incremental state enables per-item re-rendering:

```swift
@IncrementalState var items: [Item] = []

List(items) { item in
    ItemView(item)
        .incrementalID(item.id)  // only this view re-renders when item changes
}
```

### Use lazy containers for long content

Use `List`, `LazyVStack`, `LazyHStack`, `LazyVGrid`, `LazyHGrid`. Do not render hundreds of cards in a plain `VStack`.

### Profile before optimizing

| Instrument | What It Catches |
|---|---|
| SwiftUI — View Body | Excessive re-renders, slow view bodies |
| Time Profiler | CPU spikes on main thread |
| Allocations | Memory growth, retain cycles |
| Core Data / SwiftData | Fetch bottlenecks, context faults |
| Network | Request timing, repeated fetches |

---

## 22. Data, Persistence, and Networking

### SwiftData

```swift
@Model
final class WatchlistItem {
    var symbol: String
    var name: String
    @Relationship(deleteRule: .cascade) var tags: [Tag]
    var createdAt: Date

    init(symbol: String, name: String, createdAt: Date = .now) {
        self.symbol = symbol
        self.name = name
        self.createdAt = createdAt
    }
}

.modelContainer(for: WatchlistItem.self)

@Environment(\.modelContext) private var context
@Query(sort: \.createdAt, order: .reverse) var items: [WatchlistItem]
```

### When to use what

| Storage | Use When |
|---|---|
| `| `@AppStorage` | Simple primitives (Bool, String, Int) in UserDefaults |
| `@SceneStorage` | Temporary UI state — search text, selected tab |
| SwiftData | Structured relational data needing query and sort |
| `FileManager` / Documents | User-facing files (PDFs, images, exports) |
| Keychain | Passwords, tokens, sensitive credentials |
| Supabase / CloudKit | Cross-device sync, server-side logic |

### Networking

Use async functions returning domain models:

```swift
protocol PortfolioService {
    func fetchHoldings() async throws -> [Holding]
}
```

Do not return raw JSON dictionaries into views.

### Loading tasks

Use `.task(id:)` for view-driven async work:

```swift
.task(id: model.query) {
    await model.search()
}
```

Cancel work automatically where possible. SwiftUI cancels tasks when views disappear or task IDs change.

---

## 23. Error Handling

### Use user-facing error messages

Do not show raw technical errors unless the audience is technical.

Good: *"Couldn't load holdings. Check your connection and try again."*

Bad: *"The operation couldn't be completed. NSURLErrorDomain -1009."*

### Provide recovery actions

```swift
ContentUnavailableView {
    Label("Couldn't Load Data", systemImage: "wifi.exclamationmark")
} description: {
    Text("Check your connection and try again.")
} actions: {
    Button("Retry") {
        Task { await model.load() }
    }
}
```

### Log technical details separately

Keep diagnostic details in logs, not primary UI.

---

## 24. iOS-Specific Best Practices

### Favor thumb-friendly layouts

- Primary actions near the bottom when appropriate
- Use `.safeAreaInset(edge: .bottom)` for persistent bottom actions
- Keep destructive actions out of accidental reach
- Use swipe actions sparingly and always provide another way to access the action

### Use tab navigation for primary sections

```swift
TabView(selection: $selectedTab) {
    Tab("Dashboard", systemImage: "gauge", value: Tab.dashboard) {
        NavigationStack { DashboardView() }
    }
    Tab("Holdings", systemImage: "chart.pie", value: Tab.holdings) {
        NavigationStack { HoldingsView() }
    }
    Tab("Settings", systemImage: "gearshape", value: Tab.settings) {
        NavigationStack { SettingsView() }
    }
    Tab("Search", systemImage: "magnifyingglass", value: Tab.search, role: .search) {
        NavigationStack { SearchView(searchText: $searchText) }
    }
}
.searchable(text: $searchText)
.tabBarMinimizeBehavior(.onScrollDown)
```

### Tab bar rules (iOS 26 / Liquid Glass)

- The classic large button pinned above the tab bar doesn't work with the floating Liquid Glass tab bar — use a `ZStack` + glass floating button (FAB) instead
- Avoid stacking a banner above the tab bar + `.tabViewBottomAccessory` + a floating button all at once ("glass sandwich")
- Use `.tabViewBottomAccessory` for persistent shelves like mini-players or global status

### Floating action button (FAB) pattern

```swift
ZStack(alignment: .bottomTrailing) {
    // content
    Button(action: { showAdd = true }) {
        Label("Add", systemImage: "plus")
            .labelStyle(.iconOnly)
            .padding()
    }
    .glassEffect(.regular.interactive())
    .padding([.bottom, .trailing], 12)
}
```

### Respect system gestures

Avoid custom gestures that conflict with: back swipe, scroll, pull to refresh, sheet dismissal, text selection, and system edge gestures.

### Use haptics intentionally

Use haptics for meaningful confirmations, not every tap.

---

## 25. iPadOS-Specific Best Practices

### Design iPad as its own experience

Do not just scale up the iPhone layout. Use:

- `NavigationSplitView`
- Sidebar/tab adaptability
- Multi-column content
- Popovers
- Keyboard shortcuts
- Drag and drop
- Document workflows where relevant
- Stage Manager/window resizing awareness

### Avoid empty wide layouts

A stretched iPhone list on iPad looks unfinished. Add detail panes, summaries, previews, inspectors, or dashboards.

---

## 26. macOS-Specific Best Practices

### Make the menu bar useful

Every major command should have a menu item: New, Open, Import, Export, Refresh, Search, Settings, Help, Window commands.

### Support keyboard and pointer workflows

- Add keyboard shortcuts
- Use hover effects sparingly
- Provide context menus
- Support focus and selection
- Make table/list rows keyboard-navigable

### Use macOS window conventions

- Avoid full-screen-only design
- Test narrow and wide windows
- Preserve window state where useful
- Use sidebars, inspectors, and toolbar items naturally
- Consider document-based architecture for file-centric apps

### Typography & density (macOS)

Mac users expect higher information density than iOS:

- Body: `.callout` or `.body`
- Secondary: `.caption`
- Section headers: `.caption2` + `.secondary`, sentence case
- Use `Divider()` generously between logical groups

### Menu item icons

macOS 26 brings icons to menu items. Use `Label` instead of `Text`:

```swift
Button {
    refresh()
} label: {
    Label("Refresh", systemImage: "arrow.clockwise")
}
```

Only add an icon to the first of a group of related items. Don't overdo it.

### Use settings scenes

```swift
Settings {
    SettingsView()
}
```

Avoid building iOS-style settings screens as the only configuration surface for macOS.

### Liquid Glass on dense data

Several professional apps opted out of Liquid Glass on their content surfaces. On macOS, heavy glass on tables and data grids looks wrong. Apply glass to panel chrome and controls; leave data content clean.

---

## 27. macOS Menubar Apps

### Platform context

macOS Tahoe = same Liquid Glass design language, same two-layer philosophy. Recompile with Xcode 26 and the following get glass automatically: toolbar, sidebar, menu bar, Dock, window controls, NSPopover, sheets.

The macOS Tahoe menu bar is now transparent — app windows and wallpaper show through. Users can revert via System Settings → Accessibility → Display → Reduce Transparency.

### `MenuBarExtra` — the right API

```swift
@main
struct MyApp: App {
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "waveform")
                .renderingMode(.template)  // critical for transparent bar
        }
        .menuBarExtraStyle(.window)   // rich panel UI
        // or
        .menuBarExtraStyle(.menu)     // native dropdown
    }
}
```

**`.menu` style** — instant open/close, feels like a system menu; best for utility apps with a handful of actions.

**`.window` style** — `NSPanel`-like popover; best for data-rich UIs with charts or interactive content.

> ⚠️ Always use `.renderingMode(.template)` on your status bar icon — critical for proper appearance adaptation across the transparent menu bar.

### `LSUIElement = true` — hide Dock icon

Add to `Info.plist` to make your app an accessory/agent application (menubar-only). Without this, the app appears in the Dock and App Switcher.

### Always provide a quit button

Since there's no Dock presence, always provide a quit mechanism:

```swift
MenuBarExtra("App", systemImage: "waveform") {
    ContentView()
        .overlay(alignment: .topTrailing) {
            Button("Quit", systemImage: "xmark.circle.fill") {
                NSApp.terminate(nil)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .padding(6)
        }
        .frame(width: 320)
}
.menuBarExtraStyle(.window)
```

### NSPopover vs NSMenu

Avoid `NSPopover` for menubar apps — slight delay, doesn't dismiss naturally, looks like a floating app. Prefer `NSMenu` + `NSHostingView` for custom content when you need native feel.

### The 70/30 rule

**70% SwiftUI** for views and state. **30% AppKit** for system integration:

- `NSStatusBar` / `NSStatusItem` for fine-grained icon control (right-click menus require this)
- `ServiceManagement` framework for launch-at-login
- `UserNotifications` for system notifications
- `NSWorkspace` for opening URLs, files, external apps

### Panel size guidelines

- 280–340pt wide for most utilities
- 360–400pt for data-rich apps
- Use intrinsic height where possible — avoid fixed heights that clip on larger text sizes
- Wrap in `ScrollView` for content that may overflow

### Navigation inside the panel

**Single-surface** — everything visible at once (best for quick-glance utilities).

**Glass segmented control** for tab switching:

```swift
GlassEffectContainer {
    HStack(spacing: 0) {
        ForEach(Tab.allCases) { tab in
            Button(tab.label) { selectedTab = tab }
                .glassEffect(
                    selectedTab == tab ? .regular.tint(.accentColor) : .regular,
                    in: .capsule
                )
                .glassEffectID(tab.id, in: namespace)
        }
    }
}
```

**Settings** — always a separate `Settings` scene window, not navigation inside the popover.

---

## 28. Widgets (WidgetKit)

### The shift

The mobile landscape has moved from "app-centric" to **"surface-centric."** WidgetKit's memory footprint increased 15% in iOS 26, making sophisticated state-driven widgets viable. Widgets are now micro-apps, not just glanceable info.

### Three rendering modes — design for all three

| Mode | Description |
|---|---|
| Full color | Classic look, normal home screen |
| Clear glass | Content tinted white on glass background |
| Tinted | Content tinted white on user-chosen color |

```swift
@Environment(\.widgetRenderingMode) var renderingMode

Text("Portfolio")
    .foregroundStyle(
        renderingMode == .fullColor ? .secondary : .white.opacity(0.7)
    )
```

**Always test all three modes in Xcode previews before shipping.**

### Image rendering in accented mode

```swift
// Icons, charts, illustrations — blend with glass
Image("chart-sparkline")
    .widgetAccentedRenderingMode(.desaturated)

// Album art, photos, media — keep original color
Image(albumArtwork)
    .widgetAccentedRenderingMode(.fullColor)
```

### Push notification widget updates (new in iOS 26)

Your server can now directly trigger a widget reload via APNs (silent push, no user notification):

```swift
struct MyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "my-widget", provider: MyProvider()) { entry in
            MyWidgetView(entry: entry)
        }
        .pushType(.reload)  // enables server-triggered reloads
    }
}
```

**Update hierarchy:**
1. Scheduled reloads (system-managed, limited budget)
2. Push notification updates (server-triggered via APNs)
3. `WidgetCenter.shared.reloadTimelines()` (from your app)

Prioritize User Notifications for urgent updates; throttle push updates to respect system budgets.

### Relevance widgets (watchOS Smart Stack)

```swift
struct RelevanceProvider: RelevanceEntriesProvider {
    func relevance() async -> WidgetRelevance<Configuration> {
        let attr = WidgetRelevanceAttribute(
            kind: .date(from: marketOpenTime, to: marketCloseTime)
        )
        return WidgetRelevance([attr])
    }
}
```

### Interactive widgets — now expected

```swift
struct LogItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Item"

    func perform() async throws -> some IntentResult {
        await Store.shared.logItem()
        return .result()
    }
}

// In your widget view
Button(intent: LogItemIntent()) {
    Label("Log", systemImage: "plus.circle.fill")
}
.buttonStyle(.borderedProminent)
```

Button actions must be `AppIntent`-backed — you cannot run arbitrary code.

### Live Activities — now on macOS too

Live Activities on a paired iPhone now automatically surface in the macOS Tahoe menu bar. No extra code required — same `ActivityKit` API, new surface.

### Controls — the third widget type

Controls appear in Control Center, Lock Screen, Action Button, and watchOS. Single-tap executors of `AppIntent` actions:

```swift
struct RefreshControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "refresh",
            provider: RefreshProvider()
        ) { _ in
            ControlWidgetButton(action: RefreshIntent()) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
}
```

### Widget surfaces in 2026

| Surface | Notes |
|---|---|
| iOS Home Screen | Glass/tint modes, full color |
| iOS Lock Screen | Inline and circular families |
| iOS StandBy | Full-size landscape charging display |
| macOS Tahoe Desktop | Same glass/tint as iOS |
| macOS Notification Center | Glass-styled |
| watchOS Smart Stack | Relevance widgets, configurable |
| visionOS 26 | Auto-available from iPhone/iPad widgets |
| CarPlay | Widgets and Live Activities |

### visionOS distance adaptation

```swift
@Environment(\.levelOfDetail) var levelOfDetail

var body: some View {
    if levelOfDetail == .simplified {
        // Large, glanceable — user is far
        Text(value, format: .currency(code: "USD"))
            .font(.largeTitle).fontWeight(.bold)
    } else {
        // Full detail — user is close
        DetailView()
    }
}
```

### Design principles for glass-ready widgets

1. **Design content-first** — don't add fake blur or frosted backgrounds; the system applies its own glass treatment
2. **High contrast in accented mode** — only size, weight, and opacity differentiate hierarchy when tinted white
3. **Avoid hardcoded colors** — semantic system colors handle accented mode correctly
4. **Design at `.systemSmall` first** — if it's coherent small, it scales up; reverse rarely works
5. **Test all three rendering modes** in Xcode previews before shipping

### Xcode preview template

```swift
#Preview("Full Color", as: .systemMedium) {
    MyWidget()
} timeline: {
    MyEntry(date: .now, value: 142384)
}

#Preview("Accented", as: .systemMedium) {
    MyWidget()
} timeline: {
    MyEntry(date: .now, value: 142384)
}
.environment(\.widgetRenderingMode, .accented)
```

---

## 29. Previews

### Treat previews as a design tool

Create preview data for every meaningful state:

```swift
#Preview("Loaded") {
    PortfolioScreen.previewLoaded
}

#Preview("Empty") {
    PortfolioScreen.previewEmpty
}

#Preview("Error") {
    PortfolioScreen.previewError
}
```

### Preview platforms and appearances

Cover:
- iPhone small and large
- iPad regular width
- macOS window
- Dark mode
- Large Dynamic Type
- Empty/error/loading states

```swift
#Preview("Large Text") {
    DashboardView(model: .preview)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Dark + Large Type") {
    ItemDetailView(item: .sample)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
```

---

## 30. Testing

### Use Swift Testing for logic

```swift
import Testing

@Test func totalValueSumsHoldings() {
    let holdings = [
        Holding(symbol: "AAPL", marketValue: 100),
        Holding(symbol: "MSFT", marketValue: 200)
    ]

    #expect(holdings.totalValue == 300)
}
```

Use Swift Testing (Xcode 16+) for new test files — it has better async support and cleaner syntax than XCTest.

### Unit testing ViewModels

```swift
@MainActor
final class ItemViewModelTests: XCTestCase {
    func testLoadItems() async {
        let vm = ItemViewModel(service: MockItemService())
        await vm.load()
        XCTAssertEqual(vm.items.count, 3)
    }
}
```

### What to test

Prioritize: model calculations, formatters, route parsing, service mapping from DTOs to domain models, persistence logic, feature model state transitions, error handling, and accessibility labels for custom components where practical.

### UI tests

Use UI tests for critical flows: first launch, login/setup, create/edit/delete, search/filter, import/export, purchase/subscription flows.

```swift
Button("Submit") { submit() }
    .accessibilityIdentifier("submitButton")
```

Do not over-test pixel-perfect UI.

---

## 31. AI Features in Apps

### Use on-device AI thoughtfully

The Foundation Models framework provides on-device inference, offline, zero cost. Reach for it before a remote API for simple tasks:

- Summarization
- Text extraction
- Classification
- User assistance
- Natural-language search
- Drafting structured content
- Explaining local data

Use it when privacy, offline behavior, and system integration matter.

### Apple Intelligence UI patterns

- **Writing Tools** — system-level contextual popover on any text field; apps get this automatically
- **Siri overlay** — wraps screen edge with ambient glow; design so your UI doesn't compete at edges
- **Foundation Models** — prefer this over remote APIs for tasks that can run locally

### Keep AI features bounded

Good: "Summarize this transaction history." / "Extract merchant, amount, date." / "Suggest categories for these imported transactions."

Risky: "Manage my money automatically." / "Delete files based on AI guesses." / "Send generated messages without review."

### Always provide review and undo

For AI-assisted actions: show the result before applying, make changes reversible, explain uncertainty, keep destructive actions manual.

### Accepting AI-generated code

Always review, simplify, test, and make AI-generated code idiomatic before shipping it.

---

## 32. Security and Privacy

### Minimize data collection

Only request permissions when needed and explain why.

### Use platform privacy affordances

- Keychain for secrets
- App sandboxing on macOS
- Security-scoped bookmarks for user-selected files
- Local processing where possible
- Cloud sync only when it clearly benefits the user

### Do not log sensitive data

Avoid logging: tokens, full names and addresses, financial account numbers, health data, private document contents, raw AI prompts containing sensitive user data.

---

## 33. Code Style

### Prefer clear names

```swift
// Good
func refreshHoldings() async
func formattedMarketValue(for holding: Holding) -> String

// Avoid
func doIt()
func handle()
func processData()
```

### Keep view files readable

A view file should usually contain: the main view, small private subviews or computed view builders, and preview fixtures. Move reusable pieces out.

### Use extensions for organization

```swift
private extension PortfolioView {
    var header: some View { ... }
    var holdingsList: some View { ... }
}
```

### Avoid premature abstraction

Duplicate a little UI twice before creating a generic component. SwiftUI abstractions can become harder to read than the duplicated code they replaced.

---

## 34. Quick Reference Checklists

### iOS App Checklist

- [ ] Use `@Observable` + `@State` — not `ObservableObject`
- [ ] `async/await` + `@MainActor` throughout; no `DispatchQueue.main`
- [ ] Wrap co-located glass controls in `GlassEffectContainer`
- [ ] Glass on controls/chrome only — never on content
- [ ] `glassEffectID` + `@Namespace` for expanding/collapsing clusters
- [ ] iOS 18 fallback (`.ultraThinMaterial`) for every `.glassEffect()` call
- [ ] Explore Foundation Models before reaching for a remote API
- [ ] `tabBarMinimizeBehavior(.onScrollDown)` for scroll-heavy views
- [ ] Floating glass FAB instead of banner-above-tab-bar
- [ ] Reduce Motion respected in all animations
- [ ] NavigationStack (not NavigationView)
- [ ] All text uses Dynamic Type styles
- [ ] Supports Dark Mode and Increased Contrast
- [ ] VoiceOver labels on all images and icon-only buttons
- [ ] Loading and error states implemented
- [ ] Keyboard avoidance handled in forms
- [ ] Previews cover: light, dark, accessibility text size

### macOS Menubar App Checklist

- [ ] `LSUIElement = true` in Info.plist
- [ ] `.renderingMode(.template)` on status bar icon
- [ ] Quit button in panel (no Dock presence)
- [ ] `MenuBarExtra` with appropriate style (`.window` or `.menu`)
- [ ] Glass on chrome/controls only — not on data tables
- [ ] Settings as separate `Settings` scene, not in-panel navigation
- [ ] `Label` (not `Text`) for menu items with icons
- [ ] 70% SwiftUI / 30% AppKit split

### Widget Checklist

- [ ] Handle all three rendering modes (full color, accented, tinted)
- [ ] `.widgetAccentedRenderingMode(.desaturated)` on icons/charts
- [ ] `.pushType(.reload)` for server-triggered updates
- [ ] At least one `Button(intent:)` interactive action
- [ ] Design at `.systemSmall` first
- [ ] `levelOfDetail` environment for visionOS distance adaptation
- [ ] Test all three modes in Xcode previews

---

## 35. Design Checklist

Before shipping a screen, verify:

### Structure
- [ ] Clear title
- [ ] Clear primary action
- [ ] Back/navigation behavior is obvious
- [ ] Loading, empty, content, and error states exist
- [ ] Long content scrolls naturally
- [ ] Destructive actions require confirmation

### iOS
- [ ] Works on small and large iPhones
- [ ] Touch targets are comfortable
- [ ] Tab/navigation structure is simple
- [ ] Does not fight system gestures
- [ ] Keyboard does not hide important controls

### iPadOS
- [ ] Uses wide space well
- [ ] Supports split view/stage manager resizing
- [ ] Uses sidebar/popover patterns where appropriate
- [ ] Keyboard shortcuts exist for frequent actions

### macOS
- [ ] Resizable window works
- [ ] Menu commands exist
- [ ] Keyboard shortcuts exist
- [ ] Toolbar is not overcrowded
- [ ] Context menus exist where expected
- [ ] Empty detail states are handled

### Accessibility
- [ ] Dynamic Type works
- [ ] VoiceOver labels are meaningful
- [ ] Contrast is sufficient
- [ ] Color is not the only signal
- [ ] Reduced Motion is respected
- [ ] Keyboard/focus navigation works

### Visual design
- [ ] Uses semantic colors
- [ ] Supports light and dark mode
- [ ] Uses system materials appropriately
- [ ] Typography hierarchy is consistent
- [ ] Spacing is consistent
- [ ] Custom styling does not reduce legibility

### Performance
- [ ] No expensive work in `body`
- [ ] Long lists use lazy containers
- [ ] Stable IDs in `ForEach`
- [ ] Async tasks cancel naturally
- [ ] Instruments used for any suspected performance issue

---

## 36. Practical Defaults for New Apps

### App root

```swift
@main
struct MyApp: App {
    @State private var environment = AppEnvironment.live

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(\.appEnvironment, environment)
                .tint(Color("BrandPrimary"))
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(\.appEnvironment, environment)
        }
        #endif
    }
}
```

### iPhone root

```swift
struct IOSRootView: View {
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "gauge", value: Tab.dashboard) {
                NavigationStack { DashboardView() }
            }
            Tab("Items", systemImage: "list.bullet", value: Tab.items) {
                NavigationStack { ItemsView() }
            }
            Tab("Settings", systemImage: "gearshape", value: Tab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
```

### macOS root

```swift
struct MacRootView: View {
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
        } detail: {
            switch selection {
            case .dashboard: DashboardView()
            case .items:     ItemsView()
            case .settings:  SettingsView()
            case nil:
                ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
```

### Card style

```swift
extension View {
    func appCard() -> some View {
        padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
    }
}
```

### Button style

```swift
struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.tint, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
```

Use custom button styles sparingly. Prefer `.buttonStyle(.borderedProminent)` when it is sufficient.

---

## 37. Common Mistakes to Avoid

- Designing one universal screen that feels mediocre on every platform
- Using `NavigationView` (deprecated — use `NavigationStack`)
- Using custom navigation when system navigation works
- Making every view observe a giant global app model
- Using `ObservableObject`/`@Published` for new code (use `@Observable`)
- Using fixed text sizes
- Using color as the only state indicator
- Overusing translucent materials behind dense content
- Applying Liquid Glass to content surfaces (tables, lists, dense data)
- Running network calls from view `body`
- Using `ForEach(..., id: \.self)` with unstable values
- Nested `ObservableObjects` (use flat `@Observable` or explicit binding)
- `AnyView` type erasure (use generic views)
- Singleton shared state (use `@Environment`)
- Hardcoded hex colors (use `Assets.xcassets` Color Sets)
- Hiding core commands in unlabeled icons
- Ignoring macOS menu bar and keyboard conventions
- Treating previews as optional
- Treating accessibility as a final-pass checklist
- Accepting AI-generated code without simplifying, testing, and making it idiomatic
- Widget: hardcoding colors that break in accented mode
- Widget: not testing all three rendering modes
- Menubar app: missing quit button or Dock icon without `LSUIElement = true`
- Menubar app: using `NSPopover` instead of `MenuBarExtra`

---

## 38. Source Links

- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
- Designing for iOS: https://developer.apple.com/design/human-interface-guidelines/designing-for-ios
- Designing for macOS: https://developer.apple.com/design/human-interface-guidelines/designing-for-macos
- HIG Color: https://developer.apple.com/design/human-interface-guidelines/color
- HIG Typography: https://developer.apple.com/design/human-interface-guidelines/typography
- HIG Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- HIG Tab bars: https://developer.apple.com/design/human-interface-guidelines/tab-bars
- HIG Sidebars: https://developer.apple.com/design/human-interface-guidelines/sidebars
- HIG Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars
- HIG Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- SwiftUI Navigation: https://developer.apple.com/documentation/swiftui/navigation
- NavigationStack: https://developer.apple.com/documentation/swiftui/navigationstack
- NavigationSplitView: https://developer.apple.com/documentation/SwiftUI/NavigationSplitView
- Migrating to new navigation types: https://developer.apple.com/documentation/swiftui/migrating-to-new-navigation-types
- Observation framework: https://developer.apple.com/documentation/Observation
- SwiftData: https://developer.apple.com/documentation/swiftdata
- SwiftUI EnvironmentValues: https://developer.apple.com/documentation/swiftui/environmentvalues
- SwiftUI Color: https://developer.apple.com/documentation/SwiftUI/Color
- Swift Testing: https://developer.apple.com/documentation/testing
- Xcode 26 Release Notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes
- Understanding and improving SwiftUI performance: https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance
- Liquid Glass overview: https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass
- Adopting Liquid Glass: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- Applying Liquid Glass to custom views: https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- Foundation Models framework: https://developer.apple.com/documentation/FoundationModels
- What's new in iOS 26: https://developer.apple.com/ios/whats-new/
- App accessibility testing: https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app
- WidgetKit: https://developer.apple.com/documentation/widgetkit
- MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra
- WWDC 2025 Sessions: 219, 278, 310, 323, 334

---

## 39. Recommended Team Rule

When in doubt, choose the solution that is:

1. More native
2. More readable
3. More accessible
4. More adaptive
5. Easier to test
6. Easier to delete later

That rule usually leads to the best SwiftUI code.

#coding
