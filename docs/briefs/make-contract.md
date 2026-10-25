# Make: shared contract for the two builders (2026-10-24, main `9f0d8f8`)

Decisions: `docs/briefs/make.md`. Screens: `docs/mockups/make-2026-10-23.html` (Confirmed section).
Two worktrees: `agent/make-backend` and `agent/make-shell`. Each owns only the files listed in §9.
Still open with the founder (use the default, keep it in one constant/asset so it swaps in one place):
tile K5/K6/K7/K1 (default K1), status pill Q1/Q2/Q3 (default plain S2), the name the person sees for
the other side (default "Bhuvan"; "Make" recommended), the new word for "repair" (Change/Edit/Fix;
until picked, keep "Repair").

Note: the request key is `req:`, not `request:` (`shell/sdk/shell-types.js` owns `request:` in every
Sidekick, and shell types win).

## 1. Sidekick ids

- **`make`**: native, for everyone, not repairable. New `backend/src/make-sidekick.ts` like
  `jess-sidekick.ts`: `MAKE_SIDEKICK_ID = "make"`, `MAKE_LISTING = {id:"make", name:"Make",
  icon:{symbol:"plus", background:"#000000"}, reads:[], version:"built-in", builtIn:true}`. Assigned at
  sign-up (second insert next to `assignJess` in `auth.ts`, same batch); existing users by
  `scripts/assign-make-to-everyone.mjs` (copy of the jess script, `assignToEveryoneSql`).
- **`make-inbox`**: native, founder only, not repairable. `MAKE_INBOX_SIDEKICK_ID = "make-inbox"`,
  `MAKE_INBOX_LISTING` (name "Inbox", builtIn:true). Not in `assignments`: `handleListSidekicks` adds
  it when `userId === env.MAKE_FOUNDER_USER_ID`. Var per environment in `wrangler.jsonc` (lead edits).
  Staging and live each have their own inbox.
- Listing order: jess, make, make-inbox, then the rest. No bundle: `/sidekicks/:id/bundle` stays 404.

## 2. Records

Schemas: new `shell/sdk/native-types.js` (written like shell-types.js, CommonJS export at the end)
exports `MidasNativeTypes = { "make": MAKE_TYPES, "make-inbox": MAKE_TYPES }`. Server:
`record-types.ts recordProblem` checks shell types, then `MidasNativeTypes[sidekickId]`, then the
manifest. Phone: `RecordSchemaEngine` loads resource `native-types`; `RecordTypeGate.typesFor` checks
shell types, then `engine.nativeTypes[sidekickId]`, then the manifest.

Ids: reqId, msgId, cardId, optionId match `^[A-Za-z0-9_-]{8,40}$` (phone: UUID without dashes).

Person's `make` store: `req:<reqId>`, `message:<reqId>:<msgId>`, `card:<reqId>:<cardId>`,
`answer:<reqId>:<cardId>`.
Founder's `make-inbox` store: `person:<userId>`, `req:<userId>:<reqId>`,
`message:<userId>:<reqId>:<msgId>`, `card:<userId>:<reqId>:<cardId>`, `answer:<userId>:<reqId>:<cardId>`.
Every inbox record also carries `userId`. Unknown fields are kept.

| Prefix | $type | Required | Other |
|---|---|---|---|
| `req:` | `make.request` | `title` (1-200), `status`, `createdAt`, `updatedAt` | `status` in `sent`, `figuring_out`, `looking`, `building`, `built`; `sidekickId` (`^[a-z0-9-]{1,40}$`, required when built); `plan` (1-200, required when built); `builtAt` |
| `message:` | `make.message` | `from` (`person`/`maker`), `text` (1-4000), `sentAt` | |
| `card:` | `make.card` | `question` (1-300), `kind` (`choice`/`design`), `options` (1-8, each `{id, label?, image?}`), `allowsOwnWords` (bool), `sentAt` | `image` is `file:<id>`; every design option has one |
| `answer:` | `make.answer` | `cardId`, `sentAt` | exactly one of `optionId` or `text` (1-4000) |
| `person:` (inbox) | `make.person` | `name`, `firstAt` | |

Times ISO. List words: Sent, Figuring Out, Looking, Building, Built (S2: word plus 4 steps).

## 3. Copy step and write rules (new `backend/src/make.ts`, called from `sync.ts handlePush`)

`makeOpProblem(db, env, userId, op)` returns a refusal or null, after the schema check; refused ops go
into `rejected`. Deletes in `make` / `make-inbox` are refused.

`make` (owner):
- `req:<r>`: create only (refused if any op for that user+key exists); `status` must be `sent`, no
  `sidekickId`/`plan`/`builtAt`. Same opId again is fine.
- `message:<r>:<m>`: `from` = `person`; `req:<r>` exists.
- `answer:<r>:<c>`: `card:<r>:<c>` exists; first write only; `optionId` among the card's options;
  `text` only if `allowsOwnWords`.
- `card:`: refused (server only).

`make-inbox` (only `MAKE_FOUNDER_USER_ID`; others "not allowed"):
- `req:<u>:<r>`: person's `req:<r>` exists. `built` needs `sidekickId` + `plan`; `sidekickId` not
  jess/make/make-inbox; `BUNDLES sidekicks/<id>/current.json` exists.
- `message:<u>:<r>:<m>`: `from` = `maker`.
- `card:`, `answer:`, `person:`: refused.

`makeCopyStatements(...)` adds statements to the same `DB.batch` as `insertOpsStatement`. Built for
every accepted op (also already-stored ones; safe, copy ids are fixed).
- Copy op id: `"mk" + first 40 hex of SHA-256(sourceOpId + ">" + targetUserId)`; `ON CONFLICT(op_id)
  DO NOTHING` stores each copy once.
- Person to inbox: `req:`, `message:`, `answer:` to the founder's `make-inbox` under the prefixed key,
  `userId` added. First copy per person also writes `person:<userId>` (name from `users.name`, op id
  `mk-person-<userId>`, trimmed to 64).
- Founder to person: `req:<u>:<r>` to `<u>`'s `make` `req:<r>` (no `userId`); `message:<u>:<r>:<m>` to
  `message:<r>:<m>`. On `built`, same batch: `INSERT INTO assignments (user_id, sidekick_id,
  assigned_at) VALUES (?,?,?) ON CONFLICT DO NOTHING`.
- Server-written ops never pass through `handlePush` (no loops). On staging the founder is also a
  person; his own `make` records copy into his own inbox (expected).
- Files: `copyFileIfMissing(FILES, from, to, fileId)` (same httpMetadata, never overwrites), for every
  `file:<id>` in a copied record, before the batch.
- `MAKE_FOUNDER_USER_ID` unset: `make` writes stored, nothing copied, `make-inbox` writes refused.

## 4. Push

Migration `0011_make_push.sql` (additive only):

```sql
CREATE TABLE push_devices (
  token TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
  env TEXT NOT NULL CHECK (env IN ('sandbox','production')),
  bundle_id TEXT NOT NULL CHECK (bundle_id IN ('com.bhuvanrj.midas','com.bhuvanrj.midas.test')),
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, disabled_at TEXT, disabled_reason TEXT);
CREATE INDEX push_devices_by_user ON push_devices(user_id, disabled_at);
CREATE TABLE make_events (
  id TEXT PRIMARY KEY,
  audience TEXT NOT NULL CHECK (audience IN ('person','founder')),
  user_id TEXT NOT NULL, about_user_id TEXT NOT NULL, request_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('card','built','message','answer')),
  title TEXT NOT NULL, body TEXT NOT NULL,
  created_at TEXT NOT NULL, sent_at TEXT, result TEXT);
CREATE INDEX make_events_unsent ON make_events(sent_at, created_at);
```

`POST /push/register` (session), body `{token, env, bundleId}` (hex token; `sandbox`/`production`;
one of the two bundle ids). Upsert `ON CONFLICT(token) DO UPDATE SET user_id, env, bundle_id,
updated_at, disabled_at=NULL`. Returns `{ok:true}`. `backend/src/push.ts`, mounted at `/push`.

APNs sender `backend/src/apns.ts`: JWT ES256, header `{alg:"ES256", kid:APNS_KEY_ID}`, claims
`{iss:APNS_TEAM_ID, iat}`, signed with `crypto.subtle` from `APNS_KEY_P8` (pkcs8, P-256); cached,
renewed after 45 min. Secrets `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` (founder sets them).
`POST https://api.push.apple.com` or `https://api.sandbox.push.apple.com`, `/3/device/<token>`,
headers `authorization: bearer <jwt>`, `apns-topic: <bundle_id>`, `apns-push-type: alert`,
`apns-priority: 10`. Payload `{aps:{alert:{title,body}, sound:"default", "thread-id":"<userId>:<reqId>"},
make:{kind, requestId, userId, cardId?}}`. 410 or 400 `BadDeviceToken`: disable (for BadDeviceToken
try the other host once first, fix `env` if that works). 403 `ExpiredProviderToken`: new JWT, retry
once. Each outcome into `make_events.result` / `sent_at`. Sent in `c.executionCtx.waitUntil` after the
batch commits. Event row inserted ON CONFLICT DO NOTHING; push only if a row was inserted. `fetch` is
injected (tests).

First check (backend builder, before building more): one real send from staging. Workers `fetch` to
APNs needs HTTP/2. If it fails, the Mac mini runner sends unsent `make_events` rows instead.

When pushes fire (nothing else sends one):

| Event | To | Dedupe id | Title / body |
|---|---|---|---|
| New `make.card` | person | `card:<cardId>` | `<sender name>` / the question; design card: `<n> designs` |
| Request to `built` | person | `built:<userId>:<reqId>` | `<sender name>` / `<title>: Built` |
| Person's `message:` | founder | `msg:<sourceOpId>` | `Inbox` / `<name>: <text>` (120 chars) |
| Person's `answer:` | founder | `ans:<sourceOpId>` | `Inbox` / `<name>: <label or text>` |

Founder messages and other status changes send no push. `<sender name>` is one server constant
(default "Bhuvan", founder may change it to "Make").

## 5. Founder side

The inbox rides on sync: people = `person:`, requests = `req:<u>:`, thread = `message:<u>:<r>:` plus
cards and answers. Status = a write of `req:<u>:<r>`; Built = same write with `sidekickId`, `plan`,
`builtAt` (server assigns the Sidekick and pushes).
- `GET /make/sidekicks` (founder session only, else 404): `{sidekicks:[{id, name, version}]}` from every
  base `sidekicks/<id>/current.json`. Feeds the Built picker.
- Cards are made by a server path only (Claude skills use it later; no inbox UI for cards). Both take
  `requireRunner` or the founder's session:
  - `POST /make/files?userId=<u>`: raw bytes, `Content-Type`, `X-Midas-File-Id`, max 20 MB; stores
    `<founderId>/<fileId>` and copies to `<u>/<fileId>`; returns `{id, ref:"file:<id>"}`.
  - `POST /make/cards`: `{userId, requestId, cardId?, question, kind, options, allowsOwnWords}`; checks
    the request, the schema, the files; writes `card:<r>:<c>` to the person (op `mkcard-<cardId>-p`)
    and `card:<u>:<r>:<c>` to the inbox (op `mkcard-<cardId>-f`) in one batch, then the push.
    Returns `{cardId}`; same cardId again changes nothing.
  - Test script `backend/scripts/make-card.mjs --env staging`.

## 6. Repair blocked log

`0012_repair_blocked.sql`: `CREATE TABLE repair_blocked (id TEXT PRIMARY KEY, user_id TEXT NOT NULL
REFERENCES users(id), sidekick_id TEXT NOT NULL, client_id TEXT NOT NULL, app_version TEXT, app_build
TEXT, created_at TEXT NOT NULL); CREATE UNIQUE INDEX repair_blocked_client ON repair_blocked(user_id,
client_id);`
`POST /repairs/blocked` (session) `{sidekickId, clientId, appVersion?, appBuild?}`: 201
`{logged:true}`, 200 for the same clientId. `backend/src/repair-blocked.ts`, mounted at `/repairs`
before `repairRoutes`. `POST /repairs` refuses `jess`, `make`, `make-inbox` with 400 "repair not
available".

## 7. Migrations

`0011_make_push.sql`, `0012_repair_blocked.sql`. Founder applies (staging first, `docs/DEPLOY.md`).

## 8. Shell

- **Make home H1** (`MakeHomeView`): title "Make"; requests newest `updatedAt` first; row = unread dot,
  title, "last message · time", S2 status on the right. B3 pill "New Request"; Send writes `req:<r>`
  (sent, title = the words up to 200) and `message:<r>:<m>` (person), then `recordSync.syncNow()`.
- **Thread T2** (`MakeThreadView`): messages and cards in order, no status. Card = carousel swiping both
  ways; tap only selects; Send (bottom right, disabled until a pick) writes `answer:` with `optionId`;
  answered card locks with a check. B3 pill: voice starts on open, tap to type stops listening. Newest
  card unanswered and `allowsOwnWords`: pill text goes as `answer:{text}`; else as `message:`. Pull the
  pill out of `RepairChromeView` / `RepairPillTextView` into a reusable `PillBar` (repair keeps its look
  and its tests).
- **Built R2 then tile** (`MakeBuiltView`): on opening Make, a `built` request not yet shown on this
  phone plays the Built screen (tile, name, `plan`, no Open), then the tile moves and locks into its
  home grid slot (hold 1800 ms, move 760 ms, scale 2 to 1 with a 94% dip). **R3**: built card in the
  thread opens the Sidekick, small "already built" animation when first seen.
- **Inbox F1** (`MakeInboxView`): "Inbox"; people (unread count, last line) -> their requests (status)
  -> thread (cards read-only, reply pill writes `message:` from maker), status buttons Figuring Out ·
  Looking · Building · Built; Built opens a picker from `GET /make/sidekicks` plus a plan line.
- Unread state on the phone only (last seen `sentAt` per thread).
- Pull while open: Make or Inbox on screen and app active: `recordSync.syncNow()` every 3 s; screens
  refresh from `LocalRecordStore.addChangeObserver`.
- Push (`PushRegistration.swift`): after sign-in ask permission once, `registerForRemoteNotifications`,
  send `POST /push/register` on every launch. `env` from `aps-environment` in `embedded.mobileprovision`
  (`development` = sandbox, else production; not `#if DEBUG`). Both entitlements files get
  `aps-environment`. Tap: `userInfo["make"]` -> person `openMakeRequest(reqId)`, founder
  `openInboxThread(userId, reqId)`; `willPresent` syncs and shows the banner unless that thread is open.
- Swipe blocked: `RepairUnavailableSwipe.swift`, `.repairUnavailableSwipe(sidekickId:)` with a passive
  `ThreeFingerSwipeRecognizer`, on Make, Inbox and jess's screens: X2 (Volt rim flash plus toast
  "Repair not available for this Sidekick."), `POST /repairs/blocked` with a new clientId (fire and
  forget).
- `SidekickHomeGrid`: Make and Inbox tiles like jess; `MakeTile` asset (default K1).

## 9. Split

**Backend** (`agent/make-backend`): new `shell/sdk/native-types.js` (shared; backend owns it),
`backend/src/make-sidekick.ts`, `make.ts`, `push.ts`, `apns.ts`, `repair-blocked.ts`,
`migrations/0011_make_push.sql`, `0012_repair_blocked.sql`, `scripts/assign-make-to-everyone.mjs`,
`scripts/make-card.mjs`, new backend tests. Edits: `sync.ts`, `record-types.ts`, `sidekicks.ts`,
`auth.ts`, `index.ts`, `repairs.ts`. Existing tests that need changing go through test-guardian.
Lead only: `wrangler.jsonc`, secrets.

**Shell** (`agent/make-shell`): `MakeSidekick.swift`, `MakeHomeView.swift`, `MakeThreadView.swift`,
`MakeQuestionCardView.swift`, `MakeBuiltView.swift`, `MakeInboxView.swift`, `MakeLivePull.swift`,
`PushRegistration.swift`, `RepairUnavailableSwipe.swift`, `PillBar.swift`, `MakeTile` asset, new shell
tests. Edits: `SidekickHomeGrid.swift`, `MidasApp.swift`, `ShellServices.swift`,
`RecordSchemaEngine.swift`, `RecordTypeGate.swift`, both entitlements, `RepairChromeView.swift`,
`project.yml` (resource bundling only; no build number change). Until the backend lands: a copy of
`native-types.js` from this contract in the test bundle, DEBUG local `make` entry and seeds, ignore
404s from `/push/register` and `/repairs/blocked`, taps tested with `xcrun simctl push`.

Deploy order: migrations, server (staging), app with Make on TestFlight; only then
`assign-make-to-everyone.mjs --env live` (an older app treats `make` as a web page and gets 404).
