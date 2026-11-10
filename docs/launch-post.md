# LinkedIn launch post

Three variants. Pick one — do not post all three.

The first two or three lines are all LinkedIn shows before "…see more", so the
hook has to carry the click on its own.

---

## Option 1 — the problem (recommended)

> Command-Tab has always shown me apps. I wanted windows.
>
> If I have six Safari windows and four VS Code windows open, macOS gives me two
> icons. I pick one, land on the wrong window, and go hunting.
>
> So I built QuickSwitch.
>
> Press ⌥Tab and every window is its own row — app icon, app name, window title.
> Safari — GitHub. VS Code — AppDelegate.swift. Terminal — npm run dev. Start
> typing to filter. Hit Enter. Done.
>
> → Lightweight. A few megabytes, lives in the menu bar, no Dock icon
> → No account, no sign-in, no tracking
> → Nothing about your windows ever leaves your Mac — no titles, no app names,
> nothing. It does not even ask for screen recording permission
> → Three layouts: a dense list, grouped by app, or a grid of large icons
> → Pin the apps you switch to most so they always come first
>
> Free, and it works on Apple Silicon and Intel.
>
> One honest caveat: it is not notarized yet, so macOS will warn you on first
> launch. The install steps cover it.
>
> Download → quickswitchmac.com
>
> If you try it, tell me what breaks. That is the useful feedback.
>
> #macOS #Productivity #IndieDev #PrivacyFirst #MacApps

---

## Option 2 — shorter, feature-led

> Built a macOS app that fixes something that has annoyed me for years.
>
> Command-Tab switches between apps. QuickSwitch switches between windows.
>
> Six Safari windows? Six rows, each with its own title. Fuzzy search across all
> of them. Pin the apps you use most. Keyboard only, no mouse needed.
>
> Written in Swift and SwiftUI, using the Accessibility API — it never asks for
> screen recording permission, and nothing about your windows leaves your Mac.
>
> Free for Apple Silicon and Intel: quickswitchmac.com
>
> #macOS #Swift #SwiftUI #IndieDev #BuildInPublic

---

## Option 3 — the engineering angle

For a developer-heavy audience. The bugs are the interesting part, and being
specific about them reads as credible in a way a feature list does not.

> I shipped a macOS window switcher this week. The interesting part was not the
> UI — it was everything macOS does not document.
>
> Three things that cost me the most time:
>
> 1. kAXWindowsAttribute quietly omits an app's windows on other Desktops. Every
> refresh made everything on Desktop 2 vanish. The fix was to retain windows
> Accessibility stops reporting for as long as CoreGraphics still lists them.
>
> 2. A CGEventTap that macOS disables for being slow must not be re-armed
> blindly. Do that and the system hands the whole keystroke stream back to a tap
> that still cannot service it — the keyboard locks up with no way out. It now
> backs off and gives up rather than fighting.
>
> 3. SF Symbols default to a 15pt-tall image. The menu bar is 22pt and centres
> it, so the inset is 3.5pt — exactly one device pixel on Retina, and half a
> pixel on a 1080p display. That half pixel is why the icon looked blurry on one
> monitor and sharp on the other.
>
> QuickSwitch is free, Apple Silicon and Intel: quickswitchmac.com
>
> #macOS #Swift #SwiftUI #SoftwareEngineering #IndieDev

---

## Before posting

**Attach a screen recording.** A 10–15 second clip of ⌥Tab opening, typing two
letters to filter, and landing on the window will do more than any of this text.
Mac app posts live or die on showing the thing move. Record with ⇧⌘5, trim, and
export — LinkedIn plays video inline but makes people click through for links,
so put the link in the post body, not the first comment.

**Post Tuesday to Thursday morning.** Weekend engineering posts sink.

**Reply to every comment for the first two hours.** It is the single biggest
lever on how far LinkedIn carries a post.

**Say it is free early.** People stop reading at the point they suspect a
paywall.

---

## Music for the demo video

### First, the thing most people get wrong

**LinkedIn autoplays video muted.** The large majority of viewers will never
hear the track. So music is polish, not the message — the video has to work in
silence first. Before picking a track, make sure:

- there are **text overlays** at each beat ("6 Safari windows", "type to filter",
  "Enter"), and
- the cursor and keystrokes are visible enough to follow without audio.

If the video only makes sense with sound, the music is carrying weight it should
not have to.

### Where to get it (licence-safe)

| Source | Cost | Attribution |
| --- | --- | --- |
| **Pixabay Music** | Free | None required |
| **YouTube Audio Library** | Free | None for most tracks |
| **Uppbeat** | Free tier | Credit required on free tier |
| **Incompetech** (Kevin MacLeod) | Free | CC-BY, credit required |
| **Epidemic Sound** / **Artlist** | Paid subscription | None |

Do not lift a commercial track. LinkedIn's audio matching is inconsistent, so
you may get away with it — until the post is doing well and gets muted or pulled,
which is precisely when it costs you.

### What to search for

A dev tool demo wants something that stays out of the way:

- `minimal tech`, `clean corporate`, `light electronic`
- `lo-fi beat` — works well for a 60-second screen recording
- `ambient technology`, `subtle background`

Target roughly **100–120 BPM**, **no vocals** (words compete with your on-screen
text), and a track that opens gently rather than starting on a drop.

Avoid: anything described as `epic`, `inspiring corporate`, or `motivational` —
those build to a climax your 55-second UI clip does not have, and they read as
stock-footage advertising.

### Mixing

- Music only, no voiceover: **−16 to −12 dB**. Present, not competing.
- With voiceover: **−24 to −20 dB** under the voice.
- **Fade out over the last 2 seconds.** A hard cut at the end feels like a
  mistake.
- If the track has an obvious first downbeat, line it up with the moment the
  switcher panel appears. One synced beat makes a demo look deliberate.

### Worth considering instead

For a 55-second clip, a **quiet keyboard-and-click sound bed** — real key taps
as the shortcut fires — often sells a keyboard-driven tool better than music.
It is diegetic: it shows the app is fast because you hear how few keys it took.
