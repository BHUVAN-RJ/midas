# STAGING ONLY: do not publish this branch to live

Branch `agent/test-build-32` is a **test build for staging** (founder, 2026-11-14):
Midas Test build 32 = dictation round 3 (`agent/dictation-test`, do not merge) + `main` (repair lanes).

Any agent building on this branch:

- Builds and uploads only the **Midas Test** scheme (`com.bhuvanrj.midas.test`), archived with
  `-configuration Test`. `-configuration Release` builds the everyday **Midas** app: never archive or
  upload that from here.
- Deploys only to **staging** (`--env staging`). Never `--env live`, never a plain
  `npx wrangler deploy` (that is live), never live migrations, never live Sidekick pages.
- Never merges this branch into `main` (it carries the do-not-merge dictation test commits).
- Next build number goes up from 32 in `shell/project.yml`.

Live is the founder's, and only after staging has passed.
