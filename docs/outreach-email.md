# Outreach email — Mac app YouTubers

The hard truth first: creators who cover Mac apps get pitched constantly, and
most pitches are deleted in the two seconds it takes to see they are a template.
What gets a reply is being **short**, **specific to that creator**, and
**honest about the catch**.

Three rules:

1. **Under 150 words.** If it needs scrolling on a phone, it does not get read.
2. **One real sentence about their channel** — a specific video, not "I love
   your content". This is the only line that proves you are not mass-mailing.
3. **Say what is wrong with it yourself.** Not notarized, no developer account.
   A creator who finds that out mid-recording will not finish the video.

Never ask for a review. Ask them to try it. The video is their decision, and
pretending otherwise reads as entitled.

---

## Subject lines

Pick one. Short, lowercase-ish, no marketing punctuation.

**Recommended**

> Free window switcher for macOS — built it, thought of your channel

**Alternatives**

> ⌘Tab only shows apps. I built one that shows every window.

> Made a free Mac app — no account, no tracking, no screen recording permission

Avoid: "Collaboration opportunity", "Partnership", "Sponsored", anything with
"🚀", and anything in ALL CAPS. Those go to Promotions.

---

## The email

> Subject: Free window switcher for macOS — built it, thought of your channel
>
> Hi [Name],
>
> [ONE SPECIFIC LINE — see below.]
>
> I built a small free Mac app called QuickSwitch. ⌘Tab switches between
> applications — if you have six Safari windows open, macOS shows you one icon.
> QuickSwitch shows every window as its own row with its title, so ⌥Tab → type
> two letters → Enter takes you straight to the right one.
>
> A few things that might make it interesting for a video:
>
> - It never asks for Screen Recording permission — window titles come from the
>   Accessibility API, so nothing about your windows leaves your Mac
> - No account, no sign-in, no tracking. A few megabytes, menu bar only
> - Free, Apple Silicon and Intel
>
> Being upfront: it is not notarized yet — no paid Apple developer account — so
> macOS blocks the first launch and you have to click through Privacy &
> Security. If that is a dealbreaker for your audience I completely understand.
>
> Download and a 20-second demo: [quickswitchmac.com](https://quickswitchmac.com/?utm_source=youtube&utm_medium=referral&utm_campaign=creator_outreach&utm_content=CREATORNAME)
>
> No expectation of coverage — I would just genuinely like to know if it is
> useful to you. Happy to answer anything or add a feature you think is missing.
>
> Thanks,
> Muhammad
> quickswitchmac.com

---

## The one line that does the work

Replace `[ONE SPECIFIC LINE]` per creator. It has to prove you actually watched
something. Examples of the shape:

> Your video on menu bar apps is how I found Ice — still using it.

> I watched your Raycast walkthrough last month and ended up rebuilding half my
> workflow around it.

> You mentioned in your macOS 26 video that window management is still the
> weakest part of the OS. That is the itch I tried to scratch.

Rules for this line:
- Name an **actual video or app you took from them**. Vague praise is worse than
  no praise — it signals a template.
- One sentence. Two makes it read as flattery.
- Never say "I'm a big fan of your content."

If you cannot write this line honestly for a given creator, do not email them.
That is the filter — it also keeps your list to a size you can actually
personalise.

---

## Follow-up

**Once.** After 7–10 days. Then stop, permanently.

> Subject: Re: Free window switcher for macOS — built it, thought of your channel
>
> Hi [Name] — just floating this back to the top of your inbox in case it got
> buried. No worries at all if it is not a fit.
>
> Since I wrote, [ONE CONCRETE THING — e.g. "I added a grid layout and fixed a
> multi-monitor bug a few people hit."]
>
> [quickswitchmac.com](https://quickswitchmac.com/?utm_source=youtube&utm_medium=referral&utm_campaign=creator_outreach&utm_content=CREATORNAME_f2)
>
> Thanks either way,
> Muhammad

Reply to your original email so it threads. A second follow-up gets you marked
as spam, and Mac creators talk to each other.

---

## Tracking who actually posts

Give **every creator their own `utm_content`**. That is how you find out which
video sent people, without having to ask.

    https://quickswitchmac.com/?utm_source=youtube&utm_medium=referral&utm_campaign=creator_outreach&utm_content=CREATORNAME

| Parameter | Value | Why |
| --- | --- | --- |
| `utm_source` | `youtube` | Groups all creator traffic together. |
| `utm_medium` | `referral` | Not `social` — this is a third party sending traffic, and keeping it distinct stops it merging with your own Reddit/LinkedIn posts. |
| `utm_campaign` | `creator_outreach` | One report covering the whole outreach push. |
| `utm_content` | creator's handle, lowercase | The one doing the work. Use their channel handle so the GA4 report is readable months later. |

Lowercase everything — GA4 treats `YouTube` and `youtube` as different sources.

Read it in GA4: **Acquisition → Traffic acquisition**, dimension **Session
manual source / medium**, secondary dimension **Session manual ad content**.

One caveat worth knowing: a creator who covers you will usually put the plain
`quickswitchmac.com` in their description, not your tagged link. When that
happens the traffic arrives as `youtube.com` referral with no `utm_content`, so
you will see the spike but not the source. Check YouTube itself when a spike
appears — searching `QuickSwitch mac` sorted by upload date usually finds it in
under a minute.

---

## Building the list

Aim for **15–25 creators**, not 200. A personalised email to 20 beats a template
to 500, and the template will burn the addresses permanently.

Where to find them:

- YouTube search: `best mac apps 2026`, `menu bar apps mac`, `mac productivity
  apps`, `raycast alternatives`, sorted by upload date so you get people still
  active
- The creators who covered **AltTab**, **Rectangle**, **Ice**, **Raycast**, or
  **Shottr** — they cover exactly this category and have a proven appetite for
  free indie Mac tools
- Channels in the **50k–500k** range. Below that the traffic is negligible;
  above it your email will not be read at all

Get the address from the channel's **About → View email address** (needs a
CAPTCHA — you have to do that part yourself). If a channel lists no email, use
the business inquiry form or skip it. Do not DM them on three platforms at once.

---

## Before you send

**Have the demo ready first.** The single biggest reason these emails fail is
that the creator has to download and install an unnotarized app just to find out
what it does. A 20-second silent clip on your landing page removes that barrier
entirely — put it above the fold.

**Send Tuesday to Thursday morning, in their timezone.** Most Mac channels are
US or Europe based.

**Send from a real address.** `muhammadnasir.dev@gmail.com` is fine and honest;
a `noreply@` or a bulk sender is not. Do not use a mail-merge tool — the
tracking pixels get you filtered.

**One email at a time, sent manually.** BCC'ing twenty creators is visible in
the headers of some clients, and it ends the conversation before it starts.

**Expect a low reply rate.** Two or three replies from twenty is a good outcome.
One video from a mid-size channel will outperform every other thing in this
launch, which is why the personalisation is worth the hours.
