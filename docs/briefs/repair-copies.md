# Brief: repair-copies (per-user Sidekick copies)

Read `docs/briefs/repair-contract.md` first. Dev port 8788.

Founder, 2026-10-13: a repair changes **only the reporter's own copy**. Today a bundle is per
Sidekick id: `sidekicks/<id>/current.json` (`backend/src/sidekicks.ts`), served to everyone
assigned it; `backend/scripts/deploy-sidekick.mjs` uploads a new immutable version and moves
that pointer.

Build (after the founder approves your plan):
1. A per-user pointer that wins over the shared one for that user only. Old versions stay.
2. `deploy-sidekick.mjs --user <user_id>` (and a way to deploy from a directory other than
   `sidekicks/<id>/`, for the runner's worktree). The live-refuses-unless-staging rule must hold
   per user. Same deploy gate (forbidden primitives, manifest).
3. A way back: point a user at the shared version again.
4. Tests: one user's copy changes, another user's page does not; no pointer → shared page;
   versions are immutable; the live rule holds for user copies.

Owns: `backend/src/sidekicks.ts`, `backend/scripts/deploy-sidekick.mjs`,
`backend/scripts/bundle-tools.mjs`, new tests. Ask the lead for anything in `wrangler.jsonc` or
`package.json`. Question to settle in the plan: does a user copy follow later shared updates
(e.g. the founder ships a new Reminders) or stay pinned until the founder merges?
