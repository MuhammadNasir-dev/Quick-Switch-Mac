# QuickSwitch

[quickswitchmac.com](https://quickswitchmac.com)

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

1. Move **QuickSwitch.app** to `/Applications`, then launch it. There is no Dock
   icon; look for the window icon in the menu bar.
2. Grant **Accessibility** access when prompted (System Settings → Privacy &
   Security → Accessibility). The setup window detects the change automatically
   — no relaunch.
3. Turn on **Launch at Login** from the menu-bar item or Settings.

> Launch at login uses `SMAppService`, so macOS lists QuickSwitch under System
> Settings → General → Login Items and the user can revoke it there. macOS
> refuses to register an app running from a build directory or a disk image —
> `/Applications` is the reliable location.

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
| <kbd>⌘</kbd><kbd>D</kbd> | Pin or unpin the highlighted window's app |
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

**Include windows on other Spaces / displays** (both on by default) control how
far the switcher reaches. Turn either off to narrow it to the Desktop or monitor
you are looking at. Minimised windows are exempt from both — a minimised window
belongs to no Space and no display, so filtering it out would make it
unreachable.

**Favourites** pin an application to the top of the list. Press <kbd>⌘</kbd><kbd>D</kbd>
while the switcher is open, or manage the list in Settings → Favourites. They are
stored per *application*, not per window: a `CGWindowID` is reassigned whenever a
window is closed and reopened and titles change constantly, so neither survives a
restart — the bundle identifier does.

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

The row **order is frozen for the duration of a session**. The index keeps
re-sorting by most-recent-use in the background — and refreshes fire while the
panel is open, triggered by a title change in any application — so without this
the list would shuffle under the user mid-keystroke. Windows still appear,
disappear and retitle live; only the ordering is pinned, and only until the
panel closes.

Settings and the setup guide are AppKit windows owned by `UtilityWindowController`
rather than the SwiftUI `Settings` scene: opening that scene from a menu-bar item
depends on the private `showSettingsWindow:` action reaching a responder that an
`.accessory` app does not reliably have.

## Tests

```bash
xcodebuild -project window-manager.xcodeproj -scheme QuickSwitch -destination 'platform=macOS' test
```

Filtering, fuzzy matching, MRU ordering, selection, panel geometry and
preferences are covered by unit tests that need no window server. The
enumerator tests run against the live system and assert invariants; they
self-skip when Accessibility trust is absent.

## If the shortcut stops working

The menu-bar icon turns into a warning triangle whenever input interception is
down, and the menu says why:

* **Accessibility access was revoked** — re-grant it, then choose *Re-enable
  Shortcut*.
* **Shortcut disabled — the system kept dropping it** — macOS disabled the event
  tap repeatedly. The app deliberately stops re-arming it rather than fighting
  the system, because a tap that keeps timing out while installed makes the
  keyboard unusable. *Re-enable Shortcut* retries on demand.
* **Secure input is active** — another app has secure keyboard entry on; no
  global shortcut can work until it releases.

### Permission won't re-grant

macOS records an Accessibility decision **once per code signature** and then
stops prompting, so an entry left over from an earlier build cannot be switched
back on — the toggle appears to do nothing. Select QuickSwitch in the list,
remove it with **−**, then drag the app back in with **+**. The setup window has
a *Reveal App* button for exactly this.

## Failing safe

The panel sits above every other window and, while visible, the event tap
swallows the keyboard. Several independent guards make sure that state cannot
become permanent:

* Trust is polled in **both** directions; revocation tears down the tap and the
  panel within ~2 s even if the system notification never arrives.
* When macOS disables the tap, the "switcher is visible" flag is cleared
  *synchronously on the tap thread* before anything else — a disabled tap always
  fails open, so keystrokes flow to the focused app.
* Re-arming is rate-limited with exponential backoff and abandoned after four
  consecutive timeouts. Re-enabling a tap that keeps timing out is what locks a
  Mac's keyboard out; a broken switcher is strictly better.
* A 30-second idle watchdog dismisses the panel regardless.
* Clicking outside always dismisses — mouse monitoring, unlike keyboard
  monitoring, does not require Accessibility trust.

## Display scaling

The menu-bar icon is sized to an **even** number of points. The status bar
centres its button image, so the vertical inset is `(22 - height) / 2`; SF
Symbols default to a 15pt-tall image, which makes that 3.5pt. On a Retina
display half a point is exactly one device pixel and looks perfect, but on a 1x
display (a 1080p external monitor) it is *half a pixel* and the compositor
resamples the whole glyph — the icon renders soft. An even height keeps the
inset integral at every scale factor.

The same reasoning fixes the menu header (32pt) and the About icon (64pt):
both are native icon representation sizes, so each display draws a rep 1:1
instead of rescaling one.

## Naming

The product ships as **QuickSwitch.app** with bundle identifier
`com.quickswitchmac.QuickSwitch`. The Xcode *target*, scheme and source folders
are still named `window-manager` — internal identifiers that nothing
user-visible depends on. Renaming those too is a mechanical follow-up if you
want the repository to match the product.

## Releases

`.github/workflows/release.yml` builds, signs and publishes on a tag:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

It produces **two** archives — `apple-silicon` (arm64) and `intel` (x86_64) —
attaches them plus SHA-256 sums to a GitHub Release, and verifies each build
with `lipo` so a mislabelled slice cannot ship. It also fails the build if
`get-task-allow` is present, which is the debug entitlement that must never be
released.

Signing is optional so the workflow is useful immediately. Without secrets it
produces ad-hoc signed builds that run locally but that Gatekeeper refuses
elsewhere. Add these repository secrets to get signed, notarized builds:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | Base64 of the exported Developer ID Application certificate |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting it |
| `APPLE_TEAM_ID` | Ten-character team identifier |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_APP_PASSWORD` | App-specific password for that Apple ID |

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
* **Accessibility under-reports windows on other Spaces.** `kAXWindowsAttribute`
  routinely omits an application's windows that sit on a Space other than the
  active one, so a plain replace-the-list refresh makes everything on Desktop 2
  vanish while you are on Desktop 1. `WindowIndex` therefore *retains* a window
  that Accessibility stops describing for as long as `CGWindowList` still lists
  it, keeping its title and element intact. Retention rather than invention is
  deliberate: synthesising rows from the CoreGraphics list instead produces
  duplicates, because one window routinely owns several layer-0 surfaces that no
  public API distinguishes from real windows.
* **Full-screen Spaces animate.** Activating a window in another full-screen
  Space triggers the system's ~0.5 s Space transition, which cannot be skipped.
* **Sandboxing is off** — required, since a sandboxed process can neither
  inspect other apps via Accessibility nor create an event tap.
