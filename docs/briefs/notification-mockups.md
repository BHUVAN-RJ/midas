# Brief: what an iPhone notification can be and do, with mockups, 2026-10-09

You are the notification-mockups agent. You run in your own Herdr tab in `~/code/midas-intel`.
The founder talks to you directly there. Job: map everything Apple lets a notification be and do
on iPhone (current iOS; today is 2026-10-09, so iOS 26 and anything newer that has shipped), and
draw visual mockups of each kind. Research and design exploration only: no product code.

## Context

Midas (`~/Desktop/Midas/midas`, read only for you) is an iPhone shell (SwiftUI + one WKWebView per
mini app) where users get small personal apps called Sidekicks. The first is Reminders. Hard
constraint: Sidekicks are plain HTML/JS with no JS bridge (App Store guideline 4.7.2) and never call
native APIs. A Sidekick writes records like `reminder:<id>` `{ at, title, notes, repeat, timeZone }`
to a local store; the native shell's notification engine books iOS local notifications from them.

Already in the engine (detail: `~/Desktop/Midas/midas/docs/NOTIFICATIONS.md`):
- Local notifications via UNUserNotificationCenter. Unlimited queue inside Midas; iOS allows 64
  pending local requests, so the shell books 48 and keeps 16 reserved.
- Done, Snooze 10 min, Snooze 1 hour, Snooze until tomorrow on every notification; taps written
  back into the record.
- Repeats, time zones, a missed-reminder ledger, background refresh.
- Not built: nag until done, alarm levels, repeat after completion, custom snooze lengths. No
  server push (APNs) yet. Backend is Cloudflare Workers.

Sidekicks coming next: calendar, birthdays, split (bill splitting), notes, a lecture recorder
(continuous background recording, on-device transcription). Sharing between users is a planned
flagship. Use these as mockup examples.

Also read: `~/Desktop/Midas/midas/docs/PRODUCT.md` (build 1, D6, D8) and
`docs/research/reminders/ANALYSIS.md` (what reminder-app users love, why they leave).

## How you work

1. Tell the founder in a few lines what you understood, then ask if anything is missing.
2. Research (below), then draw the mockups (below). Show progress in your tab.
3. Report back (below). The founder may ask for more mockups or changes; do them.

## Research

Apple's own docs first (developer.apple.com, HIG "Notifications", WWDC sessions), then reputable
secondary sources. Cover at least:
- Surfaces: lock screen, banner, Notification Center, scheduled summary, StandBy, Apple Watch,
  CarPlay, Focus.
- Interruption levels: passive, active, time-sensitive, critical; relevance score.
- Authorization: standard, provisional, critical alerts, time-sensitive.
- Content: title, subtitle, body, badge, custom sounds (limits), attachments (image, GIF, audio,
  video; size limits), thread grouping, summary text.
- Actions: buttons (max count, destructive, auth-required, foreground), text input, action icons,
  categories.
- Notification Content Extension (custom interactive UI on long-press) and Service Extension.
- Communication notifications (sender avatar).
- Live Activities and Dynamic Island (local vs push updates, duration limits); widgets.
- AlarmKit (iOS 26): alarms/countdowns through silent mode and Focus; permission rules.
- Triggers: time interval, calendar, location, push.
- Limits: 64 pending, rate limits, app killed, what needs APNs.

For each: what it is, iOS version, what it needs (entitlement, permission prompt, extension target,
APNs, App Review risk), and its status for Midas: (a) already in the engine, (b) possible in the
shell with native work, the Sidekick only writes a record field, (c) needs entitlement or Apple
approval, (d) needs server push, (e) not possible. Facts with sources only; no recommendations.

## Mockups

One mockup per distinct kind of notification or interaction, using reminders, calendar, birthdays,
split, notes and lecture-recorder examples (e.g. split "Alex owes you $12" with a Paid action, a
birthday with a photo, a lecture recorder Live Activity). Label each with capability name and its
(a)-(e) status.

One self-contained HTML file, inline CSS and JS only (Google Fonts allowed). iPhone-style frames
(lock screen, banner, expanded view, Dynamic Island, StandBy, Watch) close to real iOS look.
Sections with an index at top. Works at phone width, no horizontal scroll. Light and dark mode via
CSS variables on `:root` and `@media (prefers-color-scheme: dark)`. JS: no chained one-liners,
descriptive function names, comments above non-obvious logic, no inline anonymous functions in
method chains.

## Output (create these only; do not commit; do not edit anything under ~/Desktop/Midas)

- `docs/prototypes/notifications/index.html`: the mockups.
- `docs/research/2026-10-09-ios-notification-capabilities.md`: capability table, sources (URLs),
  limits, (a)-(e) status.

## Report to the founder, in your tab

Paths written; number of capabilities and mockups; one line per capability with its status; what
you could not verify; anything that contradicts NOTIFICATIONS.md.
