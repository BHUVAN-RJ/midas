# Brief: fewer words in the shell and the Reminders Sidekick, 2026-10-10

**Status:** Finished 2026-10-11: founder-approved mockup built and merged into main; Reminders page deployed to staging and live. Agent closed 2026-10-11.

You are the agent that applies the new wording rules (`docs/WRITING.md`) to every screen the
founder sees today: the Midas app (shell) and the Reminders Sidekick. You work in your own git
worktree on branch `agent/wording` (`~/Desktop/Midas/midas-worktrees/wording`). The founder
talks to you directly in your Herdr tab.

## What the founder asked (2026-10-10)

Too many words. Example, the Apple Reminders import sheet: title "Bring in your Apple Reminders"
plus two explaining lines ("Midas reads your lists and reminders on this iPhone and adds them
here. Nothing in Apple Reminders is changed." / "Already brought them in from your Mac? Anything
that changed on your iPhone is updated."). It should just say "Import Apple Reminders". Apply the
same everywhere.

## How you work

1. Read `docs/WRITING.md` and every screen's text:
   - shell: `shell/Midas/*.swift` (every `Text(`, `Button(`, `Label(`, alert, sheet, error
     message, the `*Copy` enums such as `AppleRemindersImportCopy`, `WelcomeCopy`), and
     `NSRemindersFullAccessUsageDescription` in `shell/project.yml` (it must stay a full
     sentence: App Store guideline 5.1.1, see `docs/WRITING.md` rule 10);
   - notification text (`shell/Midas/Notification*.swift`, `Reminder*.swift`: action titles
     such as Done and Snooze);
   - `sidekicks/reminders/index.html`: every string a person sees.
2. **Make a mockup first, change no code.** A single HTML page with every screen's text as a
   before → after table, grouped by screen, plus phone-sized renderings of the main changed
   screens (import sheet, import summary, welcome, errors, empty states). Put it at
   `docs/mockups/wording-2026-10-10.html` in your worktree and tell the founder to open it
   (`open <path>`). Mark anything you were unsure about.
3. Wait for the founder's explicit "approved" (he may strike or change rows). Then build exactly
   the approved table.
4. Tests: existing tests that assert old strings change only through the test-guardian agent,
   citing `docs/WRITING.md` and the founder's approval of the mockup (date it). Add a test that
   fails if the removed explaining lines come back on the import sheet.

## Rules

- Every word on screen follows `docs/WRITING.md`. Change wording only, not layout or behaviour.
  Record keys and the `reminder:` record format stay exactly as they are.
- Stay inside your worktree. Never edit `CLAUDE.md`, `docs/PRODUCT.md`, `docs/WRITING.md`,
  `docs/PARALLEL-AGENTS.md`, `backend/package*.json` or `backend/wrangler.jsonc`. If a rule in
  `docs/WRITING.md` seems wrong, tell the founder; the lead session edits it.
- Run all suites after every change: `cd backend && npm test`,
  `cd shell && xcodebuild test -project Midas.xcodeproj -scheme Midas -destination "platform=iOS Simulator,name=iPhone 17"`,
  `python3 -I -m unittest discover -s tests/guard`. No `2>&1` or other redirects. After the shell
  tests, xcodebuild can hang in `simctl diagnose`: `pkill -f "simctl diagnos[e]"`.
- Never run anything against Cloudflare. The Reminders page reaches the phone only through a
  deploy the founder approves (`node scripts/deploy-sidekick.mjs reminders --env staging`, then
  `--env live`); tell him or the lead session the command.
- Commit small on your branch. Never merge into `main`; the lead session merges.
