# Midas: what is being built

State as of 2026-10-08, including the 2026-10-06 bets and falsifiers. Decisions are dated; where two decisions conflict, the later one wins.

## 1. What Midas is

North star (founder's call, 2026-10-08): Midas is **the last consumer company**. Once everyone
can write their own software, no company needs to exist to make consumer apps; Midas is the one
that closes that era. Framing only: it changes no build, scope or date below. The one-liner
stands alone in public copy; the reasoning is in the midas-intel design doc under
`## North Star, 2026-10-08: The Last Consumer Company`. Never describe Midas as a "consumer
app company".

Mission (founder, 2026-10-11): **Midas exists but does not exist.** The user's apps are front
and centre; Midas stays in the background, almost invisible. No screen keeps telling the user
"you're on Midas". The user should feel they own their apps, not that some company controls
them. Every surface (shell, widgets, Control Center, Spotlight, notifications) is checked
against this. Final wording of the line is open.

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

**D2. Name and passkey.** Changed 2026-10-08 from Sign in with Apple. A user types a display
name and creates a passkey (synced through iCloud Keychain); the passkey is the only identity. A
returning user (new phone, reinstall) signs in with the same passkey. No Sidekick implements login.
Done when: a fresh install creates an account from a name and a passkey and the backend holds a
user row and a passkey row; signing in with that passkey after a reinstall returns the same user;
a request without a valid session is rejected.
Changed 2026-10-08 (founder): sign-in is a name (one field) plus a passkey, replacing Sign in
with Apple. The shell asks for it; nothing past the welcome screen is reachable without a
session. Built on branch `agent/auth`, not yet merged.

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

1. Answered: the bundle ID is `com.bhuvanrj.midas`, team `ZQ2JPFYL98` (shell/project.yml).
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

### Plan additions, 2026-10-09 (appended; everything above still stands)

The founder: the current plan is too slow. These are added where needed and possible, inside
the same time available (no dates move).

**Now to Sun Oct 11 (the founder's "week 2"):** primitives for five Sidekicks, built in parallel
worktrees (`docs/PARALLEL-AGENTS.md` in midas), following the pattern of the reminders work and
the notification engine:

1. Calendar
2. Reminders
3. Birthdays
4. Split (new; build 1 lists three Sidekicks)
5. Notes (new)

Also named 2026-10-08, as a parallel job next to reminders: a lecture recorder. It records
audio continuously, in the background too; transcribes on the device; cleans filler words; and
lets the user chat with it while recording continues. One recording job, one main memory file
written constantly, one chat thread. Before answering, the agent reads what was transcribed
since it last read (nothing already read is read again), so a question asked five minutes later
includes those five minutes. Design is discussed with its own agent.

**W3, Oct 13 to 18, added:**

1. **AutoEvolve CI. For discussion, Oct 10 or 11; nothing designed yet.** The user is using a
   Sidekick and asks for a change ("I don't like the notifications like this, I want them like
   this"); Midas builds and deploys it. Touches "app editing in place" (must land before Nov 2)
   and "start minimal, rebuild on request" (2026-10-08).
2. **Sharing, a flagship feature.** Was W4 (fork mode, then shared mode); now starts in W3.
3. **Interop between the user's computer and phone.** Purpose open (founder: "I don't know for
   what, but that is something that is needed").

**Open:** what the existing W3 items (op-log client persistence, APNs) and W4 items give way to,
if anything. Shared mode depends on APNs push.

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
- **Few words on screen (2026-10-10).** Say the action and stop: "Import Apple Reminders", not a
  title plus two lines explaining it. Rules for every screen in the shell and every Sidekick,
  generated ones included: `docs/WRITING.md`.

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
The generator prompt also carries `docs/WRITING.md` in full, so every generated Sidekick's
words follow it; a hand-written Sidekick gets a before/after wording mockup the founder approves
before its words are built (Reminders, 2026-10-10).

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

**Private deploy and identity.** No public URL, no directory, no listing. A name plus a passkey
is the only identity (2026-10-08; it replaced Sign in with Apple); no Sidekick implements login. Build 1 users are named friends added as internal
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
End of 2026-10-07: encryption for build 1 is tier 1 on Cloudflare: a master key as a Worker
secret, a random data key per user stored wrapped in D1, record values encrypted before storage;
recovery always works, Midas could technically decrypt; tier 2 (passkey-wrapped, Midas cannot
read) is the upgrade path. Back to the folder: left-edge swipe, temporary. Focus is reminders
only. Reminders research for 20 apps: midas-intel `docs/research/reminders/ANALYSIS.md`.
Notifications and the iOS limit of 64 scheduled notifications per app (shared by all Sidekicks):
now, a simple internal engine in the shell keeps Midas's own unlimited queue, books the soonest
batch with iOS and tops it up whenever the app runs. Known issue, later: if the phone does not
run for days, reminders beyond the booked batch do not fire; the fix (server push for anything
past the phone's booking window) is deferred.
2026-10-08: Sidekicks start minimal and are rebuilt on request (build recipes from the knowledge
bank, followed by subagents), with the leave-reason basics in from day one and native shell
primitives built ahead. **Discovery through suggestions is Midas's key offering**: Midas offers
features as prototypes before the user asks. Planned for W3 (Oct 13 to 18); the item it displaces
is not yet named.
Strategy, 2026-10-08 (design doc, `### Which RFSs Midas sits on, and where the moat is`): Midas
combines Koomen's "A Cloud for Small Software", Schaad's consumer RFS and Koomen's "AI Horseless
Carriages"; it is private infrastructure sold to consumers, a wrapper like Supabase or early
Dropbox, whose moat is data gravity, sharing pull, compounding knowledge, trust and the phone
layer. Open: what Midas may learn from given the privacy rules, and whether on-device models
count as prompts.
2026-10-09: encryption (tier 1 and tier 2) is demoted to a later phase, revisited once Midas
has 5,000 users. Until then record values are stored unencrypted; the passkey sign-in gate
decides who can read an account's records but does not encrypt them.
2026-10-08: sign-in is a name plus a passkey (Apple passkeys), replacing Sign in with Apple
(D2). The shell asks once; the backend verifies passkeys with `@simplewebauthn/server` and keeps
only a hash of each session token. Passkeys on a phone need the Associated Domains capability
on the App ID and the backend's apple-app-site-association file live.
2026-10-10: the shell is signed by the paid team `ZQ2JPFYL98` (bhuvanrj83), not `YJ76245TM4`;
`DEVELOPMENT_TEAM` in `shell/project.yml` and the apple-app-site-association app ID
(`ZQ2JPFYL98.com.bhuvanrj.midas`, `backend/src/auth.ts`) follow it. The shell is installed on
the founder's iPhone 16 Pro.
2026-10-10, backend: **no user data may be lost, from now on** (nothing is stored yet, so nothing
is lost so far). **Only the founder runs database operations that delete**; agents never run
deleting statements against a remote database. Sidekicks are **assigned per person** (one small
assignments table; answers build 1 open question 3). Backend changes go to a **staging Worker**
before the live one. On the list, not built now: an independent copy of the data (backups beyond
Cloudflare's own, replication).
2026-10-10, records: **one record may hold at most 64 KB** (the record's JSON text), on the
phone and on the server, so every record the phone accepts can be backed up. Screenshots, images
and other large files do not go in records: they are planned as files stored in R2, with the
record holding a reference (`docs/CONCERNS.md`, concern 4; first user: a reminder that shows a
screenshot). Not built.
2026-10-10, import: **Apple Reminders are imported on the iPhone** (must ship before the
Reminders Sidekick goes to others; founder, 2026-10-09). The Sidekick writes a
`request:<id>` record `{kind: "import.apple-reminders"}`; the shell shows its own sheet and the
iOS Reminders permission, reads EventKit and writes the export back to that Sidekick only as
`import:<id>:<nnnn>` parts under 64 KB each; no native bridge. Reminders are matched on Apple's
`externalId`: the phone's version wins and updates what is there, Midas-only fields (snooze, last
done) stay, nothing is removed; a Mac export file only adds. The page deletes the `import:` parts
after bringing them in (their rows stay in the server's append-only history; accepted, about
100 KB per import). Built and merged 2026-10-10; not yet tried on a phone.

2026-10-10, wording: **the founder approved the whole wording mockup** (`docs/mockups/wording-2026-10-10.html`,
branch `agent/wording`) as shown, including the rows marked UNSURE at their proposed values, for
the shell and the Reminders Sidekick, following `docs/WRITING.md`. Welcome screen: "Get Started"
and **"Sign In"** (W5, replacing option B "I've used Midas before", chosen earlier the same day);
the line "What should we call you?" removed; field "Name". Import sheet: "Import Apple
Reminders" with "Continue" / "Not Now", no explaining lines.

2026-10-11, reminders: **This Week and This Month are replaced by a list stack** (founder; This
Week ran Monday to Sunday, so on a Sunday tomorrow's reminder was missing). Pulling past the bottom
of a list shows the next list's name, then the next list rises as a full page over it; pulling
down at the top goes back. Order: Today, then the drawer order. New built-in list **Next 7 Days**
(tomorrow to 7 days out, compact rows, time on the right). Removed: page dots, the red Past Due
button on Today. Circle colours: the reminder's list; with no list, blue today, Scheduled colour
another day, grey undated. Scheduled is orange, All green. Mockup
`docs/mockups/next-7-days-2026-10-11.html`. A day in Next 7 Days with no reminders shows only its
header. Defaults the founder accepted: a repeating reminder shows once, on its next occurrence (as
in Scheduled); day headers use the app's date style ("Tomorrow 12 Oct"); a reminder added in Next 7
Days is due tomorrow, all day. Reminders imported from Apple keep their Apple list and its colour,
so blue circles in Scheduled are usually Apple's "Reminders" list, not a missing rule. Commits
1baebbe, bb6fc41; tests `reminders-next7`, `reminders-circle-colour`, `reminders-next7-empty-days`.
Built 2026-10-11; not yet tried on a phone.

## 6. Current state and next steps

State on 2026-10-11 (lead session). Everything below is merged into `main` and pushed.

**Two servers** (`backend/wrangler.jsonc`; scripts take `--env staging|live`):

| | Live | Staging |
|---|---|---|
| Worker | `midas-api` (`midas-api.midas-backend.workers.dev`) | `midas-api-staging` (`midas-api-staging.midas-backend.workers.dev`) |
| D1 | `midas` | `midas-staging` |
| R2 bundles | `midas-bundles` | `midas-bundles-staging` |
| Used by | Release builds (TestFlight) | Debug builds (Xcode Run) |

- Migrations 0001 to 0004 applied on both (auth; unique names, case-insensitive; Sidekick
  assignments; append-only `ops` table with trigger `ops_are_never_updated`). Run them only with
  `node scripts/migrate.mjs --env ...`, which exports D1 first to `~/midas-backups/` and the R2
  bucket `midas-backups` (bound to no Worker). The founder approves every remote migrate, deploy
  and Sidekick deploy; the lead session's tool blocks it from deploying live, so the founder runs
  live commands.
- Routes: `/health`, `/auth/*` (name plus passkey; `RP_ID` per environment), `GET /sidekicks`
  (the signed-in person's assigned Sidekicks with name, SF Symbol and color from each manifest),
  bundles, `/sync/push` and `/sync/pull` (records, at most 64 KB each).
- Scripts in `backend/scripts/`: `migrate.mjs`, `backup-db.mjs`, `deploy-sidekick.mjs` (uploads a
  new immutable version and moves `current.json`; live refuses unless staging has the same page),
  `assign-sidekick.mjs`.
- Founder's accounts: "R J" on staging and "RJ" on live, each with a passkey on the iPhone 16 Pro;
  Reminders is assigned to both.
- Reminders page deployed with the approved wording: staging `20261011T065908559Z-1064a312`,
  live the same page (founder ran it, 2026-10-11).
- Reminders with Next 7 Days and the list stack (section 5, 2026-10-11, reminders): staging
  `20261011T195421796Z-0201ef16`; live is the founder's to run
  (`node scripts/deploy-sidekick.mjs reminders --env live`), not confirmed here.

**Shell** (`shell/`, xcodegen; signed by team `ZQ2JPFYL98`, bundle `com.bhuvanrj.midas`):

- Welcome: name field, "Get Started" (new account) and "Sign In" (existing passkey).
- Home is an icon grid of assigned Sidekicks (`SidekickHomeGrid.swift`); a Sidekick opens full
  screen in a WKWebView, swipe from the left edge to go home.
- Local record store with outbox; `RecordSync.swift` pushes and pulls; a fresh install shows the
  restoring screen before the grid.
- Notification engine for `reminder:` records (`docs/NOTIFICATIONS.md`).
- Apple Reminders import on the phone (section 5, 2026-10-10, import).
- Passkeys run in production mode on every build (2026-10-11): one entitlements file,
  `shell/Midas/Midas.entitlements`, no `?mode=developer`. Apple's CDN serves the AASA for live and
  staging (`ZQ2JPFYL98.com.bhuvanrj.midas`). The temporary Debug developer-mode file is removed.
- Version `0.1.0`; it stays 0.x until the founder calls a 1.0 (2026-10-11). The build number is
  `CURRENT_PROJECT_VERSION` in `shell/project.yml`; raise it by one before every upload.
  `tests/guard/test_release_config.py` checks both.

**Sidekicks:** `sidekicks/reminders/` (the founder's Reminders, built from the design process in
midas-intel `docs/process/sidekick-design-process.md`).

**Rules files every agent reads:** `docs/WRITING.md` (words on screen), `docs/NOTIFICATIONS.md`,
`docs/CONCERNS.md` (open risks: 4 files larger than a record go to R2, 5 a lost passkey),
`docs/PARALLEL-AGENTS.md`, `docs/briefs/` (one brief per past agent; all those agents are
finished and closed as of 2026-10-11).

**Tried on a real phone, all pass** (founder, 2026-10-11, iPhone 16 Pro, TestFlight build 0.1.0
(1) against live):

1. Records come back: the founder deleted Midas, reinstalled from TestFlight and signed in; the
   records copied from staging were all there, unchanged. Server check: live "R J" holds 84
   lists, reminders and tasks, the same as staging, and no op was written by the reinstall.
2. Apple Reminders import on the phone: works (founder).
3. The new design: icon grid, full-screen Sidekick, left-edge swipe home, new wording: good
   (founder).
4. Reminders list stack and Next 7 Days, pulling down and up: works (founder).

**Next steps:**

1. Phone tests: done 2026-10-11 (above).
2. Backend phase 3 (not started): usage metrics, sign-out, a scheduled cleanup of expired
   sessions and challenges, scheduled D1 exports. Redo the backup plan at 100 users.
3. Internal TestFlight (developer-mode entitlements removed 2026-10-11; see the readiness list).
4. Cloudflare billing alerts (Workers Paid has no hard cap): how the founder wants to be told is
   open.
5. Collect friends' Apple ID emails for internal TestFlight (D10). Two friends (founder, 2026-10-11)
   have the same Apple Reminders problem; each gets their own Reminders Sidekick, hand-written.

**Sidekicks outside the shell (founder, 2026-10-11).** Research: midas-intel
`docs/research/2026-10-11-sidekicks-outside-the-shell.md`. Mockups: widget folders artifact
(https://claude.ai/artifact/6BigRus6CmZAVKHdk5bbcK; small, medium, large, mixed; light, dark,
tinted, clear).

- **Now: widgets as folders.** A home screen widget holds Sidekick tiles like an iOS folder:
  small 4, medium 8, large 16; each tile opens its Sidekick (`Link` per tile into
  `router.open(sidekickId:)`). The user adds the widget themselves; that is fine. Guideline
  2.5.8 (alternate home screens) is a known risk; founder's call: use it on internal TestFlight,
  see what Beta App Review says, decide then. The person picks a widget's Sidekicks in its
  settings, in picked order (default: the first of the home grid); a tap on empty widget space
  opens the Midas home. Built and merged 2026-10-11.
  - Widget gallery name is "Sidekicks", not "Folder" (founder, 2026-10-11): no name that borrows
    an Apple Home Screen feature. A short row of tiles is centred (founder, 2026-10-11: one
    Sidekick sat in the top-left corner).
- **Now: the Reminders widget** (founder, 2026-10-11): today's reminders only, small, medium and
  large, as in the mockup's second row. Tapping a circle marks the reminder done from the widget
  (founder, later the same day). Widgets cannot scroll (WidgetKit has no `ScrollView`), so when
  today has more than fits, arrow buttons page through them. "All done" when nothing is left,
  "Open Midas" when signed out. Brief: `docs/briefs/widget-reminders.md`.
- **Next week:** Control Center (open a Sidekick directly), App Shortcuts ("Open Reminders",
  "Open any Sidekick"), Spotlight, and `IndexedEntity` for Siri Suggestions.
- **Recorded, not worked on:** Action button, Lock Screen widgets and controls.
- Mission check (facts for the mission line above): Siri phrases for App Shortcuts must contain
  the app name (Xcode error, per Apple forum reports); the widget gallery, controls gallery and
  Spotlight list items under the app's name. Whether iOS 26 shows "Midas" under each home screen
  widget is to be checked on the iPhone.

**Internal TestFlight readiness (checked 2026-10-11):**

Ready:
- App icon in the asset catalog: 1024 px, no alpha, plus dark and tinted versions.
- A Release build for a device compiles. The built app has `CFBundleIconName` AppIcon, the live
  host, bundle `com.bhuvanrj.midas` and iOS 17.0.
- Export compliance is answered in Info.plist (`ITSAppUsesNonExemptEncryption` false).
- Passkey domains in production mode (`Midas.entitlements`), AASA served by Apple's CDN.
- Version 0.1.0, build 1; Info.plist reads both from `project.yml`.
- The shell uses no required-reason APIs (UserDefaults, file timestamps, disk space, uptime), so
  it needs no privacy manifest.
- First build uploaded and processed (founder, 2026-10-11): App Store Connect shows it "Ready to
  Test" (Internal) in TestFlight. Friends internal group set up, founder added (2026-10-11).
  Next: invite friends, assignments.
- The founder uses the TestFlight build (live server) as their daily Midas from 2026-10-11;
  testing goes to the Simulator, or to a separate dev bundle ID if one is ever approved. Xcode Run
  and TestFlight share `com.bhuvanrj.midas`, so a Run on the phone replaces the TestFlight build
  and switches to staging, where accounts and records are separate.
- 2026-10-11: the founder's staging records (account "R J", 131 ops, Reminders) were copied by
  hand to their live "R J" account, in staging order with the same op_ids (live now holds 134 ops
  for them). Staging was only read.

Open:
- App Store Connect app record exists, renamed by the founder on 2026-10-11 to "Midas: Personal
  Software" (was "Midas: Apps Made for You"; "Midas" alone is taken; the name avoids "apps" in
  public copy). The home-screen name stays "Midas" (`CFBundleDisplayName`). Subtitle, for now
  (founder, 2026-10-11, to revisit later): "Make the things only you need" (29 of 30 characters;
  the other finalist was "Ask for what only you need"). TestFlight does not show the subtitle.
  Its bundle ID still to be confirmed as `com.bhuvanrj.midas` (App Information, General).
- Friends: each is added in Users and Access (role Marketing, Midas only), accepts that email,
  is then added to the internal group, and installs from the TestFlight email.
- A new account starts with no Sidekicks and the home grid is blank. The founder runs
  `assign-sidekick.mjs "<name>" reminders --env live` after each friend signs up.
- Done 2026-10-11: the Release build from TestFlight runs on the founder's phone against live
  (phone tests above).

**Brand and icon, 2026-10-11 (founder):** the record is `docs/DESIGN.md` (colour, type, mark, motion).
Short version: direction is handwritten. The wordmark "Midas" and a
lowercase signature "m" in a hand; the icon is either the small written word or the m on a square.
Colours: black and white plus one accent; no brown, no purple, no blue, no gradients. Opening
motion, chosen: Μίδας in Greek first, then each letter cycles through Greek capitals and locks into
the English letter, left to right ("cycle then lock"). Icon shortlist: centred written "Midas"
(leading), lowercase "midas", small "m" with underline bottom-right. Accent, chosen (2026-10-11, revised the same day): Tomato light #FF6347, held in reserve; the shell is
black and white until the founder assigns the accent per use case. Sidekick tiles use a fixed
palette of eight (DESIGN.md 2.3). Dark mode defined now, ships later. App icon landed:
`shell/Midas/Assets.xcassets/AppIcon.appiconset/` (written "Midas", black on white, Caveat Bold
placeholder for the founder's hand), source in `shell/icon-source/`. Founder's
shortlist if it changes: cherry #C41E3A, tomato light #FF6347, tangerine #FF8A00, amber #FFBF00,
lemon #FFE600, turquoise #30D5C8, charcoal (no accent), chartreuse #C9F24D. The real mark is traced from the founder's handwriting (sheet
not yet written). Research and mockups: midas-intel `docs/research/2026-10-11-*.md`.

**Planned, not now (founder, 2026-10-11): the first-open touch screen.** Before the public
TestFlight, not build 2. On first open (and sign-in) the screen says Midas and asks the user to
touch. Where the finger rests, the screen shakes and gathers energy, the app tiles are pulled in to
the touch point, and after a few seconds the energy bursts and the same tiles come floating back
out. Then one line: "The personal touch your apps needed." Still to be planned: duration, haptics,
reduced-motion fallback, skip on later opens, and how it hands over to sign-in.

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
