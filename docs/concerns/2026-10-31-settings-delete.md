# Concerns: Settings and delete (2026-10-31)

Founder approved 2026-10-31 (build 22 brief, `docs/briefs/build-22-2026-10-31.md`, settings-delete row).
Built on `agent/settings-delete` as `df563db`, merged to main as `36caec1`. Mockup:
`docs/mockups/settings-delete-2026-10-31.html`. Full suite passed at `df563db` (backend 1199,
shell 1056, midas-intel 31). Not tried by hand on a simulator or device.

What it does: initial circle top right of home → Settings (name, Sidekicks, Sign Out, Delete
Account). Press and hold a tile → jiggle and minus badge → "Delete Water?". Delete Account → alert →
"Your account will be deleted within 7 days." → welcome. Server: `DELETE /sidekicks/:id` (marks the
assignment removed, appends delete ops, logs `sidekick_removals`), `POST /account/sign-out`,
`POST /account/delete-request` (records `account_deletion_requests`, expires sessions, pushes the
founder). Nothing is deleted in D1; the founder carries out account deletions.

## Open

- **Deploy: migration 0013 first.** `backend/migrations/0013_settings_delete.sql` must be applied
  (staging, then live) before this Worker version goes out; the Worker reads `assignments.removed_at`.
  Picked up at the deploy step, by the lead. Command:
  `cd ~/Desktop/Midas/midas/backend && node scripts/migrate.mjs --env staging`.
- **Sign-in after a deletion request still works.** During the 7 days the person can sign in again
  with their passkey; a second request is ignored (200, no second push). Founder decides whether
  sign-in should be refused.
- **Other per-account local files are not wiped.** Delete Account and a different account signing
  in clear only the records store (`LocalRecordStore`, now with an owner) and the Sidekick list.
  jess result cards, the repair centre's files and Make's files stay on the phone.
- **Files and per-person copies stay after deleting a Sidekick.** Its R2 FILES and the person's R2
  copy of the bundle remain (founder cleanup). Re-assigning brings back their copy, not their data.
- **Founder scripts and removed assignments.** db-tools `assign-sidekick` / `assign-to-everyone` use
  `INSERT OR IGNORE`, so they do not bring back a Sidekick the person deleted (only Make's Built
  does, via `ON CONFLICT ... SET removed_at = NULL`). `deploy-sidekick` and `plan-user-copies` read
  assignments without `removed_at IS NULL`, so they keep updating copies for people who deleted it
  (harmless, wasted work).
- **Founder push tap does nothing.** The account-deletion push carries
  `founderAlert: {kind: "account-deletion", userId}`; the shell ignores it on tap.
- **Tile taps changed from NavigationLink to a tap gesture** (`SidekickHomeGrid.swift`), so no
  pressed highlight. Long press inside the scroll view not checked on a device: confirm scrolling
  is not blocked.
- **Sign Out offline.** Sign Out syncs first, best effort. If it fails and a different account then
  signs in on the same phone, changes that never reached the server are lost (store erased on owner
  change).
- **Inbox cannot be deleted** (default taken, with jess and Make). Not in the brief.
- **Full suite command shape.** The test guard blocks `scripts/sim.sh run scripts/test-all.sh`
  as typed; it was run through a scratchpad wrapper that calls `./scripts/test-all.sh` from the
  worktree root. Guard files change only by the founder.
