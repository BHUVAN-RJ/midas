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
