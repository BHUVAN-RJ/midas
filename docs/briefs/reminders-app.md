# Brief: the reminders Sidekick, 2026-10-09

**Status:** Finished 2026-10-10: merged into main; deployed to staging and live. Agent closed 2026-10-11.

You are the agent for the reminders Sidekick, the first real Sidekick in Midas. You work in your
own git worktree on branch `agent/reminders-app` (the folder is still named
`midas-worktrees/notification-engine`; it was reused). The founder talks to you directly in your
Herdr tab.

## How you work: four steps, in order, no skipping

1. **Go through the idea.** Read this brief and the sources below. Then tell the founder, in
   plain words, what you understood the problem and the goal to be.
2. **Ask the founder questions.** Ask what you need to know before planning, a few at a time.
   The founder gives directions. Do not write code.
3. **Propose a plan and get it approved.** Screens, records, what is tested and how, and what is
   left out. Wait for an explicit "approved" / "build it". Changes to the plan go back to the
   founder.
4. **Build the approved plan.** Only now write code, with tests (see Rules).

Never start a later step before the earlier one is done. "Discuss, the founder approves, then
build" is the project rule (`CLAUDE.md`).

## The goal

Replace the placeholder `sidekicks/reminders/index.html` with the reminders Sidekick the founder
and his friends use on their phones (build 1 deliverable D6, with D8's notifications).

## What is already decided

- **D6 (`docs/PRODUCT.md`, `### Build 1`):** the Sidekick keeps all its data through the store
  (no localStorage, no IndexedDB), records keyed `type:id`, and a manifest: id, name, icon (SF
  Symbol name plus background color), `reads`. Done when: on the founder's phone it creates,
  lists, edits and deletes its records, and the data survives deleting and reinstalling the
  shell; the bundle references neither localStorage nor indexedDB.
- **Start minimal, rebuild on request (2026-10-08):** the first version is the basic one;
  features are added later by rebuilding when the user asks. The basics whose absence makes users
  leave are in from day one: reliable notifications, Done and Snooze on the notification,
  repeats.
- **Notifications are already built and merged** (`docs/NOTIFICATIONS.md`). The Sidekick never
  schedules anything: it writes `reminder:<id>` records `{ at, title, body, repeat, timeZone }`
  through `store`, and the shell books them. Done, Snooze 10 min, Snooze 1 hour and Snooze until
  tomorrow are on every notification; taps are written back into the record (`done`,
  `snoozedUntil`, `lastDoneAt`). Read the record before writing it so those are not lost. Not
  built in the engine: nag until done, alarm levels, repeat after completion, custom snooze
  lengths.
- **No bridge (guideline 4.7.2):** the page is plain HTML/JS in a WKWebView. No native API, no
  script message handlers. Paste `shell/sdk/midas-store.js` into the page's inline script.
- **Bundle rules (deploy gate, `backend/scripts/bundle-tools.mjs`):** one HTML file, inline
  script and style only; no `<script` with attributes, no `import`, no `require`, no
  `WebSocket`. CSP `script-src` is the hash of each inline script, computed at deploy.
- **The shell already lists Reminders** (`shell/Midas/SidekickCatalog.swift`: orange,
  `checklist`) behind the passkey sign-in gate.
- **Encryption is demoted** (2026-10-09, revisited at 5,000 users). Records are on the phone only
  for now (not synced to the backend).

## Open, for you to ask the founder

- Which of the eight behaviour prototypes go into the first version, beyond the basics. The
  founder chose by trying them; no choice is recorded yet.
- The screens and the look (iOS-native or a Midas style; this sets the pattern for calendar,
  birthdays, split and notes, which are built next in parallel).

## Facts that limit what can be tried on a phone today

- The live backend (`https://midas-api.midas-backend.workers.dev`) is the 2026-10-05 version:
  `/sidekicks/<id>/bundle` and `/auth/*` return 404. Until the founder approves `wrangler deploy`
  and the D1 migration `0001_auth.sql`, the phone can neither sign in nor load a Sidekick.
  Deploying, migrating and `node scripts/deploy-sidekick.mjs reminders` change live systems:
  ask the founder first, every time.
- Passkeys on a phone also need Associated Domains on the App ID (the founder's step).
- If you need a way to load the page in the simulator without the live backend, say so in your
  plan; do not change the shell's loading without approval.

## Sources to read

- `docs/PRODUCT.md`: build 1 (D1, D5, D6, D8), the 2026-10-08 and 2026-10-09 decisions.
- `docs/NOTIFICATIONS.md`: the record format, repeats, time zones, errors, what the user sees.
- `shell/sdk/midas-store.js`; `sidekicks/reminders/index.html` (the placeholder);
  `backend/scripts/deploy-sidekick.mjs` and `bundle-tools.mjs`.
- `CLAUDE.md` (working rules, "Tests are guarded"), `docs/PARALLEL-AGENTS.md` (worktree rules).
- midas-intel (`~/code/midas-intel`, read only): `docs/research/reminders/ANALYSIS.md` (what
  users love, why they leave), `docs/prototypes/reminders/` (eight behaviour prototypes and their
  `BRIEF.md`), and the design doc `docs/designs/jess-personal-assistant-shell.md`,
  `### Start minimal, rebuild on request; discovery through suggestions, 2026-10-08`.

## Rules

- Every word on screen follows `docs/WRITING.md` (founder, 2026-10-10): say the action and stop.

- Stay inside your worktree. Edit only files your approved plan names. Shared files
  (`CLAUDE.md`, `docs/PRODUCT.md`, `docs/PARALLEL-AGENTS.md`, `backend/package.json`,
  `backend/package-lock.json`, `backend/wrangler.jsonc`) are changed only by the lead session.
- Every piece you build gets tests that can fail for the reason they exist. Run the whole suite
  after every change and report results honestly. From inside the worktree the test guard allows
  the suites in these forms: `cd backend && npm test`, `cd shell && xcodebuild test ...`,
  `python3 -m unittest discover -s tests/guard`, and in midas-intel
  `python3 -m unittest discover -s intel/tests`. Avoid `2>&1` or other redirects in those
  commands; the guard reads `>` as a write.
- You may add new tests. Changing or deleting an existing test goes through the test-guardian
  agent; a hook enforces this.
- Commit small and often on your branch. Never merge into `main`; the lead session merges after
  review.
- If you are blocked on a question or an approval, ask the founder in your tab and wait.
