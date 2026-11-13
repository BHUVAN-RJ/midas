# Brief: dictation cleanup test (TEST BUILD ONLY)

> **THIS IS A TEST BUILD. Branch `agent/dictation-test` is NEVER merged into `main` and NEVER
> shipped to live.** Midas Test (bundle `com.bhuvanrj.midas.test`, staging) only. Founder,
> 2026-11-13. Do not open a PR, do not push to `main`, do not upload a "Midas" (live) build.
> Do not touch `docs/PRODUCT.md`, `CLAUDE.md`, `docs/PARALLEL-AGENTS.md`, backend files.

## Why

The founder is exploring a Wispr Flow-style dictation keyboard for Midas (mockup on main's
checkout, uncommitted: `~/Desktop/Midas/midas/docs/mockups/dictation-keyboard-2026-11-13.html`).
Before any keyboard work, measure one thing on his iPhone 16 Pro: **how fast and how good is
on-device cleanup** of dictated text using Apple's Foundation Models framework (iOS 26,
`LanguageModelSession`, Apple Intelligence phones only), on top of the existing on-device
transcriber. For comparison: jess's server model call averages 2.3 s (staging `voice_logs`, 52 calls).

## What to build (step 1 only; no keyboard extension)

A hidden test screen inside the Midas app, compiled **only in the `Test` configuration**:

1. Add a compilation condition for the Test config only (e.g. `SWIFT_ACTIVE_COMPILATION_CONDITIONS:
   $(inherited) MIDAS_TEST_BUILD` under `configs: Test:` in `shell/project.yml`) and wrap every new
   file's contents and its entry point in `#if MIDAS_TEST_BUILD`. A Debug or Release build must
   contain none of it.
2. Entry point: a quiet way in from the Test build only (e.g. a row in an existing settings / "?"
   menu, or a long-press). Say in your report where it is.
3. The screen, titled "Dictation Test" with a visible "TEST BUILD" label:
   - **Hold to talk**: uses the existing `OnDeviceSpeechTranscriber` (`shell/Midas/VoiceTranscriber.swift`).
     Extend it with options if needed (long dictation, no end on silence); do not fork it
     (PRODUCT.md "Shared voice components"). Keep default behaviour for existing callers unchanged.
   - Shows **raw text** and **cleaned text** side by side.
   - Shows timings in ms: release → final raw text; cleanup start → cleaned text; total.
   - **Five fixed phrases** with one tap each to run cleanup only (repeatable timing, no speaking):
     "um so like be there at 5 no wait 6", "uh tell mom im on my way",
     "buy eggs milk and uh bread oh and coffee", a sentence with names ("send the deck to Priya and
     Tomasz by friday"), and a 60-word rambling paragraph. Also "Run all ×5" that reports average
     and worst time per phrase.
   - **Model status**: available / not available and the reason (`SystemLanguageModel.default.availability`:
     device not eligible, Apple Intelligence off, model not ready).
   - First-call vs warm-call timing shown separately (prewarm the session when the screen opens).
4. Cleanup instruction: remove fillers (um, uh, like, so), apply self-corrections ("5 no wait 6" → "6"),
   punctuate and capitalise, keep the person's words otherwise, no added content, plain text out.
   Keep the instruction in one constant so it can be tuned.
5. Everything new is `@available(iOS 26, *)`; the app still builds and launches on iOS 17
   (deployment target stays 17.0).

## Tests

- Add unit tests (new files only) for: the cleanup instruction builder, the timing math, the
  availability-reason mapping, the phrase list. A check must be able to fail for the reason it exists.
- Do not change existing tests (guarded; `test-guardian` only).
- Run the full suite with `scripts/test-all.sh` before saying done; report results honestly.
- Simulators only through `scripts/sim.sh`. Note: the simulator has no Apple Intelligence model, so
  real timings come only from the founder's phone.

## Done

- Builds with the "Midas Test" scheme; full suite passes (or failures reported exactly).
- Commit on `agent/dictation-test` only. Commit messages start with `TEST BUILD (do not merge):`.
- Report: where the entry point is, files changed, test results, and the exact founder steps to
  install on his iPhone (every command starts with `cd` into its absolute folder; Midas Test scheme;
  iOS 26+ with Apple Intelligence on). Do not upload to TestFlight unless the founder asks.
- If blocked on signing, bundle IDs or entitlements: stop and give the founder exact steps; never
  override them.
