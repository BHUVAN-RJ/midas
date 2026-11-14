# Hand-back: W7 Publish first (`agent/repair-publish-first`), 2026-11-13

Brief: `docs/briefs/repair-lanes.md` W7. Decision: `docs/PRODUCT.md`, "Plan additions, 2026-11-13:
repair lanes", "Publish first". Stage: testing only (full suite, `wrangler dev` on 8796). Nothing
deployed. Built on main with W4 merged (431fcc7).

## Result: report → the person has the fix

| Request | Today (runner logs, live) | Publish first (estimate, see below) | Measured on `wrangler dev` |
|---|---|---|---|
| Colour, "make the text white" `92fb0f86` | 107.7 s | ~64 s | checks + flip 0.69 s after the agent (today's way, same files: 24.2 s) |
| Hide, "remove the search feature" `2da2e6b0` | 90.5 s | ~60 s | 0.67 s (today's way: 20.4 s) |
| Small feature, "add a plus button" `c3d1cdf8` | 292.9 s | ~235 s | 0.68 s (today's way: 20.0 s) |

The estimate is today's own setup and agent times from the logs (unchanged by W7) plus what was
measured here: pickup 1.0–1.2 s (long poll), gate + shield fast part + copy tests 0.66–0.78 s with
the upload alongside (0.04–0.06 s), pointer flip 0.01 s, status 0.01 s. The upload and flip go to
Cloudflare R2 through the Worker on staging; not yet measured there (local Worker, local R2 here).
The agent is now most of the time; the rest that remains is setup (12–18 s, below).

### Publish first, per step, `wrangler dev` (`runner/tools/time-publish.mjs`)

| Step | `92fb0f86` | `2da2e6b0` | `c3d1cdf8` |
|---|---|---|---|
| Pickup (report sent → long poll wakes → claimed) | 1.23 s | 1.01 s | 1.02 s |
| Upload through the Worker (alongside the checks) | 0.06 s | 0.04 s | 0.04 s |
| Gate + shield fast part (old and new page in parallel) + copy tests | 0.68 s | 0.66 s | 0.66 s |
| Pointer flip (Worker checks the files' hash first) | 0.01 s | 0.01 s | 0.01 s |
| Status live (person told) | 0.01 s | 0.01 s | 0.00 s |
| **Person has it, after the agent** | **0.69 s** | **0.67 s** | **0.68 s** |
| After: shield slow part (taps over 3 WebKit programs per page, widget) | 3.10 s | 4.30 s | 3.31 s |
| Today's way on the same files: gate + whole shield + tests, then 16–18 `wrangler --local` calls | 10.0 + 14.2 s | 8.8 + 11.6 s | 7.7 + 12.3 s |

(Against Cloudflare today's upload was 42.8 / 16.7 / 33.9 s; `--local` has no network.)

### Forced slow-check failure, rolled back (`--force-slow-failure`, `wrangler dev`)

A script that throws after a tap on "go-search" was put inside the page's own script on `92fb0f86`:

```
upload (alongside the checks) | 0.01 s | 0.04 s
checks before publish         | 0.01 s | 0.78 s     fast part passes: the fault is behind a tap
pointer flip                  | 0.79 s | 0.01 s
status: live (the person is told) | 0.79 s | 0.01 s
checks after publish          | 0.80 s | 3.26 s
roll back                     | 4.06 s | 0.01 s
mark failed                   | 4.07 s | 0.01 s
rolled back: shield page-views: the view after a tap on "go-search": uncaught: Error: search broke
the person's copy now: the version they had before (read back from the Worker)
```

The person had the broken version for 3.3 s. The repair is `failed` (reason "rolled back"); the
founder gets the `failed` event and the edit-failed push (existing flow), the Mac a "Rolled back"
notification.

## What was built

**Worker** (`backend/src/repair-publish.ts`, runner token only, acts only on the report's own user
and Sidekick):
- `POST /repairs/:id/publish/files {version, files}`: stores page, manifest, tools.js, tests under
  the person's prefix; nothing points at them yet. Names and content types decided by the Worker;
  a version ever pointed at is immutable (409).
- `POST /repairs/:id/publish/pointer {version, pointer}`: checks the stored files hash to
  `contentHash` (the read-back, done before the flip), writes `version.json` (with the pointer it
  replaces and the report id) and then `current.json`.
- `POST /repairs/:id/publish/rollback {version, reason}`: puts back the replaced pointer (or removes
  it when there was none: the person gets the base again), only while the person is still on that
  version (a later repair is never undone); writes `rolled-back.json`.
- `GET /repairs/jobs/wait?seconds=…` (≤25): long poll; answers the moment a job can be claimed.
  Runs the claim's sweeps (expired leases, unanswered cards) first.
- `repairs.ts`: `deployed_live → failed` allowed only with `rolledBack: true`; the sweeps moved into
  an exported `sweepBeforeClaim`. `index.ts` mounts the routes.

**Runner:**
- `runner/lib/publish-first.mjs` (new): `planVersion` (the checkout's `bundle-tools.mjs`
  `planDeploy`, same version name and hashes as `deploy-sidekick.mjs`), `publishFirst` (upload ∥
  checks, flip only after both), `afterPublish` (slow checks; fail or cannot run → roll back, mark
  failed), step timer.
- `runner/lib/run-job.mjs`: `publishRepairFirst` after the runner's own records check, when
  `settings.publishMode` is `first`. Writes `timings.json` / `timings.md`, `shield.txt` (fast) and
  `shield-after-publish.txt` (slow) to the log folder. The old path (checkRepair + wrangler deploy)
  stays for `MIDAS_RUNNER_PUBLISH=wrangler` and for settings built by hand (every older test).
- `runner/lib/config.mjs`: `publishMode` from `MIDAS_RUNNER_PUBLISH` (`first` default, `wrangler`).
- `runner/lib/check.mjs`: `checkBeforePublish` (gate, then shield fast part ∥ copy tests),
  `checkAfterPublish` (shield slow part), `prepareShield`.
- `runner/core-checks/shield.mjs`: `part: "fast" | "slow" | "all"` (`PART_CHECK_IDS`); old and new
  page open in parallel; the slow part's taps shared over 3 WebKit programs per page. `all` is W1's
  behaviour (its 37 tests unchanged and passing).
- `runner/core-checks/page-open.mjs`: `openPage({ kinds })` runs only the first view, the widget
  step or the tapped views.
- `runner/lib/loop.mjs`, `runner/bin/runner.mjs`: the loop waits on `waitFromEnvironments` (every
  environment's long poll at once; the first ready one wins); falls back to the 30 s poll when every
  wait fails (an older Worker). The shield's WebKit program is compiled at start.
- `runner/lib/backend.mjs`: `waitForJob`, `publishFiles`, `flipPointer`, `rollBackPointer`.
- `runner/tools/time-publish.mjs` (new): the timing run above; reusable on staging.

**Person's notes line (W4 item 9):** kept before the upload, not moved after the publish. It lives
in `tests/PERSON_NOTES.md`, which travels inside the version, and a published version never changes:
written after the flip it would never reach the copy. It takes about 1 ms, so it does not delay the
person. A rolled-back version takes its line with it.

## Tests (new files; each check shown failing with its guard removed)

- `backend/test/repair-publish-route.test.ts` (14): the Worker routes. With the hash check or the
  "moved on" check removed, 2 fail.
- `backend/test/runner-publish-first.test.ts` (19): timer, publishFirst, afterPublish, planVersion,
  shield parts (one in real WebKit: a fault behind a tap passes fast, fails slow), check split,
  end to end through the Worker in process with real WebKit (roll back puts the person back), long
  poll. Six mutations (flip despite refusal, upload before checks, no roll back, tests after the
  shield, fast part opens every view, loop ignores the long poll): each fails 1–4 tests.
- `backend/test/runner-publish-first-run-job.test.ts` (4): runJob in publish-first mode. Mutations
  (no roll back result, always the old path, no notes line): each fails 1–3 tests.

Full suite (`scripts/test-all.sh` in this worktree, 2026-11-13, after merging origin/main with W4
and the last code change, setup included): ALL SUITES PASSED. Guard OK; backend 171 files, 1846
tests; shell 1301 tests, 0 failures; midas-intel OK. (One earlier run failed the shell suite while
another session held the simulator; this branch changes no shell file.)

## How to try it

```
cd ~/Desktop/Midas/midas-worktrees/repair-publish-first/backend && npx vitest run test/repair-publish-route.test.ts test/runner-publish-first.test.ts test/runner-publish-first-run-job.test.ts
```

Timing run on `wrangler dev`, with a scratch state folder `S`:

```
cd ~/Desktop/Midas/midas-worktrees/repair-publish-first/backend
npx wrangler d1 migrations apply midas --local --persist-to $S
H=$(printf 'local-user-token' | shasum -a 256 | cut -d' ' -f1)
npx wrangler d1 execute midas --local --persist-to $S --command "INSERT INTO users (id, name, created_at) VALUES ('localperson', 'Local', 'now'); INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES ('$H', 'localperson', 'now', 99999999999999); INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES ('localperson', 'todo', 'now');"
# the person's current copy: sidekicks/todo/{index.html,manifest.json,tools.js} put under
# midas-bundles/sidekicks/todo/users/localperson/<version>/ plus a current.json naming <version>
# (npx wrangler r2 object put … --local --persist-to $S)
npx wrangler dev --port 8796 --persist-to $S --var REPAIR_RUNNER_TOKEN:local-runner-token
```

then from the worktree root
`node runner/tools/time-publish.mjs --backend http://localhost:8796 --runner-token local-runner-token --user-token local-user-token --persist-to <state> 92fb0f86 2da2e6b0 c3d1cdf8`
(add `--force-slow-failure` for the roll back). Uses this Mac's runner logs.

## What the lead must add

1. **Deploy order:** the Worker (new routes) to staging before the runner runs this code; the
   runner defaults to `MIDAS_RUNNER_PUBLISH=first` and a Worker without the routes fails the
   publish ("publish files failed: 404"). Set `MIDAS_RUNNER_PUBLISH=wrangler` in
   `~/.midas-runner/env` for live until live's Worker has the routes. No migration, no
   `wrangler.jsonc` or `package.json` change, no new secret.
2. **Long poll cost:** while idle, each environment's Worker reads D1 once a second (one
   `SELECT … LIMIT 1`), about 86,000 reads a day per environment.
3. **Staging run:** time the same three requests on staging (the tool takes any backend URL) for
   the Cloudflare numbers of upload and flip.

## Open questions

1. **A failed roll back** (the Worker unreachable right after the publish) leaves the broken copy
   live and the repair `deployed_live`; the Mac gets "ROLL BACK FAILED, broken copy live". The
   founder push only goes with a `failed` status. Retry the roll back, or something else?
2. **The phone after a roll back:** the person was told "done", then gets Couldn't Fix. A page
   already open keeps the rolled-back version until it reloads (shell work, not W7's).

## Setup (added after the first hand-back)

Setup was 12–18 s, most of it `fetch-sidekick-copy.mjs` running one `wrangler r2 object get
--remote` per file (~11). Now, in publish-first mode:
- `GET /repairs/:id/copy-tests` (Worker, runner token, claimed report only): the tests stored with
  the version the person has (own copy, else the base), one request; 409 when the index names a
  file that is not stored.
- `copy-tests.mjs fetchCopyTestsThroughWorker` (same rules as the script path: bad name throws, no
  stored test → the base Sidekick's from the checkout); `run-job.mjs copyTestsFor` uses it when
  `publishMode` is `first`, the script otherwise.
- `run-job.mjs downloadReport`: the six report files download at the same time.
- When the Worker cannot serve the tests (no route, an error), the fetch script still does; the
  fetch output in the log folder says why.

On `wrangler dev`: copy tests 0.04–0.10 s (7 files); the six downloads 0.03–0.48 s at once against
0.08–0.59 s one after another. Expected setup on Cloudflare: about 1–2 s instead of 12–18 s (not
measured on staging yet). That makes the estimates above about 11–16 s lower: ~49 s, ~48 s, ~218 s.

Tests: `backend/test/runner-publish-first-setup.test.ts` (6). Mutations: always the fetch script,
downloads one after another, no missing-file guard: each fails 1 test.

## Not done (needs files outside W7 or a decision)

- **The notice reaches the phone on its 15 s poll** (`RepairCenter.pollSeconds`), avg 7.5 s after
  `deployed_live`; a push on `deployed_live` would remove it (shell + push).

## Phase 1: where a repair's time goes today

Sources: every runner log folder in `~/Library/Application Support/midas-runner/log` (57 jobs,
2026-10-16 to 11-13; step times from the files each step writes), plus the new shield steps timed
on this Mac on the real before/after files of the three requests below (the shield is not yet
called by `run-job.mjs`). Records: 12 To-Do records made with the copy's own tools.

### The three requests (all To-Do, live)

| Step | Colour: "make the text white" `92fb0f86` | Hide: "Remove the search feature from the bottom" `2da2e6b0` | Small feature: "add a plus button" `c3d1cdf8` | How it runs today |
|---|---|---|---|---|
| Pickup (report sent → runner claims) | 2.2 s | 15.6 s | 25.0 s | runner polls every 30 s |
| Setup (download report, fetch copy's tests, job folder, prompt) | 18.4 s | 12.5 s | 18.2 s | ~11 `wrangler r2 object get --remote`, one process each |
| Agent | 42.6 s | 44.3 s | 214.2 s | Claude Code, Opus |
| Tests compare + outcome | 0.8 s | 0.8 s | 0.8 s | |
| Deploy gate | 0.02 s | 0.00 s | 0.00 s | timed here |
| Shield: tools before/after | 0.04 s | 0.02 s | 0.02 s | timed here (not yet wired) |
| Shield: settings engine, records fit, primitive blocks | 0.01 s | 0.00 s | 0.00 s | timed here |
| Shield: page opens, first view + widget, old and new in parallel | 1.6 s | 1.0 s | 0.9 s | timed here |
| Shield: page opens, every view (12–14 taps), old then new | 20.0 s | 17.5 s | 15.2 s | timed here; how W1 runs it today |
| Copy's own tests (sandboxed vitest) | 0.5 s | 0.5 s | 0.4 s | runner log |
| Records fit (publish step's own) | 0.4 s | 0.2 s | 0.4 s | runner log |
| Upload + pointer + read back | 42.8 s | 16.7 s | 33.9 s | 13 puts + 2 gets + 1 D1 query + read-back get, one `wrangler --remote` process each, in a row |
| Summary, status, notices | 0.0 s | 0.0 s | 0.0 s | |
| Notice reaches the phone | avg 7.5 s | avg 7.5 s | avg 7.5 s | phone asks every 15 s (`RepairCenter.pollSeconds`) |
| **Total, report → live** | **107.7 s** | **90.5 s** | **292.9 s** | |
| Total once the shield is wired as W1 left it | ~129 s | ~109 s | ~309 s | adds the 15–20 s page taps before publish |

### All 31 published repairs

| Step | Median | Slowest tenth | Range |
|---|---|---|---|
| Pickup | 20.9 s | 30.0 s | 1.3–188.9 s |
| Setup | 20.6 s | 26.9 s | 10.6–29.4 s |
| Agent | 88.2 s | 277.5 s | 32.4–371.3 s |
| Gate + copy tests + records | 1.6 s | 2.2 s | |
| Upload + pointer + read back | 25.3 s | 39.1 s | 13.1–53.5 s |
| Total | 161.0 s | 355.0 s | 90.5–430.7 s |

One `wrangler` call costs about 0.9 s locally (`--local`, no network) and 1.5–3 s against
Cloudflare. Pickup, setup and upload are about 67 s of a median 161 s, all of it waiting or
starting `wrangler`; the checks that protect the person are under 3 s.
