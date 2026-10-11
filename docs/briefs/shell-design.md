# Brief: shell and Sidekick design changes, 2026-10-10

**Status:** Finished 2026-10-10: merged into main (icon grid home, full-screen Sidekicks, welcome wording, Apple Reminders import on the phone). Not yet tried on a real phone. Agent closed 2026-10-11.

You are the agent for changes the founder wants to the iPhone shell (the Midas app itself) and to
the design of the Sidekicks inside it, starting with Reminders. You work in your own git worktree
on branch `agent/shell-design` (`~/Desktop/Midas/midas-worktrees/shell-design`). The founder talks
to you directly in your Herdr tab. Dev port, if you ever serve a page: **8790**.

## How you work: four steps, in order, no skipping

1. **Go through the idea.** Read this brief and the sources below. Then ask the founder what he
   wants changed, and repeat it back in plain words.
2. **Ask the founder questions.** A few at a time, only what you need. Do not write code.
3. **Propose a plan and get it approved.** Which screens and files change, what it will look like
   (describe it, or show a quick mockup), what is tested and how, what is left out. Wait for an
   explicit "approved" / "build it".
4. **Build the approved plan,** with tests (see Rules).

"Discuss, the founder approves, then build" is the project rule (`CLAUDE.md`).

## Where things are

**The shell** (SwiftUI, generated with xcodegen from `shell/project.yml`; run `xcodegen generate`
in `shell/` after changing `project.yml` or adding files):

- `shell/Midas/WelcomeView.swift`: the sign-in screen (name field, two passkey buttons).
  Pending from the founder: the button wording is confusing. Options offered on 2026-10-10:
  A "Create my account" / "Sign in with my passkey", B "Get started" / "I've used Midas before".
  No choice recorded yet; ask.
- `shell/Midas/MidasApp.swift`: `RootView` (switches on sign-in state), the Sidekick folder
  (home grid), opening a Sidekick in a WKWebView.
- `shell/Midas/SidekickDirectory.swift`: the folder's list comes from `GET /sidekicks` on the
  server (name, SF Symbol, background color from each Sidekick's `manifest.json`), cached for
  offline.
- `shell/Midas/AuthModel.swift`: sign-in states and the error messages shown.

**Sidekicks** (each is one HTML file in `sidekicks/<id>/`):

- `sidekicks/reminders/index.html` and `manifest.json`: the Reminders Sidekick, built by the
  reminders agent (`docs/briefs/reminders-app.md` has its decisions; read it). Its data goes
  through the store only (`shell/sdk/midas-store.js` pasted inline); reminder records
  `reminder:<id>` are booked as notifications by the shell (`docs/NOTIFICATIONS.md`). Keep the
  record format unchanged.
- Bundle rules (deploy gate, `backend/scripts/bundle-tools.mjs`): one HTML file, inline script
  and style only; no `<script` with attributes, no `import`, `require`, `WebSocket`,
  localStorage or indexedDB. No native bridge (App Store guideline 4.7.2).

**How a change reaches the founder's phone:**

- Shell changes: the founder presses Run in Xcode on `~/Desktop/Midas/midas/shell/Midas.xcodeproj`
  after the lead merges your branch. To let him try it before merging, tell him to open
  *your worktree's* `shell/Midas.xcodeproj` and press Run. Debug builds talk to the **staging**
  server and use developer-mode passkey domains (`Midas-Debug.entitlements`, temporary).
- Sidekick page changes: deployed to staging with
  `node scripts/deploy-sidekick.mjs reminders --env staging` (from `backend/`). **You never run
  it.** Tell the founder or the lead session the command; the founder approves every deploy.
  Reminders is assigned to the founder's staging account ("R J"). Live gets the same version
  only after staging (`--env live`, refused otherwise).

## In parallel, do not collide

- The **backend agent** (`agent/backend`) is changing `LocalRecordStore.swift`,
  `SidekickStoreChannel.swift`, `ShellServices.swift`, `RecordSync.swift` and `MidasApp.swift`
  (a "Restoring your records" screen). It is about to be merged into main. Do not edit those
  files until it is; when it is, merge main into your branch first. Tell the founder if your plan
  needs them.
- The notification engine files (`Notification*.swift`, `Reminder*.swift`) belong to the
  notification work; change them only if the approved plan says so.

## Sources to read

- `docs/PRODUCT.md` (build 1, product principles, section 5 decisions, section 6 state).
- `docs/briefs/reminders-app.md`, `docs/NOTIFICATIONS.md`.
- The files above.
- midas-intel `docs/word-list.md` for any words shown to users.
- `CLAUDE.md` (rules, "Tests are guarded"), `docs/PARALLEL-AGENTS.md` (worktree rules).

## Rules

- Every word on screen follows `docs/WRITING.md` (founder, 2026-10-10): say the action and stop.

- Stay inside your worktree. Never edit `CLAUDE.md`, `docs/PRODUCT.md`,
  `docs/PARALLEL-AGENTS.md`, `backend/package*.json` or `backend/wrangler.jsonc`.
- Every change gets a test that can fail for the reason it exists. Run all suites after every
  change, report results honestly. The guard allows: `cd backend && npm test`,
  `cd shell && xcodebuild test -project Midas.xcodeproj -scheme Midas -destination "platform=iOS Simulator,name=iPhone 17"`,
  `python3 -I -m unittest discover -s tests/guard`. No `2>&1` or other redirects in those
  commands. The first shell run after `xcodegen generate` sometimes dies with "Test crashed with
  signal kill before establishing connection"; rerun once.
- Changing or deleting an existing test goes through the test-guardian agent, with a dated
  decision. New tests you may add.
- Never run anything against Cloudflare (no `wrangler ... --remote`, no deploys).
- Commit small and often on your branch. Never merge into `main`; the lead session merges.
- Blocked on a question or an approval: ask the founder in your tab and wait.
