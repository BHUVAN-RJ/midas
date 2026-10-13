# Repair: shared contract for the four repair agents (2026-10-13)

Feature: `docs/PRODUCT.md` section 2, "Plan additions, 2026-10-13: repair". Hosting research:
midas-intel `docs/research/2026-10-13-repair-agent-hosting.md`. Enhancements (not now):
`docs/ENHANCEMENTS.md`.

Flow: user scribbles (2-3 zigzags, anywhere) in a Sidekick → screen freezes into a drawing layer
→ user draws and speaks (transcribed on the phone; audio never leaves it) → Send → backend stores
the report (D1 row + R2 objects, linked by report id) and queues a job → the founder's Mac mini
pulls the job, runs Claude Code (founder's Max subscription, not an API key) in a folder that
holds only that Sidekick, runs the gate and tests, and stops at **fix ready** → founder is notified
of the request and of the fix → founder deploys it **live, to the reporter's own copy** → the user
gets a notification "The update you requested is done." The user gets no report.

| Agent (tab, branch `agent/<name>`) | Owns |
|---|---|
| `repair-copies` | Per-user Sidekick version pointers (backend + deploy script) |
| `repair-intake` | Report endpoint, D1 tables, R2 storage, job queue for the Mac, founder/user notification records |
| `repair-shell` | Gesture, drawing layer, on-device transcription, upload (iPhone shell) |
| `repair-runner` | Mac mini runner, Reminders repair agent prompt, intel tool, repair log |

## Settled (founder, 2026-10-13, after the plans)

- **No staging for Sidekick user copies.** Staging has its own accounts, so a reporter's user id
  does not exist there. A fix goes to the live bucket as the reporter's per-user pointer only;
  the "live refuses unless staging matches" rule applies to base deploys, not user copies.
- **The runner never deploys.** It stops at `fix_ready`. The founder runs
  `deploy-sidekick.mjs <id> --env live --user <uid> --dir <job folder>` (built on
  `agent/repair-copies`, `530095c`).
- **Status chain:** `received → queued → running → fix_ready → deployed_live | failed`.
- **R2:** reports under the `repairs/<report_id>/` prefix in the existing BUNDLES bucket; no new
  bucket.
- **Transcript required:** an empty transcript is rejected (400).
- **User copy layout** (repair-copies): `sidekicks/<id>/users/<uid>/<version>/` plus
  `current.json`; the first bundle load copies base into the user's folder; header
  `X-Midas-Bundle-Scope: user|base`; `--from-base` resets a user to base.
- Gesture sample: `docs/briefs/repair-gesture-sample-2026-10-13.json` (general shape; tuned on
  phone captures after the first build).

Open, one answer needed for intake and runner together: who marks `deployed_live` (the deploy
script posts it, or a separate `mark-live` command), and where the fixed page sits for the
deploy (Mac mini job folder, or uploaded through intake so any laptop can deploy).

Proposed interfaces (each agent may propose changes in its plan; the founder approves):

- **Per-user pointer.** R2 `sidekicks/<id>/users/<user_id>/current.json`, same shape as
  `sidekicks/<id>/current.json`. The bundle route serves the user's pointer if present, else the
  shared one. `deploy-sidekick.mjs <id> --env staging|live --user <user_id> [--dir <path>]`.
- **Report.** `POST /repairs` (signed-in session), multipart: `sidekickId`, `kind` hint (`bug` |
  `change` | unknown), `transcript` (text, with word timings if the phone gives them), `strokes`
  (JSON, points `[x, y, ms]` in screen points), `screenshot` (PNG/JPEG), `drawing` (PNG, the
  strokes rendered over the screenshot), `bundleVersion` the user was on, device and app version.
  D1 `repair_reports` row: id, user_id, sidekick_id, bundle_version, transcript, kind, status,
  created_at, R2 keys. R2: `repairs/<report_id>/screenshot.png`, `drawing.png`, `strokes.json`.
- **Status.** `received → queued → running → fix_ready → deployed_live` or `failed`
  (with reason). Every repair is kept: this table is the repair log; classification comes later.
- **Job pull for the Mac.** Mac pulls with a dedicated runner token (not a user session):
  `POST /repairs/jobs/claim` → one report or none (lease), `GET /repairs/<id>/assets/<name>`,
  `POST /repairs/<id>/status`.
- **Notifications.** The founder notification channel is built later (founder, 2026-10-13); for
  now the backend records an event per request and per fix and the runner surfaces it on the
  Mac (macOS notification). The user notification is a `reminder:`-style record or a shell
  notification once the fix is live; exact mechanism in the plans.

Rules for every repair agent: plan first, post the plan, **wait for the founder's approval before
writing any code**; questions go to the founder in the plan. Then follow `docs/PARALLEL-AGENTS.md`
(own worktree, own files, own dev port, small commits, full suite `scripts/test-all.sh`, every
feature gets a test that can fail for the reason it exists). Read `CLAUDE.md`, `docs/PRODUCT.md`,
`docs/WRITING.md` (any words on screen) first. Never deploy live; never run deleting statements
against a remote database.
