# Brief: simple sign-in for the shell, 2026-10-08

You are the agent for Midas's sign-in. You work in your own git worktree on branch
`agent/sign-in`. The founder talks to you directly in your Herdr tab.

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

## What the founder decided (2026-10-08)

- **Sign-in only, kept simple.** The shell (the main Midas app, not a Sidekick) asks for one
  field, **name** (one field: no first name / last name), and has the user create a **passkey**
  (Apple's passkeys). That is all for now; everything else waits.
- This is for the main shell app. It is not part of the notification engine, which another agent
  is building on `agent/notification-engine`.

## Recorded by the notification-engine agent, not yet in `docs/PRODUCT.md`

- D2 in `docs/PRODUCT.md` says Sign in with Apple is the only identity. The founder's decision of
  2026-10-08 replaces it with name plus passkey. The lead session updates `docs/PRODUCT.md` and
  the midas-intel design doc.
- Facts to check before planning (not verified by the writer of this brief): a passkey in an iOS
  app needs the Associated Domains entitlement with a `webcredentials:` domain that serves
  `/.well-known/apple-app-site-association`; the backend must verify WebAuthn registration and
  assertion.

## What the notification engine needs from sign-in

Nothing for build 1: the engine runs on the phone with local records. Later (sync of local
records, the server-push safety net) it needs a stable user id.

## Sources to read

- `docs/PRODUCT.md` (this repo): D2 and D3, section 5.
- `CLAUDE.md` (this repo): working rules, including "Tests are guarded".
- `docs/PARALLEL-AGENTS.md`: rules for an agent in a worktree.
- `shell/` and `backend/`.

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
