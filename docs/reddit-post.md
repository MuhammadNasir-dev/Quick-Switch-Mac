# Reddit launch post

Reddit is not LinkedIn. The same text will fail here. Three rules that decide
whether this works:

1. **No marketing voice.** "Excited to announce" gets downvoted on sight. Write
   like a person describing a thing they made because it annoyed them.
2. **Disclose that you made it, in the first line.** Reddit finds out anyway,
   and being caught concealing it is far worse than saying it.
3. **Lead with the limitation, not the pitch.** Not notarized is the single
   thing this audience will raise. Saying it yourself turns a "sketchy dev"
   thread into a "fair enough" thread.

---

## Titles

Pick one. Reddit titles are the whole game — most people never open the post.

**Recommended**

> I built a free macOS window switcher because ⌘Tab only shows apps, not windows

Why it works: states what it is, who it is for, that it is free, and the exact
frustration — all before anyone clicks.

**Alternatives**

> ⌘Tab shows you 2 icons when you have 10 windows open. I made one that shows all 10.

> QuickSwitch — free, keyboard-driven window switcher for macOS (no screen recording permission, nothing leaves your Mac)

Avoid: "Introducing…", "Check out my new app", anything with an emoji, anything
with "🚀".

---

## Body

> I made this, so — self-promo, flagged upfront.
>
> ⌘Tab switches between **applications**. If I have six Safari windows and four
> VS Code windows open, macOS shows me two icons. I pick one, land on the wrong
> window, and go hunting for the right one.
>
> QuickSwitch shows every window as its own row:
>
>     Safari      GitHub
>     Safari      ChatGPT
>     VS Code     AppDelegate.swift
>     Terminal    npm run dev
>
> Press ⌥Tab, type a couple of letters to filter, hit Enter. Minimised windows
> and windows on other Desktops are included.
>
> * Free, no account, no sign-in, no tracking
> * A few megabytes, lives in the menu bar, no Dock icon
> * **It never asks for Screen Recording permission** — window titles come from
>   the Accessibility API, so nothing about your windows ever leaves your Mac
> * Three layouts: dense list, grouped by app, or a grid of icons
> * Pin the apps you switch to most so they always come first
> * Apple Silicon and Intel builds, macOS 15.7+
>
> **The catch, up front:** it is not notarized. I do not have a paid Apple
> developer account yet, so macOS will block the first launch and you will need
> to go to System Settings → Privacy & Security → Open Anyway. If you are not
> comfortable with that, completely fair — wait until I get it notarized.
>
> [quickswitchmac.com](https://quickswitchmac.com/?utm_source=reddit&utm_medium=social&utm_campaign=quickswitch_launch&utm_content=r_macapps)
>
> Genuinely want to hear what breaks. Multi-monitor and Stage Manager setups
> especially — those are the hardest to test alone.

Note the indented block for the window list: four leading spaces makes a code
block on both old and new Reddit, and it is the only way to keep those columns
aligned. A markdown table will not render on old.reddit.

---

## Where to post

Check each subreddit's rules before posting — several require a specific flair,
and a few ban self-promotion outright regardless of quality. Space these out
over a week or two; posting to five subs in one hour is the pattern spam filters
and moderators look for.

| Subreddit | Fit | Notes |
| --- | --- | --- |
| **r/macapps** | Best | The single best fit. Indie Mac apps are the point of the sub. Expect questions about notarization and open source. |
| **r/MacOS** | Good | Larger, less tolerant of promotion. Read the rules carefully; some weeks self-promo is restricted to a thread. |
| **r/SideProject** | Good | Receptive, but lower-intent traffic — people there are builders, not necessarily Mac users. |
| **r/productivity** | Moderate | Only works if you lead with the workflow problem, not the app. |
| **r/apple** | Skip | Self-promotion is not welcome. Posting there costs you more than it gains. |

Start with **r/macapps**. If it does well there, the others are worth the
effort; if it does not, fix what the comments tell you before spending the other
posts.

---

## UTM links

Reddit's mobile apps and privacy settings frequently strip the referrer, so a
plain link shows up in GA4 as **Direct** and you learn nothing. UTM parameters
are carried in the URL itself, so they survive that.

**Use a markdown link.** If you type `quickswitchmac.com` as plain text, Reddit
auto-links the bare domain and you lose the parameters.

    [quickswitchmac.com](https://quickswitchmac.com/?utm_source=reddit&utm_medium=social&utm_campaign=quickswitch_launch&utm_content=r_macapps)

### Ready-made links

Only `utm_content` changes — that is what tells you which subreddit actually
sent people.

| Where | URL |
| --- | --- |
| r/macapps | `https://quickswitchmac.com/?utm_source=reddit&utm_medium=social&utm_campaign=quickswitch_launch&utm_content=r_macapps` |
| r/MacOS | `https://quickswitchmac.com/?utm_source=reddit&utm_medium=social&utm_campaign=quickswitch_launch&utm_content=r_macos` |
| r/SideProject | `https://quickswitchmac.com/?utm_source=reddit&utm_medium=social&utm_campaign=quickswitch_launch&utm_content=r_sideproject` |
| r/productivity | `https://quickswitchmac.com/?utm_source=reddit&utm_medium=social&utm_campaign=quickswitch_launch&utm_content=r_productivity` |
| Your comments in the thread | `https://quickswitchmac.com/?utm_source=reddit&utm_medium=social&utm_campaign=quickswitch_launch&utm_content=r_macapps_comment` |
| LinkedIn (for comparison) | `https://quickswitchmac.com/?utm_source=linkedin&utm_medium=social&utm_campaign=quickswitch_launch&utm_content=post` |
| Hacker News | `https://quickswitchmac.com/?utm_source=hn&utm_medium=social&utm_campaign=quickswitch_launch&utm_content=show_hn` |

### What each parameter means

| Parameter | Value | Why |
| --- | --- | --- |
| `utm_source` | `reddit` | The platform. Groups every subreddit together in one row. |
| `utm_medium` | `social` | The channel type. Keep it `social` everywhere so GA4's default channel grouping files it correctly. |
| `utm_campaign` | `quickswitch_launch` | The push. Reuse it across every launch link so one report covers the whole launch. |
| `utm_content` | `r_macapps` etc. | The specific placement. This is the one doing the real work. |

Keep them **lowercase**. GA4 treats `Reddit` and `reddit` as two different
sources and you will end up reading a split report.

### In GA4

Reports → Acquisition → **Traffic acquisition**, then change the dimension
dropdown to **Session manual source / medium**, and add **Session manual ad
content** as a secondary dimension. That last one is where `r_macapps` versus
`r_macos` shows up.

Data takes up to 24–48 hours to settle. Use **Realtime** on launch day instead —
it is the only view that will show anything in the first hours.

---

## The gap worth closing

UTMs tell you who arrived. They do **not** tell you who downloaded, because your
download button leaves for GitHub Releases and GA4 stops watching there.

GA4's Enhanced Measurement records outbound clicks automatically, but the event
does not distinguish a download link from any other external link. Tag the
download explicitly on your site:

```html
<a href="https://github.com/MuhammadNasir-dev/QuickSwitch-Mac/releases/latest"
   onclick="gtag('event', 'download_click', { arch: 'apple_silicon' });">
  Download for Apple Silicon
</a>
```

Then in GA4, mark `download_click` as a key event (Admin → Events). That gives
you the number that matters: not visits, but **downloads per subreddit**.

Cross-check it against the actual asset download counts from GitHub:

```bash
./scripts/download-counts.sh
```

If GA4 says 400 visits and GitHub says 12 downloads, the problem is your landing
page, not your Reddit post. That distinction is worth having before you spend
your remaining subreddits.

---

## Before you post

**Include a GIF or short video.** r/macapps posts with a demo clip do
substantially better than text-only ones. A 10–15 second silent GIF of ⌥Tab →
type → Enter is enough. Reddit hosts GIFs natively; an imgur link is a second
click and loses people.

**Post Tuesday to Thursday, early morning US Eastern.** That is when the US
wakes up and the sub is most active.

**Answer every comment for the first three hours.** Early engagement decides
whether Reddit's ranking carries the post. This matters more here than the text
itself.

**Have answers ready for the three questions you will definitely get:**

- *"Why not just use AltTab? It's free and open source."* — Be honest and
  specific. AltTab shows window previews and is highly configurable; QuickSwitch
  is a search-first list with no thumbnails, closer to Raycast than to ⌘Tab. If
  someone wants previews, AltTab is the better tool and saying so buys you more
  credibility than deflecting.
- *"Is it open source?"* — Answer plainly either way. "Not right now" is an
  acceptable answer; a vague non-answer is not.
- *"Not notarized = I'm not running it."* — Do not argue. Agree that it is a
  reasonable position, and say notarization is planned once you have the
  developer account.
