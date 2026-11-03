# Build 22 feedback (founder, 2026-11-02)

The founder tried build 22 on Midas Test (staging) and sent TestFlight feedback. Branch
`agent/build22-feedback`. Mockup: `docs/mockups/build22-feedback-2026-11-02.html`.

## Decisions (founder, in chat, 2026-11-02)

1. **Consent screen** (Apple 5.1.2(i)): "Nobody mentions that. If they want to use it, they're going
   to look at the privacy policy page." No feature names (jess, Edit), no provider names
   (OpenRouter, Anthropic), no list of what is sent. Then: "I like the third-party services thing.
   We will use that." Words: title **"Third-Party Services"**, line **"Midas uses third-party
   services."**, Privacy Policy link, **Allow**, **Not Now** (S1). The Settings switch says
   "Third-Party Services" too (same word for the same thing, docs/WRITING.md rule 13).
2. **The Settings switch in dark mode** was white on white (the founder's screenshot: `ink` is
   `#FFFFFF` in dark mode, the same as iOS's knob). Light stays `ink`; dark "on" is `#6B6B6B`
   (pick T2; Volt T3 not chosen). Code: `ShellSwitchTint` in `shell/Midas/SettingsView.swift`.
3. **jess: tap to toggle.** Tapping the orb while listening stops listening and sends what was
   heard (nothing heard: nothing sent, the orb waits); tapping again listens.
4. **Workdesk: swipe shows Delete**, as the Reminders Sidekick's rows do (either direction; tap
   Delete, or swipe most of the way across). Replaces the 2026-10-31 fling-away on the Workdesk
   (home cards still swipe away).
5. **Deleting a task that has not finished stops it** ("Deleting a request that is still
   processing also cancels/deletes that request on the server so it does not finish later"). This
   replaces the 2026-11-02 small-fixes rule "a request still on its way finishes, but shows no
   card": a deleted request leaves the phone's queue (never sent again), its ops are never
   written, and `POST /voice/jess/cancel` marks its request id, its grow request and the Edit it
   filed so none of them runs (`backend/src/jess-cancel.ts`). A cancel that does not reach the
   server is kept on the phone and sent on the next open.

## Limits

- An Edit the runner has already started (status `running` or later) is not stopped; the runner
  publishes outside the Worker. A grow request's re-run is still stopped.
- No migration: cancels reuse existing states (`answered` with a "deleted" reply, `failed` with
  reason "deleted" / "deleted by the person").
