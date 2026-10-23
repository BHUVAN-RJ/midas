# Deploying Midas

For the founder and for any agent asked to deploy (founder, 2026-10-23). Written so each step can
later become a CI/CD job. Every command starts with `cd` into its folder: copy the whole line.

Who runs what: **staging** may be deployed by an agent when the founder asks for it. **Live** is
run by the founder only (deploys, migrations, secrets, user data on live). An agent working on live
writes out the commands for the founder; it does not run them.

## 0. The parts and where they go

| Part | Source | Goes to | Tool |
|---|---|---|---|
| Database changes | `backend/migrations/NNNN_*.sql` | D1 `midas-staging` / `midas` | `scripts/migrate.mjs` |
| Server (incl. the jess Sidekick) | `backend/src/` | Worker `midas-api-staging` / `midas-api` | `npx wrangler deploy` |
| Sidekick pages | `sidekicks/<id>/` (`index.html`, `manifest.json`, `tools.js`) | R2 bundles bucket | `scripts/deploy-sidekick.mjs` |
| Repair runner | `runner/` | the Mac mini clone `~/Library/Application Support/midas-runner/midas` | `git pull` + launchd restart |
| iPhone app | `shell/` | TestFlight ("Midas Test" = staging, "Midas" = live) | Xcode archive |

Environment names, and the one trap:

| | Staging | Live |
|---|---|---|
| Repo scripts (`node scripts/...`) | `--env staging` | `--env live` |
| Plain `npx wrangler ...` | `--env staging` | **no `--env` at all** (live is the top-level config; `--env live` fails) |
| Worker URL | `midas-api-staging.midas-backend.workers.dev` | `midas-api.midas-backend.workers.dev` |

## 1. Before any deploy

```
cd ~/Desktop/Midas/midas && git checkout main && git pull && git status --short
cd ~/Desktop/Midas/midas && scripts/test-all.sh
cd ~/Desktop/Midas/midas/backend && npx wrangler whoami
```

- `git status` must show nothing you did not mean to ship. Deploy from `main` only.
- All suites must pass. Do not deploy on a red suite.
- `whoami` must show the founder's account. If a later step says `Authentication error [code: 10000]`
  or `code: 7403`: `cd ~/Desktop/Midas/midas/backend && npx wrangler logout && npx wrangler login`.

## 2. Order (always this order)

1. **Migrations** (database first: a new server writes columns that must already exist).
2. **Server.**
3. **Sidekick pages** (only the ones that changed).
4. **Runner** (after the server: a new runner posts statuses only the new server accepts).
5. **App build** (only when `shell/` changed).

Staging first, try it, then live in the same order. Sidekick pages refuse to go live unless
staging already runs exactly the same page.

## 3. Staging

### 3.1 Migrations

```
cd ~/Desktop/Midas/midas/backend && npx wrangler d1 migrations list midas-staging --remote --env staging
cd ~/Desktop/Midas/midas/backend && node scripts/migrate.mjs --env staging
cd ~/Desktop/Midas/midas/backend && npx wrangler d1 migrations list midas-staging --remote --env staging
```

- The first line shows what is waiting. "No migrations to apply" means skip to 3.2.
- `migrate.mjs` backs up the database to `~/midas-backups/` (and R2) first, then applies; if the
  backup fails nothing is applied. Wrangler asks before applying: answer yes.
- The last line must say no migrations are waiting. If one is still listed, it did not apply:
  stop and do not deploy the server (2026-10-23: the server went out without `0010` and staging
  repairs returned 500 until it was applied).

### 3.2 Server

```
cd ~/Desktop/Midas/midas/backend && npx wrangler deploy --env staging
```

Ends with the URL `midas-api-staging...` and a version id. Note the version id (for rollback).

### 3.3 Sidekick pages (only if `sidekicks/<id>/` changed)

```
cd ~/Desktop/Midas/midas && git diff --stat <last-deployed-commit> HEAD -- sidekicks/
cd ~/Desktop/Midas/midas/backend && node scripts/deploy-sidekick.mjs reminders --env staging
cd ~/Desktop/Midas/midas/backend && node scripts/deploy-sidekick.mjs care-reminders --env staging
```

Each prints the new version and which user copies moved with it. Repaired user copies are left
alone and listed by name. A closing `✘ The specified key does not exist.` for a user with no
copy is harmless.

### 3.4 Runner (only if `runner/` changed, or after a server change it depends on)

```
cd ~/Library/Application\ Support/midas-runner/midas && git status --short && git pull --ff-only origin main && git log --oneline -1
launchctl kickstart -k gui/$(id -u)/com.midas.repair-runner
tail -20 ~/Library/Logs/midas-runner/runner.log
```

- The clone must have no local changes (`git status` empty), or the pull stops.
- One runner serves live and staging. After the restart the log shows
  `polling live ...` and `polling staging ...` and, a minute later, no `claim failed: 500`.
- If live still runs an older server than the runner expects, a live job can get stuck. Update
  live soon after, or hold the runner restart until live is deployed too.

### 3.5 App (only if `shell/` changed)

```
cd ~/Desktop/Midas/midas/shell && xcodegen generate
```

- The Xcode project is generated from `project.yml` and not kept in git: run `xcodegen generate`
  after every pull, or new files are missing from the build (2026-10-23: 43 tests never ran).
- In Xcode: scheme **Midas Test** (staging server). Run on the phone to try, or Product → Archive →
  Distribute → TestFlight.
- Every TestFlight upload needs a higher build number: `CURRENT_PROJECT_VERSION` in
  `shell/project.yml`, then `xcodegen generate` again. Both apps share it.

### 3.6 Check staging

- Open Midas Test, open a Sidekick, try what changed.
- Repair: three-finger swipe, send, and watch the runner log for
  `job <id> on staging` then `deployed_live` or `no_change`.

## 4. Live (founder)

Same order, after staging is tried.

```
cd ~/Desktop/Midas/midas/backend && npx wrangler d1 migrations list midas --remote
cd ~/Desktop/Midas/midas/backend && node scripts/migrate.mjs --env live
cd ~/Desktop/Midas/midas/backend && npx wrangler d1 migrations list midas --remote
cd ~/Desktop/Midas/midas/backend && npx wrangler deploy
cd ~/Desktop/Midas/midas/backend && node scripts/deploy-sidekick.mjs reminders --env live
cd ~/Desktop/Midas/midas/backend && node scripts/deploy-sidekick.mjs care-reminders --env live
```

- No `--env` on plain wrangler commands for live (table in section 0).
- Runner: already updated in 3.4 (one runner for both). Check its log shows no live errors.
- App: scheme **Midas**, archive, upload to TestFlight. Internal testing first.

One-off steps that come with some releases (check the release's brief):

```
cd ~/Desktop/Midas/midas/backend && node scripts/assign-jess-to-everyone.mjs --env live
cd ~/Desktop/Midas/midas/backend && node scripts/assign-sidekick.mjs "<user name>" <sidekick-id> --env live
cd ~/Desktop/Midas/midas/backend && npx wrangler secret put JESS_GROW
```

Secrets: `wrangler secret put <NAME>` (add `--env staging` for staging) asks for the value.
Never put a secret in a file, a command line, a commit or a chat.

## 5. If something goes wrong

| Problem | Do |
|---|---|
| Server deploy broke something | `cd ~/Desktop/Midas/midas/backend && npx wrangler rollback --env staging` (live: no `--env`) goes back to the previous version |
| A migration was applied by mistake | Do not try to undo it with SQL. Stop and tell the founder; the backup from `migrate.mjs` is in `~/midas-backups/`. Restoring a database is the founder's call |
| A Sidekick page is broken | Old versions stay in R2. Check out the last good commit's `sidekicks/<id>/` and deploy it again with `deploy-sidekick.mjs`. One user's repaired copy back to the base: `deploy-sidekick.mjs <id> --env <env> --user <user-id> --from-base` |
| `Cannot find module '.../shell/scripts/...'` | You are in the wrong folder. Use the full line with `cd ~/Desktop/Midas/midas/backend &&` |
| `Authentication error [code: 10000]` / `7403` | `npx wrangler logout && npx wrangler login` (in `backend/`) |
| Runner `claim failed: 500` | The server it talks to is failing: check that environment's migrations (3.1) and deploy |
| New app files not in the build | `cd ~/Desktop/Midas/midas/shell && xcodegen generate` |

## 6. Toward CI/CD

Each numbered step above is one job. What a pipeline needs:

- **Test job:** `scripts/test-all.sh` on a macOS runner (the shell suite needs Xcode and a
  simulator).
- **Cloudflare token** with D1, Workers and R2 write as a CI secret (replaces `wrangler login`).
- **Migrations job:** `migrate.mjs` asks before applying; CI needs a non-interactive form, and the
  backup's `~/midas-backups/` copy must go somewhere CI can keep.
- **Gate:** staging jobs run on push to `main`; live jobs run only on the founder's manual approval.
- **Runner:** stays a manual step, or a scheduled `git pull` + restart on the Mac mini.
- **App:** `xcodebuild archive` + upload needs the signing certificate and an App Store Connect API
  key in CI.
