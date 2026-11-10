# Contributing to QuickSwitch

Thank you for your interest in contributing to QuickSwitch! We welcome contributions from everyone, whether reporting bugs, proposing new features, improving documentation, or writing code.

---

## Code of Conduct

This project is governed by the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

---

## Development Prerequisites

- **macOS**: macOS 15.7 or later
- **Xcode**: Xcode 16.0 or later (Swift 6.1+ toolchain)
- **Permissions**: Accessibility permission is required for the switcher to inspect window titles and switch between windows.

---

## Getting Started

1. **Fork the repository** on GitHub.
2. **Clone your fork**:
   ```bash
   git clone https://github.com/<your-username>/window-manager.git
   cd window-manager
   ```
3. **Open the project in Xcode**:
   ```bash
   open window-manager.xcodeproj
   ```
4. **Select the Scheme**: Choose the `QuickSwitch` scheme and destination `My Mac`.
5. **Build and Run** (<kbd>⌘</kbd><kbd>R</kbd>).

### Important: Accessibility Permissions in Development

- QuickSwitch relies on the macOS Accessibility API (`AXUIElementCopyAttributeValue`, etc.) to read window titles and activate windows.
- macOS ties Accessibility approval to the app bundle's code signature. When building locally with an ad-hoc or development certificate:
  1. Open **System Settings → Privacy & Security → Accessibility**.
  2. If a previous build exists, remove it using the **−** button.
  3. Add the newly built `QuickSwitch.app` using **+** or drag it into the list.

---

## Project Architecture

The codebase is organized into modular layers:

| Layer | Path | Responsibility |
| --- | --- | --- |
| **App** | `window-manager/App/` | Composition root (`AppServices`), application lifecycle (`AppDelegate`), status bar item (`StatusItemController`), and update checking. |
| **Accessibility** | `window-manager/Accessibility/` | Type-safe Swift wrappers around CoreGraphics/AX C APIs (`AX`, `AXPrivateAPI`, `AXElementRef`), trust monitoring (`AccessibilityAuthorizer`). |
| **Windows** | `window-manager/Windows/` | Window enumeration (`WindowEnumerator`), filtering switchable windows (`WindowFilter`), MRU cache (`WindowIndex`), event observers (`WindowObservationCenter`), and activation pipeline (`WindowActivator`). |
| **Input** | `window-manager/Input/` | Low-level event tap (`CGEventTap`) on a dedicated background thread (`HotKeyMonitor`), shortcut decoding (`SwitcherCommand`). |
| **Search** | `window-manager/Search/` | Subsequence scoring and fuzzy matching (`FuzzyMatcher`) with highlight offsets. |
| **UI** | `window-manager/UI/` | Floating switcher panel (`SwitcherPanel`, `SwitcherView`), presentation layouts (List, Grouped, Grid), settings window, and setup guide. |

---

## Testing

Run unit tests via Xcode (<kbd>⌘</kbd><kbd>U</kbd>) or via the command line:

```bash
xcodebuild -project window-manager.xcodeproj -scheme QuickSwitch -destination 'platform=macOS' test
```

Unit tests cover:
- Fuzzy matching algorithm and ranking
- Window filtering logic
- Recency tracker & MRU ordering
- Settings and preference persistence
- Panel geometry and layout calculations

---

## Guidelines for Code Contributions

1. **Strict Concurrency**: The project compiles with Swift 6 concurrency checking. Respect actor boundaries and isolation rules (`@MainActor`, `nonisolated`, `Sendable`).
2. **Fail-Safe Input Handling**: The global shortcut interceptor (`CGEventTap`) must always fail open. If the tap times out or is disabled by macOS, never lock the user out of their keyboard.
3. **Privacy First**: QuickSwitch must never collect or transmit window titles, process names, or user data. Network requests are strictly limited to opt-in release update checks against `appcast.json`.
4. **Documentation**: Document non-obvious workarounds for macOS quirks or undocumented behaviors.
5. **Keep Pull Requests Focused**: A PR should address a single feature or bug fix.

---

## Submitting a Pull Request

1. Create a feature branch:
   ```bash
   git checkout -b feature/my-cool-feature
   ```
2. Commit your changes with clear, descriptive commit messages.
3. Ensure the project builds cleanly and all tests pass.
4. Push your branch to GitHub:
   ```bash
   git push origin feature/my-cool-feature
   ```
5. Open a Pull Request against the default branch (`main` / `master`).
6. Complete the PR template with context, screenshots (if applicable), and testing steps.

---

## Reporting Issues

If you find a bug or have a suggestion:
1. Search existing issues to verify it hasn't already been reported.
2. If opening a new issue, use the appropriate Issue Template (Bug Report or Feature Request).
3. Include your macOS version, Mac hardware (Apple Silicon or Intel), and steps to reproduce.
