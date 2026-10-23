# jess-workdesk: changes for the lead

Changes the jess-workdesk agent may not make itself (worktree rules: `CLAUDE.md`, `docs/PRODUCT.md`,
`backend/package*.json`, `backend/wrangler.jsonc` are the lead's).

## 1. Rule for every design or prototype (founder, 2026-10-22)

Add to midas `CLAUDE.md` (and midas-intel `CLAUDE.md`), near "Any text a person sees":

> **Designs and prototypes:** any agent making a design, mockup or prototype first reads the design
> doc (the design language: colours, type, the mark, motion, jess's orb, components). Designs are
> made as HTML files in the repo (`docs/mockups/`), not as Claude artifacts or Claude Design
> canvases. (Founder, 2026-10-22.)

Until the design doc below exists, "the design doc" is `docs/DESIGN.md` plus `docs/WRITING.md`.

How (founder, 2026-10-22: "plain HTML is the way to go"):

- One self-contained file per round: `docs/mockups/<topic>-<YYYY-MM-DD>.html` (inline CSS and JS,
  no CDN, no build step). Design tokens as CSS variables from `docs/DESIGN.md`; SF Pro via the
  system font stack.
- Phones at iPhone 16 Pro size, 402 x 874 pt. jess's orb drawn on a canvas with the app's own
  geometry (`shell/Midas/JessOrb.swift`), not a CSS look-alike.
- Variations side by side on one page; anything that moves gets controls: play, pause, scrub,
  frame step, speed, the timing values as sliders, and a frame strip.
- Before showing the founder: load it in a headless browser (Playwright, installed in the
  session scratchpad, never in the repo), screenshot the key moments, check there are no page
  errors, and look at the screenshots. Then open it for the founder (`open <file>`).
- Known limits to state when asked: HTML does not show iOS springs, haptics, safe areas, Reduce
  Motion or exact text wrapping; a Midas Test build checks the feel before a design is final.

## 2. Workdesk design, finalized by the founder (2026-10-22)

For `docs/PRODUCT.md` ("jess queue, instant acknowledgement and the Workdesk") and midas-intel's
design doc. Mockup: `docs/mockups/jess-workdesk-2026-10-22.html`.

- **Layout: W4 stack.** The jess screen shows the orb at the bottom centre and the tasks at the
  top: the newest as one big card, the next two as slim cards (all slim cards one size), two more
  tucked behind showing only their edges. Try Again always on the right of the card.
- **Card words:** the whole task on top ("Water the ferns every 3 weeks"), only the Sidekick's
  name under it. No status words: the orb core (green, red, grey) and its spinner say the status.
  Status words only where the Sidekick is not known yet: "On It" (working), "Waiting for
  Connection" (cut off).
- **Instant acknowledgement = the new card.** When listening ends, the new task comes out of the
  orb (fast, a slight overshoot to 105 %, then a slow settle; 820 ms) and the stack moves down one
  slot like a carousel (700 ms, starting 80 ms after the card). No separate notice, no pill.
- **Repair is a wait, not done:** the card stays with a grey core until the repair is live and
  the server has re-run the request once; then the same card turns green or red and moves to the
  top. (Today the phone shows a green "Sent to Repair" card and the result later as a second card.)
- **Scrolling (A, carousel; founder: "for now, we will decide later"):** the stack moves one slot
  per card under the finger: the big card leaves upwards behind the others, the next card grows
  into the big slot, tucked cards come forward; snaps to a card on release. No scroll bar, no dots.
- **Cut off:** grey core, "Waiting for Connection", sent again by itself; never applied twice.
- **No glow on the orb's thinking arc** (founder: the glow was removed from the orb, the circling
  arc still had it). App: `shell/Midas/JessOrb.swift:274`.
- **Give up after 1 hour** (founder, 2026-10-22): a cut-off task keeps retrying (app open, network
  back, jess screen open) for 1 hour from when it was said, then shows Not Done with Try Again.
- **The jess tile starts listening at once** (founder, 2026-10-22), the same as the Action button.
- Defaults stated to the founder, not objected to (2026-10-22): the home result card stays as
  today (dismissing it there does not remove the task from the Workdesk); a plain repair (not a
  grow) stays grey until its repair's done notice arrives (matched by reportId), then turns green,
  no re-run; the button reads Cancel while listening before any words, Done after; the Workdesk
  log keeps the last 200 tasks on the phone.

## 2a. Run once: migration 0009 (for the lead to apply to staging, then live)

`backend/migrations/0009_jess_requests.sql` adds `jess_requests` (one row per user and phone
request id, holding the answer given) and `voice_logs.request_id`. `POST /voice/jess` takes an
optional `requestId` (UUID): the same id sent again gets the kept answer without a second model
call, repair or grow; 409 `{ "error": "busy" }` while the first send still runs; a model that could
not be reached leaves the id open to run again. Apply before deploying the Worker from this branch:
`node scripts/migrate.mjs --env staging`.

## 2b. Handoff to the lead: staging and Midas Test TestFlight (founder, 2026-10-22)

The founder wants to try this on the Midas Test internal TestFlight and asked for the push to
staging; the founder said the lead takes it from here. Branch `agent/jess-workdesk`, built and
committed, main (jess-look: Volt, Jess tile) merged in. All suites green on a free simulator
(`scripts/test-all.sh` picks the simulator by the name "iPhone 17", which another session had
booted: run it with `MIDAS_SIMULATOR` set to a free one).

Order, and why it matters:

1. **Migrate staging first:** `cd backend && node scripts/migrate.mjs --env staging` (0009). If
   the Worker is deployed without it, every jess request from the new build gets a 500 (the
   `jess_requests` table is missing), the phone treats that as no answer, keeps the task "Waiting
   for Connection" and gives up as Not Done after 1 hour. (This session's attempt was blocked by
   the permission check, nothing was applied.)
2. **Deploy the staging Worker** from the merged branch (or from main after merging it).
   Phones on build 7 and older send no `requestId` and work as before.
3. **Midas Test build** (bump `CURRENT_PROJECT_VERSION`), TestFlight internal.

Checks on a simulator before TestFlight (not yet seen running; only the unit tests ran):

- Speak a reminder: the card comes out of the orb, the stack moves down, the card turns green.
- Airplane mode, speak: the card goes grey, "Waiting for Connection"; network back: it finishes.
  Nothing applied twice.
- "Make the reminders bigger" (repair): grey card that stays grey.
- Scroll the stack with several cards; Cancel before speaking, Done after; tap the orb to listen
  again.
- The thinking arc has no glow; the listening core is Volt.

Known: the arrival and carousel feel is unverified on a device (springs and timings are taken from
the HTML mockup). A plain repair whose repair fails stays grey (only "done" notices exist).

Status 2026-10-22: this handoff was sent to the lead session ("Testflight internal publishing",
on `main`), which took it. Nothing applied to staging by this agent. The jess-workdesk agent has
no open work; it answers only if the lead or the founder asks.

## 3. Task: write the design doc (founder, 2026-10-22, "a bit later")

One doc every design agent reads first, with all items of the design language. Starting point:
`docs/DESIGN.md` (colour, type, mark, motion, orb). Not yet in it: components (cards, buttons, result
card, Workdesk card), spacing and sizes, screen layouts, animation timings. Add to the task list in
`docs/PRODUCT.md` section 6.
