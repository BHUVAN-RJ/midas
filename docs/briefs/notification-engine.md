# Brief: the notification engine (simple version), 2026-10-07

You are the agent for Midas's notification engine. You work in your own git worktree on branch
`agent/notification-engine`. The founder talks to you directly in your Herdr tab.

## How you work: four steps, in order, no skipping

1. **Go through the idea.** Read this brief and the sources below. Then tell the founder, in
   plain words, what you understood the problem and the goal to be.
2. **Ask the founder questions.** Ask what you need to know before planning, a few at a time.
   The founder gives directions. Do not write code.
3. **Propose a plan and get it approved.** Modules, interfaces, data, what is tested and how, and
   what is left out. Wait for an explicit "approved" / "build it". Changes to the plan go back
   to the founder.
4. **Build the approved plan.** Only now write code, with tests (see Rules).

Never start a later step before the earlier one is done. "Discuss, the founder approves, then
build" is the project rule (`CLAUDE.md`).

## The problem

iOS keeps at most **64 scheduled local notifications per app** and silently discards the rest
(a repeating notification, such as every day at 9, counts as one). An app must book
notifications with iOS ahead of time because iOS suspends apps in the background: iOS, not the
app, fires them. Midas is one app hosting many Sidekicks, so **every Sidekick shares the same 64**.
A user will have more than 64 upcoming reminders, so Midas needs its own booking system.

Two notifications due at the same moment do not conflict: iOS delivers both, grouped under
Midas. A booking with the same identifier replaces the earlier one; that is how edits and
cancels work.

## What the founder decided (2026-10-07)

- **Build a simple internal engine now.** Midas keeps its own unlimited queue of everything due,
  books only the soonest batch with iOS, and tops the batch up whenever the app gets to run (the
  app is opened, a notification is acted on, background refresh). Keep it simple.
- **Known issue, later, not yours now:** the server-side safety net. If the phone does not run
  for days, reminders beyond the booked batch do not fire. Deferred fix: the phone reports how
  far ahead it has booked and the server pushes anything later (APNs).

## How notifications reach a Sidekick in Midas (fixed architecture, do not change)

- A Sidekick is an HTML/JS page in a WKWebView. It has **no native API and no bridge** (guideline
  4.7.2): no script message handlers, no injected scripts.
- Native features are reached by **request records**: the Sidekick writes data through the Midas
  SDK, the shell reads it and does the native work. For notifications, a Sidekick writes
  `store.set("reminder:<id>", { at, title, body })`; `reminder:` is a reserved prefix. The shell
  watches these records and books the notifications. The Sidekick never schedules anything.
- Notification permission belongs to the shell: asked once, never delegated.
- Behaviours under consideration for the reminders Sidekick (the founder is choosing now, from
  prototypes in midas-intel `docs/prototypes/reminders/`): nag until done (repeats every N
  minutes until Done or Snooze), snooze from the notification, alarm levels (Standard, Time
  Sensitive, AlarmKit alarms). Each changes how many of the 64 slots a reminder uses; ask the
  founder which matter for the engine's first version.

## Sources to read

- `docs/PRODUCT.md` (this repo): the current build, especially section 5 and the 2026-10-07
  decisions.
- `CLAUDE.md` (this repo): working rules, including "Tests are guarded".
- `docs/PARALLEL-AGENTS.md`: rules for an agent in a worktree.
- `shell/`: the parked D1 shell draft (SwiftUI, xcodegen `shell/project.yml`). There is no
  notification code yet and no SDK or op-log yet; tell the founder what you would need from them.
- midas-intel (`~/code/midas-intel`, read only): `docs/research/reminders/ANALYSIS.md` (what users
  love and why they leave; the 64 limit is a named reason people leave Galarm), and the design
  doc `docs/designs/jess-personal-assistant-shell.md`, section `### Notifications: the 64 limit,
  decided 2026-10-07`.

## Rules

- Stay inside your worktree. Edit only files your approved plan names. Shared files
  (`CLAUDE.md`, `docs/PRODUCT.md`, `docs/PARALLEL-AGENTS.md`, `backend/package.json`,
  `backend/package-lock.json`, `backend/wrangler.jsonc`) are changed only by the lead session.
- Every piece you build gets tests that can fail for the reason they exist. Run the whole suite,
  `scripts/test-all.sh`, after every change and report results honestly.
- You may add new tests. Changing or deleting an existing test goes through the test-guardian
  agent; a hook enforces this.
- Commit small and often on your branch. Never merge into `main`; the lead session merges after
  review.
- If you are blocked on a question or an approval, ask the founder in your tab and wait.
