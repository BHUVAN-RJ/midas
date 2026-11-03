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

## jess's camera (founder, 2026-11-02, build 23)

"There's no camera access for Jess ... we need to add a camera button to the right side." Mockup
`docs/mockups/jess-camera-2026-11-02.html`, approved ("Yes, this is the mockup. You can build
this."). Never planned before (PRODUCT.md only said "later ... camera").

- A quiet camera button right of the orb on the jess screen. Tap: listening stops, the words heard
  wait; iOS's camera opens (photo library on a simulator). Use Photo sends the photo with those
  words (words optional). Cancel sends the words alone, or listens again if there were none.
- The phone shrinks the photo to 1024 px on its longest side, JPEG 0.7, keeps it on disk with the
  request (so a cut-off request sends it again) and shows it on the Workdesk card ("Photo" when no
  words). Deleting the card deletes the photo.
- Server: `POST /voice/jess` takes `photo: { mediaType: "image/jpeg", data }` (base64, at most
  2,000,000 characters). A photo request goes to `deepseek/deepseek-v4.1-flash` (reads images, calls
  tools; text requests stay on `deepseek/deepseek-v4-flash`), 15 s per attempt. The photo is never
  stored or logged; the log's model column says it was a photo request.
- Camera permission text: "Midas uses the camera when you take a photo for jess, like a flyer to
  add as a reminder." Privacy page: new "Camera" section.
- Build number 23.

## Home title (founder, 2026-11-02, build 23)

"The Midas at the top ... use the font we usually use, like the Jess make ... the profile [initial]
is a bit out of place. Align it." Mockup `docs/mockups/home-title-2026-11-02.html`, pick H2 ("Let's
try H2"): "Midas" in Caveat Bold 40, ink, on the left with its left edge on the first tile's edge;
the initial's right edge on the last tile's edge (was 20 pt from the screen, about 12 pt outside
the tiles), its middle level with the middle of the capital M. The edges come from the grid's
numbers, so they hold on every iPhone width (`HomeTopBarSpec`, `SidekickHomeLayout.tileEdgeInset`).

Open for the founder: App Store Connect App Privacy answers (photos are sent for real-time
processing only and not kept); the model choice was made from OpenRouter's list on 2026-11-02 and
is untested on real photos until staging.
