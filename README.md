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

1. Open the `.dmg` and drag **QuickSwitch** onto the **Applications** shortcut,
   then launch it. There is no Dock icon; look for the window icon in the menu
   bar.
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

This repository is private and releases are uploaded to the public
[QuickSwitch-Mac](https://github.com/MuhammadNasir-dev/QuickSwitch-Mac) by hand,
so `.github/workflows/release.yml` **builds only — it publishes nothing**. That
also means it needs no tokens and no write permissions.

```bash
git tag v1.0.1 && git push origin v1.0.1
```

The **tag is the version**. The workflow passes it as `MARKETING_VERSION`, so
`v1.0.1` produces a bundle reporting `1.0.1` no matter what the Xcode project
says, and `CURRENT_PROJECT_VERSION` becomes the workflow run number so every
build is distinct. Use three components — `v1.0.0`, not `v1.0` — to match the
tag, the release and `appcast.json` exactly.

It produces **two disk images** — `apple-silicon` (arm64) and `intel` (x86_64) —
plus `SHA256SUMS.txt`, as a single downloadable artifact on the workflow run.
Each `.dmg` opens to the app beside an `/Applications` shortcut, so installing is
a drag. The workflow mounts each image before finishing and fails if the app or
the shortcut is missing.
The run summary contains paste-ready release notes and the checksums, so
creating the public release is: download the artifact, open
[releases/new](https://github.com/MuhammadNasir-dev/QuickSwitch-Mac/releases/new),
drop the files in, paste the notes.

Each build is verified with `lipo` so a mislabelled architecture cannot ship,
and the workflow fails outright if `get-task-allow` is present — the debug
entitlement that must never be released.

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

This repository is private. Built releases are published to the public
[MuhammadNasir-dev/QuickSwitch-Mac](https://github.com/MuhammadNasir-dev/QuickSwitch-Mac),
which is what users download from and what the download counts below read.

## Counting users

There are two different numbers, and they come from different places.

### Downloads — available today, no setup

GitHub records a download count per release asset. Nothing to host, nothing in
the app:

```bash
./scripts/download-counts.sh
```

```
v1.0.1         2026-07-28         412 downloads
    QuickSwitch-1.0.1-apple-silicon.zip                 366
    QuickSwitch-1.0.1-intel.zip                          46

TOTAL                                412 downloads
  apple-silicon                       366  (89%)
  intel                                46  (11%)
```

The Apple Silicon / Intel split is genuinely useful — it tells you when the
Intel build stops being worth producing.

A download is **not** an install. The same person re-downloading, or taking both
architectures, counts twice; someone who downloads and never opens it counts
once. Read it as a floor on reach, not a user count.

### Releasing: what goes where

Two destinations, one file each way round:

| File | Goes to | Why |
| --- | --- | --- |
| `QuickSwitch-<version>-apple-silicon.dmg`<br>`QuickSwitch-<version>-intel.dmg` | GitHub release on [QuickSwitch-Mac](https://github.com/MuhammadNasir-dev/QuickSwitch-Mac/releases/new) | What users download. GitHub counts these for you. |
| `appcast.json` | Root of **quickswitchmac.com** | What running copies check daily. Nothing else goes on the website. |

The disk images are **not** uploaded to the website — `appcast.json` only points
at the GitHub release, so there is one copy of each build and one download count.

`appcast.json` is two lines:

```json
{
  "version": "1.0.1",
  "url": "https://github.com/MuhammadNasir-dev/QuickSwitch-Mac/releases/latest"
}
```

**Bumping `version` is what triggers the update notice.** Publish the release and
forget the website and nobody is told anything — the app compares its own version
against this file and stays quiet when they match. The workflow run summary
prints the exact JSON for the version just built, so it is a copy-and-paste.

### Active users — needs a host with request logs

The app checks `https://quickswitchmac.com/appcast.json` once a day, so one log
line per running copy per day is a real daily-active count.

**GitHub Pages will not give you this.** Pages serves the file happily but
exposes no access logs, so the requests arrive and vanish. If you host the
manifest there you get updates working and no numbers at all.

Anything that reports request counts works. The least effort is putting the
domain behind Cloudflare's free tier and reading the analytics for
`/appcast.json`; a small VPS or any host with raw logs does the same:

```bash
awk '$7 ~ /appcast.json/ {print substr($4,2,11), $1}' access.log | sort -u | uniq -c
```

Because nothing identifying is sent, that counts distinct addresses per day, not
installs — several Macs behind one router count once, one laptop on two networks
counts twice. Accurate enough to watch a trend.

### What is deliberately not sent

No install identifier, no account, no persistent token, and **nothing derived
from the user's windows** — no titles, no app names, no counts. An app holding
Accessibility permission has to be able to state that plainly and have it be
true, so the check is a plain `GET` carrying the app version and macOS version
(`?v=1.0.1&os=15.7`) and nothing else. Settings → General says the same in the
same words, with an off switch.

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
