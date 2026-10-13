# Brief: repair-intake (backend: reports, storage, job queue)

Read `docs/briefs/repair-contract.md` first. Dev port 8789.

Build (after the founder approves your plan):
1. Migration for `repair_reports` (and an events table if you need one). Write the migration only;
   the founder runs remote migrations (`node scripts/migrate.mjs`).
2. `POST /repairs`: signed-in user, Sidekick must be assigned to them. Text and metadata to D1,
   screenshot / drawing / strokes to R2 under `repairs/<report_id>/`, linked by id. Size limits
   (screenshot a few MB at most). Nothing goes into the op-log records (64 KB limit).
3. Runner endpoints with a dedicated runner token (Worker secret): claim with a lease and retry,
   fetch assets, update status. Choose pull (Mac polls the Worker or a Cloudflare Queue) or a
   tunnel and say why; research says pull survives the Mac being off.
4. Events for the founder (request received, fix on staging, failed) and the user's "The update
   you requested is done." once live. Founder channel is built later; record the events now.
5. Tests: a report lands as one D1 row plus its R2 objects with the same id; another user cannot
   read it; claim gives each job to one runner; an expired lease comes back; a user cannot reach
   runner endpoints.

Owns: new `backend/src/repairs.ts`, a new migration, the route mount in `backend/src/index.ts`,
new tests. Ask the lead for `wrangler.jsonc` changes (R2 binding, secret).
