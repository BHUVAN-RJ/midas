# Hand-back: W3 ask-back cards on the phone (`agent/repair-askback`, 2026-11-13)

Brief: `docs/briefs/repair-lanes.md` W3. Decisions: `docs/PRODUCT.md` "Plan additions, 2026-11-13:
repair lanes" (D4 = A). Mockup: `docs/mockups/repair-ask-back-2026-11-08.html`.

## What was built

Send now waits for the sort's lane when the Worker sorts (W2 contract in the brief), then:

| Lane | Phone |
|---|---|
| `ask_back` | Tag "One question". Card "What should it be?" with 2–3 picture guesses, 14 pt above the B3 pill. Pill placeholder "Or say it…". Rim, drawing, pill stay. A tap picks a guess and fills the pill with its label; Send posts `POST /repairs/:id/answer` (`{ optionId }` if the pill still says the label, else `{ text }`), then the reply is sorted again. |
| `not_a_request` | Pill says the message in bold ("Say or draw what to change."), jess listens again, no tag change, no job. Next Send is a new report (new phone id); the drawing stays. |
| `shell_cant` | Dark sheet: bold message, "Sent to Midas." in grey under it. After 4 s repair mode closes (rim fades, tag back into the island). Nothing for the tag. |
| `jess_command`, `setting`, `look`, `code` | Closes as Send always did: Send animation into the tag, "On it" / "Editing". |

While the lane is on its way the tag says "Editing" with the spinning orb and Send is off.
Up a lane, never down: no reply, an error, an unknown lane, an `ask_back` with no guesses or no
id, or no reply within 10 s → closes as an edit (the upload carries on as today, queued if offline).

Today's Worker replies `{ id, status }` with no lane: reads as `code`, so the phone behaves as
before (one extra wait for the upload round trip before the layer closes).

An upload API that does not sort (`sortsReports == false`, every existing test fake) still closes
at once, so no existing test changed.

## Files

- `shell/Midas/RepairSort.swift` (new): lanes, contract types (lenient decode), rules, words, tag
  rule, and a Debug-only local stub of the W2 sort.
- `shell/Midas/RepairQuestionCard.swift` (new): the card, the dark sheet, the guess picture rule.
- `shell/Midas/RepairSession.swift`: lane state machine (`askStage`), `pick`, answer, time-out,
  `RepairFinish.answered`, `reportId` renewed after not a request.
- `shell/Midas/RepairUploader.swift`: `RepairUploadAPI.sortsReports / uploadSorted / answer`
  (defaults for old fakes); live API reads the lane from the POST /repairs body and posts answers.
- `shell/Midas/RepairCanvasView.swift`: card or sheet above the pill; placeholder; bold message.
- `shell/Midas/RepairChromeView.swift`: tag "Editing" while sorting, "One question" while asking.
- `shell/MidasTests/RepairAskBackTests.swift` (new, 28 checks): contract decode, rules, words,
  session against a W2 stub (card, tap, answer joins same report, not a request → new report,
  shell can't → `.answered` with nothing sent, edit lane closes, time-out closes, cancel sends no
  answer, old API closes at once), card/sheet layout.

Not touched: `MidasApp.swift` (`SidekickScreen` already treats any non-`.sent` finish like Cancel).

## How to try it

1. Tests: `cd ~/Desktop/Midas/midas-worktrees/repair-askback && scripts/test-all.sh`.
2. Simulator without W2 (Debug "Midas Test" build only): launch with
   `MIDAS_REPAIR_SORT_STUB=1` in the app's environment (Xcode: Midas Test scheme → Run →
   Arguments → Environment Variables; or `SIMCTL_CHILD_MIDAS_REPAIR_SORT_STUB=1 xcrun simctl
   launch ...` through `scripts/sim.sh`). Nothing is uploaded while it is on. Words pick the lane:
   "change this" → card; "how are you" → not a request; "every hour" → shell can't; anything
   else → code. Note: in stub mode a code-lane close leaves an "Editing" tag that never resolves
   (no real job); erase the sim (`scripts/sim.sh reset`) after.
3. Against W2 on staging: no flag; Midas Test build points at staging.

Renders of the card and sheet (light, dark) were checked against the mockup; options carry no
shadow, picked guess has a 2 pt ink edge.

## Open questions (W2 / lead, not founder)

- `icon` format in the contract: the phone reads an SF Symbol name; a 1–2 character text
  (emoji, "∅") is drawn as text; anything else draws a plain circle. W2 should send SF Symbol names.
- `shell_cant` `message`: the phone shows it bold and adds "Sent to Midas." under it once, whether
  or not the server's line ends with it.
- An answer after the 2-minute drop: if `POST /repairs/:id/answer` fails, the layer closes as an
  edit and the tag waits on a report the server dropped. W2 could answer a late answer with a lane
  instead of an error.
- Phone wait cap 10 s (`RepairAskBackSpec.sortWaitSeconds`) on top of W2's 6 s model time-out.

## Lead to add

No dependency, config or guard-path changes needed.
