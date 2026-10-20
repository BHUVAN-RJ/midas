# Legacy sweep, agent A (backend and scripts): notes for the lead

2026-10-20, branch `agent/legacy-sweep-a`.

- No change needed to `CLAUDE.md`, `docs/PRODUCT.md`, `docs/PARALLEL-AGENTS.md`,
  `backend/package*.json` or `backend/wrangler.jsonc` from this sweep.
- Outside A's scope, seen while searching (for agent C): `runner/README.md:104` gives the failure
  detail example `(stored as task:9)`. The code comment it mirrors
  (`runner/lib/user-records.mjs`, `describeFailureKey`) now reads `<key> (stored as <stored key>)`.
- New check `backend/test/legacy-quarantine.test.ts` scans `backend/src`, `backend/scripts`,
  `backend/migrations`, `runner/lib`, `runner/bin`, `runner/tools`, `runner/install.sh` and
  `scripts/` for `task:`, `settings:sidebar`, `~rule`, `@HHMM` and "epoch ms" outside
  `record-upgrades.mjs` and `migrate-records.mjs`. Any later code that names those fails it.
- Kept on purpose (tests that assert old shapes are refused or read-ignored, not presented as
  current): `record-types-manifests.test.ts` refusal tests, `record-schema.test.ts` `task:`
  undeclared-key checks, `sync-record-types.test.ts` (server refuses `task:` writes from a typed
  version, accepts them from an untyped one), `runner-repair-data.test.ts:123` (a literal
  `store.query('task:')` read is not counted as a write) and `:224-229` (prompt must not describe
  `task:` as current). Question for the lead: should these also get the "old shapes allowed here"
  header, or be rewritten with neutral prefixes? Agent A left them.
