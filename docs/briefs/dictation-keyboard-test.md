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

## Build 34: mic inside the keyboard (founder approved 2026-11-19)

The founder finds the app switch (keyboard → Midas → swipe back) "pretty annoying and killing the
user experience". Apple's guide says keyboards get no microphone; one unverified report says it may
work with Full Access on and mic permission already granted to the containing app
(github.com/asre1212/Dictation/pull/2, developer.apple.com/forums/thread/800500). Test it on the
founder's phone. Only this; no layout, swipe or haptics work in this build.

1. **Mic in the keyboard:** with Full Access on, the keyboard itself tries to record: `AVAudioSession`
   (record category) + `AVAudioEngine` + the existing on-device speech recogniser, then the gate,
   then `insertText`, with no app switch. Reuse `OnDeviceSpeechTranscriber` and `DictationGate` if
   they compile into the extension; add `NSMicrophoneUsageDescription` /
   `NSSpeechRecognitionUsageDescription` to the extension's Info.plist if needed.
2. **Setting, no rebuild later:** `keyboardMic` in the Dictation Sidekick's `settings:main`:
   `"keyboard"` (try in the keyboard; fall back to the app switch on failure) or `"app"` (today's
   path). Default `"keyboard"`. The page's Settings edits it; agent block + `tools.js` + tests.
   The keyboard reads it through the App Group (the app writes it there when it syncs).
3. **Show and log the answer:** on the listening panel, one line while testing: "Mic in keyboard:
   works" or "Mic in keyboard: <exact error>". Save a `dictation.probe` record (new `$type` in the
   manifest) with: result (works | failed), the exact error domain/code/message, which step failed
   (session category, activate, engine start, recogniser), full access on/off, mic permission
   state, build, iOS. Every attempt, so staging shows it without screenshots.
4. Build number **34**. New tests only (the probe record, the setting parsing and fallback, the
   step-by-step result mapping). Full backend suite; shell suite on both schemes through
   `scripts/sim.sh`. Commit with the TEST BUILD prefix; redeploy the Dictation Sidekick to staging
   only. Report: what changed, test results, the founder's install steps (cd first), and how he
   tests: open any app, Midas keyboard, tap voice, speak, read the line.

## Build 35: make the mic test unmistakable (founder approved 2026-11-19)

Build 34 on the founder's phone: Midas Test opened before dictation started, then three keyboard
inserts landed on staging (source keyboard, ~1.04 s after the pause), but **no `dictation.probe`
record ever reached staging**, so nobody can tell whether the keyboard's own mic was tried, failed,
or worked. Founder: "I couldn't tell what happened." In build 34 the app opens only from the Start
Dictation button, which shows only when the route is `app` (mode app, or a failed keyboard attempt),
so either the attempt failed and its probe was lost, or the keyboard never attempted.

1. **Find and fix why no probe reached staging** (queued in the App Group `probes/` → Darwin
   notification → `DictationKeyboardSession.saveKeyboardRecords` → `saveProbe` → sync). Check every
   link, including: is the probe written before a failure falls back, does the app observe the
   notification while backgrounded, is `saveKeyboardRecords` called on open, does sync push
   `probe:` keys, does a crash/kill of the extension (memory limit while starting audio + the
   recogniser) leave an attempt that is never turned into a probe. Add a failing test first for the
   cause found, then fix it. Say in the report what the cause was.
2. **`keyboardMic: "keyboard-only"`** (new value in `settings:main`, the page's Settings and the
   tools): the keyboard never opens Midas Test and never falls back; on failure the panel shows the
   exact error in place of the Start button. **Write it as staging's `settings:main` value for R J**
   (one ops row, same shape as the sync push, staging only; read it back), so the founder's next try
   is keyboard-only without touching Settings.
3. **Visible mic label** on the listening panel, large and plain: `KEYBOARD MIC` or `APP MIC`
   (whichever is recording now), plus the build 34 line ("Mic in keyboard: works" / the error).
4. **`mic` on every run record** (`keyboard` | `app`) for keyboard-source runs; the page and summary
   show the count per mic.
5. **Keyboard log:** the keyboard appends each step to a small ring log in the App Group (last 50:
   time, event, detail: appeared, route chosen and why, full access, mic permission, each mic step
   with its result/error, extension memory if available, disappeared). Midas Test saves it as one
   `log:keyboard` record of the Dictation Sidekick when it opens or is notified; the Dictation page
   shows it newest first ("Keyboard Log"). Agent block/tools.js: a tool to read it.
6. Build number one above the current value. New tests only; full backend suite; shell suite on
   both schemes through `scripts/sim.sh`; commit with the TEST BUILD prefix; redeploy the Sidekick
   to staging only. Report: the probe-loss cause, what changed, test results, install steps (cd
   first), and the founder's test: reinstall, delete and re-add the keyboard + Full Access, open
   Messages, Midas keyboard, speak, read the label and line.

## Build 40: our UI while Apple listens (founder approved 2026-11-22)

Build 38 answer (founder's phone, iOS 27, Full Access on, keyboard-only): the keyboard's own mic
fails at **engine start**, `com.apple.coreaudio.avfaudio` **2003329396** (`'what'`, unspecified);
session category and activate passed. Keyboards can't record. The screenshot also shows iOS draws
its own 🎙 bottom-right under the Midas keyboard (Apple dictation). Founder: use Apple's mic, but
give it Midas's UI/UX. Apple's 🎙 can't be moved, restyled or triggered by a keyboard (no public
API; no private calls). Test what *can* be done: when the person taps Apple's 🎙, does the Midas
keyboard stay on screen, can it tell dictation is running, see the words, and clean them after.
Build number **40** (the founder's phone has 39).

1. **New `keyboardMic` value `"apple"`** (settings:main, page Settings, tools, tests); write it as
   staging's value for R J (one ops row, sync-push shape, staging only; read back). In `"apple"`
   mode the keyboard never opens Midas Test and never starts its own mic; the listening panel says
   only "Tap 🎙 below" (WRITING.md) until dictation is detected.
2. **Detect Apple dictation** with every public signal, logging each to the Keyboard Log with time:
   `UITextInputMode.currentInputModeDidChangeNotification` and the current/`textInputMode`
   `primaryLanguage` (look for `"dictation"`), `textWillChange`/`textDidChange`,
   `documentContextBeforeInput` length and the change since the last key Midas itself typed,
   `viewWillDisappear`/`viewDidAppear` (does iOS hide the keyboard during dictation?),
   `hasDictationKey` value. Text that changes without a Midas key press counts as dictated.
3. **Our UI while it listens:** when dictation is detected and the keyboard is still shown, switch
   the panel to the listening look (jess's orb pulsing Volt, the dictated words so far, from the
   context diff). Large label `APPLE MIC`.
4. **Cleanup after:** when dictation ends (input mode back, or no change for 1.5 s, a constant),
   run the gate (fillers only, as settings:main says) on the dictated span; if the text before the
   cursor still ends with exactly that span, `deleteBackward` its length and `insertText` the
   cleaned text; else skip and log why. Flash the inserted text like build 33. Setting
   `appleCleanup` (on by default) in settings:main.
5. **Records:** each dictation saves a `dictation.run` with `source: "keyboard"`, `mic: "apple"`,
   raw (what Apple typed), cleaned, whether cleanup was applied or the skip reason, ms from end
   to cleanup. The Keyboard Log record as build 35.
6. New tests only (detection from a fake input-mode/text sequence, span check and replace, skip
   reasons, the setting). Full backend suite; shell suite on both schemes via `scripts/sim.sh`.
   Commit with the TEST BUILD prefix; redeploy the Sidekick to staging only. Report: what changed,
   tests, install steps (cd first), and the founder's test: Messages → Midas keyboard → tap Apple's
   🎙 bottom right → say "um tell mom I'm on my way" → stop → see if the Midas panel stayed and the
   "um" went; then open Midas Test once so the log reaches staging.

## Build 41: the keyboard experience (founder approved 2026-11-22)

Build 40 on the founder's phone: **success.** Apple's 🎙 (bottom right, drawn by iOS) does the
speech-to-text, the Midas keyboard stays up, and the cleanup works; no Midas app needed. Founder:
"focus completely on the UI/UX." The mic stays **Apple's** (`keyboardMic: "apple"`; keep
`hasDictationKey` false so iOS shows its 🎙). Founder will refine the UX after this build; build
the defaults below, Wispr Flow's keyboard is the reference (founder's screenshot 2026-11-22: top bar,
then number and symbol rows, then ABC · space · return).

1. **Layout (numbers-first, like Wispr Flow):**
   - Top bar: undo (left) and, while Apple listens, the cancel ✕ (right).
   - Rows: `1 2 3 4 5 6 7 8 9 0` / `- / : ; ( ) $ & @ "` / `#+=  . , ? ! '  ⌫` / `ABC · space · return`.
     `#+=` toggles the second symbols page (`[ ] { } # % ^ * + =` / `_ \ | ~ < > € £ ¥ •`, as Apple's).
   - **ABC switches to the next keyboard** (`advanceToNextInputMode()`), the way Wispr Flow does, so
     letters and emoji come from Apple's keyboard. No 😊 key, no letters page in Midas.
   - When Apple dictation is detected: the listening view (jess's orb pulsing Volt, the words so far,
     `APPLE MIC`) covers the keys, with ✕ cancel. When it ends: cleanup, flash, back to the keys.
   - Light and dark; key sizes and spacing match Apple's on iPhone 16 Pro. Large tap targets.
2. **Sounds: Apple's exact keyboard clicks.** The input view adopts `UIInputViewAudioFeedback`
   (`enableInputClicksWhenVisible = true`) and plays Apple's system keyboard sounds the way other
   keyboards do: character key, delete key, modifier keys (shift/#+=/ABC/return/space) each with
   Apple's own sound for it (system sound IDs 1104 / 1155 / 1156, or `UIDevice.playInputClick()`
   where it fits). Respect the person's Keyboard Clicks setting where iOS lets a keyboard know it.
3. **Haptics:** a light impact on every key press (`UIImpactFeedbackGenerator(style: .light)`,
   prepared ahead), like Apple's keyboard haptics; a soft one when listening starts and when the
   cleaned text lands. Full Access only (it's on).
4. **Cancel ✕** while Apple listens: delete exactly what this dictation typed (if the text before
   the cursor still ends with it; else log the skip), close the listening view. Try whether a
   keyboard action ends Apple's dictation (e.g. the delete/insert itself); log what Apple's
   dictation did after cancel (input mode, further text changes). No private APIs.
5. **Animation:** keys ↔ listening view as a smooth swipe/cross-fade (≈250 ms, spring), the cleaned
   text flash as build 33. Respect Reduce Motion.
6. **Keyboard Log** additions: sound and haptic availability (Full Access, Keyboard Clicks),
   cancel results. Build number **41**. New tests only (layout pages, ABC → next keyboard, cancel
   span delete and skip reasons, sound per key kind, Reduce Motion). Full backend suite; shell suite
   on both schemes via `scripts/sim.sh`. Commit with the TEST BUILD prefix; redeploy the Sidekick to
   staging only (settings stay `keyboardMic: "apple"`). Report: what changed, tests, install steps
   (cd first), the founder's test: order keyboards Midas → English; type numbers (sound + haptic),
   ABC → Apple's keyboard and back via 🌐, tap Apple's 🎙 and speak, try ✕ cancel.
