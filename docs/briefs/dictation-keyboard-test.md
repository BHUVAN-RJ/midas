# Brief: Midas dictation keyboard (TEST BUILD ONLY)

> **TEST BUILD. Branch `agent/dictation-test` is NEVER merged into `main` and NEVER shipped to
> live.** Midas Test (bundle `com.bhuvanrj.midas.test`, staging) only. Never `--env live`, no
> TestFlight upload unless the founder asks. Founder approved building it 2026-11-14 ("lets build
> this keyboard dictation app right now").

Read first: `docs/mockups/dictation-keyboard-2026-11-13.html` (the agreed look and motion),
`docs/briefs/dictation-gate-test.md` (all rounds; the gate and its settings), `docs/DESIGN.md`,
`docs/WRITING.md`, and the dictation code on this branch (`shell/Midas/Dictation*.swift`,
`VoiceTranscriber.swift`, `sidekicks/dictation/`).

## What dictation does today (keep it)

On-device speech (`OnDeviceSpeechTranscriber`) → the deterministic gate with the staging
`settings:main` of the Dictation Sidekick. Current settings: **fillers only** (um, uh, erm, hmm
removed; capital first letter, `I`, days/months, end punctuation), no correction cues, no triggers,
**no model call**. Reuse `DictationGate` exactly as it is; the keyboard gets the gate's output.

## What to build

1. **Keyboard extension** target (`MidasKeyboard`, bundle `com.bhuvanrj.midas.test.keyboard` for the
   Test config), `RequestsOpenAccess` on, sharing the Test app's App Group. Follow how `MidasWidgets`
   is set up in `shell/project.yml`. Prefer embedding it only in the Test config; if XcodeGen cannot
   do that cleanly, embed it on this branch for all configs (the branch never ships) and say so.
2. **Layout as the mockup:** the keyboard opens in **listening mode** (jess's orb, the raw words as
   they come, no waveform, no Done). Left: `ABC` (switches to letters). Right: `123` (numbers and
   symbols) and `😊` (switches to the next keyboard, for emoji). In letters/numbers, a `●` key next to
   space goes back to listening. Full QWERTY letters, shift, backspace, space, return, numbers and
   symbols pages (App Review 4.4.1: a keyboard must type without dictation and without full access;
   without full access the keyboard shows letters only, with one line saying Allow Full Access turns
   on dictation). iOS draws 🌐 bottom-left; nothing to do there. Light and dark.
3. **Mic lives in the app** (extensions can't record): a **dictation session** in the Midas Test app.
   - Keyboard, no live session: the listening panel shows one button, "Start Dictation", that opens
     Midas Test (`midastest://dictation` or the scheme the Test app has; via the responder-chain open
     URL, as other dictation keyboards do; fine for a test build). Midas starts the session (audio
     session active, background audio mode, Test config only) and shows one line: "Swipe back to
     keep typing." The person goes back with iOS's ◀ breadcrumb.
   - Session live: keyboard appears → starts listening at once. Keyboard ↔ app talk through the App
     Group (start/stop/state, last text) plus Darwin notifications for wake-ups; no network.
   - When the person pauses (end of speech; start with 1.0 s of silence, a constant), the app runs
     the gate on the final text, hands it to the keyboard, and the keyboard inserts it with
     `textDocumentProxy.insertText` (a space before it when the text before the cursor doesn't end in
     whitespace). Then it listens again. Switching to ABC/123, the keyboard closing, or 😊 stops
     listening (text already said still inserts).
   - The session ends 5 minutes after the last use (a constant) or when the app is swiped away.
     The orange mic dot shows while it is live; that is iOS.
4. **Logging:** each inserted dictation saves a `dictation.run` record like the test screen does
   (source `keyboard`, raw, inserted text, path, release→raw ms, total ms from end of speech to
   insert, build, thermal), so the founder's real use lands on staging. Same record type and code
   path as `DictationTestCenter.save`; extend, don't fork.
5. Build number: one above the current `CURRENT_PROJECT_VERSION` on this branch.

Everything new in the app stays inside `#if MIDAS_TEST_BUILD` and `@available(iOS 26, *)` where it
uses iOS 26 APIs. Signing, bundle IDs, App Groups, entitlements: if blocked, **stop and give the
founder exact Xcode steps; never override them.**

## Not now

Always-listening without the bounce, the model, corrections, Mac, App Store review.

## Tests

New test files only (existing tests are guarded; known failing old dictation checks and the
sheet-kinds/App Group/JessWorklogLink checks stay as they are; list them). Cover: the session state
machine (start, live, pause → insert, timeout), the App Group handoff encoding, the spacing rule,
the layout switching (listening/letters/numbers/next keyboard), no-full-access mode. Full backend
suite; the shell suite on both schemes through `scripts/sim.sh`.

## Done

Committed on `agent/dictation-test` (`TEST BUILD (do not merge):`). Report: what was built, test
results, anything blocked, and the founder's steps: install build N (commands start with `cd`;
Midas Test scheme), then Settings → General → Keyboard → Keyboards → Add New Keyboard → Midas Test,
tap it → Allow Full Access, then order keyboards so Midas is first and Emoji second.
