# Midas: what is being built

State as of 2026-10-08, including the 2026-10-06 bets and falsifiers. Decisions are dated; where two decisions conflict, the later one wins.

## 1. What Midas is

North star (founder's call, 2026-10-08): Midas is **the last consumer company**. Once everyone
can write their own software, no company needs to exist to make consumer apps; Midas is the one
that closes that era. Framing only: it changes no build, scope or date below. The one-liner
stands alone in public copy; the reasoning is in the midas-intel design doc under
`## North Star, 2026-10-08: The Last Consumer Company`. Never describe Midas as a "consumer
app company".

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

<!-- build1-deliverables:start (identical in midas docs/PRODUCT.md and midas-intel design doc; intel/tests/test_build1_deliverables.py checks) -->
Goal, from the decisions of 2026-10-04: friends named by the founder install Midas from
internal TestFlight and use three hand-written Sidekicks, live for a16z Tech Week from Oct 13.
What they ask for is the evidence the generator is built against after Oct 8. Usage metrics
give the stickiness numbers. Success criteria 1 to 3 need the generator and are not tested on
build 1.

"Submitted Oct 8" means: build 1 is processed in App Store Connect and installable by the
internal TestFlight group. No Beta App Review.

The "Done when" lines were proposed on 2026-10-07 from the decisions cited in each item. They
are not founder decisions; the founder edits them.

**D1. Shell.** SwiftUI app on the registered bundle ID. One WKWebView per Sidekick, served
through a WKURLSchemeHandler so each bundle has a real origin. CSP pins `connect-src` to the
platform origin and `script-src` to a per-deploy sha256 hash. No script message handler; no
native API exposed to Sidekicks (transport reversal, 2026-09-26).
Done when: a Sidekick bundle stored in R2 opens in the shell on a phone; a fetch from it to any
other origin is blocked; the project registers no script message handler.

**D2. Sign in with Apple.** The only identity. No Sidekick implements login.
Done when: a fresh install signs in with Apple and the backend holds a user row for that Apple
ID; a request without a valid session is rejected.

**D3. Per-Sidekick tokens.** Short-lived, issued by the shell, scope is a list of grants,
enforced server side. Sidekicks call the backend with plain HTTPS fetch.
Done when: a token for one Sidekick cannot read another Sidekick's records without a grant; an
expired token is rejected; nothing a Sidekick sends can widen its scope.

**D4. Op-log server and the build 1 SDK calls.** Ops table, dedup on op_id, server-assigned
sequence, last-write-wins per key in sequence order, cursor sync, claim. SDK: `store.get`,
`store.set`, `store.query`, `store.delete`, `store.claim`, `user.me`, `time.now`. Query is
prefix or single-field equality. Append only: a delete is a tombstone, excluded from query
(reversibility rule, 2026-10-04).
Done when: the same op_id sent twice is applied once; of two writes to one key the higher
sequence wins; `store.claim` on a key returns true for exactly one caller; a deleted record is
absent from query while its ops are still in the table.

**D5. Bundles and private deploy.** Bundles are immutable and versioned in R2; each version
records the op-log sequence it was deployed at. No public URL, no directory, no listing. The
founder deploys a hand-written Sidekick with one command.
Done when: redeploying a Sidekick creates a new version and the previous one is still stored
and launchable; a bundle cannot be fetched without a valid token.

**D6. Three Sidekicks: reminders, calendar, birthdays.** Each keeps all its data through the SDK
(no localStorage, no IndexedDB), with records keyed `type:id` and a manifest: id, name, icon
(SF Symbol name plus background color), `reads`.
Done when: on the founder's phone each one creates, lists, edits and deletes its records, and
the data survives deleting and reinstalling the shell; none of the three bundles references
localStorage or indexedDB.

**D7. Cross-app read with consent.** The calendar declares `reads: ["reminder", "birthday"]`.
The shell, never the Sidekick, shows the consent screen generated from that list the first time
the access is needed; consent adds a grant to the token. Read only. Tapping a reminder on the
calendar opens the reminders Sidekick.
Done when: before consent the calendar receives no reminder or birthday records; after consent
it shows both; a write from the calendar to a `reminder:` key is rejected server side.

**D8. Notifications.** The shell requests notification authorization once, for itself. Its
reminder watcher schedules a local notification for each `reminder:<id>` record
`{ at, title, body }`. No notification API in the SDK.
Done when: a reminder created for two minutes ahead fires while the shell is in the background;
deleting it before then cancels the notification.

**D9. Usage metrics.** Events carry an anonymous random id, a Sidekick id, open or close, and
server time. Writes are counted per Sidekick per day. No keys, values, titles or text.
Done when: opening a Sidekick adds an open event; no metrics table has a column that can hold
record content.

**D10. Release.** Code signing confirmed against the bundle ID; a throwaway build uploaded first
to prove the pipe; export compliance answered; build 1 uploaded; friends' Apple IDs added to the
internal TestFlight group.
Done when, Oct 8: build 1 shows as ready to test for the internal group. Done when, Oct 13: the
friends added as internal testers have installed it.

Not in build 1 (decided 2026-10-04): the generator, app editing in place, APNs and push,
on-device persistence, sharing, external TestFlight and Beta App Review.

Open, waiting on the founder:

1. The exact registered bundle ID string. Blocks D1 and D10.
2. Whether the assistant surface (text field, status line, launcher) and snapshot-on-generate
   stay in build 1 now that the generator has moved out.
3. Whether every friend gets all three Sidekicks or the founder assigns them per person (that
   needs one small assignments table).
4. The shed order if build 1 runs over. Proposed, not answered: D6 birthdays first, then D7's
   consent screen becomes a plain system alert, then D9 shrinks to open events only.
<!-- build1-deliverables:end -->

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

**Architecture discussion, 2026-10-07** (full record: design doc, `## Architecture Discussion,
2026-10-07`). Native reach now: notifications and widgets; later location, haptics, camera;
permission prompts are acceptable. Mechanism open: direction is a bridge where the shell calls
native APIs and the Sidekick uses the resulting data, which reopens the 2026-09-26 transport
reversal. Rendering: free-form HTML and JS in a sandbox for now, with Midas-provided primitives
as the fallback if that becomes uncontrollable; an agent-categorized, check-backed component
layer is proposed. Storage: server-first stays, on-device later per Sidekick where it fits.
Deferred: prototype-first personalization (Midas mocks up directions, the user picks).
Later the same session: native features are reached by request records (the Sidekick writes a
request, the shell makes the native call and writes the result back; no function in the page),
as long as Apple has no objection; 4.7.3 consent per instance applies. Widgets are not in build
1; a calendar widget comes with the calendar Sidekick. Nobody, the operator included, can read a
user's data: it is encrypted, by an encryption engine whose design is deferred.
Security answers: user data never goes into prompts (tests and rebuilds included); no
cross-Sidekick read without consent; data protected anywhere between device and server (a
held phone is out of scope); Sidekicks may call outside APIs, how is open (5.1.2(i) disclosure
and permission apply to personal data sent to third parties); checks before a Sidekick runs
are deterministic first, agentic review on top. Down the line: a knowledge bank built by
dissecting the top 10 to 20 apps per category for what users love, starting with reminders.
Decided: outside APIs go through Midas (backend proxy: keys on the server, declared and consented
domains only, bodies never logged or stored). Checks are three layers a Sidekick must pass:
platform checks and a base set per kind of app, both written by Midas, plus extra checks from a
testing agent attached to the generator for the user's added requirements. Keep it simple; the
product evolves with use.
Design language: Midas opens as a folder of apps, with the feel of an iOS folder (guidelines
2.5.8 on alternate home screens and 5.2.5 on looking like Apple interfaces apply; a literal copy
of the iOS folder is what 5.2.5 names). The entry for making a Sidekick is not "Build an App";
its name, the name Sidekick itself, and the gesture back to the folder are open. A Sidekick
fills the whole screen.
Decided after precedent research (midas-intel `docs/research/2026-10-07-folder-home-precedents.md`):
build the folder home now and deal with any review problem later; the identified risk is 5.2.5
as applied to Mac grid launchers in 2025-26. Midas will also let a user pin a single Sidekick
to the real iOS home screen through Shortcuts "Add to Home Screen", as Kiln does; timing open.

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

Next steps, in order (deliverable numbers from `### Build 1` above):

1. Create the Xcode project for the shell (D1). Blocked on the exact registered bundle ID string
   (`com.bhuvanrj.midas` was suggested, not confirmed).
2. Confirm code signing against the real bundle ID; upload a throwaway build to prove the pipe
   (D10).
3. Backend: Sign in with Apple, per-Sidekick tokens with grant lists, op-log tables and sync
   (D2, D3, D4, D5).
4. The three hand-written Sidekicks, the consent screen, the reminder watcher, metrics (D6 to D9).
5. Collect friends' Apple ID emails for internal TestFlight (D10). Runs in parallel from now.

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
