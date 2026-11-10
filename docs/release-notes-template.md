Switch between **every open window**, not just apps — including minimised windows
and windows on other Desktops.

## Download

| Your Mac | Download |
| --- | --- |
| **Apple Silicon** (M1, M2, M3, M4…) | `QuickSwitch-1.0.0-apple-silicon.dmg` |
| **Intel** | `QuickSwitch-1.0.0-intel.dmg` |

Not sure which? Apple menu → **About This Mac**. If it says **Chip**, take Apple
Silicon; if it says **Processor**, take Intel.

## Install

1. Open the `.dmg` and drag **QuickSwitch** onto the **Applications** shortcut.
2. Launch it from Applications. macOS will refuse the first time — see below.
3. Open **System Settings → Privacy & Security**, scroll to the bottom, and
   click **Open Anyway** next to QuickSwitch. Confirm.
4. Grant **Accessibility** access when prompted. The setup window detects it
   automatically — no relaunch needed.

QuickSwitch has no Dock icon. Look for the window icon in your menu bar.

### If step 3 does not appear, or macOS says the app is damaged

Some macOS versions block the app outright instead of offering **Open Anyway**.
The app is not damaged — that message means the quarantine flag is set on a build
macOS cannot verify. Clearing the flag in Terminal has the same effect as the
button:

```bash
xattr -d com.apple.quarantine /Applications/QuickSwitch.app
```

Then launch it normally.

Only run that on software you actually trust. It is the same command attackers
ask people to run, precisely because it switches off the check macOS was making
— it is safe here because you can see where this build came from, not because
the command is harmless.

> **Why the security warning?**
> QuickSwitch is not notarized by Apple, which requires a paid developer
> account. macOS shows this warning for any app it cannot check that way — it is
> not a judgement about the app. The step is needed once, on first launch only,
> and again after each update because the replacement is a fresh download.

> **Why Accessibility access?**
> It is the only way macOS lets an app read window titles and bring another
> app's window to the front. QuickSwitch cannot work without it. Nothing about
> your windows ever leaves your Mac.

## Using it

Press **⌥ Option + Tab**. Keep Option held and tap Tab to move down the list;
let go to switch.

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

Prefer **⌘ Command + Tab**? Settings → Shortcut. That replaces the built-in
macOS switcher entirely while QuickSwitch is running.

## In this release

- Every window listed separately, not one entry per app
- Minimised windows and windows on other Desktops included
- Three layouts: List, Grouped by app, and Grid
- Fuzzy search across app names and window titles
- Favourites — pin the apps you switch to most
- Launch at login

## Known limitations

- **Not notarized**, so first launch needs the Open Anyway step above.
- **Accessibility access is revoked whenever the app is replaced.** If the
  shortcut stops working after an update, remove QuickSwitch from
  System Settings → Privacy & Security → Accessibility with the **−** button,
  then add it back with **+**. macOS only offers the permission prompt once per
  build, so a stale entry cannot be re-approved — it has to be replaced.
- Windows on Desktops you have not visited since launching appear once you
  switch to them. macOS does not report them until then.

## Checksums

```
PASTE SHA256SUMS.txt HERE
```

---

Requires macOS 15.7 or later · [quickswitchmac.com](https://quickswitchmac.com)
