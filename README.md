# Window Switcher

A macOS window switcher that lists **every open window individually**, not just
applications.

```
🌐 Safari      ChatGPT — OpenAI
🌐 Safari      GitHub
🌐 Safari      Gmail
💻 VS Code     Browser.swift
💻 VS Code     AppDelegate.swift
🖥 Terminal    npm run dev
📁 Finder      Downloads
```

## Setup

1. Build and run. The app has no Dock icon; look for the window icon in the
   menu bar.
2. Grant **Accessibility** access when prompted (System Settings → Privacy &
   Security → Accessibility). The setup window detects the change automatically
   — no relaunch.

> Accessibility trust is tied to the code signature, so **every rebuild revokes
> it**. Remove the stale entry in System Settings and re-add the new build.

## Shortcuts

| Key | Action |
| --- | --- |
| <kbd>⌥</kbd><kbd>⇥</kbd> | Open, then advance |
| <kbd>⇧</kbd><kbd>⌥</kbd><kbd>⇥</kbd> | Open at the end, then go back |
| <kbd>↑</kbd> <kbd>↓</kbd> | Move one row (one row of cards in Grid) |
| <kbd>←</kbd> <kbd>→</kbd> <kbd>⇥</kbd> <kbd>⇧⇥</kbd> | Move one item |
| <kbd>⌘</kbd><kbd>L</kbd> | Cycle List → Grouped → Grid without closing the panel |
| <kbd>⌘</kbd><kbd>1</kbd>–<kbd>9</kbd> | Jump to a row and switch |
| <kbd>⏎</kbd> | Switch to the highlighted window |
| <kbd>esc</kbd> | Cancel |
| *type anything* | Fuzzy-filter by app name and window title |

Releasing <kbd>⌥</kbd> switches to the highlighted window, the way Command-Tab
does. **Typing or pressing an arrow key pins the panel open**, so you can let go
of the modifier and keep browsing — without that, reaching the arrows would
release the modifier and switch away before the arrow key ever landed.

The summoning modifier is configurable in Settings. Choosing **Command** takes
over <kbd>⌘</kbd><kbd>⇥</kbd> and replaces the system app switcher entirely;
Option is the default so the system switcher stays available as a fallback.

## Layouts

Set in Settings, cycled live with <kbd>⌘</kbd><kbd>L</kbd>, or picked from the
menu-bar item:

* **List** — a flat list, one window per line. Densest, and the fastest to scan
  when titles differ.
* **Grouped** — the same list with an application header above each run of that
  app's windows, and the app name dropped from the rows themselves.
* **Grid** — large icons like the system switcher, five across.

Grouping only reorders windows so each app's are contiguous; the app that led
the list still leads it. Arrow keys, <kbd>⌘</kbd><kbd>1</kbd>–<kbd>9</kbd> and
search all address the same flat sequence in every layout — headers are never
selectable.

**Show the active app's windows first** (on by default) groups every window of
the app you are currently in at the top, then everything else in
most-recently-used order. Turn it off in Settings for strict MRU, where the
second entry is whatever you were on immediately before.

## Architecture

| Layer | Type | Responsibility |
| --- | --- | --- |
| `App/` | `AppServices` | Composition root; owns everything, wires the trust state machine |
| | `AppDelegate`, `StatusItemController` | Lifecycle, menu-bar presence |
| `Accessibility/` | `AX`, `AXPrivateAPI`, `AXElementRef` | Type-safe, non-trapping wrappers over the C AX API |
| | `AccessibilityAuthorizer` | Trust detection, guidance, automatic recovery |
| `Windows/` | `WindowEnumerator` | Off-main snapshot: AX for identity, `CGWindowList` for order |
| | `WindowFilter` | Which processes and windows are switchable |
| | `WindowObservationCenter` | Per-app and per-window `AXObserver`s + `NSWorkspace` |
| | `WindowIndex` | Always-warm MRU cache; coalesced background refresh |
| | `RecencyTracker` | Focus history that drives MRU ordering |
| | `WindowActivator` | Raise → main → focus → activate, with verification and retry |
| `Input/` | `HotKeyMonitor` | `CGEventTap` on a dedicated thread; decodes `SwitcherCommand`s |
| `Search/` | `FuzzyMatcher` | Scored subsequence matching with highlight offsets |
| `UI/` | `SwitcherController` | Orchestration: commands → view model → activation |
| | `SwitcherPanel`, `SwitcherView` | Non-activating floating panel and its content |
| | `SwitcherLayout`, `SwitcherMetrics` | Layout geometry, shared by SwiftUI and the panel |
| | `WindowRowView`, `GroupHeaderView`, `WindowCardView` | The three presentations, one visual vocabulary |

Opening the panel reads the warm cache and schedules a refresh; it never blocks
on Accessibility IPC.

## Tests

```bash
xcodebuild -project window-manager.xcodeproj -scheme window-manager -destination 'platform=macOS' test
```

Filtering, fuzzy matching, MRU ordering, selection, panel geometry and
preferences are covered by unit tests that need no window server. The
enumerator tests run against the live system and assert invariants; they
self-skip when Accessibility trust is absent.

## Known macOS limitations

* **Accessibility access cannot be granted programmatically**, and it is
  revoked on every rebuild.
* **Secure input**: while any app has secure keyboard entry enabled (a password
  field in Terminal, a login prompt), no `CGEventTap` receives key events, so
  the hotkey is inert. The menu bar surfaces this.
* **`_AXUIElementGetWindow` is private.** It is the only way to map an
  `AXUIElement` to a `CGWindowID`. It is resolved with `dlsym`, so its removal
  degrades to geometry correlation rather than failing to launch.
* **Window titles via `CGWindowList` need Screen Recording.** Titles are read
  through Accessibility instead, so that permission is never requested.
* **Full-screen Spaces animate.** Activating a window in another full-screen
  Space triggers the system's ~0.5 s Space transition, which cannot be skipped.
* **Sandboxing is off** — required, since a sandboxed process can neither
  inspect other apps via Accessibility nor create an event tap.
