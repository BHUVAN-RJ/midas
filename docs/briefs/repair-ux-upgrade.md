# Repair UX upgrade (founder, 2026-10-23)

Founder, 2026-10-23: the repair "is not part of our actual Midas workflow, and that is not
acceptable"; upgrade the repair feature and its UI. Design first: nothing is approved to build
until the founder says go.

Mockup (all rounds, picks as clickable rows): `docs/mockups/repair-feedback-2026-10-23.html`.

## Decided

- **O4, orb into the bar:** after the 3-finger swipe, jess's orb pops out and drops into the left
  slot of the bottom bar. One orb on screen.
- **B3, floating pill:** the bottom bar is a floating pill (orb, words, round send arrow; small Undo
  and Clear pills above). Voice starts on its own; the user can still type.
- **Tomato leaves Midas's colours.** Volt is the third colour, with black and white. Light mode:
  circle strokes, pen and the repair glow are black; dark mode: white (founder's mono idea). A bold
  Volt version is also being tried.
- **The glow stays on for the whole repair** (from the swipe until Send or Cancel), so it is clear
  that repair mode is on.

- **Glow V1, Volt rim on an ink line** (founder, 2026-10-23), plus the **"Repair" tag** that drops
  out of the island while repair mode is on.

- **On Send, the screenshot goes into the Repair tag** (not the island), which becomes
  "Repairing" (founder, 2026-10-23).
- **S2, the tag stays, only on that Sidekick:** it shows only while the user is on the Sidekick
  being repaired, hides elsewhere, never goes into the island, and shows the result there.

- **Build now, before the public TestFlight** (founder, 2026-10-23: "I need this done right now").
- **Two cases when a fix is live** (founder, 2026-10-23):
  1. The user is on that Sidekick (pill says "Repairing"): the pill changes to "Repair done. Click
     to update". Tapping it updates the page (animation: the new page expands out of the pill and
     takes over the screen; the pill goes away; variations U1-U4, mockup round 6).
  2. The user is not on that Sidekick: the copy updates in the background; next open shows the fix.
     A notification "Your app has been repaired." when the app is closed is deferred: it needs push,
     which Midas does not have yet. **Push is the next item after this** (founder, 2026-10-23).
- Defaults the founder did not change (2026-10-23): Couldn't Fix stays until Try Again or closed;
  Try Again resends the same report; tap on "Repairing" shows what was sent; tap on a result shows
  the one-line summary; after 10 min "Taking longer"; a second repair on the same Sidekick waits;
  haptics on swipe lock and Send; Reduce Motion fades instead of moving; built in a worktree,
  tried in Midas Test on staging first. "Already there" result keeps its own words, never "failed".

## Open (founder picks)

- Update animation U1-U4 (mockup round 6).
- Tomato in the tile palette (`docs/DESIGN.md` §2.3, line 57): stays as a tile colour or is replaced
  (keeping eight).
- The "chess" line in the founder's dictation was read as "jess" (orb stays off the content being
  circled; the screenshot is the Sidekick page only, so the orb and the glow are never in it).

## Found, to fix when building

- **Red in the Send button:** a recording dot, `Circle().fill(Color.red)`,
  `shell/Midas/RepairCanvasView.swift:133-135`, on the whole time jess listens (listening starts on
  open, `:74-75`).
- **"What to fix" off-centre:** `shell/Midas/RepairCanvasView.swift:106-108`, `TextField(...,
  axis: .vertical)` with `.lineLimit(1...3)` puts the text top-left; the field is on its own row.
- **Glow that follows the fingers** needs `ThreeFingerSwipeRecognizer` to report progress (it only
  reports recognised or failed).
- **"Nothing to change" shows as failed:** the runner's `no_change` result is stored as status
  `failed` (`fail_reason` "no change"), so the notification says "failed" (staging report
  `9d619921`, "every 2 hrs": the option already existed).
- **A live fix needs an app restart:** after report `fdd6509a` went live (16:56Z), the open page kept
  the old version until the founder closed and reopened the app.
- **Tomato elsewhere** (pen `RepairPen` `#FF6347`): `shell/Midas/RepairSession.swift:15-19,177`,
  `RepairCanvasView.swift:7,193,195`; tests `RepairDrawingRendererTests.swift:31-60` (assert
  `#FF6347`; change via test-guardian), `FolderWidgetLayoutTests.swift:160`; docs
  `docs/DESIGN.md:33,39-43,57,82,200-211`, `docs/PRODUCT.md:1070,1075`,
  `docs/briefs/repair-shell-wiring.md:89-90`; older dated mockups (history, left as is).
