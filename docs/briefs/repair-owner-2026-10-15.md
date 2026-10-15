# Brief: repair, one owner (2026-10-15)

You own the repair feature end to end: the iPhone shell part (gesture, drawing layer, speech,
upload), the backend part (`backend/src/repairs.ts`, migration `0005_repairs.sql`) and the Mac
mini runner (`runner/`). Four agents built it on 2026-10-13/14 and are now closed; their parts
were merged to `main` but were never run together on a phone. The first phone test failed.
Make it one working thing.

Read first: `CLAUDE.md`, `docs/PRODUCT.md` section 2 "Plan additions, 2026-10-13: repair"
(including the 2026-10-15 lines), `docs/briefs/repair-contract.md`, `docs/WRITING.md` (every word
a person sees), `docs/DESIGN.md`. Earlier briefs for history: `docs/briefs/repair-*.md`.

## Founder decisions, 2026-10-15

1. **Permissions at launch: done by the lead, 2026-10-15.** `shell/Midas/VoicePermissions.swift`
   asks for the microphone and speech recognition when Midas opens, signed in (only the iOS
   prompts); the repair layer's permission screen is removed; tests in
   `VoicePermissionsTests.swift`. Keep it that way: no repair file asks for anything.
2. **Gesture: a circle, not a scribble.** One finger draws a circle anywhere on the Sidekick;
   that opens repair. Replaces the zigzag scribble (`ScribbleDetector`,
   `ScribbleGestureRecognizer`). Defaults to start from, all in one thresholds struct to tune
   from phone captures later: either direction; the path turns through at least about 300
   degrees; the end comes back near the start (within about a third of the circle's width); the
   circle is at least about 80 points wide, so taps, scrolls and small wobbles never fire it;
   between about 200 ms and 2 s. Stays passive: never cancels or delays the Sidekick's own
   touches, no script injected (guideline 4.7.2). Left-edge swipe clashes: handle only if they
   happen.

3. **Voice is a shared component.** The Action button voice reminders (midas-intel
   `docs/plans/2026-10-13-voice-reminders-v1.md`, "Shared components") will reuse the
   transcriber and `VoicePermissions` instead of building their own. Do this first, before the
   circle and the layout, so that builder can start on it:
   - Fix the Swift 6 crash (bug 1 below).
   - Make `OnDeviceSpeechTranscriber` configurable per use without changing repair's behaviour:
     hint words (`contextualStrings`), end of speech after a silence (with a callback when it
     ends), a maximum length (repair keeps its 5 minute backstop), and stop on demand. Repair sets
     none of the first two.
   - Keep it on-device only, always. Give it neutral names where it is used outside repair (for
     example a `VoiceTranscript` type); a rename that touches existing tests goes through
     test-guardian.
   - Test each option.
   - Pass a `VoicePermissionSystem` into the transcriber and add the test: permission denied →
     `start` throws and nothing listens (`docs/CONCERNS.md` item 10).

## Bugs from the first phone test (2026-10-14, Midas Test scheme, iPhone, dark mode)

Founder's report: white screen after the gesture, then the two iOS prompts, then a frozen app,
no X, the text box hidden under the keyboard, Xcode stopped on `Thread 25: EXC_BREAKPOINT`.
Screenshots described in `docs/PRODUCT.md` (2026-10-15 line). Causes found by reading the code;
confirm each before fixing.

1. **Crash when listening starts.** `SWIFT_VERSION` is 6.0, so the runtime traps when code marked
   main-actor runs off the main thread. `OnDeviceSpeechTranscriber` is `@MainActor`; the audio tap
   closure (`RepairSpeechTranscriber.swift:149`) and the recognition result handler (`:111`) are
   created inside it, inherit main-actor isolation, and are called by iOS on background threads.
   Make both closures nonisolated (for example built by `nonisolated static` functions) and hop
   to the main actor only to deliver the transcript. Check every other callback in the repair
   files (and `SFSpeechRecognizer.requestAuthorization`) for the same pattern.
2. **Invisible permission screen.** White background, `Color.primary` text: white on white in
   dark mode. The screen is gone (decision 1), but the repair layer hard-codes `Color.white`
   (`RepairCanvasView.swift:27`). Nothing in the layer may assume light mode.
3. **Layout.** The snapshot is framed at the web view's full height inside a container that the
   bottom bar (`safeAreaInset`) and the keyboard shrink, so the stack overflows and shifts: the
   frozen screen slides up under the status bar, Cancel (top left) goes off screen, and the text
   box does not rise above the keyboard. Required: the frozen screen sits pixel-exact on the web
   view it replaced and never moves; the bottom bar floats over its bottom edge and rises with
   the keyboard; Cancel is always visible inside the safe area; no white band anywhere.
4. **Three steps before anything works** (our screen, mic prompt, speech prompt). Gone with
   decision 1; the layer must open instantly after the circle.

Order: 3 (shared voice, crash) first, then the layout and dark mode, then the circle.

## Tests (midas `CLAUDE.md`, "Tests are guarded")

- Every fix gets a test that fails without the fix. Examples: the audio and speech callbacks run
  on a background queue in a test without trapping; the layer renders in dark mode with no
  hard-coded white; with a shorter container (keyboard up) the snapshot keeps its frame and
  Cancel stays inside the bounds; the circle detector fires on circles (both directions, a few
  sizes) and not on taps, straight drags, scrolls or zigzags.
- Changing or deleting an existing test (for example `ScribbleDetectorTests.swift`,
  `RepairSessionTests.swift` permission cases) goes through the `test-guardian` agent with this
  brief's founder decisions of 2026-10-15 as the authority. It may refuse; it logs either way.
- Use your own simulator, never the shared one: `xcrun simctl create "Midas Repair" "iPhone 16"`
  (or any installed iPhone type), then `MIDAS_SIMULATOR="Midas Repair" scripts/test-all.sh`.
- Also build the device app: `xcodebuild -project shell/Midas.xcodeproj -scheme "Midas Test"
  -destination generic/platform=iOS build` must succeed.
- Done = the full `scripts/test-all.sh` passes and the device build succeeds. Report the counts
  honestly, failures included.

## Rules

- Edit only inside your worktree. Never edit `CLAUDE.md`, `docs/PRODUCT.md`,
  `docs/PARALLEL-AGENTS.md`, `backend/package*.json`, `backend/wrangler.jsonc` or any guard file
  (`.claude/hooks`, `.claude/settings.json`, `.claude/agents/test-guardian.md`, `.githooks`).
  If one of them needs a change, write the exact text in your final report.
- Never merge into `main`; never deploy, migrate or put secrets anywhere remote.
- Before writing code, post a short plan (files, approach, tests) and any open questions, all in
  one list, and wait for the lead to answer.
- When done, list what the founder should try on the phone, step by step, and anything you
  could not check without a phone.
