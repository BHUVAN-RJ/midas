# Midas: what is being built

State as of 2026-10-08, including the 2026-10-06 bets and falsifiers; section 6 is current as of 2026-10-24. Decisions are dated; where two decisions conflict, the later one wins.

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
  Returned 2026-10-13 as the voice-first interface (section 2, "Plan additions, 2026-10-13").

## 2. Dates and builds

| Date | Event |
|---|---|
| Thu Oct 8 | Build 1 submitted. Internal TestFlight only (up to 100 internal testers, no review). |
| Mon Oct 12 | Submit build 0.1.0 to Beta App Review for external TestFlight and a public link (founder, 2026-10-11). |
| Oct 13 | Link live (a16z Tech Week). Runs on internal testers. |
| Thu Oct 22 | Build 2 submitted. |
| Oct 21 to 27 | Cost probe; reported Oct 28. |
| Nov 2 | VC application. The goal is real users using the product, not a demo. |

External TestFlight and Beta App Review come after Oct 8 (decided 2026-10-04). Changed
2026-10-11 (founder): submit to Beta App Review as soon as possible, target Mon Oct 12. The
item it displaces is not yet named. The review fallback below still holds. Build 1 has no
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
`{ at, title }`. No notification API in the SDK.
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

**Changed 2026-10-11 (founder):** calendar and split are on hold (split involves other people).
Next are **birthdays, notes and a new alarm app**, starting with primitives research: three
research agents, one per category, collect the best-rated apps, what users love and hate, and
**what makes the app complete** (not broken). The completeness study is new: it was missing in
the reminders research and is now part of every Sidekick's research stage (midas-intel
`docs/process/sidekick-design-process.md`, `docs/research/primitives-BRIEF.md`). The founder
knows what he wants for birthdays; notes is open.

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

### Plan additions, 2026-10-13: jess, voice first (founder)

jess returns as the voice-first interface to the user's Sidekicks. The user presses the Action
button, speaks, and jess puts the request into the Sidekick that owns it ("add a reminder" goes
to Reminders, "put this on split" goes to Split), or answers from it.

**Now: a voice-first interface for Reminders only.** A local, old-school voice engine on the
phone that translates spoken reminder requests into Reminders actions. Built to be faster than
anything else; no LLM in this path.

**The general idea, for every Sidekick later:**

1. **jess is the first orchestrator.** A fast decision model takes the input and decides which
   Sidekick's agent to call. Founder's direction (2026-10-13): something like **Jev**
   (TypeSafe's fast zero-shot classifier, "System One") orchestrates the whole thing: the
   user's request keeps being passed to it, it returns which Sidekick or agent to use, and that
   agent is invoked. Research: `jev-orchestrator.md`.
2. **One agent per Sidekick.** Each knows only how to serve requests for its own Sidekick; no
   general intelligence is needed there. Midas builds a model per Sidekick.
3. **Escalation.** If the Sidekick's agent cannot fulfill the request, it calls a general model
   that handles everything.
4. **Every Sidekick is agent-ready** through a single-file protocol that is always accurate: the
   agent reads and writes through it, and it serves both the fast deterministic path and the
   model path. Its shape is not decided; options are in the research below.

Founder facts, 2026-10-12 and 13:

- Audio never leaves the phone; transcription is on the device.
- Models are reached through OpenRouter, not Anthropic. Not Gemini.
- jess is never called a Siri replacement in any wording.
- Mixing the old-school path and an LLM into one system is a bad idea (founder). The plan
  above keeps them separate: the Sidekick's own agent first, the general model only on
  escalation.
- The Action button is the way in. Sidekicks get the user's permission for voice when voice is
  used.

Research (midas-intel `docs/research/agent-ready/`): `deterministic-fast-path.md`,
`fast-llm-path.md`, `single-file-protocol.md`, `reminders-voice-engine.md`,
`orchestrator-and-specialists.md`, `openrouter-numbers.md`, `jev-orchestrator.md`.

Facts from the 2026-10-12 code audit that bear on agent-readiness: no machine-readable schema for
any record type; a reminder's meaning lives in the Reminders page JS, with partial hand copies in
Swift (notifications, widget) that already disagree on Done for repeats; the server validates no
record content and does not enforce which Sidekick owns a record type; last write wins on the
whole record.

**Not yet decided:** the protocol beyond the data format (format decided below); whether Jev is the decision model; how a
per-Sidekick model is built; the general model and when escalation happens; the iOS deployment
target (controls need iOS 18); the item this displaces before Nov 2. The 2026-10-07 rule "user
data never goes into prompts" is not restated for the general model.

### Plan additions, 2026-10-13: repair (founder)

In a Sidekick, any user does a gesture (not yet chosen; the founder will draw it on a capture
page). The screen freezes into a drawing layer that does not look like a screenshot; the user
draws (arrow, circle) and speaks the whole time. Two kinds: a bug said out loud ("reminders fire
when I haven't set them") and a change shown on screen ("I don't need this tag here, I need it
here"). The screenshot, drawing and transcript go to a repair agent, which knows the Sidekick's
primitives research and the shell's capabilities and limits, edits **the reporter's own copy
only** and redeploys it. Reminders first; one repair agent per Sidekick category later.

- Every user can trigger it, on their own phone (§3 listed screenshot-to-fix as out; changed
  2026-10-13). The screenshot may leave the phone (founder, 2026-10-13); the 2026-10-07 rule "user
  data never goes into prompts" does not hold for repair. Audio still stays on the phone; only
  the transcript leaves.
- A third kind (founder, 2026-10-13): a **new feature** asked by voice, with or without drawing
  ("I want my reminders to store images as well"). The agent builds it in the user's copy.
- Every repair is logged (all of them, unclassified); classification into categories comes later.
- The agent gets the Sidekick's intel through a tool that pulls what it needs into context (or
  a Reminders subagent); not decided. Its worktree holds only the Sidekick being repaired.
- Decided 2026-10-13 (founder): the agent runs on the founder's always-on Mac mini, on Claude
  Code with the founder's Max subscription, not an API key (API cost). Self-repair was always the
  plan: it is an addition, it displaces nothing.
- Gesture (changed again 2026-10-15, founder, after the phone test): **three fingers swipe down**
  anywhere on the Sidekick, replacing the one-finger circle of earlier the same day (which had
  replaced the 2026-10-13 scribble of two or three zigzags). Founder: "three-finger swipe down is
  a gesture that needs to be intentionally done. It cannot happen unless the person actually
  wants to start fixing." Clashes noted, not solved: VoiceOver (three-finger scroll) and Zoom
  (three-finger drag); the iOS editing gestures use three-finger left, right and pinch, not down.
  Clashes with the left-edge swipe are handled if they happen.
- **Schema changes made by repairs (founder, 2026-10-19): refuse every breaking change, for now.**
  A repair may add optional fields and new record types, and updates the copy's `manifest.json`
  `types` in the same change. A fix that needs to rename a field, change a field's type or add a
  required field is refused and marked failed with the reason. The runner never rewrites a user's
  records; it only reads them (runner-only route `GET /repairs/:id/records`, founder 2026-10-19)
  to check them against the new schema before publishing. The choices were: (a) refuse all for
  now, chosen; (b) allow with migration, the full 2026-10-15 middle path: the runner writes a
  migration and rewrites that user's records unattended in the same deploy (bigger build:
  migration writer, a dry run per user, a way back; a wrong migration means wrong records).
  Revisit when a real repair needs a rename. Built by `agent/repair-data` (CONCERNS §8).
- Permissions (founder, 2026-10-15): Midas asks for the microphone and speech recognition when it
  opens, not at the first repair, so the repair layer never stops for prompts. The repair layer's
  own permission screen is removed. If either is declined, repair still works by typing. Built
  2026-10-15 (`shell/Midas/VoicePermissions.swift`).
- **Shared voice components (founder, 2026-10-15):** repair's voice layer is reused, not rebuilt,
  by every voice feature, the Action button voice reminders first: `VoicePermissions` (asked at
  launch), the on-device transcriber (made configurable: hint words, end on silence, maximum
  length, stop on demand) and the app-wide permission strings. A feature that needs more extends
  the shared component; it never forks it. Voice plan: midas-intel
  `docs/plans/2026-10-13-voice-reminders-v1.md`, "Shared components".
- First phone test, 2026-10-14 (Midas Test, iPhone): crash when listening started (Swift 6
  main-thread check on the audio and speech callbacks); permission screen white on white in dark
  mode; the frozen screen shifted under the status bar, Cancel off screen, the text box hidden by
  the keyboard. One agent now owns repair end to end (founder, 2026-10-15); the four build agents
  are closed.
- Storage: the report's text and metadata go to D1, the screenshot and drawing to R2, linked by
  the report id.
- Per-user copies: each user's Sidekick has its own version pointer; a repair moves only the
  reporter's pointer. Tested.
- Deploy (changed 2026-10-13, later the same day): the runner publishes a repair to **the
  reporter's own live copy** itself, checks it landed, then marks it done, which sends the user's
  notification. No founder step and no staging for user copies. Base Sidekick deploys stay the
  founder's.
- The founder is notified of every request and when a fix is ready to deploy (how: to be built
  later). The user gets no report, only a notification: "The update you requested is done."
  Changed 2026-10-23: the Repair tag shows the result (section 2, "Plan additions, 2026-10-23").
- **Next build item (founder, 2026-10-13): notifications to the founder** for every repair
  request and every fix published, built as soon as possible after the repair merge. Until then
  the runner shows a macOS notification on the Mac mini only.
- Enhancements go to `docs/ENHANCEMENTS.md` (first: match "here" in speech to the drawing).
- Hosting research: midas-intel `docs/research/2026-10-13-repair-agent-hosting.md`.
- **State 2026-10-14:** built and merged to `main` (copies, intake, shell, runner, shell wiring),
  full suite green (guard 36, backend 296, shell 347, midas-intel 31). Not yet on a server or a
  phone. Founder steps before first use: remote migration `0005_repairs.sql`, Worker secret
  `REPAIR_RUNNER_TOKEN`, `claude setup-token` and `runner/install.sh` on the Mac mini (runner
  README), a TestFlight build, then scribbles captured on the phone to tune the gesture.

**jess voice router, founder 2026-10-21 (being built):** the Action button opens jess
listening; a command is routed to the right Sidekick and that Sidekick's action runs. Every action
of every Sidekick is a tool (agent block in `manifest.json` plus `tools.js` handlers, MCP-style);
every agent that builds or changes a Sidekick maintains them. DeepSeek only (Jev later, CONCERNS
§14). Repair requests go straight to the repair agent. Cannot act: a home-page card with the
transcript. Siri phrases later. Plan: midas-intel `docs/plans/2026-10-21-jess-voice-router.md`.

**A published repair is always marked done (founder, 2026-10-21):** when the deploy script
reports that a repair was published to the user's copy, the repair ends `deployed_live` and the user
gets the done notice, even if the read-back check after publishing fails (that failure is logged,
not treated as a failed repair). It happened three times that a published repair showed as "deploy
failed" and the user got no notice.

**Repairs that fix wrong behaviour go to the base (founder, 2026-10-21):** a repair that fixes
behaviour that is wrong for everyone (a bug, not a personal preference) is put into the base
Sidekick, so every user whose copy is built from that base gets it. First case: R J's Reminders
title box that wraps and grows while typing (repair report `13edb182`, 2026-10-16) goes into the
base Reminders. Updating staging means bringing all of staging to the current state, including
such fixes.

**Runner serves live and staging (founder, 2026-10-21):** one repair runner on the Mac mini polls
both the live and the staging Worker and runs each job entirely in its own environment, one job at
a time, so repairs and jess's grow path can be tested on staging without taking the runner off
live.

**jess outside the app (founder, 2026-10-23):** the controls (Control Center, Lock Screen, Action
button as a control) show the written "Jess" as a custom one-colour symbol; the App Shortcut shows
Apple's `waveform` on the `grayBlue` tile (iOS allows only SF Symbols there); the Spotlight platter
is ink with a white symbol; the label stays "Ask jess"; the microphone symbol is retired. Details:
`docs/DESIGN.md` §5a.

**jess's look (founder, 2026-10-22):** while jess listens, the orb's core is Volt (`#CEFF00` light,
`#E7FF85` dark; core only, crisp; idle and thinking stay black/white, done green, not done red).
The jess icon is "Jess" in Caveat Bold, set exactly like the Midas icon. Control Center, the Action
button and Shortcuts keep the `mic` symbol for now (replaced 2026-10-23, "jess outside the app"
above). Details: `docs/DESIGN.md` §5a.

**jess queue, instant acknowledgement and the Workdesk (founder, 2026-10-22):** every jess action
runs exactly once, through a queue: a request that is cut off (iOS ends the time, no network, a
timeout) stays in the queue and is retried later until it is done or definitely not doable; nothing
is ever applied or sent to repair twice. As soon as listening ends, the jess screen shows a small
notification at its top ("Task added" / "I'll get it done") over the circling orb, so the person
knows they can leave. jess gets a Workdesk: a log of every task jess has done (and, later, tasks the
person can pick up and continue). Both are designed in the Midas theme. Listening colour and the
jess icon are being redesigned (the earlier palette options were rejected).
Finalized by the founder, 2026-10-22 (mockup `docs/mockups/jess-workdesk-2026-10-22.html`; replaces
the notice above):
- Layout W4 stack: orb at the bottom centre, tasks at the top; the newest as one big card, the next
  two as slim cards (one size), two more tucked behind showing only their edges. Try Again always
  on the right of the card.
- Card words: the whole task on top, only the Sidekick's name under it. No status words: the orb
  core (green, red, grey) and its spinner say the status. Status words only where the Sidekick is
  not known yet: "On It" (working), "Waiting for Connection" (cut off).
- Instant acknowledgement is the new card: when listening ends, it comes out of the orb (overshoot
  to 105 %, slow settle, 820 ms) and the stack moves down one slot (700 ms, starting 80 ms after).
- Repair is a wait: the card stays grey until the repair is live and the server has re-run the
  request once, then the same card turns green or red and moves to the top. A plain repair (not a
  grow) stays grey until its done notice arrives (matched by reportId), then turns green, no re-run.
- Scrolling A, carousel ("for now, we will decide later"): one slot per card, snaps on release; no
  scroll bar, no dots.
- Cut off: grey core, "Waiting for Connection", sent again by itself (app open, network back, jess
  screen open, every 15 s on it), never applied twice; Not Done with Try Again after 1 hour.
- No glow on the orb's thinking arc. The jess tile starts listening at once, like the Action button.
- Defaults not objected to: the home result card stays as today (dismissing it does not remove the
  Workdesk task); the button reads Cancel while listening before any words, Done after; the
  Workdesk log keeps the last 200 tasks on the phone.
- Run once on the server: `POST /voice/jess` takes `requestId`; `jess_requests` (migration 0009)
  keeps each answer, so a resend never calls the model, repairs or grows twice; 409 busy while
  running. Phones on build 7 and older send no `requestId` and work as before.
- State 2026-10-22: merged to main (`69f5604`); 0009 applied to staging (backup first) and the
  staging Worker deployed; Midas Test 0.1.0 (8) uploaded to TestFlight. Live: not migrated, not
  deployed (rolled out 2026-10-23, section 6). Not yet seen on a device: the arrival and carousel feel (timings from the HTML mockup).
  Known: a plain repair whose repair fails stays grey (only "done" notices exist).
  Handoff 2026-10-22: the simulator checks in `docs/briefs/jess-workdesk-lead.md` §2b were not run
  before the build 8 upload (unit tests only); the founder tries them on build 8. Live: run
  `node scripts/migrate.mjs --env live` before deploying the live Worker (same order as staging).
- Next (founder, "a bit later"): one design doc every design agent reads first, starting from
  `docs/DESIGN.md`, adding components, spacing and sizes, screen layouts, animation timings.

**jess in the background, one result card, jess for everyone (founder, 2026-10-22):** the usual
flow is "can you set a reminder …" and then leaving the screen: jess keeps working in the background
(iOS background time) and the action is still applied. No iOS notification is ever sent for a jess
result. The result is shown only inside Midas, as one card at the top of the home page: green orb
core for done (the Sidekick's own line, e.g. "Added Call mom, tomorrow 9:00 AM"), red core with the
transcript and Try Again for not done. Both kinds stay until dismissed; the separate success banner
is replaced by this card. A result that finished while the app was closed shows on the next open.
jess is a Sidekick every user has by default (assigned to existing users and at sign-up): a home
tile that opens the same voice screen as the Action button; for now that screen is all it is.

**jess grows the Sidekick (founder, 2026-10-21; flagged, monitored):** when a spoken request does
not fit a Sidekick's tools (the page cannot do it yet, for example "every 3 weeks", or nothing
supports it, for example care "every 8 hours"), jess does not stop at Not Done: it stores the
request as a pending request, files a feature request to the repair agent with the transcript, and
shows "Sent to repair". When the repair is published to that user's copy, the backend (the repair
runner) runs the pending request again automatically against the new tools (with its original time and time zone) and its result is
shown. If the repair fails or the re-run still cannot act, the transcript card shows. The feature
sits behind a flag and every step is logged so the founder can review it after use. "That's how it's
supposed to work: malleable software."

**jess router review, founder 2026-10-21:** (1) the Action button entry (App Intent, App Shortcut
short title, control) is named "Ask jess"; Siri phrases unchanged. (2) Apple Reminders import stays
a page button, no voice tool. (3) Snooze is not a voice tool: it is a notification action, not a
page action; the `reminders.snooze` and `care-reminders.snooze` tools are removed. (4) Tool removal
is allowed: a repair that removes a feature removes its tool, `tools.js` handler and test together,
and the runner checks the page no longer offers it (CONCERNS §15). (5) The server reads each
Sidekick's manifest (the user's own copy version) for the agent block and tools; the phone no longer
sends them. (6) One sign-in check per `/voice` request. (7) Tools accept only what the page offers
(same repeat presets, alert steps, interval range and uncomplete window as the page). (8) Care
"every 8 hours" stays Not Done (the page supports 2, 3 or 4 hours).

**Voice reminders, founder 2026-10-15:** saves at once (no Add/Undo card): Action button, speak,
leave; a small banner at the top of Midas says added, or not done with the transcript. DeepSeek
only (eval 2026-10-16; integrated without a second run, founder 2026-10-17). Every
attempt (transcript, model reply, result) is logged to a separate D1 table `voice_logs` for
analysis, never mixed with people's data; later reduced to errors only (founder, 2026-10-19). The orb (jess) is Midas black and white; glow and violet core are
being prototyped. Plan: midas-intel `docs/plans/2026-10-13-voice-reminders-v1.md`.

**Order, founder 2026-10-13 (later):** the foundation first: **one stored data format for every
Sidekick**, the same format all agents use, so every Sidekick works with LLMs, Midas's own and
outside ones (Claude, OpenAI). Chosen for how easy it is to connect to Midas and to other systems.
Research first, then the founder decides. After that: the data rework and every doc updated to
it; then the Action button feature; then the voice router.

**Data format, decided by the founder 2026-10-13:** JSON records, one JSON Schema per record type
(option 1 of midas-intel `docs/research/agent-ready/data-format-interop-standards.md`). Chosen for
flexibility. Each user's Sidekick owns its schema and can change it freely, including after it is
shared (the copy belongs to the friend). What is shared and synced between people is only a
Sidekick's **core** data, marked when the Sidekick is built (Split: the amount owed and who owes
it). Everything else is personal. Scale is not a concern: each Sidekick serves a handful of
people. Harder cases (several people running different versions on one shared record) are handled
when a Sidekick needs them.

**Old formats retired (founder, 2026-10-20):** live and staging are converted to the unified data format (live dry run after the conversion: 0 writes). The upgrade-on-read code, the shell's epoch-millisecond and `body` fallbacks and the one-time migration tools are retired: no code reads or writes an old record shape. The migration scripts are kept only as history in `docs/legacy/code/` (not run, not tested). The server refuses every save that comes from a Sidekick version without schema types (the bundles from before the unified data rework, build 2 and older); it no longer lets them through unchecked (founder, 2026-10-20).

Held for when the voice work starts:

- The voice reminders plan, midas-intel `docs/plans/2026-10-13-voice-reminders-v1.md`, is not yet
  read by the founder. He reads it before implementation starts.
- Voice router: ask the founder for more details before building it or starting its agent.
- jess's look: the founder's design from his earlier project Job Autopilot (a circle with a blob
  inside), used at first and possibly converted to the Midas theme and `docs/DESIGN.md`. Remind
  him and take it from him then.

### Plan additions, 2026-10-23: repair UX upgrade, Make, push (founder)

**Repair UX upgrade, built and merged 2026-10-23** (founder: repair "is not part of our actual
Midas workflow, and that is not acceptable"; "I need this done right now"). Brief
`docs/briefs/repair-ux-upgrade.md`, mockup `docs/mockups/repair-feedback-2026-10-23.html`.

- **O4:** after the three-finger swipe, jess's orb pops out and drops into the left slot of the
  bottom bar. One orb on screen.
- **B3:** the bottom bar is a floating pill (orb, words, round send arrow); voice starts on its own,
  typing still works. Small Undo and Clear pills above it, **B+2**: frosted, active only when
  something is drawn; off, the words dim but stay readable.
- **V1 glow, then G+1:** a Volt rim on an ink line stays on from the swipe until Send or Cancel.
  G+1 (replaces L1): thicker and brighter, and it grows with the voice while the person speaks.
- **Repair tag:** drops out of the island while repair mode is on. **T1c Send:** the screenshot
  slips in under the tag, small swell, "Repair" becomes "Repairing". **S2:** the tag shows only on
  the Sidekick being repaired and shows the result there.
- **Fix live while on the Sidekick:** "Repair done. Tap to update"; tapping it updates the page,
  **U4** (the tag grows into the page). **Fix live while away:** the copy updates in the
  background; on return the page is already new and the tag shows "Fixed" for 1 second.
- **Results:** fixed, already there, couldn't fix, each with the runner's one-line summary. A
  runner `no_change` is now "Already there", never "failed" (migration `0010_repair_result.sql`:
  `result_kind`, `result_summary`; the status stays `failed` with reason "no change").
- **Voice in repair, fixed 2026-10-23:** the spoken words show live in the pill; the orb follows the
  voice level; word times are the recogniser's real ones; stale recogniser callbacks are dropped;
  listening starts again after the recogniser stops, and a voice error goes into the report
  (`voiceError`).
- **Colours:** tomato leaves Midas's own colours; Volt `#CEFF00` is the third colour, with black and
  white. Tomato stays a Sidekick tile colour. Details: `docs/DESIGN.md` §2.2.
- Builds 11 and 13 were set in Xcode only; build 12 carried the upgrade and live words, 14 the L1
  rim, **15 G+1 and B+2** (`052df5e`).

**Deploying (founder, 2026-10-23):** `docs/DEPLOY.md` is the step-by-step guide (order:
migrations, server, Sidekick pages, runner, app; staging first; live is the founder's). Every
command given to the founder starts with `cd` into its absolute folder (rule in `CLAUDE.md`).

**Make (working title, was "Build"; founder, 2026-10-23 and 24):** a default Sidekick for everyone,
like jess. Brief: `docs/briefs/make.md` (decisions, research, storage design); mockup
`docs/mockups/make-2026-10-23.html`.

- Built into the app (a native screen like jess), not a web page. Voice first, typing too; text
  only, no audio kept.
- One thread per request; Make's home is a list of requests, each with a status the founder sets
  by hand. Status shows only in the list.
- The thread uses repair's B3 pill bar. The founder's questions come as **T2 question cards**
  (carousel; tap selects, Send sends); the person can always answer in their own words. Cards are
  made by Claude skills later; the record format comes now.
- No repair on Make or on jess: the swipe there says "Repair not available for this Sidekick." and
  each try is logged.
- The founder has one inbox (staging and live) and gets a push for every message.
- The word "Repair" is not understood by everyone; a new word is being researched.

**Push notifications are built with Make** (founder, 2026-10-23 and 24): Midas has no remote push
yet. Push to the person only for a question card and for "built"; to the founder for every message.
The deferred repair notice "Your app has been repaired." (app closed) uses the same push.

### Plan additions, 2026-10-25: every repair reaches test-guardian (founder)

Repairs `50ca5522` and `9c699df4` (staging, 2026-10-24, "I don't want the year to be shown")
ended unsupported: the test from the same user's earlier repair `e298466e` ("add year as well")
blocked them, and no repair run since 2026-10-19 had the Agent tool, because the runner denied
"Task" (the Agent tool's own name in Claude Code). Founder: a user reversing their own request is
a valid request and must work as a fix, through the guardian's rules and the sandbox rules, for
all repair jobs.

- **Only test-guardian changes or deletes a test in a user's copy**, unchanged. The runner no
  longer denies "Task"; it denies every other subagent by name (Explore, Plan, general-purpose,
  claude, statusline-setup).
- **The guardian's file gains "Inside a repair job"** (founder's one-time permission,
  2026-10-25): the user's report is the authority, the check command is the full suite, change a
  reversed behaviour's test rather than delete it, log every answer in the copy's
  `TEST_CHANGES.md`. The repair prompts hand the guardian the check command.
- **A test deletion the guardian logged passes the runner**, like a logged change (for a feature
  removed with its tool, 2026-10-21). An unlogged deletion still fails the job.
- **`check-sandbox --agent` also proves the guardian path:** the session has the Agent tool and
  lists test-guardian, the agent reaches the guardian, and Explore and claude are refused.

### Plan additions, 2026-10-25: Water, a hydration Sidekick for Amogh (founder)

Plan: `docs/briefs/hydration-sidekick.md`. Look: "E. Tide" (`docs/mockups/hydration-2026-10-24.html`).
Research: midas-intel `docs/research/2026-10-24-hydration-apps.md`. Built and merged 2026-10-25
(`5ec5ac6`, `a3aa119`, `0355b13`). On staging since 2026-10-25 (accounts "test" and "R J"); not
live yet. The widget fix below is in build 17 (2026-10-26). Build 18 (2026-10-26) adds the
last-opened default, the "Add to Home Screen" sheet, the Glass icon and the Reminders widget on the
builder; Midas Test first, then live (founder, 2026-10-26). Build 19 fixes a crash found on
build 18 (2026-10-26 21:00): a notification button pressed with Midas in the background aborted
the app, because the notification callbacks answered iOS off the main thread (old code, since the
notification engine). Both now answer on the main actor (`ShellServices.swift`).
Build 20 (2026-10-27): the empty-day widget fix, Sidekicks first in the gallery, one Water
widget, and the Widget button on Water's Today (decisions below). Water deployed to staging.

**Widget builder: light and dark for every widget (founder, 2026-10-27, build 21).** Seen on build 20
in dark mode: Water's widget kept its light sand and sea while its text turned white (system
colour), white on light. Founder: "we forgot to build a dark mode for the widget builder itself...
add this [to the widget builder] cause every widget built should have these light and dark modes
and to be used as needed."
- Every explicit colour in a widget description (background, fill, text, button, symbol, chart) is a
  `{ light, dark }` pair; the builder draws the one that matches the phone's appearance.
- Text and symbols over a widget's own background never fall back to the system colour: the
  builder picks a readable ink for that background in each mode, so white on light cannot happen.
- A single colour from an older page still draws: the builder derives the dark one, so nothing
  already placed breaks; the checker and `docs/WIDGETS.md` tell every new or repaired widget to
  give both. Water sends its night Tide colours; Reminders gets pairs too.
- Tests render light and dark and check that text contrasts with what is behind it.

**Widget taps at once (founder, 2026-10-27: "clicking the button doesn't update it instantly. It
takes a couple of seconds").** The tap's intent runs in the app, which iOS wakes in the background
first. Build 21 runs it in the widget extension: the tap is queued and the widget redraws from the
tap preview (build 17); the app applies queued taps when it next runs. Reminder ticks the same.
Alarm and Live Activity buttons stay in the app. Until the app runs, a widget drink is not yet
backed up and Water can still remind inside its 45-minute quiet; the quiet then counts from the
tap's time.

Build 21 (2026-10-27): light and dark for every widget, and widget taps in the extension (both
above). Water and Reminders deployed to staging; R J's repaired Reminders copy was left for a merge
decision.

- **Water** (`sidekicks/hydration/`). Icon: "D · Glass", an ink tumbler on sand with the sea inside
  (founder, 2026-10-26; `docs/mockups/water-icon-2026-10-26.html`), drawn by the shell
  (`SidekickIcon.swift`); the catalog's Turquoise `drop.fill` is only the fallback.
  - Logging with presets, a custom amount and undo.
  - ml, L or oz. Everything is stored in ml; the unit is display only.
  - A streak: a day counts when the goal is met.
  - The Tide look: sand by day, the sea rising with the day's total; a night sea in dark mode.
  - On first open, Amogh sets the daily goal and the unit.
  - Screens: Today, Log, Settings.
  - 6 jess tools: `hydration.log`, `undo`, `today`, `set_goal`, `set_unit`, `set_reminders`.
- **Reminders that are right** (the research's top complaint was a reminder right after drinking
  or after the goal):
  - They fire only between a start and an end time (`endTime`).
  - Once the goal is met, they stop for the day; tomorrow's come back.
  - After any drink, logged on the page or on the widget, they stay quiet for 45 minutes (`listen`).
  - Defaults: 9:00–21:00, every 2 hours.
- **The widget logs water from the Home Screen**:
  - The Tide sea fills to the day's share.
  - Amount and goal show in the person's unit.
  - The streak, and preset buttons.
  - A week chart.
  - The day starts again at midnight without opening Water.
  - Fixed 2026-10-26 (founder: "+0.25 L saves but the widget does not change until Midas opens"):
    a tap that waits for the app now shows on the widget at once. The app publishes the records of
    every Sidekick with a widget; the widget refills itself with the waiting taps
    (`shell/Midas/SidekickWidgetTapPreview.swift`, `ba220e5`). General for every Sidekick widget.
  - Gallery order (founder, 2026-10-27: "lets get the folder things of all sidekicks to the front
    (in the list it should be the first)"): "Sidekicks" (the folder widget, small only) first, then
    "Sidekick" (`MidasWidgetsBundle.swift`). Adding the Sidekick widget swipes past the one
    Sidekicks page. Replaces "Sidekick first, no swipe" (2026-10-26).
  - One Water widget (founder, 2026-10-27: "in the water, there are still two options, like Water
    Today and Water Week, which should not be the case"): `widget:today`, named "Water"; small and
    medium show the day, large adds the week chart. The page deletes `widget:week`. The key stays
    `widget:today` so widgets already placed keep working.
  - Empty day fixed 2026-10-27 (`ac56453`): with nothing logged yet there is no `water:{today}`
    record; the fill's value resolved to nothing and the whole widget showed "Open Midas" (founder's
    phone, build 18). A missing fill value now draws an empty sea at "0 L".
- **Adding the widget, approved 2026-10-25/26, built 2026-10-26 (build 18):**
  - A newly added "Sidekick" widget shows the last Sidekick opened that has a widget (`745ec18`).
    A widget with nothing picked follows the last one opened; a picked one never changes.
  - An "Add to Home Screen" sheet in the iOS 26/27 look, the founder's chosen demo
    (`docs/mockups/widget-howto-demo-2026-10-25.html`) ported to SwiftUI
    (`shell/Midas/HomeScreenWidgetSheet*.swift`). It plays the steps, spotlights the Sidekick
    widget and lands the asking Sidekick's own small widget on the Home Screen (Water shows Water).
    No "pick the Sidekick" step: the last-opened default already picks it. Reduce Motion: the four
    steps as a still list. A Sidekicks folder version exists with no entry point yet.
  - Any Sidekick opens it by writing `request:<id>` `{ kind: "home-screen.widget", widget:
    "sidekick" }`; a page asks the shell (`{op:"shell"}`) which request kinds it supports and hides
    its entry on older builds. Rule for every Sidekick with a widget: `docs/WIDGETS.md`, reaches
    every repair agent through `{{WIDGETS}}`. Reminders has no entry yet.
  - Where it opens (founder, 2026-10-27, option A of
    `docs/mockups/water-add-widget-entry-2026-10-27.html`: "remove the add to home screen +" from
    Settings; "Let's go with A, but as soon as the widget is added, let's remove it. It should only
    be visible until the widget is added. Also, the log and settings should rearrange once the
    widget button is removed."): a "Widget" button in Water's bottom bar on Today, after Log and
    Settings. Shown only while no Water widget is on the Home Screen (the page asks the shell
    `{op:"widget-placed"}`, on open and on return); hidden, Log and Settings re-centre. Settings has
    no Add to Home Screen row. Builds 18 and 19 cannot answer, so they show no button.
  - Not possible: placing a widget for the person; iOS has no call for it (iOS 27 SDK, WidgetKit).
- **Shell additions (new app build), general for any Sidekick:**
  - Widget day keys `{today}`.
  - `format` (ml/L/oz) on text.
  - A streak source.
  - The `fill` piece and widget `background`.
  - `limit` on summed sources.
  - Reminder `endTime` and `listen`.
  - Syntax: `docs/WIDGETS.md`, `docs/NOTIFICATIONS.md`.
- **Repair: every personal Sidekick has a repair agent; only jess and Make have none.**
  `runner/agents/hydration.md`.
- **Limits as built:**
  - Widgets don't animate on iOS, so the wave on the widget is still.
  - An app build older than this one shows a plain widget: ring, amount in ml, buttons.
- **Ship:** staging (account "test") → Midas Test on the founder's phone → TestFlight (new build) →
  live, `assign-sidekick.mjs "Amogh" hydration --env live`.

### Plan additions, 2026-10-15: complaint first (founder)

Midas starts from the person's problem, not from an app request. The first thing Midas asks a
new user is **what their problem is and what they need to achieve**, and Midas works out the
solution; the person never has to describe or name an app. "Building apps" is not the poster;
solving the person's problem is.

Why (founder, 2026-10-15): everyone building personal software today is a developer (Kasey
Klimes's train app, Craig Mod, Lee Robinson, the daily Reddit "built it for myself" posts);
non-developers do not start from a blank prompt (the "Kuyda: 90% create nothing" figure in
the Wabi record could not be found in any source on 2026-10-15; unverified, do not cite). People cannot say what app they want; they can say exactly what bothers them (founding
essay, "people don't know what they want, but they know exactly what they don't want"). The
2026-10-13 repair feature already works this way inside a Sidekick (a bug said out loud, a change
shown on screen); this extends the same stance to the first contact.

What this touches, not yet decided:

- The opening question's exact wording (`docs/WRITING.md` applies). Candidates come from
  midas-intel `docs/research/2026-10-15-complaint-first-and-why-not-a-moment.md`.
- The generator's input: a problem statement plus a goal, not an app description. The generator
  (must land before Nov 2) and the knowledge bank's build recipes take the problem as input and
  choose the Sidekick shape.
- Tester outreach (X, Reddit, SHIP): the first message asks "what's your problem, what do you need
  to achieve", never "what app do you want". The request log records the problem in the person's
  words.
- Public copy: the App Store subtitle finalists ("Make the things only you need", "Ask for what
  only you need") and the pinned post are checked against this; not changed yet.

Research: midas-intel `docs/research/2026-10-15-complaint-first-and-why-not-a-moment.md` (why
personal software is not yet a mass moment; evidence for and against complaint-first; candidate
opening questions).

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
  Changed 2026-10-13 (founder): jess drives Sidekicks by voice, Reminders first (section 2,
  "Plan additions, 2026-10-13").
- Cross-app writes or actions. The owning Sidekick is the only writer of its record types.
- Siri exposure and MCP exposure of Sidekicks, and reaching the generator from an outside
  assistant. All need the manifest action layer first.
- Outside service connectors (for example Gmail), device data connectors, widgets.
- A rollback interface for users (2026-10-04).
- Voice input (typed only; changed 2026-10-13: voice is in, Reminders first), metering and billing, any public directory or URL, capability
  prompts, per-member roles and member removal, generated icons in build 1, screenshot-to-fix
  (changed 2026-10-13: repair is in, section 2, "Plan additions, 2026-10-13: repair").
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

**Shell vs separate native apps, research 2026-10-22** (midas-intel
`docs/research/2026-10-22-shell-vs-native/`): what the shell can and cannot do compared with one
native app per Sidekick, technical and App Store policy, with examples (walkie-talkie, location per
Sidekick). Fact recorded, no decision: guideline 4.7.2 bars a host from exposing native platform
APIs to mini apps "without prior permission from Apple" and names no transport, so request records
fall under it on its plain text; no public process for that permission was found.

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
`store.set("reminder:<id>", { at, title })`; `reminder:` is a reserved prefix. Notifications show the record's
`notes` under the title (founder, 2026-10-20). The shell
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
screenshot). Built 2026-10-15 in the unified data rework: files go to R2 (`midas-files`), the
record holds `file:<id>`, Sidekicks call `store.putFile` (midas-intel `docs/plans/2026-10-15-unified-data-v2.md`).
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

### Open tasks, 2026-10-24

State: main `5bc4692`, pushed (2026-10-24). Live and staging run main's server: migrations
0001-0010 on both (0010 `repair_result` on live since 2026-10-23), `midas-api` deployed. Midas
0.1.0 (15) uploaded to TestFlight (G+1 voice glow, B+2 Undo/Clear, the repair UX upgrade). Sidekick
pages on live: Reminders `20261023T073609661Z-57f3402b`, care-reminders
`20261023T073725671Z-d3e6d333`, with `tools.js`; jess assigned to every user. `JESS_GROW`: on for
staging; on live the founder's call. The repair runner on the Mac mini serves live and staging
from one process. Deploys follow `docs/DEPLOY.md`.

Next, in order:
1. **Make** (founder, 2026-10-24: "Docs are updated first, then building starts"): built into the
   app, one thread per request, T2 question cards, no repair on Make or jess, text only.
   Brief `docs/briefs/make.md`; section 2, "Plan additions, 2026-10-23".
2. **Push notifications, with Make:** only for question cards and "built" to the person, every
   message to the founder; then "Your app has been repaired." when the app is closed.
3. **The rest of public TestFlight, then the App Store (unlisted)** (founder, 2026-10-23): end-to-end
   test on live, a new account's first screen, privacy policy URL, Test Information, review notes,
   dead-end sweep, external group and Beta App Review, tester cap. Prep list and owners:
   `docs/briefs/public-testflight-prep.md`. Whether Make gates the public link is the founder's
   call.

Done 2026-10-26 (build 18), founder: "why are reminders their own widgets... we might need to fix
this":
- The Reminders widget is made with the widget builder: the Reminders Sidekick writes `widget:today`
  (small, medium, large). The builder gained late times (red once late, up to 24 extra looks a day),
  a "+N more" line instead of page arrows, and a reminder tick that shows at once. The native
  Reminders widget is removed from the gallery; a person who placed one re-adds it as a Sidekick
  widget. Merge `aa892ea`.

To do (founder, 2026-10-23), not started:
- Every Sidekick app icon has a light and a dark variant. Today the Reminders tile stays light when
  the phone is in dark mode.
- Repair runner uptime (`docs/concerns/2026-10-13-repair-runner.md` section 5): offline alert from
  the server, hourly health line and a free-disk check, stale-code warning; the founder's FileVault
  and automatic-update settings. "We will come back to it later."
- Daily-planner primitive (`docs/primitives/daily-planner/`, on the current record format since
  `7e6ab19`): the founder approves the type names (`planner.item`, `planner.settings`, ...) and the
  draft `repeat.moved` field, and decides the 9 patterns the current format cannot hold (its
  `records.md` section 12). Its guard check `test_daily_planner_primitive.py` passes and is not
  committed (guard files are the founder's).

Done 2026-10-26, build 16 (founder archives and uploads):
- **jess's logo from one place** (to do of 2026-10-25): the `JessTile` and `MakeTile` images live in
  `shell/Shared/Shared.xcassets`; `SidekickIconView` draws them for jess and Make on the home grid,
  in widget folders and in Make, never the catalog's `circle.circle.fill` / `plus` symbols. Controls
  keep `JessSymbol` (the same written word); the App Shortcut keeps `waveform` (iOS takes only SF
  Symbols there).
- **"Jess" with a capital J** (to do of 2026-10-23): the shell shows it whatever the catalog sends.
  The server's `JESS_LISTING.name` still says "jess": its test changes only through test-guardian.
- **The app installs on iOS 17 and up again:** `deploymentTarget` sat under `configs:` in
  `shell/project.yml` since 2026-10-07, where xcodegen ignores it, so each build needed the iOS of
  its SDK (iOS 27 with Xcode 27; phones on iOS 26 could not install). Guard test
  `tests/guard/test_deployment_target.py`.
- **Bhumi's Reminders:** her copy with Today, Next 7 Days and Scheduled only, in
  `copies/reminders/boomi/` (concerns: `docs/concerns/2026-10-25-boomi-reminders.md`). Live user
  `Gp9BeoMrdPjuKLBHY4s2jg`; assigning and deploying her copy is the founder's to run. Import Apple
  Reminders and Import File are back in her More menu (founder, 2026-10-26: "it's a reminders
  feature"); Apple's lists are left behind, since her copy has no lists.
- **jess and Make stay built into the shell** (founder, 2026-10-26): native screens, assigned at
  sign-up; not moved to web Sidekicks or manual assignment. So every shell change ships as a new
  build: raise `CURRENT_PROJECT_VERSION`, the founder archives in Xcode and uploads.

Done 2026-10-23: the repair UX upgrade and repair voice fixes, merged, build 15 uploaded, 0010 on
live (section 2, "Plan additions, 2026-10-23"); `docs/DEPLOY.md`; live rollout of the jess work;
the runner's token-file exposure closed (concerns section 4: agent file tools limited to the job folder, the agent's tests under
`sandbox-exec`); `agent/repair-data`, `agent/jess-look` and `agent/jess-workdesk` merged; the
daily-planner primitive moved to the current format and committed; midas-intel `docs/` (digests,
shell-vs-native research, X header drafts, YC draft) committed.

Later (founder, 2026-10-23: no router work soon): the jess router eval
(`backend/scripts/eval-jess.mjs`, 156 sentences, never run live) and any router revamp (Jev,
CONCERNS §14).

Later, already recorded elsewhere: Siri phrases ("Talk to jess in Midas"); repair notifications to
the founder (section 2, "Next build item"); Jev for the router (CONCERNS §14); tool removal history
(§15); relative times after a repair re-run (§16); voice logs reduced to errors (§12); staging test
accounts "Test" and "Voice Check …" look disposable (deletion is the founder's).

Worktrees left, all merged and safe to remove (2026-10-24): `care-repeat`, `jess-look`,
`jess-workdesk`, `repair-data`, `repair-polish`, `repair-ux`, `repair-voice`, `repair-words`,
`widget-app`, `widget-extension`, `widget-reminders`.

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

- **Midas Test, a second app on the same phone (founder, 2026-10-14):** "create a new bundle (for
  the shell midas test) so that I can have 2 installs on my phone at the same time", so the
  everyday Midas stays the same and updates are tried quickly in the test app. Build configuration
  `Test` and scheme "Midas Test": bundle `com.bhuvanrj.midas.test` (widgets
  `com.bhuvanrj.midas.test.widgets`), App Group `group.com.bhuvanrj.midas.test`, name "Midas Test",
  staging server, its own entitlements files `Midas-Test.entitlements` and
  `MidasWidgets-Test.entitlements` (same production-mode passkey domains, test App Group). Staging
  serves the test app ID in its apple-app-site-association. Debug and Release are unchanged.
  Founder, 2026-10-15: every build made to try something (simulator or iPhone) uses Midas Test,
  never Midas (rule in `CLAUDE.md`).

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

0. Beta App Review, target Mon Oct 12 (founder, 2026-10-11). Needed before submitting:
   a privacy policy URL (required for external testing); a new account must not open to an
   empty home grid (today Reminders is assigned by hand with `assign-sidekick.mjs`; how it
   becomes automatic is to be discussed first); Test Information (description, feedback email,
   contact, What to Test) and review notes (sign-in not required: the reviewer taps Get Started,
   types a name, uses Face ID); an external group with the build added, public link on after
   approval. Later builds of 0.1.0 usually skip full review; a new version number is reviewed.
   Plan for Mon Oct 12 (discussed 2026-10-11, start tomorrow; not yet approved to build):
   - The generator is not needed for review. Automatic Reminders is enough: Beta App Review
     checks that the build works as described, is not empty or broken, and follows the guidelines.
   - Proposed design, automatic Reminders: account creation also inserts an `assignments` row
     for `reminders`, in the same sign-up step, on staging and live. `assign-sidekick.mjs` stays for
     other Sidekicks; existing accounts already have Reminders. New test: a fresh sign-up has
     Reminders assigned. Server only, so build 0.1.0 (1) can be submitted without a new upload.
   - Beta description and What to Test describe only what exists (Reminders, made for you,
     Apple Reminders import), never the not-yet-built "ask in your own words" flow.
   - Before submitting: check the shell and the Reminders page for dead ends (a button or screen
     that goes nowhere, placeholder text; guideline 2.1).
   - Known review risks: 4.7 and 2.5.2 (Sidekick pages loaded from the server; answer in the
     review notes: a closed web view, no other origins, no native code) and 2.5.8 (widget folders,
     founder's call to test it here).
   - Questions put to the founder on 2026-10-11, no answer recorded (handoff 2026-10-22; status
     since then not checked): build automatic Reminders as proposed; submit build 1 as is or a
     build with the widgets; privacy policy URL and whether the lead drafts the text; feedback and
     contact email; public link tester limit; the item this displaces before Nov 2.
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
- **The native Reminders widget** (founder, 2026-10-11; replaced 2026-10-26 by the Reminders
  Sidekick's own `widget:today` on the widget builder, build 18): today's reminders only, small, medium and
  large, as in the mockup's second row. Tapping a circle marks the reminder done from the widget
  (founder, later the same day). Widgets cannot scroll (WidgetKit has no `ScrollView`), so when
  today has more than fits, arrow buttons page through them. "All done" when nothing is left,
  "Open Midas" when signed out. Brief: `docs/briefs/widget-reminders.md`. Today's order:
  reminders with a time first, earliest first, then untimed ones (founder, 2026-10-11); the
  Sidekick's Today follows. Built and merged 2026-10-12; count placement: layout D, "Today" and the
  count in a blue pill on one line across the top, rows full width (founder, 2026-10-12).
  A tick works like Apple's Reminders: the circle fills with a dot in the list's colour, the
  title greys, then the row leaves; no cross, no strikethrough (founder, 2026-10-12). All widget
  work is on main and pushed as build 0.1.0 (2) (`8bd3e89`); live on TestFlight and on the
  founder's iPhone (founder, 2026-10-12). Their worktrees are merged and safe to remove (section 6,
  "Open tasks, 2026-10-24").
- **Next week:** Control Center (open a Sidekick directly), App Shortcuts ("Open Reminders",
  "Open any Sidekick"), Spotlight, and `IndexedEntity` for Siri Suggestions.
- **Key feature, built and merged to `main` (`02bc0b4`): one widget any Sidekick fills** (founder, 2026-10-13: "one of
  the key features that needs to be built"; approved to build the same day: "Approve. You can start
  building". Version 2 chosen (layout described by the Sidekick). Displaces nothing before Nov 2
  (founder: "just build and add this to the doc as built"). Plan:
  https://claude.ai/artifact/UXKbkcZ4wkFUagH26rFd8m (`docs/mockups/sidekick-widget-plan-2026-10-13.html`);
  branch `agent/sidekick-widget`. One small/medium/large widget can be placed many times, each copy
  showing a different Sidekick or a different widget of the same Sidekick. The Sidekick saves
  `widget:<name>` records; they sync with the account; the shell fills `$` bindings from records
  and the widget draws fixed pieces. First user: care-reminders "Meds today".)
  Built 2026-10-13, 3 commits on `agent/sidekick-widget` (4cef4d4, 3e1f720, d375410): the
  `widget:` checker, filler, publisher, tap intent (tick, increment, toggle, set, open), two-step
  picker (Sidekick, then its widget), small/medium/large views; care-reminders "Meds today" and
  "Next up"; how to write one: `docs/WIDGETS.md`. 56 new shell tests; worktree shell suite 348/348.
  Not built from the plan: `page` taps and Lock Screen sizes. Renders of the real views:
  `docs/mockups/sidekick-widget-render-{light,dark}-2026-10-13.png`. Waiting on the founder: merge,
  then TestFlight 0.1.0 (3) to check on the phone. One widget named
  "Sidekick" in the gallery; the person adds it and picks a Sidekick in its settings (the list
  comes from the account at runtime, as in the Sidekicks folder widget, so a new Sidekick needs no
  new build). The Sidekick fills it; the shell draws it. Two versions (version 2 chosen):
  - Version 1, templates in the shell: the Sidekick names a template and sends data only. Drafted
    templates: List, Now & Next, Countdown, Progress, Counter, Actions, Number, Habit grid, Day,
    Stack (several Sidekicks in one widget), Card. A new template needs a new build; a new
    Sidekick using an existing template does not.
  - Version 2, layout described by the Sidekick: the shell knows a fixed set of pieces (stack,
    grid, text, symbol, tick circle, bar, ring, chart, timer, image, button) and draws the boxes
    the Sidekick sends. A new look needs no build if it uses known pieces.
  - Both: taps only run actions built into the shell (tick, increment, page, open); a new action
    or a new gallery entry needs a new build; no web view or Sidekick JavaScript in any widget.
  - Guideline 2.5.2 (checked 2026-10-13 on Apple's text): it bars downloaded code "which
    introduces or changes features or functionality"; DPLA 3.3.1(B) allows downloaded interpreted
    code that keeps the advertised purpose, stays in the sandbox and makes no app store. Version 1
    sends data only, so 2.5.2 does not apply (same as the Reminders widget now). Version 2: live
    App Store precedents go further (Widgy imports and shares widget designs as JSON with a public
    gallery; Scriptable runs user JavaScript to build widgets). 2.5.16 met; 4.7.2 answered as for
    the notification engine.
  - Mockups and how widgets and layouts work: https://claude.ai/artifact/T8uxN3REAU923UQsMUNQS3
    (`docs/mockups/widget-lab-2026-10-13.html`). Parked smaller limits:
    `docs/concerns/2026-10-13-glance-widget.md`. Same idea as option C in
    `docs/primitives/daily-planner/shell/planner-widget.md`. Research: midas-intel
    `docs/research/2026-10-13-one-widget-any-sidekick.md`.
- **Recorded, not worked on:** Action button, Lock Screen widgets and controls.
- **Siri App Intents for Reminders, parked (founder, 2026-10-19):** a typed `AddReminderIntent`
  plus `OpenIntent` on `SidekickEntity` would let Siri add reminders and open a Sidekick by voice
  today. Parked: the Action button stays the only voice door for now. Facts recorded: App
  Shortcut phrases cannot carry a free-text `String` parameter (only `AppEnum`/`AppEntity`), so
  "ask Midas to <sentence>" is two turns on classic Siri; whether Siri AI (iOS 27) fills a
  `String` parameter from the full utterance is untested. Research: midas-intel
  `docs/research/reports/App Intents agent access iOS 27.md`.
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
- Version 0.1.0, build 2 (build 1 uploaded 2026-10-11; build 2 adds the widgets, 2026-10-12); Info.plist reads both from `project.yml`.
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
(leading), lowercase "midas", small "m" with underline bottom-right. Accent, chosen (2026-10-11, revised the same day; replaced 2026-10-23 by Volt `#CEFF00`, tomato stays
a tile colour, `docs/DESIGN.md` §2.2): Tomato light #FF6347, held in reserve; the shell is
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

**care-reminders Sidekick, 2026-10-12 (founder).** A Sidekick for one friend of a friend:
medicine, injections, water, appointments, meetings. Merged to `main` (`79333a1`).
Deployed to staging (account "test") and live, assigned on live to Amogh.
Decisions:
- Design: mockup B2 "Size by urgency" (`docs/mockups/med-reminders-b2-2026-10-12.html`). List
  colours, final: Butter, Slate, Cocoa, Sky, Charcoal, Stone, Sand, Clay, Lavender, Teal, Sage,
  Pistachio, Forest, Apricot. Calm rules: off-white/off-black, overdue soft amber "When you can",
  done sage, "N today" only. Midas brand palette rules do not apply inside a Sidekick.
- Build option A: Sidekick only, no shell change. No nag, alarm or live timer for now.
- Lists carry early alerts that every reminder in them inherits; a list may have none. Delete a
  list deletes its reminders, with Undo. Done on any early alert completes the whole event.
- Add/Edit Reminder (founder, 2026-10-12, change 1): title, Date, Time, Repeat only. No icon
  (a reminder shows its list's icon), no list field (added from inside a list), no own alerts,
  no several-times-a-day. Tests for the removed behaviour go.
- Custom repeat (founder, 2026-10-12, change 2): Repeat gains "Every 2 hours", "Every 3 hours",
  "Every 4 hours" only, around the clock from the reminder's Time. Built as one daily-repeat
  `reminder:` record per time (12, 8 or 6 notification slots).
- Icon (founder, 2026-10-12): mockup "2 · Size by urgency"
  (`docs/mockups/care-reminders-icon-2026-10-12.html`), drawn by the shell
  (`SidekickArtwork.careUrgencyTiles` in `shell/Shared/SidekickIcon.swift`), since a manifest holds
  only an SF Symbol and a colour. Needs a TestFlight build; until then phones show the pill on sage.
- Merged since (`05a0f45`). State 2026-10-12: change 2 and the icon are on `agent/care-repeat` (`ad42cbf`, `b99fb59`,
  `ebdd734`, handoff `a9b170b`), full suite passing, not merged. Live version
  `20261013T053859761Z-596a1d4c`. Next: merge, remove the worktree, TestFlight build with
  `CURRENT_PROJECT_VERSION` above 2. `main` not pushed to GitHub; mockups in `docs/mockups/` not
  committed; founder to say.
- Known limits of option A: a later early alert still fires after Done until the page is opened; a
  repeat gets early alerts for its next occurrence only; the over-48 warning counts this Sidekick's
  records only; not yet tried on a real phone. Open concerns:
  `docs/concerns/2026-10-12-care-reminders.md`.
- Open: display name (now "Reminders").

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
