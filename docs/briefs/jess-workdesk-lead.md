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
- **Cut off:** grey core, "Waiting for Connection", sent again by itself; never applied twice.
- **No glow on the orb's thinking arc** (founder: the glow was removed from the orb, the circling
  arc still had it). App: `shell/Midas/JessOrb.swift:274`.
- Open: when a cut-off task gives up (after how many tries or hours) and shows Not Done.

## 3. Task: write the design doc (founder, 2026-10-22, "a bit later")

One doc every design agent reads first, with all items of the design language. Starting point:
`docs/DESIGN.md` (colour, type, mark, motion, orb). Not yet in it: components (cards, buttons, result
card, Workdesk card), spacing and sizes, screen layouts, animation timings. Add to the task list in
`docs/PRODUCT.md` section 6.
