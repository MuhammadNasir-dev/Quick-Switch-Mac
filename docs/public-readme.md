# QuickSwitch

**A window switcher for macOS that shows every open window, not just apps.**

The built-in Command-Tab switches between *applications*. If you have six Safari
windows and four editor windows, it gives you two icons. QuickSwitch gives you
all ten, each with its own title, so you go straight to the one you meant.

```
🌐 Safari      ChatGPT — OpenAI
🌐 Safari      GitHub
🌐 Safari      Gmail
💻 VS Code     Browser.swift
💻 VS Code     AppDelegate.swift
🖥 Terminal    npm run dev
📁 Finder      Downloads
```

[**Download the latest release →**](https://github.com/MuhammadNasir-dev/QuickSwitch-Mac/releases/latest)

| Your Mac | File |
| --- | --- |
| **Apple Silicon** (M1, M2, M3, M4…) | `QuickSwitch-<version>-apple-silicon.dmg` |
| **Intel** | `QuickSwitch-<version>-intel.dmg` |

Not sure which? Apple menu → **About This Mac**. **Chip** means Apple Silicon;
**Processor** means Intel.

Requires **macOS 15.7 or later**.

## Install

1. Open the `.dmg` and drag **QuickSwitch** onto the **Applications** shortcut.
2. Launch it from Applications. macOS blocks the first launch — see below.
3. Open **System Settings → Privacy & Security**, scroll to the bottom, and
   click **Open Anyway** next to QuickSwitch.
4. Grant **Accessibility** access when prompted. The setup window notices as soon
   as you do — no relaunch.

QuickSwitch has no Dock icon. Look for the window icon in your menu bar.

### If there is no "Open Anyway", or macOS says the app is damaged

The app is not damaged. That message means macOS cannot verify a build that has
not been notarized, and some versions refuse it outright instead of offering the
button. Clearing the quarantine flag does the same thing the button does:

```bash
xattr -d com.apple.quarantine /Applications/QuickSwitch.app
```

Then launch it normally.

Only run that for software you trust. It is the same command attackers ask
people to run, precisely because it switches off the check macOS was making —
it is safe here because you can see where this build came from, not because the
command is harmless.

## Using it

Press **⌥ Option + Tab**. Hold Option and tap Tab to move down the list; let go
to switch.

| Key | Action |
| --- | --- |
| <kbd>⌥</kbd><kbd>⇥</kbd> | Open, then move down |
| <kbd>⇧</kbd><kbd>⌥</kbd><kbd>⇥</kbd> | Move up |
| <kbd>↑</kbd> <kbd>↓</kbd> | Move the selection |
| <kbd>⏎</kbd> | Switch to the highlighted window |
| <kbd>esc</kbd> | Close without switching |
| <kbd>⌘</kbd><kbd>1</kbd>–<kbd>9</kbd> | Jump straight to a row |
| <kbd>⌘</kbd><kbd>D</kbd> | Pin an app to the top |
| <kbd>⌘</kbd><kbd>L</kbd> | Switch between List, Grouped and Grid |
| *type anything* | Filter by app name or window title |

Prefer **⌘ Command + Tab**? Settings → Shortcut. That replaces the macOS
switcher entirely while QuickSwitch is running.

## Features

- **Every window individually** — including minimised ones and windows on other
  Desktops
- **Three layouts** — a dense list, grouped by application, or a grid of large
  icons
- **Fuzzy search** — start typing to filter by app name or window title
- **Favourites** — pin the apps you switch to most so they always lead
- **Launch at login**
- Keyboard-first: nothing needs the mouse, and a resting cursor never steals
  your selection

## Permissions and privacy

QuickSwitch needs **Accessibility** access. It is the only way macOS lets an app
read window titles and bring another app's window to the front — the app cannot
do its job without it.

**Nothing about your windows ever leaves your Mac.** No titles, no app names, no
counts. The only network request QuickSwitch makes is a daily check for a newer
version, which sends the app version and your macOS version and nothing else.
Turn it off in Settings → General.

QuickSwitch does not ask for Screen Recording. Window titles come from the
Accessibility API precisely so that permission is never needed.

## Known limitations

These are macOS constraints rather than missing work:

- **Not notarized**, so the first launch needs the step above. Notarization
  requires a paid Apple developer account.
- **Accessibility access is revoked whenever the app is replaced**, because
  macOS ties the grant to the exact build. If the shortcut stops working after
  an update: System Settings → Privacy & Security → Accessibility, remove
  QuickSwitch with **−**, then add it back with **+**. macOS only offers the
  permission prompt once per build, so a stale entry cannot be re-approved — it
  has to be replaced.
- **Windows on Desktops you have not visited** since launching appear once you
  switch to them. macOS does not report them before that.
- **Secure input** — while another app has secure keyboard entry on (a password
  field in Terminal, a login prompt), no global shortcut can fire. The menu bar
  says so when it happens.

## Support

Found a bug or want something added?
[Open an issue](https://github.com/MuhammadNasir-dev/QuickSwitch-Mac/issues).

---

[quickswitchmac.com](https://quickswitchmac.com) · Copyright © 2026
QuickSwitchMac. All rights reserved.
