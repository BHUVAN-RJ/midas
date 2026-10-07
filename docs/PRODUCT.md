# Midas: what is being built

State as of 2026-10-07, including the 2026-10-06 bets and falsifiers. Decisions are dated; where two decisions conflict, the later one wins.

## 1. What Midas is

A person asks for a small personal app in their own words. Midas builds it, deploys it
privately (no public URL, no directory, no listing) and keeps it working. The apps run inside
one iPhone app, the shell, and their data lives on the Midas backend.

Three names, not to be mixed up (decided 2026-10-04):

- **Midas** is the platform: the app builder, the iPhone shell and the backend. This is the product.
- **Sidekicks** are the mini apps Midas builds and hosts. Each is narrow, one per problem, owned
  by the person who asked for it.
- **jess** is the assistant, an interface layer on top of Midas. Demoted, to be returned to later.

## 2. Dates and builds

| Date | Event |
|---|---|
| Thu Oct 8 | Build 1 submitted. Internal TestFlight only (up to 100 internal testers, no review). |
| Oct 13 | Link live (a16z Tech Week). Runs on internal testers. |
| Thu Oct 22 | Build 2 submitted. |
| Oct 21 to 27 | Cost probe; reported Oct 28. |
| Nov 2 | VC application. The goal is real users using the product, not a demo. |

External TestFlight and Beta App Review come after Oct 8 (decided 2026-10-04). Build 1 has no
slack. Any addition before Nov 2 must name the item it displaces.

Review fallback (2026-10-06): if build 2 or any resubmission is still in review on Nov 2, the
product runs on internal TestFlight only. Beta App Review clearing is an upgrade, never a
dependency.

### Build 1 (submitted Thu Oct 8)

Changed on 2026-10-04: the founder asks each friend what they need, writes the Sidekick by hand
and deploys it to them. The generator is built after this, against the evidence of what people
actually asked for.

Ships:

1. SwiftUI shell: one WKWebView per Sidekick behind a WKURLSchemeHandler, so bundles get a real
   origin; CSP; minimal native surface with no API bridge.
2. Three hand-written Sidekicks: **reminders, calendar, birthdays**.
3. Cross-app read with consent: the calendar shows reminders and birthdays (see section 5).
4. Notifications: the shell-side reminder watcher schedules local notifications from app data.
5. Identity: Sign in with Apple only.
6. Per-Sidekick tokens: short-lived, issued by the shell, scope enforced server side.
7. Op-log server: ops table, dedup on op_id, server-assigned sequence, cursor sync, claim.
8. Private deploy: no public URL, no directory, no listing.
9. Anonymous usage metrics (section 5).

Not decided for build 1: whether the assistant surface (text field, status line, launcher) and
snapshot-on-generate stay in build 1 now that the generator has moved out; whether every
friend gets all three Sidekicks or the founder assigns them per person (that needs one small
assignments table); the shed order if build 1 runs over. Proposed shed order, not yet
answered: the birthdays Sidekick first, then the consent screen becomes a plain system alert,
then metrics shrink to open events only.

### Must land after Oct 8 and before Nov 2

- **Generator**: typed request to bundle, deploy gate, launch. Generation and editing on Claude
  Sonnet 5, estimated 3k input and 6k output tokens per app (to be checked against real usage).
- **App editing in place**: regenerate with the previous bundle as context, op log preserved.

Not decided: whether these ship inside the build 2 submission or separately.

### Build 2 (submitted Thu Oct 22)

1. Op-log client persistence and replay, so offline is native.
2. APNs: key, device-token registration, push service.
3. Sharing, fork mode: universal link, recipient path (TestFlight, then deferred deep link),
   copied bundle, new group.
4. Sharing, shared mode: members, share.members, share.mode, server-side push fan-out triggered
   by app data, plus a report button and an owner-side block (guideline 4.7.1).
5. The Amazon order pooler (a shared Sidekick that uses store.claim).

Shed order if build 2 slips: shared mode, then the pooler, then the hosted landing page.
Oct 23 to Nov 1: testers use the apps and the application is written from real numbers.

## 3. Scope for v0

In:

- Hand-written Sidekicks in build 1; generated and edited Sidekicks before Nov 2.
- Cross-app **read** between Sidekicks, with user consent (in as of 2026-10-04). It is the only
  cross-app connectivity that is in.
- Shell-owned notifications driven by `reminder:` records.
- Sharing to named people (fork and shared modes) in build 2.
- Offline-native storage in build 2.

Out (down the line, not v1 and not v2):

- Assistant-driven app actions. The assistant builds and edits Sidekicks; it does not drive
  them. The manifest's "actions the assistant may call" field is removed from v0.
- Cross-app writes or actions. The owning Sidekick is the only writer of its record types.
- Siri exposure and MCP exposure of Sidekicks, and reaching the generator from an outside
  assistant. All need the manifest action layer first.
- Outside service connectors (for example Gmail), device data connectors, widgets.
- A rollback interface for users (2026-10-04).
- Voice input (typed only), metering and billing, any public directory or URL, capability
  prompts, per-member roles and member removal, generated icons in build 1, screenshot-to-fix.
- Any feature that shows, exports or edits source code, or suggests a Sidekick can leave the
  shell as a standalone app.

## 4. Product principles (2026-10-06)

- **App lifespan is a spectrum.** Some Sidekicks are thrown away after their purpose (a trip
  planner), some need years of upkeep. Users never label an app disposable or durable; use
  decides. No new mechanism: an idle Sidekick is a row, upkeep is paid once at the SDK level,
  and the append-only log with versioned bundles lets a finished app come back.
- **Where a Sidekick lives is the user's choice** (home screen, messenger thread, agent chat or
  the shell). It should exist where the user wants it, not ask for attention, and do its job
  exactly the way the user wants.
- **Apps for persistent personal behaviour; agents for the one-off and cross-system glue.**
  Natural-language input inside an app ("remind me at 3pm tomorrow") is baseline behaviour, not
  an agent. Today the agent in Midas is the generator.
- **Personalizing an app must be as easy as installing one.** Growth is word of mouth: a
  Sidekick personal enough to one person gets shared with their friends.
- **The happy place:** the app the user asked for after the request plus one edit.

Falsifiers, checked Nov 1 (from tester data):

| Bet | Alive | Dead |
|---|---|---|
| Word of mouth is the growth mechanism | 10 Sidekicks shared or 10 users acquired through sharing (5 is the floor) | Not yet set (proposed: zero unprompted shares) |
| Apps, not agents, for persistent behaviour | Testers ask for trackers, lists, reminders, votes and edit them | Testers mostly ask for "do it for me" behaviour inside their apps |
| Two iterations reach the happy place | Median tester keeps using an app within one edit of the first generation | Most apps need 3+ edits or are abandoned after the first |

## 5. Architecture

**Shell (iPhone).** SwiftUI plus WKWebView. Sidekicks are HTML5 mini apps hosted under
guideline 4.7: the shell loads no native code and exposes no native platform APIs to them
(transport reversal, 2026-09-26). Store text, review notes and UI must not say app builder, app
maker, native iOS apps, code export or App Store submission; the vocabulary is Sidekicks.

**Transport.** Sidekicks call the backend with ordinary HTTPS fetch, carrying a short-lived
token issued by the shell. No WKWebView message-handler bridge. A leaked token is limited by
short expiry, shell-side reissue and server-side scope the client cannot widen.

**Contract enforcement.** The generator prompt forbids imports, script tags, frameworks and any
network call not made through the SDK (guidance). The deploy gate rejects `import`, `require`,
`script src` and `WebSocket`. At runtime, CSP pins `connect-src` to the platform origin and
`script-src` to a per-deploy sha256 hash.

**Backend** (confirmed 2026-10-04, live 2026-10-05). Hono on Cloudflare Workers. D1 holds the
op log and group membership: one database with a `group_id` column, not one database per
group. R2 holds Sidekick bundles and snapshots. The host may change later; Hono runs on any.
Rule from the infrastructure section: a Sidekick is a row, not a deployment, and the cost of an
idle Sidekick must approach zero.

**SDK v0** (nine calls, revised 2026-09-26): `store.get`, `store.set`, `store.query`,
`store.delete`, `store.claim`, `user.me`, `time.now` in build 1; `share.members`, `share.mode`
in build 2. Query is prefix or single-field equality only, no operators, sort or pagination;
tombstones are excluded. `time.now` is display only. `store.claim(key)` succeeds for exactly one
caller, decided server side by sequence order.

**Data model and store.** Every write is an op with a client-generated id, deduped server
side, applied last-write-wins per key, ordered by server-assigned sequence (client timestamps
are display only). The namespace key is the share-group id. One user-scoped store per person
with group namespaces inside it, never separate physical stores per app. The store is
eventually consistent. Every Sidekick keeps all its data through the SDK: no localStorage, no
IndexedDB. Records are keyed `type:id` with a plain JSON value, for example `birthday:7f3a`.

**Cross-app read** (2026-10-04). Each Sidekick has a manifest: id, name, icon (SF Symbol name
plus background color) and a `reads` list of record types it wants from other Sidekicks, for
example calendar `reads: ["reminder", "birthday"]`. The shell, never the Sidekick, shows the
consent screen, generated from that list, at the moment the access is first needed. A token's
scope is a list of grants, enforced outside the Sidekick's code. Editing a reminder shown on the
calendar opens the reminders Sidekick; reopened if that hand-off feels slow.

**Reversibility** (2026-10-04, architectural rule). The op log is append only; a delete is a
tombstone; undo is a new op; any past state can be rebuilt by replay to a sequence number.
Bundles are immutable and versioned; an edit creates a new version and the old one stays
launchable. Each bundle version records the op-log sequence it was deployed at, so code and
data roll back together. This is for operator recovery; there is no user-facing rollback.

**Where data lives** (2026-10-04). Direction is local first, with cloud as backup and a desktop
app for sync later. For build 1, data lives on the server. On-device persistence is build 2.
Nothing a later change does may damage data already stored.

**Private deploy and identity.** No public URL, no directory, no listing. Sign in with Apple
only; no Sidekick implements login. Build 1 users are named friends added as internal
TestFlight testers. In build 2, sharing reaches named people through a universal link that
resolves only for authorized members (also satisfying the 4.7.4 index requirement).

**Notifications.** No notification API in the SDK. A Sidekick writes
`store.set("reminder:<id>", { at, title, body })`; `reminder:` is a reserved prefix. The shell
watches these records and schedules local notifications (build 1). The server pushes to other
members of a shared group when the record appears (APNs, build 2). Notification authorization
belongs to the shell, is requested once and never delegated.

**Offline.** Build 2: ops written to local SQLite first, sent in the background, replayed. Build
1 is server-backed.

**Data export.** The Re-plan's snapshot-on-generate writes the bundle plus a data export to the
repo on every generation and edit. A user-facing data export feature: not decided.

**Usage metrics** (2026-10-04). Events carry no content: anonymous random id, Sidekick id, event
name (open, close), server time. Writes are a count per Sidekick per day. Derived: installs,
daily and weekly actives, days active per person per Sidekick, day 1 and day 7 retention,
opens per day, Sidekicks per person. The App Privacy answers must declare usage data.

## 6. Current state and next steps

Exists in `backend/` (deployed 2026-10-05 as Worker `midas-api` at
`https://midas-api.midas-backend.workers.dev`):

- Hono app with one route, `GET /health`, which probes D1 (`SELECT 1`) and R2 (`list`) and
  returns `{ ok, d1, r2, time }`, 200 or 503.
- Bindings: D1 database `midas` as `DB`, R2 bucket `midas-bundles` as `BUNDLES`.
- No tables and no features yet. Deploy with `npx wrangler deploy` from `backend/`.

Done per the checklist: Apple Developer membership; private repo; bundle ID registered with Push
Notifications and Sign in with Apple; App Store Connect record (listing name "Midas: Apps for
You", exact string to confirm; display name Midas); internal TestFlight group; backend skeleton,
health URL confirmed from the phone on 2026-10-05. No shell code exists.

Next steps:

1. Create the Xcode project for the shell. Blocked on the exact registered bundle ID string
   (`com.bhuvanrj.midas` was suggested, not confirmed).
2. Confirm code signing against the real bundle ID; upload a throwaway build to prove the pipe.
3. Backend: Sign in with Apple, per-Sidekick tokens with grant lists, op-log tables and sync.
4. The three hand-written Sidekicks, the consent screen, the reminder watcher, metrics.
5. Collect friends' Apple ID emails for internal TestFlight.

## 7. Success criteria (v1 Re-plan, 2026-09-25)

1. A non-founder installs the app, asks for an app in their own words and uses it on three
   separate days. Needs the generator, so testable only once it lands (2026-10-04).
2. At least five apps the founder did not hand-write. Needs the generator (2026-10-04).
3. At least one app edited after first use by the person who asked for it, data intact. App
   editing moved out of build 1 on 2026-10-04; when this becomes testable is not restated.
4. One link forked by someone who then asked for a change to their copy. Build 2; first to drop.
5. The pooler live with three members, and `store.claim` prevented a duplicate order. Build 2;
   second to drop.
6. Cost extrapolated from the Oct 21 to 27 probe, reported Oct 28. Ceilings: $0.15 per
   generation and $0.35 per app per 30 days (Apple membership excluded). Exceeding either
   re-opens metering before any further scope.

Founder plan, design history, essays and market intel live in the private repo BHUVAN-RJ/midas-intel.
