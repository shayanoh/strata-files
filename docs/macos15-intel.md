# Building Strata for Intel Macs and macOS 15

Upstream Strata requires an Apple silicon Mac and macOS 26. This branch builds it as an **x86_64** app with a **macOS 15**
deployment target, and it runs there. This page explains what had to change and why, so the changes can be reviewed,
rebased or dropped piece by piece.

## What works, and what doesn't

Verified: `scripts/build.sh release` produces `build/Strata.app` (x86_64, `minos 15.0`, ad-hoc signed). It launched on an Intel
Mac running macOS 15.7 and showed the window, sidebar, List view with live folder sizes, inspector, tags, Locations, dual pane, and a
colour theme with Window tint on; the home-folder index was built (about 2.6 million items).

Not verified: `swift test`, and most features beyond browsing (⌘K, search, Quick Look and previews, Disk Usage, Settings, servers,
containers, archives).

Differences on macOS 15:

- No Liquid Glass. Backdrops that are glass on macOS 26 use a translucent `NSVisualEffectView` material with the same rounded shape.
- The status bar, notice bar, search scope bar and sidebar footer are plain stacked views, not AppKit split-view accessories.
- Titlebar and toolbar theme tinting only recognizes macOS 26's layer structures (`NativeHeaderFillTint`), so macOS 15 falls back to native drawing.
- Apple Intelligence (Ask Strata's model planner, summaries, natural-language search) is reported as unavailable before macOS 26, as it already
  is on Intel. Ask Strata's built-in rules and key-sentence summaries still work.
- With a theme and Window tint on, the traffic-light row above the sidebar draws black instead of themed (not investigated).

## Building

```bash
scripts/build.sh release      # build/Strata.app
open -n build/Strata.app
```

Needs Xcode 26 or later (the macOS 26 SDK; the code uses `#available` for newer API). It was built with Xcode 26.0.1 (Swift 6.2). `scripts/build.sh`
now builds `x86_64`; use `--arch arm64 --arch x86_64` in it for a universal binary.

Every rebuild changes the app's ad-hoc signature, so macOS asks again for access to the "Strata Safe Storage" Keychain item (the key for the encrypted
index and history). Sign with a stable identity (`STRATA_SIGNING_IDENTITY`) to avoid it.

## Why it didn't build, and the changes

### 1. Swift 6.2 instead of 6.3

The project targets Swift 6.3 (Xcode 26.4 or later). Xcode 26.0.1's Swift 6.2 is stricter in a few places. With a newer toolchain, this group isn't needed.

| File | Problem | Change |
|---|---|---|
| `Model/MediaDetails.swift` | `sending 'items' risks causing data races` | `nonisolated(nonsending)` on the local `firstString` |
| `Model/PlaceChecks.swift` | `[URL] + PrefixSequence<[URL]>` has no `+` | `Array(visited.prefix(100))`, expression split |
| `Model/OperationLog.swift` | type-checker timeout in `movesBack` | the chained expression split into typed steps (same behaviour) |
| `AI/AIModel.swift`, `AI/Summarizer.swift` | `SystemLanguageModel.contextSize` / `.tokenCount` don't exist in the 26.0 SDK | gated with `#if compiler(>=6.3)`, with a 4096-token fallback |
| `Views/ContainerDrag.swift` | non-`Sendable` closure sent to `Task` | the captured `var` replaced by a small `@unchecked Sendable` box, ordered by the existing semaphore |
| `Window/BrowserWindowController+Palette.swift` | `async let` sending `self` | explicit main-actor `Task` plus `withTaskCancellationHandler` |

**Release-only compiler crash.** `scripts/build.sh release` crashed `swift-frontend` (signal 11, in IR generation for `BatchedReads`'s synthesized deinit); debug builds were fine.
It is reproducible in one line: a *generic* class under main-actor default isolation that stores a `Task`:

```swift
// swiftc -O -swift-version 6 -default-isolation MainActor
final class T<V: Sendable> { private var c: Task<Void, Never>?; init() {} }
```

`-Osize`, `@MainActor` on the class and `-sil-disable-pass=optimize-hop-to-executor` don't avoid it; `-Onone` and a `nonisolated` class do.
The fix is an explicit `nonisolated deinit {}` on `BatchedReads` (identical behaviour: class deinits are nonisolated by default).
Another generic main-actor class holding a `Task` would crash the same way on Swift 6.2.

### 2. macOS 26-only API (deployment target 15)

`Package.swift` now says `.macOS(.v15)` and `Resources/Info.plist` has `LSMinimumSystemVersion 15.0`. Lowering the target exposed five groups:

| Family | macOS 26 API | Where | Change |
|---|---|---|---|
| Liquid Glass tinting | `NSGlassEffectView` type checks and `tintColor` | `App/ColorTheme`, `HeaderMaterialTint`, `ToolbarBackdropTint` | `Support/GlassCompat.swift`: availability-guarded helpers; "no glass" before macOS 26 |
| Safe-area control | `NSSplitViewItem.automaticallyAdjustsSafeAreaInsets` | `App/ThemeSurfaces` | same helper |
| Glass backdrops the app creates | `NSGlassEffectView` with `cornerRadius` and `contentView` | filter pill, ⌘K palette, path suggestions, Shelf, Dock search | `Support/GlassView.swift`: glass on 26, `NSVisualEffectView(.hudWindow)` with a rounded layer on 15 |
| Split-view accessory bars | `NSSplitViewItemAccessoryViewController` and `add{Top,Bottom}AlignedAccessoryViewController` | `NoticeBar`, `SearchScopeBar`, `StatusBarController`, the sidebar footer, `MainSplitViewController` | `Window/AccessoryBars.swift`: see below |
| Apple Intelligence | all of `FoundationModels` | six files in `AI/` | `@available(macOS 26, *)` on the model-calling types and members; `AIModel.status` returns `.deviceNotEligible` before 26; callers check `#available`. The framework is weak-linked automatically |

`AccessoryBarController` is the new base class of the four bars (a plain view controller with `isHidden`). `SplitAccessories.dock(top:bottom:on:)` hosts each bar in a
real accessory controller on macOS 26 (so nothing changes there) and, on macOS 15, replaces the item's controller with a vertical `NSStackView` of the top bars, the
content and the bottom bars.

### 3. Two bugs found by running it on macOS 15

Both are in the macOS 15 stand-in for the accessory bars.

- **List squeezed against the right edge.** `NSStackView.alignment = .width` only makes arranged views as wide as *each other*, not as wide as the stack. The pane
  container ended up 300 pt wide at the right edge of an 818 pt column. Fixed with `alignment = .leading` and explicit leading and trailing constraints on every arranged view.
- **Blank window with a colour theme and Window tint on.** `ThemeAccessoryView.viewDidMoveToSuperview` paints a "padding canvas" sized to its superview, directly beneath itself.
  On macOS 26 the superview is AppKit's small per-bar container; in the stack it was the whole column, so the canvas covered the file list and the sidebar with the tint colour.
  (Without a theme the canvas is hidden, which is why it only showed with one.) Fixed by wrapping each bar in its own plain container view (`wrapped(_:)`), as AppKit does.
  Each split item's root view is also a plain `NSView` holding the stack, as on macOS 26.

## Remaining work

- Run `swift test`, and the audits in `AGENTS.md`; some tests may assert macOS 26 chrome (glass, accessories).
- Exercise ⌘K, search, previews, Disk Usage, Settings, servers, containers and archives on macOS 15.
- Find out why the top-left sidebar corner is black with a theme and tint.
- Keep or drop the macOS 26 code paths: this change keeps real Liquid Glass and native accessories on 26, at the cost of the shims above.
