# SwiftUI Visual Design & Polish — 2026

A focused guide to the felt quality of native Apple apps: hierarchy, color, typography, spacing, and the small details that separate assembled from considered. Oriented toward personal daily-use apps displaying real-time data across Mac, iOS, and menubar surfaces.

---

## Table of Contents

1. [Visual Hierarchy & Composition](#1-visual-hierarchy--composition)
2. [Color in Practice](#2-color-in-practice)
3. [Typography as Design](#3-typography-as-design)
4. [Spacing & Density](#4-spacing--density)
5. [The Small Details That Add Up](#5-the-small-details-that-add-up)
6. [Cards vs. Rows vs. Sectioned Lists](#6-cards-vs-rows-vs-sectioned-lists)
7. [Displaying Real-Time & Numeric Data](#7-displaying-real-time--numeric-data)
8. [Light & Dark Mode in Practice](#8-light--dark-mode-in-practice)
9. [Animation & Motion as Design](#9-animation--motion-as-design)
10. [Liquid Glass & Material Surfaces](#10-liquid-glass--material-surfaces)
11. [Accessibility as Visual Design](#11-accessibility-as-visual-design)
12. [Haptic Feedback as Polish](#12-haptic-feedback-as-polish)
13. [Menubar Surface Design](#13-menubar-surface-design)

---

## 1. Visual Hierarchy & Composition

### The one-thing rule

Every screen should have one element that lands first — not five important things, one. Everything else is support. If you squint at a screen and three elements compete equally for attention, the hierarchy has failed. Establish the primary read, then let secondary and tertiary content recede.

On a home status screen, that primary thing is probably the overall state: *everything is fine* or *something needs attention*. Everything else — individual device cards, timestamps, category labels — is detail.

### Balance vs. clutter

Clutter is not the same as density. A screen can be dense and feel calm, or sparse and feel chaotic. The difference is **visual grouping and consistent rhythm**.

Clutter happens when:
- Elements have no consistent left-edge alignment
- Multiple font sizes appear at the same visual weight level
- Padding around items is inconsistent — some tight, some loose
- Color is applied to many elements with no clear priority
- Every row has a disclosure chevron regardless of whether there's anything behind it

Calm density happens when:
- Each row or card has a clear primary label, a clear secondary label, and nothing else fighting them
- Whitespace is consistent — the same gap between cards, the same inset from the screen edge
- Color is reserved for state (warning, critical) rather than decoration
- Visual weight decreases as you move from primary → secondary → tertiary

### Creating a focal point

Use exactly one of these to establish primacy on a screen. Using more than one dilutes all of them:

- **Size** — one element noticeably larger than everything around it
- **Weight** — one element in `.bold` or `.semibold` when everything else is `.regular`
- **Color** — one element in the accent color or a status color when everything else is `.primary`/`.secondary`
- **Position** — the top-left or top-center of a scroll view is where the eye lands first

For a data monitoring app, a good pattern is a large summary indicator at the top (status, count of issues, overall state), followed by a calm grid or list of detail below. The summary does the heavy lifting; the detail rewards closer inspection.

### Avoid symmetric overload

Grids of equally-sized, equally-weighted cards with the same icon size, same font, same padding create a wall. The eye has nowhere to start. Break symmetry intentionally:

- Vary card height when content genuinely differs in volume
- Use a wider "hero" card for the most important status item
- Let some rows be plain list rows while cards are reserved for richer content

### The squint test

Before shipping a screen, squint at it until it blurs. What remains visible? That's your hierarchy. If three things are still roughly equal in visual mass when blurred, the screen needs work.

---

## 2. Color in Practice

### Build a 3–4 color system, not a palette

A personal app needs very few colors. More colors do not create more richness — they create noise and make it harder for individual colors to carry meaning.

A practical system for a data/monitoring app:

| Role | Source | Notes |
|---|---|---|
| **Tint / accent** | `Color("BrandPrimary")` from asset catalog | One color, used sparingly for interactive elements and primary actions |
| **Positive / normal** | `.primary` or system green | State that is fine, active, on |
| **Warning** | System orange | State that needs attention but is not urgent |
| **Critical** | System red | State requiring immediate notice |

Everything else — backgrounds, separators, secondary labels — comes from semantic system colors, not custom values. This keeps the design coherent in both light and dark mode without any extra work.

### Tint color: strategic vs. everywhere

Tint color loses its power when it appears on every element. Its job is to say *"this is interactive"* or *"this is the thing that matters most right now."* When it's everywhere, it says nothing.

Good uses of tint:
- The primary action button on a screen
- The selected tab indicator
- An active toggle or selected state
- A badge count on a critical item

Tint color on: every row label, every icon, every section header, every divider — these all dilute each other. Strip tint from anything that isn't either interactive or the single most important piece of information on the screen.

### Accent color as a signal, not decoration

When you use your accent color on a device row to indicate it's powered on, that's using color as a signal. When you use it on the section header "Lights" just because it looks nice, that's decoration — and it competes with the signal. Decide what your accent means and use it only for that meaning.

For a monitoring app, a clean rule is: **accent color appears only on interactive controls and on items that are "active" or "on."** Everything in an off/idle/normal state uses `.primary` or `.secondary`.

### `.secondary` and `.tertiary` do the heavy lifting

You do not need custom colors to create visual depth. The system provides three levels of foreground style that do this automatically, including adapting perfectly to dark mode and accessibility contrast settings:

```swift
Text("Device Name")          // .primary — full weight, main read
    .foregroundStyle(.primary)

Text("Last updated 2m ago")  // .secondary — recedes, clearly supporting
    .foregroundStyle(.secondary)

Text("v2.1.4")               // .tertiary — barely there, fine print
    .foregroundStyle(.tertiary)
```

`.secondary` is the most underused tool in SwiftUI. A single-color design using `.primary` + `.secondary` + `.tertiary` thoughtfully will feel more sophisticated than one using six custom colors. The hierarchy is baked in, adapts to context, and never looks wrong in dark mode.

### Status colors: own them, don't abuse them

Red, orange, and green carry strong psychological weight. If you use orange for a section header because it looks warm, you've stolen urgency from your warning state. Reserve status colors strictly for status.

Also: never use color as the *only* signal for status. Pair it with an icon or a label so the meaning survives grayscale, accessibility color filters, and a quick glance in sunlight.

```swift
// Good — color + icon + label, all three reinforce each other
Label("Leak detected", systemImage: "drop.fill")
    .foregroundStyle(.red)

// Fragile — color alone
Circle()
    .fill(.red)
    .frame(width: 8, height: 8)
```

### Building light/dark coherence

Custom colors defined in `Assets.xcassets` with Light and Dark variants are the correct approach — never hardcode hex values in code. But the more important discipline is trusting the semantic system colors for backgrounds, fills, and separators:

- `.background` — primary window/screen background
- `.background.secondary` — card surfaces, inset grouped backgrounds
- `.background.tertiary` — nested surfaces
- `Color(uiColor: .separator)` — dividers and borders

These compose naturally. A card using `.background.secondary` over a `.background` screen will always look correct in both modes without any custom logic.

---

## 3. Typography as Design

### Type scale creates rhythm, not just hierarchy

Hierarchy tells you what's important. Rhythm is about whether the screen feels like it breathes or stutters. A good type scale has clear size jumps between levels — not five sizes clustered within 2pt of each other.

A practical scale for a data-dense app:

| Level | Style | Use |
|---|---|---|
| Screen title | `.title2` or `.title3` | Navigation title or prominent section header |
| Primary label | `.body` (default) | Device name, item name, main read per row |
| Secondary label | `.subheadline` or `.callout` | Supporting context, category, location |
| Metadata | `.caption` | Timestamps, firmware versions, fine print |
| Numeric data | `.title` or `.title2` + `.monospacedDigit()` | Key readings: temperature, battery %, sensor values |

Avoid having more than 4 distinct sizes on any single screen. Beyond that, the eye stops reading the scale and starts seeing noise.

### Bold is a design decision, not a default

Bold draws the eye. When everything is bold, nothing is. Use bold/semibold for:
- The single most important piece of text on a card or row (usually the device name or the primary value)
- A critical status value that needs immediate attention

Use `.regular` for everything else. Secondary labels, metadata, supporting context — all `.regular`. Let weight be meaningful by using it rarely.

A common mistake: making all labels in a row bold because the designer wanted them to "feel important." The result is a row where nothing is important because everything is equally heavy.

### Number formatting for data displays

Numbers in a monitoring app deserve specific treatment:

**Use `.monospacedDigit()`** whenever numbers appear in a list or alongside each other. Without it, proportional digit widths cause numbers to jump left/right as values update — visually jarring in a real-time display.

```swift
Text("98.6°")
    .font(.title2.monospacedDigit())
```

**Significant figures over false precision.** A temperature sensor that reads to 4 decimal places should display as `72.4°`, not `72.3847°`. A battery at 84.7% should display as `85%` in a glanceable row and `84.7%` only in a detail view. Match precision to the decision the number is supporting.

**Units belong with numbers, but at a lower weight:**

```swift
HStack(alignment: .firstTextBaseline, spacing: 2) {
    Text("72")
        .font(.title.monospacedDigit())
    Text("°F")
        .font(.callout)
        .foregroundStyle(.secondary)
}
```

This keeps the unit readable without competing with the value.

**Thresholds communicate meaning better than raw values for status rows.** Instead of displaying `423 ppm` in a device list row, display `Good` or `Fair` using your threshold logic — with the raw value available in the detail view. This keeps glanceable rows meaningful without requiring the reader to remember what 423 ppm means.

### Pairing styles intentionally

A well-paired row might look like:

```swift
VStack(alignment: .leading, spacing: 2) {
    Text(device.name)               // .body, .regular, .primary
    Text(device.statusSummary)      // .subheadline, .regular, .secondary
}
```

That's it. Two lines, two sizes, two weights (both regular), two foreground styles. Clean, readable, fast. Resist adding a third line unless it carries information the first two cannot.

---

## 4. Spacing & Density

### Rhythm systems: 8pt vs. 12pt vs. 16pt base

Spacing rhythm is the single biggest contributor to whether an app feels considered or accidental. Pick a base unit and derive everything from it. The three common systems:

**8pt system** — tight, information-dense. Good for data grids, menubar panels, compact displays. Feels professional when executed consistently; feels cramped when applied to content that needs breathing room.

**12pt system** — a middle ground. Works well for iOS list rows and card content where you want reasonable density without a spacious feel.

**16pt system** — relaxed, generous. Good for primary content screens, card surfaces, and anywhere you want a calm, unhurried feel. Can feel wasteful on small screens or in menubar contexts.

The key is not which you choose but that you **pick one and apply it everywhere**. An app that uses 8pt gap between some elements and 14pt between others for no reason feels unfinished even if you can't articulate why.

```swift
enum Spacing {
    static let xs: CGFloat  = 4
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 12
    static let lg: CGFloat  = 16
    static let xl: CGFloat  = 24
    static let xxl: CGFloat = 32
}
```

Use these constants everywhere. Never write `.padding(10)` or `.padding(14)`.

### The difference between compact and cheap

Compact means less space is used intentionally because the context warrants density — a menubar panel with 12 items, a widget surface, a watch complication. The reduced space is deliberate and consistent.

Cheap means less space was used because no decision was made — the default padding was removed, items are crammed together, nothing has room to breathe.

The distinguishing test: **is every spacing value a deliberate choice?** Compact layouts have tight but consistent padding. Cheap layouts have inconsistent padding or no padding at all on some elements.

A menubar panel can feel polished at 8pt internal padding. The same 8pt on a primary iOS screen feels unfinished. Match density to surface.

### Consistent screen insets as brand feel

Every screen should have the same horizontal content inset. On iOS, this usually comes from `.scenePadding()` or the automatic insets of `List` and `Form`. Where you're building custom layouts, define the inset once:

```swift
// Define once
extension CGFloat {
    static let screenInset: CGFloat = 16
}

// Use consistently
.padding(.horizontal, .screenInset)
```

When some views use 16pt horizontal padding and others accidentally use 12pt or 20pt, the screen edge feels ragged. The content looks like it doesn't know where it lives.

### Breathing room: the space before and after sections

The gap between sections matters as much as the gap within them. A list with 8pt between rows but 8pt between sections too will feel like one undifferentiated mass. Sections need more air than rows:

```swift
VStack(spacing: Spacing.xl) {      // 24pt between sections
    SummarySection()
    DevicesSection()
    ActivitySection()
}
// But inside a section:
VStack(spacing: Spacing.sm) {      // 8pt between rows within a section
    ForEach(devices) { DeviceRow($0) }
}
```

That gap differential is what makes sections read as sections rather than as arbitrary line breaks.

---

## 5. The Small Details That Add Up

These are the details that are individually subtle but collectively determine whether an app feels polished or approximate. None of them requires significant work — they require attention.

### Corner radius consistency

Corner radius is one of the most visible inconsistency signals in a SwiftUI app. Mixing `cornerRadius(8)`, `cornerRadius(12)`, and `cornerRadius(18)` on different elements of the same screen looks accidental even if each individual choice was intentional.

Define radius values the same way you define spacing:

```swift
enum Radius {
    static let sm: CGFloat  = 8   // small chips, badges, tags
    static let md: CGFloat  = 12  // standard cards, input fields
    static let lg: CGFloat  = 18  // prominent cards, sheet surfaces
    static let xl: CGFloat  = 28  // full-bleed hero cards, large containers
}
```

Apply them consistently: all device cards use `.md`, all status badges use `.sm`, all summary cards use `.lg`. Never let a radius value be chosen by feel in the moment — always reach for the enum.

The system uses `.continuous` corner curves (squircles), not circular arcs. Match it:

```swift
RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
```

### Icon weight matching text weight

SF Symbols have weights that correspond to text weights. When you place a symbol next to text, they should match. A `.regular` label with a `.bold` symbol looks wrong even if neither element is wrong on its own.

```swift
// Good — weights match
Label("Battery low", systemImage: "battery.25")
    .font(.body)                                   // .regular weight for both

// Mismatched — label is regular, symbol defaults may not match
Image(systemName: "battery.25")
    .imageScale(.medium)
    // Missing: font modifier to match text weight
Text("Battery low")
    .font(.body)
```

When using symbols standalone, set the font explicitly so the weight is predictable:

```swift
Image(systemName: "drop.fill")
    .font(.body.weight(.medium))
```

Also match symbol scale to context. `.imageScale(.small)` for inline symbols within text, `.imageScale(.medium)` for standalone icons in rows, `.imageScale(.large)` for prominent standalone icons.

### Shadow usage: almost never

Shadows are one of the most overused tools in custom UI. The Liquid Glass design language uses depth through translucency and layering, not drop shadows. Adding shadows to cards in a SwiftUI app usually:

- Fights the system's own layering model
- Looks heavy and dated in dark mode
- Creates visual noise that competes with content

Before reaching for `.shadow()`, ask whether the same sense of elevation could come from using `.background.secondary` on a card surface — which gives a subtle, system-appropriate lift without any shadow.

When shadows are appropriate:
- A floating action button that genuinely needs to feel lifted above a content layer
- A custom overlay that needs physical separation from content beneath it

When they are not:
- List cards that already have a background color
- Navigation elements (the system handles these)
- Anything inside a `List` or `Form`

### Separator usage: less than you think

Separators are visual noise when used between every row. They're most useful when two sections of content would otherwise blur together without a clear visual boundary. Within a homogeneous list of rows, the whitespace between rows is usually sufficient — the separator adds nothing and makes the layout feel heavier.

```swift
// Usually unnecessary — the list already separates rows
List {
    ForEach(devices) { device in
        DeviceRow(device)
        Divider() // Remove this
    }
}

// Appropriate — separating genuinely different sections
VStack {
    SummaryCard()
    Divider()
        .padding(.horizontal, Spacing.lg)
    DetailSection()
}
```

In `List`, prefer `.listStyle(.insetGrouped)` and let the system handle section separation. Its built-in treatment is more considered than manual dividers.

### List row height and roominess

Row height is a direct expression of how much an app respects each piece of content. Rows that are too tight feel rushed — the label barely has room, the secondary text is clipped or too close to the primary. Rows that are too tall feel wasteful and make lists feel slow to scan.

A comfortable single-line row uses around 44pt height (Apple's minimum touch target). A two-line row with primary + secondary label reads well at around 52–60pt. Achieve this through padding, not fixed frames:

```swift
HStack {
    Image(systemName: device.icon)
        .frame(width: 32)
    VStack(alignment: .leading, spacing: 2) {
        Text(device.name)
        Text(device.subtitle)
            .foregroundStyle(.secondary)
            .font(.caption)
    }
    Spacer()
    Text(device.value)
        .foregroundStyle(.secondary)
        .font(.subheadline.monospacedDigit())
}
.padding(.vertical, Spacing.sm)   // 8pt top and bottom
```

### Progressive disclosure, not information dumping

Every row in a list should show exactly what's needed to identify the item and its current state — nothing more. The detail view is where additional data lives. A device row that tries to show name, category, status, last updated, battery level, and signal strength all at once is serving no one.

Decide per device type: what is the one secondary value that matters most in a glance? For a lock: locked/unlocked. For a thermostat: current temperature. For a camera: last motion time. Show that, nothing else.

---

## 6. Cards vs. Rows vs. Sectioned Lists

This is one of the most common visual design decisions in data apps, and the wrong choice makes layouts feel either overbuilt or underdressed.

### Plain rows

Use plain rows when:
- Content is homogeneous — all items are the same type
- The list is long and needs to scan fast
- Each item has a clear primary label and one secondary value, nothing more
- Items don't need visual separation from each other — their type is self-evident

Plain rows are faster to scan and feel more native on iOS and macOS. They let content breathe without the overhead of a card surface. Overusing cards for content that should be rows is one of the most common ways apps look overdesigned.

### Cards

Use cards when:
- Items are heterogeneous — each one has a different structure
- An item carries enough data that it deserves visual containment (3+ data points)
- Items benefit from visual separation because they represent meaningfully different things
- You want a grid layout rather than a linear list

Cards cost visual weight. Every card surface adds a background, a corner radius, and padding — that's three layers of visual noise that need to earn their place by organizing content that genuinely needs organizing.

```swift
// Card: multiple data points, heterogeneous content
VStack(alignment: .leading, spacing: Spacing.sm) {
    HStack {
        Label(device.name, systemImage: device.icon)
            .font(.headline)
        Spacer()
        StatusBadge(device.status)
    }
    Text(device.primaryValue)
        .font(.title2.monospacedDigit())
    Text(device.lastUpdated)
        .font(.caption)
        .foregroundStyle(.secondary)
}
.padding(Spacing.lg)
.background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
```

### Sectioned lists

Use sectioned lists when:
- Content is heterogeneous in type but homogeneous within each type (device categories, for example)
- You want the speed and native feel of a `List` with the organizational clarity of grouping
- The platform is macOS or iPad where sidebar/list combinations are native

Sectioned lists are often the right answer for a multi-category device display — they're faster to scan than cards, more organized than a flat list, and more native than a custom grid.

### The grid question

Grids (2- or 3-column `LazyVGrid`) suit content that:
- Is primarily visual — images, thumbnails, status indicators
- Has roughly equal importance across all items
- Benefits from spatial comparison (air quality across rooms, camera thumbnails)

Grids fail when cell content has variable length text — the layout becomes uneven and awkward. For text-primary content, rows or cards almost always work better.

---

## 7. Displaying Real-Time & Numeric Data

This section is specific to apps that display sensor readings, device states, and live-updating values — where the visual design of data itself matters.

### The glanceable vs. detail split

Every data value in your app lives at one of two levels:

**Glanceable** — the value that answers "is this fine?" in under 2 seconds. Should be expressed in plain language where possible: *Good*, *Locked*, *72°*, *On*, *3 issues*. Avoid raw sensor values that require the user to know what a threshold means.

**Detail** — the full picture, available on tap. Raw values, history, trend, confidence, update time. This belongs in a detail view, not a list row.

Resist the pull to show everything in the row. The row's job is to tell the user whether they need to look closer — not to replace looking closer.

### Communicating staleness without being noisy

A monitoring app that displays data has an implicit promise: the data is current. When it isn't, the visual design needs to surface that — but not panic about it.

A clean staleness pattern:
- **Under 5 minutes:** no staleness indicator. Show the value normally.
- **5–30 minutes:** show "X min ago" in `.caption` + `.secondary` — visually receded, informational
- **Over 30 minutes:** shift the value text to `.secondary` and show "Stale" or "Last seen Xh ago" in `.caption` + `.tertiary`
- **Offline / unknown:** show the value as `—` and use `.secondary` foreground throughout the row

The key is that staleness uses the existing foreground style system to communicate — not additional colors, not warning icons, not banners unless genuinely critical.

### Trend and direction indicators

A raw number with a direction arrow carries significantly more meaning than a raw number alone:

```swift
HStack(spacing: 4) {
    Text("72.4°")
        .font(.title2.monospacedDigit())
    Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
        .font(.caption)
        .foregroundStyle(trend > 0 ? .primary : .secondary)
}
```

Keep trend indicators small and secondary — they're context, not the headline. The value is the headline.

### When to use color for data values

Use color on a data value only when the color maps to a defined status threshold — not to make the screen more colorful. Green temperature = warm? No. Red temperature = fever threshold exceeded? Yes.

For a sensor reading, the color decision should be driven by your threshold logic, not aesthetic preference:

```swift
Text(reading.displayValue)
    .foregroundStyle(reading.severity.color)
```

Where `severity.color` is `.primary` (normal), `.orange` (warning), or `.red` (critical). The reading displays in full-weight `.primary` when it's fine. It earns color when it matters.

---

## 8. Light & Dark Mode in Practice

### Trust the system, minimize custom logic

The most common dark mode mistake is writing `colorScheme == .dark ? X : Y` branches. Every such branch is a liability — it's an additional code path, it can get out of sync, and it's almost always solving a problem that wouldn't exist if semantic colors were used from the start.

If you find yourself writing dark mode branches, the root cause is almost always a hardcoded color somewhere. Fix the root cause.

### Backgrounds that always work

The system background stack composes correctly in both modes without any custom logic:

```swift
// Screen background — use implicitly (the window provides it)

// Card surface over screen background
.background(.background.secondary, in: ...)

// Nested surface over a card
.background(.background.tertiary, in: ...)
```

These three levels are all you need for the vast majority of layouts. Adding custom background colors on top of this system creates layers that can look wrong in one mode or the other.

### Testing dark mode is not optional

Test every screen in both modes before considering it done. The specific failure modes to look for:

- **Text contrast** — `.secondary` text over a `.background.secondary` surface should still be readable. If it's not, the surface color is wrong.
- **Status colors** — red and orange need sufficient contrast over your card surfaces in dark mode. System red and orange handle this; custom colors may not.
- **Shadows** — dark mode makes most shadows invisible or inverted-looking. If you have shadows, check them in dark mode.
- **Images and icons** — template-mode SF Symbols adapt automatically. Custom images may need dark mode variants in the asset catalog.

### The increased contrast setting

Users with accessibility needs can enable Increased Contrast, which asks apps to reduce transparency and increase the contrast of all UI elements. If you use semantic colors and system materials, this is handled automatically. If you use custom opacity-based colors or `.ultraThinMaterial` backgrounds where text must be readable, test with Increased Contrast enabled.

---

## 9. Animation & Motion as Design

Animation is not decoration. Every transition and motion in your app is either doing communicative work — showing where something came from, confirming an action, indicating a state change — or it's noise. If you can't articulate what an animation is communicating, it shouldn't be there.

### Spring is the Apple default — for good reason

The system's animations across iOS and macOS use spring physics, not ease-in-out curves. Springs produce motion that feels alive because they have momentum: elements overshoot slightly and settle, the way physical objects do. Eased animations feel mechanical by comparison.

Use spring for virtually all transitions in a native app:

- `.smooth` — gentle, professional. Good for content that slides in, cards that expand, lists that reload.
- `.snappy` — quick and confident. Good for toggles, selection changes, button feedback.
- `.bouncy` — expressive, playful. Use sparingly — for celebrations, confirmations, or one-off moments of delight. Not for status updates or data refreshes.

The wrong spring choice is more visible than no animation. A bouncy spring on a critical alert feels dismissive. A slow smooth spring on a toggle response feels sluggish.

### Animate state changes, not screen construction

The most valuable place for animation is in *transitions between states* — not in the initial appearance of a screen's content. A screen that animates every element into place when it first loads is performing. A screen where the status indicator smoothly shifts from green to orange when a sensor crosses a threshold is communicating.

Reserve animation for:
- Status changes (normal → warning → critical)
- Value updates on live numeric displays
- Row insertions/deletions in a list
- Expanding and collapsing sections
- Sheet presentations and dismissals

Avoid animation on:
- The initial load of a screen's static content
- Background data refreshes where no state visible to the user has changed
- Navigation transitions (the system handles these correctly already)

### `contentTransition` for value changes

When a displayed value updates — a temperature reading, a battery percentage, a sensor count — use `.contentTransition(.numericText())` to communicate that the number changed, not just replaced:

```swift
Text(reading.displayValue)
    .font(.title2.monospacedDigit())
    .contentTransition(.numericText())
    .animation(.snappy, value: reading.displayValue)
```

This makes the update feel like a measurement changing rather than a string replacing another string. It's a small thing that makes live data feel genuinely live.

### Phase Animator for discrete state sequences

When an element needs to cycle through a series of visual states — a pulsing indicator, a multi-step confirmation, an attention-getting alert — `PhaseAnimator` defines those states explicitly rather than chaining `.onAppear` callbacks:

```swift
PhaseAnimator([1.0, 1.1, 1.0]) { scale in
    Circle()
        .scaleEffect(scale)
        .foregroundStyle(scale > 1 ? .red : .orange)
} animation: { _ in .easeInOut(duration: 0.6) }
```

This is cleaner than manual timers and produces more reliable visual results. Use it for attention indicators on critical status items.

### The reduce motion contract

Some users experience nausea or disorientation from animated motion. Respecting their system preference isn't optional — it's a visual design responsibility.

Check `@Environment(\.accessibilityReduceMotion)` and replace motion-based transitions with instant swaps or simple fades when it's enabled:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

var body: some View {
    content
        .animation(reduceMotion ? .none : .spring(.snappy), value: isExpanded)
}
```

A fade is almost always an acceptable substitute for a slide or scale transition. The content still changes — the user just isn't subjected to spatial movement.

### What not to animate

- **Pulsing indicators on every "active" device.** One pulsing element draws attention. Eight pulsing elements create visual noise and lose all meaning.
- **Continuous loops on non-critical status.** A spinning or breathing animation that never stops trains the eye to ignore it. Reserve continuous animation for genuinely time-sensitive states.
- **Layout shifts during data updates.** If a list reorders itself or a card resizes every 30 seconds as data refreshes, the screen never feels settled. Prefer stable layouts where values update in place over layouts that restructure.

---

## 10. Liquid Glass & Material Surfaces

iOS 26 and macOS Tahoe (2025) introduced Liquid Glass — Apple's new material language built on translucency, refraction, and depth rather than flat color. Understanding when and how to use it is now part of getting native visual design right.

### What Liquid Glass actually is

Liquid Glass is a dynamic translucent material that reflects and refracts the content beneath it. Unlike the earlier `.ultraThinMaterial` approach (which was simply a frosted blur), Liquid Glass actively responds to the colors and motion behind it — tinting slightly toward background content, catching virtual light, and behaving more like physical glass than a translucent filter.

The system uses it on tab bars, navigation bars, sheets, controls, and toolbars. It replaces the more static material and blur treatments of iOS 15–17.

### When to use it

Use Liquid Glass for surfaces that:
- Float above content — panels, popovers, toolbars, floating controls
- Need to feel spatially elevated without a shadow
- Sit over dynamic, colorful content where a static background color would look disconnected

The key question is whether the surface **needs** to communicate elevation above content beneath it. If the answer is yes, a material is the right tool. If the answer is no — the surface is just a background, not a layer — a solid semantic color is better.

### When not to use it

Translucent materials are not a free way to add visual richness. They become problematic when:

- **Content beneath is text-heavy.** The refraction effect can make overlaid text harder to read, especially at small sizes. A solid `.background.secondary` surface protects text legibility better than glass over a busy list.
- **The surface is static and surrounded by static content.** Glass responds to what's behind it. If nothing is moving or colorful beneath the surface, it just looks like a gray blur — none of the dynamism that earns its visual cost.
- **You're layering glass on glass.** Multiple translucent surfaces stacked create muddy depth. Glass works when it sits over clearly different content below.
- **You're in a compact context like a menubar popover.** Small, dense panels are better served by solid backgrounds with clear typographic hierarchy. Glass in a 300pt-wide panel at 8pt padding is hard to pull off cleanly.

### Adopting it correctly in SwiftUI

The simplest correct adoption is to use the updated system controls — tab bars, navigation bars, sheets — without customization. These are already Liquid Glass in iOS 26 and macOS Tahoe. The mistake is overriding them with custom backgrounds that break the material.

For custom floating surfaces (a HUD overlay, a contextual action panel, a status badge over content):

```swift
// System material — responds to Liquid Glass rendering context
.background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
```

Avoid layering `.opacity()` modifiers or custom color blends over materials — these break the glass effect and produce ugly compositing artifacts, especially in dark mode.

### Color over glass

Text placed over a material surface must use semantic colors — `.primary`, `.secondary` — not custom hex values. Semantic colors are designed to maintain legibility over translucent surfaces and adapt as the underlying content changes. Custom colors that look fine over a solid background may become unreadable when the background shifts.

Status colors (red, orange) over glass need extra scrutiny in dark mode. Test them — system red and orange are calibrated for this; custom variants often are not.

---

## 11. Accessibility as Visual Design

Accessibility is not a separate concern from visual design — it *is* visual design. An app that becomes illegible at larger text sizes, or that loses meaning without color, has failed at its visual design goals even before an accessibility audit begins.

### Design for Dynamic Type from the start, not after

Dynamic Type lets users set their preferred text size system-wide, from Small to Accessibility XXL. Designing for it means:

**Avoid fixed-height containers for text.** A card that is always 80pt tall will clip text at Accessibility XL sizes. Let containers grow with their content.

**Adapt layout for large text sizes.** A horizontal row with a label on the left and a value on the right works at default sizes. At Accessibility XL it will truncate. The right pattern is to check `sizeCategory` and stack vertically at larger sizes:

```swift
@Environment(\.dynamicTypeSize) private var typeSize

var body: some View {
    Group {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading) { label; value }
        } else {
            HStack { label; Spacer(); value }
        }
    }
}
```

**Test with Accessibility XL before shipping.** Simulator → Settings → Accessibility → Display & Text Size → Larger Text. If a screen breaks at this size, it will break for real users. At minimum, test with `.extraExtraExtraLarge`.

### Color is never the only signal

This is the most common accessibility failure in visual design, and it's entirely visible without any special tools. Ask of every colored element: *if this were grayscale, would it still communicate the same thing?*

A green dot meaning "online" and a red dot meaning "offline" fail the grayscale test. The same dots with a checkmark and an X, or labeled "Online" and "Offline," pass it. A status badge that is colored red and reads "Critical" passes it.

For a monitoring app, pair every color state with at least one of: an icon, a label, or a shape change. Color reinforces — it doesn't replace.

### Contrast is a design decision, not just a compliance check

WCAG requires 4.5:1 contrast ratio for normal text against its background. But the more useful design heuristic is: **can a user read this comfortably in bright sunlight on a phone screen with the brightness turned down?** That's a harder test than the ratio, and it's the real-world condition your app will face.

Specific patterns that frequently fail contrast:
- `.secondary` text over a `.background.secondary` card in dark mode — borderline at default contrast settings
- Tinted icon on a matching tinted background ("green icon on light green badge")
- `.tertiary` text over any non-white background at small sizes (`.caption` or smaller)

The Increased Contrast accessibility mode asks apps to use higher-contrast versions of system colors. Trust semantic colors and this is handled automatically. Custom colors with manually set opacity values will not respond correctly.

### VoiceOver-aware visual grouping

Visual grouping and VoiceOver grouping should match. If a card visually groups a device name, status, and last-updated time as a single unit, VoiceOver should read them together as a single element. A card that presents as visually unified but is read by VoiceOver as three separate elements creates a confusing experience.

This is a visual design concern because it forces you to think clearly about what constitutes a logical unit of information — which produces better layout decisions regardless of VoiceOver.

---

## 12. Haptic Feedback as Polish

Haptics are a tactile layer of the visual design system — they confirm interactions, reinforce state changes, and give physical weight to digital actions. Used well, they make an app feel more confident and precise. Overused, they feel spammy and lose all meaning.

### Haptics work on iPhone only

Haptic feedback is available on iPhone via the Taptic Engine. Macs and iPads do not vibrate. This means every haptic decision must answer: *does this make sense on iPhone, given that the same interaction on Mac will have no tactile response?* Design so the interaction doesn't depend on haptic confirmation to be understandable.

### The right moments for haptics

SwiftUI's `sensoryFeedback` modifier provides a vocabulary of feedback types that map to different interaction qualities:

- **`.success`** — confirmation that something completed correctly. A device connected, a value was saved, a reading came back in range.
- **`.warning`** — something needs attention but isn't broken. A threshold crossed, a value entering the warning zone.
- **`.error`** — something failed. Use sparingly — only for genuine failures, not for empty states or missing data.
- **`.selection`** — light tick for a picker or segmented control moving between values.
- **`.impact`** — physical sensation for drag completion, snap-to-grid, or an element settling into place.

```swift
.sensoryFeedback(.warning, trigger: reading.isInWarningZone)
```

### What to avoid

- **Haptics on every row tap.** Selection feedback on every list row creates a machine-gun effect if the user scrolls with taps. Reserve it for actions that actually do something — not navigation.
- **Repeated haptics during animation.** A pulsing alert that fires a haptic on each pulse is unbearable. Fire once on entry into the alert state.
- **Haptics on data refreshes.** Background data arriving is not an event the user caused — confirming it with a haptic is unexpected and disorienting.

The test for whether a haptic earns its place: would its absence make the interaction feel incomplete? If yes, add it. If the answer is "no, it's just a nice extra," think harder about whether it adds or distracts.

---

## 13. Menubar Surface Design

The menubar popover is a distinct design surface with its own rules. It's not a shrunk-down iOS screen — it has different density expectations, different interaction patterns, and a different relationship to the user's attention.

### Sizing: narrow and purposeful

A menubar popover should be narrow — typically 280–360pt wide — and only as tall as its content requires. The user is expecting a quick glance or a rapid action, not a full app experience. If content wants to be taller than about 400–500pt, that's a signal that it belongs in a full window, not a popover.

Resist the temptation to make the popover match your iOS layout. The compact width is a constraint that forces better information architecture — use it.

### Density calibration for the surface

The menubar popover warrants the tightest density of any surface in your app. An 8pt base spacing system, `.caption`-level metadata, and rows in the 36–44pt height range all feel appropriate here. The same density on an iOS primary screen would feel cramped; here it reads as purposeful.

A menubar app showing 8–12 device statuses at a glance is serving its purpose. One that shows 3 items with generous spacing is wasting the surface.

### Avoid cards in the menubar

Cards — with their backgrounds, corner radii, and padding overhead — cost too much visual weight for a compact surface. Prefer plain rows with consistent left-edge alignment and a value on the right trailing edge. The popover frame itself provides containment; you don't need internal surfaces adding more layers.

```swift
// Good menubar row pattern
HStack {
    Label(device.name, systemImage: device.icon)
        .font(.subheadline)
    Spacer()
    Text(device.displayValue)
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(device.severity.color)
}
.padding(.horizontal, Spacing.md)  // 12pt — tighter than main app
.padding(.vertical, Spacing.xs)    // 4pt vertical — compact rows
```

### The menubar icon

The icon in the menu bar represents your app at all times — it's always visible, even when the popover is closed. It should be:

- **Template-rendered** — a monochrome SF Symbol or simple shape that the system can tint correctly in both the light and dark menu bar. Avoid full-color custom images; they look inconsistent and often become illegible against certain desktop wallpapers.
- **State-aware when warranted.** It's legitimate to change the icon when your app needs attention — switching from a neutral symbol to a filled or colored variant when there's a critical alert. But the default state icon should be neutral and visually quiet.
- **Simple at small sizes.** The menu bar icon renders at roughly 18×18pt. Complex artwork or fine detail disappears entirely. Test the icon at actual size.

```swift
MenuBarExtra("My App", systemImage: hasAlert ? "exclamationmark.circle.fill" : "circle") {
    MenuBarView()
}
```

### MenuBarExtra window style vs. menu style

**Window style** (`.menuBarExtraStyle(.window)`) gives you a floating panel with full SwiftUI layout. This is appropriate for any content that includes custom controls, live-updating data, or a layout richer than a simple list.

**Menu style** (the default) renders native macOS menu items. This limits you to text, buttons, and dividers — but it's visually indistinguishable from system menus, which is a strong native quality signal for simple utility apps.

Choose menu style only if your content is genuinely list-of-actions. Choose window style if your content is live data. Don't try to approximate live data display in menu style — the rendering constraints will produce a worse result than a properly designed window-style popover.

---

## Quick Reference

**Before shipping any screen, ask:**

- What is the one thing that should land first? Is it actually the first thing that lands?
- Are all spacing values from the design token enum — nothing arbitrary?
- Are corner radii consistent — all from the enum, all `.continuous` style?
- Is accent/tint color appearing only on interactive elements or active states?
- Are `.secondary` and `.tertiary` foreground styles doing the depth work instead of custom colors?
- Do symbol weights match adjacent text weights?
- Is every data value showing the right level of precision for its context?
- Does the screen look right in dark mode without any `colorScheme` branches?
- Are shadows absent unless genuinely earned?
- Does the squint test reveal one clear primary read?
- Does every animation communicate something, or is it just motion?
- Does the app work — and look good — at Accessibility XL text size?
- Does every color signal have a paired icon or label that survives grayscale?
- If this surface uses a material, does that material earn its visual cost?
- On the menubar popover: is every piece of information glanceable in under 2 seconds?

#coding
