# Brief: dictation cleanup gate + trigger words (TEST BUILD ONLY)

> **TEST BUILD. Branch `agent/dictation-test` is NEVER merged into `main` and NEVER shipped to
> live.** Midas Test configuration only; the Dictation Sidekick is staging only, R J only. Never run
> anything with `--env live`. Founder approved this build 2026-11-13.

Read first: `docs/briefs/dictation-cleanup-test.md`, `docs/briefs/dictation-sidekick-test.md`, and the
code they produced (`shell/Midas/DictationTest*.swift`, `shell/Midas/DictationSidekick.swift`,
`sidekicks/dictation/`).

## Results so far (founder's iPhone 16 Pro, iOS 27, staging records)

Speech to raw text 0.17–0.33 s. On-device cleanup 1.2–1.5 s for short phrases, ~2.0 s for 60 words
(avg 1.47 s, worst 2.02 s). Wispr Flow's target is under 0.7 s end to end. Quality: one run changed
"I just referred you" to "He just referred you" (meaning changed); "oh, and coffee" kept a filler.
"send the deck to Priya and Tomasz by friday" needed no cleanup but still waited 1.3 s.

## What to build

1. **Deterministic gate (rules only, no model; Laya/Jev are out, founder 2026-11-13).** After the raw
   text is final, decide one path:
   - **skip**: no filler words and no correction cues → insert the raw text (Apple's punctuation;
     add a capital first letter and end punctuation by rule if missing). No model call.
   - **light**: fillers and/or correction cues present → the light cleanup instruction (fillers,
     backtrack/self-corrections, punctuation, numbered lists when the speaker enumerates). Tighten the
     instruction: never change pronouns, names, numbers or meaning except what a correction cue
     explicitly replaces; never add words.
   - **rewrite**: the text starts with a trigger word → strip the trigger and use that trigger's
     rewrite instruction. Start set: `email` (turn into an email), `formal`, `casual`, `list`
     (bulleted list), `bullets`. Match case-insensitively, with or without a following colon/comma.
   Word matching is whole-word and case-insensitive. Start lists: fillers `um, uh, erm, hmm, like,
   you know, I mean, sort of, kind of, basically, so` (careful: "like"/"so" only as fillers by simple
   position rules, e.g. sentence start or between commas/pauses; document the rule); correction cues
   `no wait, wait no, scratch that, I mean, actually, sorry, no no, make that, I meant`.
2. **Settings from the Sidekick (no rebuild for tuning):** a `settings:main` record in the Dictation
   Sidekick holds the filler list, correction cues, trigger words with their instructions, and the
   light instruction. The shell reads it before each run (falls back to built-in defaults if missing
   or invalid; schema-checked like other records). The Dictation page shows these as editable fields
   (WRITING.md: few words) and saves the record. Add a jess tool to read settings
   (and to update them, if it fits the agent-connected rule).
3. **Logging:** every run record gains `path` (skip | light | rewrite), `trigger` (if any),
   `matched` (which filler/cue words triggered), `gateMs`, plus the existing timings; the summary
   gains average total time per path and the share of runs per path. The page shows the per-path
   numbers.
4. **Phrases:** keep the five, add: "send the deck to Priya by friday" (expect skip), "email tell sam
   the launch moved to monday and thank him for the help" (expect rewrite email), "the browser is
   firefox scratch that chrome" (expect light), "list eggs milk bread coffee" (expect rewrite list).
5. Build number: set `CURRENT_PROJECT_VERSION` to **29** (the founder's last install reported 28).

Everything new in the shell stays inside `#if MIDAS_TEST_BUILD` and `@available(iOS 26, *)`.
Extend existing code; do not fork.

## Tests

New tests (new files) for: the gate (each path, whole-word matching, filler-position rule, trigger
stripping), settings record parsing and fallback, the summary math per path, the page settings
editor, the tools. Existing tests are guarded (test-guardian only). Run backend and the shell suite
on both schemes via `scripts/sim.sh` (`scripts/test-all.sh` cannot run the shell part: missing
"iPhone 17" simulator). Known Midas Test-scheme failures from before: the sheet-kinds check, the
App Group check, possibly the flaky JessWorklogLinkTests. Report honestly.

## Done

Committed on `agent/dictation-test` (`TEST BUILD (do not merge):` prefix). Redeploy the Dictation
Sidekick to staging (`cd ~/Desktop/Midas/midas-worktrees/dictation-test/backend && node scripts/deploy-sidekick.mjs dictation --env staging`;
it is already assigned to R J; D1/R2 commands need the sandbox off). Check the page loads the new
settings on staging. Report: what changed, test results, and the founder's install steps for build 29
(commands start with `cd`). No TestFlight upload unless asked.

## Next round (founder, 2026-11-13)

- Add about **20 more test phrases** (29 total or more) so results are less noisy: more skip cases
  (clean sentences with names, days, numbers), more backtracks ("scratch that", "I mean", "make that"),
  casual chat with "like"/"so" used as real words, lists spoken in a sentence, each trigger word twice.
- Round 1 results on build 29 (45 runs, staging): skip 0 ms; light avg 1.38 s (short 1.13–1.32 s,
  60 words 1.97 s); rewrite avg 1.26 s. Wrong outputs to fix:
  - "the browser is firefox scratch that chrome" → "The browser is Firefox. 1. Chrome" (backtrack
    failed; the list rule fired on one item).
  - "list eggs milk bread coffee" → items in ALL CAPS.
  - light turned "buy eggs milk and uh bread oh and coffee" into a numbered list (maybe fine for
    notes, odd in a chat message).
  - skip leaves "friday" lowercase (no model on that path).

## Round 2 build (founder approved 2026-11-13): last rebuild, then Sidekick-only

Goal: after this build, every later round (phrases, instructions, word lists) changes only the
Dictation Sidekick's `settings:main` on staging; no app rebuild.

1. **Phrases move into `settings:main`** (list of `{ text, expect: skip|light|rewrite, note? }`).
   The test screen reads them before each Run All; built-in list as fallback. The page shows and
   edits them ("?" → Settings). Run All runs every phrase ×5 and logs `expect` vs actual `path`
   (a mismatch count on the page).
2. **Capitalise list in `settings:main`** (days, months by default; editable) applied on the skip path.
3. **About 20 new phrases** added to the built-in defaults and to staging's `settings:main` (29+ total):
   more skip cases (clean sentences with names, days, numbers), more backtracks ("scratch that",
   "I mean", "make that", "no wait"), casual chat where "like"/"so" are real words, lists spoken in a
   sentence, each trigger word at least twice.
4. **Instruction fixes**, in the defaults and in staging's `settings:main`:
   - Backtrack: the words before a correction cue are replaced by the words after it ("firefox
     scratch that chrome" → "Chrome"); never keep both.
   - Numbered lists only for three or more items, and only when the text is clearly a list; never
     for a single item; a chat sentence stays a sentence.
   - `list`/`bullets`: keep the speaker's casing (sentence case items), never ALL CAPS.
5. Build number **30**.
6. Write staging's `settings:main` for R J the same way the page's Save does (through the store /
   sync path, not raw SQL); check it reads back.

Tests, Done and limits as above (new tests only; full suite; commit with the TEST BUILD prefix;
redeploy the Sidekick to staging; founder install steps for build 30).

## Round 3 build (founder approved 2026-11-14): do less, rules first

Results after build 30 (staging): every path matched (165/165 and 495/495). Light ≈ 2.0 s median,
rewrite ≈ 1.9 s; halving the light instruction (1,169 → 522 chars, with examples) did not make it
faster and made output worse: the 3B model copied the examples into its answers (the 60-word ramble
came back as "Send it to Tim. Book it for Saturday. Meet at the library."). **Never put examples in
an instruction.** Timings rose batch to batch across three Run All ×5 (rewrite median 1.67 → 2.46 →
2.16 s, its instruction unchanged), probably the phone heating. Founder: "we are trying to do way too
much; cut it short and only tackle the most frequent stuff."

Strategy: the model does at most one small job; everything else is rules.

1. **Paths:** `skip` (nothing to change but casing/punctuation), `rule` (new: fillers stripped
   and/or a simple correction applied by rule, no model), `light` (model). `rewrite` stays in the
   code but the default trigger list is **empty** (email/formal/casual/list/bullets parked).
2. **Filler rule:** remove `fillers` as whole words, case-insensitive, with any comma next to them.
   Default `fillers`: `um, uh, erm, hmm`. Default `positionFillers` (like/so): **empty**.
3. **Simple correction rule:** a correction cue followed by exactly one token of kind number
   (digits or one–twelve), time (`5:30`, `5pm`, `5 pm`), weekday or month, and nothing after it:
   find the last token of the same kind before the cue, replace it with the new one, drop the cue
   and the old token. "the call is at 2 no wait 3" → "The call is at 3."; "order 3 pizzas make that
   4" → "Order 4 pizzas."; "book the table for friday no wait saturday" → "Book the table for
   Saturday." No same-kind token before the cue, or anything else after the cue → `light`.
4. **Model (`light`) only for the remaining corrections.** It gets the text after the filler rule.
   Default instruction, one line, no examples: "Remove the correction and the words it replaces.
   Change nothing else. Reply with the text only." Then the skip finishing (capitalise list, first
   letter, `I`, end punctuation) runs on every path's output.
5. **Default `corrections`:** `no wait, wait no, scratch that, make that, I mean, I meant, actually,
   sorry`.
6. **Warm-up:** after every model call (and when the screen opens), prewarm a fresh session with the
   current instruction, so the next timed call does not include reading the instruction. Log whether
   the call used a prewarmed session (`prewarmed: true|false`).
7. **Heat:** every run record logs `thermal` (`ProcessInfo.thermalState`: nominal|fair|serious|
   critical); the page and summary show the share of runs per heat state.
8. **Run All repeats:** `repeat` in `settings:main`, default **3** (was a fixed 5); editable on the page.
9. **Phrases (15, replace the 33 as defaults):**
   - skip: "send the deck to Priya by friday", "lunch with Maya on tuesday at 12:30", "I like the
     new logo a lot", "it was so good to see you yesterday", "call David back before 5 tomorrow"
   - rule (fillers): "uh tell mom im on my way", "um pack the charger the passport and the tickets",
     "for the party we need uh cups plates napkins and ice"
   - rule (correction): "the call is at 2 no wait 3", "order 3 pizzas make that 4", "book the table
     for friday no wait saturday", "um be there at 5 no wait 6"
   - light: "the browser is firefox scratch that chrome", "send it to Tom I mean Tim", "meet at the
     cafe on 5th street scratch that the library"
10. **Staging `settings:main`:** R J already has one (round 2 values, seq 1179), and it overrides the
    built-in defaults, so write a new version with the round 3 defaults: one row in `ops` with the
    exact shape the sync push writes (`insertOpsStatement` in `backend/src/sync.ts`: new upper-case
    UUID `op_id`, `user_id` `9-GAkqjLqjvn6Hyr9-AbTg`, `sidekick_id` `dictation`, key `settings:main`,
    `deleted` 0, ISO `client_time`/`received_at`), on **staging only** (`--env staging --remote`,
    sandbox off). Read it back.
11. Page: shows the `rule` path with the others, `repeat`, heat share; Settings edits the new fields.
    Agent block + `tools.js` updated for the new fields (same change, with tests).
12. Build number **31**.

Tests, Done and limits as above (new tests only; full backend suite and the shell suite on both
schemes through `scripts/sim.sh`; commit with the TEST BUILD prefix; redeploy the Sidekick to
staging; never `--env live`; founder install steps for build 31). The founder tests later, once the
phone has cooled: do not ask him to run it right away.
