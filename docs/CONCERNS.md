# Concerns to revisit

Known issues the founder has chosen to revisit later. Each has a date, what it is, and when it
must be looked at again. Nothing here is decided; decisions go into `docs/PRODUCT.md`.

## 1. Account deletion versus "only the founder deletes" (raised 2026-10-10)

The founder runs every database operation that deletes (2026-10-10). App Store guideline
5.1.1(v) requires an app that lets users create an account to let them delete it from inside the
app. Internal TestFlight is not reviewed, so build 1 is not blocked; external TestFlight and Beta
App Review are. One possible shape: the app records the user's request and the founder carries
it out. Revisit before the first external TestFlight build.

Allowed without the founder (2026-10-10): the backend deletes a sign-in challenge the moment it
is used (so it cannot be replayed), and a scheduled cleanup removes expired challenges and
sessions. Neither holds user data.

## 2. An independent copy of the data (raised 2026-10-10)

D1 keeps one primary database, each write stored on 5 servers in different data centers
(committed when 3 confirm), plus Time Travel: restore to any minute of the last 30 days (Workers
Paid) or 7 days (Free). All of these live in one Cloudflare account, so an account problem or a
bad statement reaches every copy. Proposed: export the database before every migration, and on a
schedule to R2, with a copy outside Cloudflare later. Replication is on the list, not built.
**The backup plan (exports before migrations, scheduled exports to R2, a full `.sql` copy on the
founder's Mac) must be redone once Midas reaches 100 users** (founder, 2026-10-10).
Note: a Time Travel restore overwrites the database in place and erases everything written after
the chosen minute (it returns a bookmark, so the restore itself can be undone).

## 3. Per-Sidekick tokens (D3) (raised 2026-10-10)

Since 2026-10-09 Sidekicks talk only to the shell's local store, so build 1 needs no per-Sidekick
server tokens. They matter again for `store.claim` (the pooler), shared mode and the outside-API
proxy, where the server must know which Sidekick is asking. Open: the shell as the gate (it
forwards with the user's session and the Sidekick id) or server-enforced per-Sidekick tokens.
Revisit when the pooler, sharing or the proxy is planned.

## 4. Files larger than a record: screenshots, images (raised 2026-10-10)

**Built 2026-10-15** in the unified data rework: `store.putFile` / `store.fileUrl`, files in R2 as
`file:<id>` (20 MB), `POST /files`, `GET /files/:id` (`docs/briefs/data-rework-product-changes.md`,
phase 5). The text below is the concern as raised.

Records are capped at 64 KB (decided 2026-10-10). **Founder, 2026-10-13: files are in scope now, built in the unified data rework; a Sidekick must be able to save a screenshot.** The founder wants a reminder that shows a
screenshot and tells him to get to work, and other Sidekicks will need images, audio or documents.
A compressed screenshot is about 200 to 500 KB; D1 holds at most about 2 MB per row and 10 GB per
database, and every pull would carry the images. Proposed: the phone compresses the file and
uploads it to R2 under the user (stored only, never changed or deleted); the record holds a
reference such as `"image": "file:<id>"`; Sidekicks get a call like `store.putFile`; a reinstall
restores records first and fetches files when needed. Not built and not in build 1; estimated
about a day (backend routes, shell upload and display, the Sidekick call). Plan after phase 2 is
merged and tested on the phone.

## 5. A deleted passkey means a lost account (raised 2026-10-10)

The passkey is the only identity (D2). It is saved in the user's password manager, normally
iCloud Keychain, and syncs to their other Apple devices, so uninstalling Midas or moving to a new
phone keeps it. If the user deletes it themselves (Passwords app), it is gone from every device
once Recently Deleted is emptied (30 days). The server still holds the account and its records,
but nobody can prove they own it; "Get started" then makes a new, empty account with no link to
the old one. The same happens if the user loses their Apple Account. Known ways out, none chosen:
a second passkey on another device, a recovery code, an email or phone fallback, or the founder
moving the data by hand. Revisit before external TestFlight.

**Decided 2026-11-02 (founder): W1, manual recovery by email.** `/support` has a "Lost passkey"
section: "Email bhuvanrj73@gmail.com with your Midas name." Nothing in the app (no line under the
sign-in popup, no Recover button). The founder answers each email by hand and decides later how to
check who the person is and how to give the account back. Options worked out, none chosen:
- Check: V1 the person names things only the owner knows (list names, reminders, when they joined),
  checked against `ops`; V2 the founder knows them (text or call).
- Give back: A1 a founder script makes a one-time code (hashed, 24 h, single use, 5 tries), the
  founder emails a `/recover?code=` link, the person creates a new passkey in Safari on the same
  domain (RP ID), attached to the old user id (`passkeys` already allows several per user; needs a
  phone trial); A2 the same code typed in the app (app build, clashes with the onboarding popup);
  A3 the person makes a new account and a founder script copies the old account's ops and
  assignments to it (ops are append only, so copy, never update).
- Out of scope: self-serve recovery, email or phone at sign-up, recovery codes at sign-up, a
  passkey list in Settings, merging accounts.
Until a give-back path is built, a recovery email cannot be completed: no script attaches a
passkey or copies data today. Revisit when the first recovery email arrives.

## 6. Expired sign-in and unsynced changes (raised 2026-10-13)

The session token lasts 90 days. On a 401 the phone stops syncing (`RecordSync.swift:198`); the
change stays in the outbox because push throws before anything is removed (`RecordSync.swift:132`),
and at launch a 401 clears the token (`AuthModel.swift:39-40`). Not checked: whether anything tells
the user their changes are not backed up while signed out, and what happens to the outbox if they
reinstall or never sign back in. Founder, 2026-10-13: not an issue now; flagged.

## 7. Errors must heal themselves (raised 2026-10-13, founder)

The user never sees limits (100 ops per push, 1 MB, 64 KB per record) or sync errors; the product
just works. Today a correct phone never hits a push refusal, but if one happens (a bug, an old app
version) nothing repairs it. Wanted as a feature: every sync or storage error is detected, retried
or repaired automatically (for example: a too-large value moves to R2, an oversized push splits, a
refused op is reshaped or reported to the founder), and the data architecture is changed where an
error shows the design cannot hold the data. First step in the unified data rework (midas-intel
`docs/plans/2026-10-13-unified-data-v1.md`): nothing is ever dropped from the outbox unless the
server accepted it.

## 9. Voice denied by accident has no way back in Midas (raised 2026-10-15, founder)

iOS shows the microphone and speech prompts once. After a deny it never shows them again; only
the iOS Settings app (Settings › Midas) can turn voice back on. Midas asks at launch
(`shell/Midas/VoicePermissions.swift`, founder 2026-10-15), and the repair layer's permission
screen, which had an Open Settings button, was removed the same day. So today an accidental deny
leaves voice off with nothing in Midas pointing the user to Settings; repair still works by typing.
Wanted (founder, 2026-10-15): instructions that direct the user to bring it back, for example a
"Turn on voice" link to Settings wherever voice is used (repair layer, the Action button Listening
screen). Not needed now; must be done later, at the latest before the Action button voice
reminders ship.

## 8. Repair agent and the unified data rules (raised 2026-10-15, founder)

**Done 2026-10-19** (`docs/briefs/repair-data-2026-10-19.md`, merged): the prompts describe only the
current record types, the runner checks the schema and the user's records before publishing.

The unified data rework (midas-intel `docs/plans/2026-10-15-unified-data-v2.md`) does **not** touch
the repair agent, the runner or existing user copies. The founder says when; it happens before
deploy, after the Action button work. Needed then: the repair agent updates a copy's schema
whenever it adds a field or type; the runner checks the user's records against the new schema
before publishing; the prompt describes only the current record types, says files are supported and that the runner
publishes live, and care-reminders gets its own prompt; repaired copies are brought to the new
record shapes (few Sidekicks, so small); the pasted SDK pin in copies' tests
(`reminders-bundle.test.ts:30`) is updated.

## 10. Voice-permission check not yet proven by a test (raised 2026-10-15)

**Closed 2026-10-15** by `VoiceTranscriberTests.testPermissionDeniedThrowsAndNothingListens`.

From the 2026-10-15 test change (`TEST_CHANGES.md`, permission screen removed). The founder
approved the proof that the edited tests can still fail; breaks 1-3 ran on the simulator and each
turned the expected tests red. Break 4 (removing `await VoicePermissions.askAtLaunch()` from
`MidasApp.swift`) was blocked for test-guardian by the auto mode classifier; the lead ran it the
same day: `testMidasAsksOnceSignedInAndTheRepairLayerNeverAsks` failed with "Midas no longer asks
at launch", and the file was restored. Still open:

- **No test for "never listen before permission":** the guard is in `OnDeviceSpeechTranscriber.start`
  (`shell/Midas/RepairSpeechTranscriber.swift:50`, throws `notAuthorized`), and nothing tests it.
  Making it testable needs a small app-code change (pass a `VoicePermissionSystem` into the
  transcriber), then one new test: denied → start throws. Given to the repair owner agent
  (`docs/briefs/repair-owner-2026-10-15.md`), which reworks the transcriber anyway.

## 11. A Sidekick scrolls while the repair gesture is made (raised 2026-10-15, founder)

The circle is passive (it never stops the Sidekick's own touches, guideline 4.7.2), so on a page
that scrolls, drawing the circle also scrolls it, and the frozen screen shows where the page ended
up, not where the circle started. Accepted for now (founder, 2026-10-15). The founder's idea for
the fix, in their words: "2 finger for scrolling (dont implement yet)". Not built.

**Smaller since the three-finger swipe replaced the circle (2026-10-15), not gone:** a web view's
scroll follows any number of fingers (UIScrollView's pan has no maximum touch count by default),
so three fingers moving down still scroll the page up. The swipe fires as soon as every finger is
80 pt down, without waiting for the lift, so the page moves by about that much before it freezes,
instead of a whole circle's worth. At the top of a page the drag pulls it down (bounce) instead.
Not yet seen on the phone.

## 12. Voice transcripts are stored in full (raised 2026-10-19, founder)

Founder decision: every voice attempt's transcript, model reply and result go to D1 `voice_logs`,
separate from people's data, to see what works. Wanted later: rebuild it to obscure the words and
keep only errors. Until then the table holds what people said, readable by whoever can query D1.

## 13. Apple's App Store Review Guidelines update of 2026-10-16 (checked 2026-10-20)

Checked 2026-10-20: nothing concerning for Midas. Apple released the update on 2026-10-16
(https://developer.apple.com/news/?id=92th7e5i, plus
https://developer.apple.com/news/?id=vvzx6cul the same day). Not changed: 4.2, 4.3, 4.7,
5.1.1(v), 5.1.2(i).

Changed, worth knowing:
- 2.5.19 (new): no hidden, dormant or undocumented features; Apple ties it to apps that add
  features after approval. Touches the repair three-finger swipe (`shell/Midas/MidasApp.swift`,
  not shown in the app or review notes) and Sidekicks served from the server, which change after
  review (already a known 4.7 / 2.5.2 risk).
- 1.2: "AI content creation apps" now named; missing safeguards, or not fixing violations after
  notice, can breach the Developer Code of Conduct. Touches the generator and build 2 sharing
  (report button and owner-side block already planned); build 1 has neither.
- 2.3.14 (new): creative assets on the product page must match the app, suit all audiences, no
  misleading claims or pricing. Midas has none planned.
- No effect: links in Before/After You Submit, 3.1.1(a) wording merge, section 5 intro.

## 14. Revisit Jev for jess's router (raised 2026-10-21, founder)

The voice router uses DeepSeek only for now. Once `voice_logs` holds real cases, check DeepSeek's
routing failures and cost; if either is too high, test Jev (`typesafe/jev-1.13`, about $0.00002 a
call, about 0.43 s via OpenRouter) with the routing eval. Plan: midas-intel
`docs/plans/2026-10-21-jess-voice-router.md` section 3.

## 15. Removing a Sidekick's voice tools (raised 2026-10-21, founder)

Founder decision, for now: when a repair removes a feature from a Sidekick, the repair agent removes
its tool, its `tools.js` handler and its test in the same change, and the runner checks the page no
longer offers that action (option A, "allow removal"). Saved records stay. Not handled yet: a copy of
past tool lists (or a "retired" mark instead of deletion) for older page versions or phones still
using a removed tool. Revisit when that becomes a problem.

## 16. A re-run after a repair can land after a relative time has passed (raised 2026-10-21)

"Remind me in 20 minutes …" that goes to repair is re-run with its original time once the repair is
published. If the repair takes longer than 20 minutes, the resolved time is already past and the
handler refuses: the person sees Not Done. Founder, 2026-10-21: discuss it when it actually happens.
Related: a re-run that never starts or never finishes shows Not Done after 10 minutes (builder
default, kept).

## 17. Notification levels: open points (raised 2026-10-24)

Founder decisions are in `docs/PRODUCT.md` section 2, "Plan additions, 2026-10-24". Each point
below has the default an agent uses unless the founder says otherwise.

- **L1 Passive:** not built (founder, 2026-10-24: "It should work as it is right now").
- **Every timed reminder is Time Sensitive** (founder, 2026-10-24: "All-time reminders have to
  follow this new thing ... unless the user asks for some reminders to not be that way"). This
  covers reminders saved before the change: a reminder without `reminderType` is Time Sensitive.
  Undated reminders notify nobody.
- **The stored field is `reminderType`** (founder, 2026-10-24: "reminder type" instead of
  "level"), values `"normal"`, `"timeSensitive"`, `"alarm"`; absent = `"timeSensitive"`. Not the
  record's `$type`.
- **Where the person picks:** one choice per timed reminder, Normal / Time Sensitive / Alarm, in the
  Reminders page and as an argument of jess's add and edit tools. Care keeps the default until its
  page gets the choice.
- **Merge conflicts with other branches** (`agent/make-shell` also changes `shell/`): resolved by
  another agent the founder assigns, not by the notification-levels lead (founder, 2026-10-24).
- **Early alerts, snoozes, hourly times, missed notifications:** same level as their reminder,
  except an Alarm reminder's early alerts and missed notice, which are Time Sensitive (an alarm
  ringing "2 days before" is not what Alarm means).
- **Alarm repeats:** AlarmKit repeats only never or weekly. Other repeats (daily every N days,
  monthly, yearly, `until`) are booked as one-time alarms, next occurrence only, re-booked on each
  engine run. If Midas does not run before the next occurrence, it fires as a Time Sensitive
  missed notification.
- **Alarm buttons:** Stop (iOS) and Snooze (the one secondary button; starts L7). The L7 card has
  Done and Stop. Done on the alarm itself is not possible alongside Snooze.
- **Permissions:** AlarmKit asks once, when the first Alarm reminder is saved. Declined: the
  reminder is booked as Time Sensitive. If the person turns Time Sensitive off in iOS Settings, it
  arrives as Active; Midas shows nothing about it.
- **Subtitle = the name the person sees** (founder, 2026-10-24): the person names their own
  Sidekicks ("He can call the app whatever he wants to"), and that name is the subtitle.
  care-reminders is "care reminders" only to the developer; to the person it is "Reminders", so two
  Sidekicks both called "Reminders" is the person's own choice. Until a rename exists, the subtitle
  is the manifest `name`, as on the home tile.
- **Layout F parked:** revisit with a Midas Test build on a phone; App Review acceptance for a
  non-messaging app is unknown.
- **Left after the build (merged 2026-10-25, `fb6d946`, `6e16ed9`; recorded 2026-10-29):**
  - Not tried on a phone: the alarm ringing, the L7 countdown card's look, the Time Sensitive label.
    Check with a Midas Test build on the founder's iPhone.
  - Founder step, only if Xcode's automatic signing does not add it on the first device build:
    Apple developer portal › Identifiers › `com.bhuvanrj.midas` and `com.bhuvanrj.midas.test` ›
    tick Time Sensitive Notifications › Save.
  - `backend/scripts/jess-golden.json` (jess eval sentences, never run live) has `reminders.add`
    calls without `reminderType`, which the tool now requires (null allowed). Update before the
    eval is run.
  - test-guardian's change to `NotificationNotesTests` (commit `8a2c7ae`, `TEST_CHANGES.md`) still
    owes its own "can still fail" check.
  - `repair-data-review-fixes` hit its 5-second limit once during a full run, passed on reruns:
    possibly flaky.
  - Not built (not asked): the picker in the new-reminder toolbar (it is in the Details sheet only,
    row "Alert"); Apple Reminders "Urgent" mapped to Alarm on import.
  - Alarm snooze length is 9 minutes (agent's default, from the mockup's "rings again at 11:09").

## 18. Sidekicks cannot read the phone's tilt (raised 2026-10-27, founder)

Amogh asked Water on live, twice (2026-10-28 01:05 and 01:06 UTC, repair jobs `ef0e08d6`,
`a3cc0820`): "Can we make the water interactive by using phones gyroscope?" The repair agent
answered unsupported and changed nothing, correctly: iOS gives a page motion and orientation only
after `DeviceOrientationEvent.requestPermission()`, which inside WKWebView goes through the
shell's `WKUIDelegate` (`requestDeviceOrientationAndMotionPermissionFor`), and the shell does not
implement it. Same kind of gap as camera, microphone and location.
Fix when picked up: a shell build that grants (or prompts for) motion for Sidekick pages, then
the Water page tilts its existing wave layers from `deviceorientation`, still under Reduce Motion.
Founder, 2026-10-27: not now, record it.

## 19. Water: removing a drink is hard to find, and only today's (raised 2026-10-28)

Amogh told the founder he asked for a way to remove water once logged. No such repair reached the
runner (his only Water jobs are #18's two; `~/Library/Logs/midas-runner/runner.log` shows no
failed claim then), so it was never sent or only said aloud. Water already has it: Undo on the
4-second toast after a log, and an × on each of today's drinks (and on "From widget") under Log.
Gaps: the × sits behind Log, and earlier days' drinks cannot be removed. The founder tells Amogh
where it is; build it in his copy only if he still asks.

## 20. Repair keeps listening while the person types (raised 2026-10-29, founder) — FIXED in build 22

**Fixed (checked 2026-11-02):** `c720617` (build 22 edit-voice). The keyboard stops the
transcriber, the words already heard stay, it does not listen again by itself; tapping the orb
listens again and puts the keyboard down (`RepairSession.isTyping`). Tests:
`testTheKeyboardStopsVoiceAndKeepsTheWordsHeard`,
`testTappingTheOrbListensAgainAfterTheWordsAndPutsTheKeyboardDown` (`Build22EditVoiceTests`).
Reaches the phone with the 0.1.0 (22) upload. Original report below.

After the three-finger swipe, voice starts and transcribes correctly. When the person starts
typing, the orb goes grey but the microphone keeps listening and words keep landing in the pill.
Founder: typing should stop transcribing. In the code, typing only changes the orb's look
(`shell/Midas/RepairCanvasView.swift:171`, `session.isListening && !isTyping`); the transcriber is
never stopped, and `RepairPillTextView.swift:91` deliberately inserts words heard while typing.
Fix: stop the transcriber when typing starts (keep what was already heard). Open: whether tapping
the orb restarts listening.

## 21. jess ends listening too soon when the person pauses to think (raised 2026-10-29, founder) — FIXED in build 22

**Fixed (checked 2026-11-02):** `c720617` (build 22 edit-voice), founder 2026-10-31: listening ends
2.5 s after the last word, 30 s at most (`VoiceReminderListening`, `shell/Midas/VoiceReminderFlow.swift`).
Tested in `Build22EditVoiceTests`. Reaches the phone with the 0.1.0 (22) upload. Original report below.

When jess is listening and the person stops to think, listening ends at once and the half-said
request is acted on. Current setting: listening ends after 1.2 s of silence after the first word
(`VoiceReminderFlow.endOfSpeechSilence`, `shell/Midas/VoiceReminderFlow.swift:87`; 15 s maximum).
Founder will think about how to rework the cutoff; not decided.

## 22. Leftovers from the repair-guardian fix (raised 2026-10-29, lead session)

The fix (`8938c37`, PRODUCT.md "Plan additions, 2026-10-25: every repair reaches test-guardian")
is on the runner; repairs `35cadeae` and `bffa6356` changed tests through the guardian since.
Left open:

- **Repair summary says the wrong environment.** `summary.md` of staging jobs `50ca5522` and
  `9c699df4` says "Environment: live" while `job.json` says `staging`
  (`runner/lib/summary.mjs`). Not fixed.
- **The founder's staging "hide the year" repair was never sent again** after the fix. The
  staging copy still shows the year and carries `reminders-today-year.test.ts` (from `e298466e`).
  Founder's call whether to resend.
- **midas-intel design doc lacks the 2026-10-25 decision** (only `docs/PRODUCT.md` has it). The
  lead session adds a dated line there.
- **Untracked on `main`:** `docs/mockups/notification-levels-2026-10-24.html` (not on origin).
  Commit or delete: founder's call.
- **Stale Herdr workspaces** whose worktree folders are gone: notif-levels-shell,
  notif-levels-reminders, reminders-widget-builder, home-screen-sheet, widget-entry, widget-dark,
  widget-tap-speed. The lead session closes them.

## 23. Notification levels, Reminders side: leftovers (raised 2026-10-24, Reminders agent)

Built and merged: `agent/notif-levels-reminders` (`c808441`, `da5b590`). Open points (§17) are the
decisions; these are what the build left out.

Status 2026-11-01 (lead, merging this handoff): the toolbar Alert choice is built in build 22;
Apple "Urgent" cannot import as Alarm (EventKit does not expose the flag; PRODUCT.md build 22).

- **No Alert choice while typing a new reminder.** The Normal / Time Sensitive / Alarm menu is
  only in the Details sheet (`sidekicks/reminders/index.html`, `sheetMainHtml`), not in the
  toolbar shown while typing a reminder. A reminder typed there stays Time Sensitive until opened in Details.
  Founder's call whether the toolbar gets it.
- **Apple Reminders "Urgent" is not imported as Alarm.** `mapAppleExport` ignores it; imported
  reminders are Time Sensitive. Founder's call.
- **No jess eval cases for the new words.** `backend/scripts/jess-golden.json` has no "set an
  alarm …" or "… not time sensitive" case; existing cases still hold (missing nullable args
  default to null). Add cases with the next eval run.
- **Possibly flaky check:** `backend/test/repair-data-review-fixes.test.ts` ("refuses the repair
  when the reporter's record already has a priority field …") timed out at 5 s once on
  2026-10-24 while the shell suite ran in parallel; passed on every rerun. Watch it.
- **Not deployed by the agent:** Reminders Sidekick with `reminderType` goes out with the lead's
  next Sidekick deploy (`docs/DEPLOY.md`); check whether it already went to staging and live.

## 24. Leftovers from the Sidekick test guardian (raised 2026-10-30, lead session)

(§23 is taken on the unmerged branch `handoff/notif-levels-reminders`.) The fix is `e9ea6ea`
(PRODUCT.md "Plan additions, 2026-10-30: a separate test guardian for Sidekicks"), pushed, and
the runner clone pulled `c71a4c7..e9ea6ea` and restarted on 2026-10-30;
`check-sandbox --agent` passed on it. Left open:

- **Photo Reminders repair not resent yet.** Staging job `5700cf94` (Reminders, "add screenshots")
  failed before the fix. Founder resends. If a sidebar test blocks it again, the new guardian
  should accept; the job's `summary.md` shows it under "Changed by test-guardian". If it fails,
  read that job's log in `~/Library/Logs/midas-runner/`.
- **Live claims fail.** `runner.log` repeats `live: claim failed: 500` from before 2026-10-30
  (staging claims work), so live repairs are not picked up. Not investigated. DEPLOY.md
  troubleshooting: check live migrations and deploy.
- **The test guard was not active in this session.** It started in `~/Desktop`, so Midas's
  `.claude/settings.json` (the PreToolUse hook) and the `test-guardian` subagent type did not
  load: guard-file and test edits were not blocked. The guard files were changed under the
  founder's one-time permission (2026-10-30); the two test changes went to an Opus agent told to
  follow `.claude/agents/test-guardian.md` (logged in `TEST_CHANGES.md`); the pre-commit hook
  passed. Any session started outside the repo has no guard. Founder's call.
- **Guard suite has one failing test, not from this fix:** `tests/guard/test_simulator_pool.py`
  (untracked, another session's simulator-pool work, with untracked `scripts/sim.sh`) expects
  `scripts/test-all.sh` without the `:-iPhone 17}` default. On this Mac `scripts/test-all.sh`
  alone fails the shell suite (no "iPhone 17" simulator); `scripts/sim.sh run scripts/test-all.sh`
  passes it (1028 tests). Whoever owns the pool work finishes it.
- **midas-intel design doc lacks the 2026-10-30 decision** (only `docs/PRODUCT.md` has it). The
  lead session adds a dated line there.
- **`CLAUDE.md` "Tests are guarded" does not name the Sidekick guardian**
  (`runner/agents/sidekick-test-guardian.md`). Lead session adds it; `CLAUDE.md` also has
  another session's uncommitted edits, so commit them separately.
- **Brittle-test audit (2026-10-30, read-only):** about 700 brittle assertions in about 214 test
  files, about 200 that block features. Only the Reminders sidebar checks were fixed. Others that
  block repairs: exact tool lists (`reminders-tools.test.ts:114`, `care-reminders-tools.test.ts:115`,
  `hydration-tools.test.ts:156`, `HydrationSidekickTests.swift:334`) and source-text checks on
  Sidekick pages (`RemindersSidekickWidgetTests.swift:96-97, 217-220`,
  `reminders-title-wrap.test.ts:12-30`, `reminders-next7-empty-days.test.ts:14`,
  `reminders-reminder-type.test.ts:315, 329-332`, `jess-page-limits.test.ts:219`). In a user's
  copy the Sidekick guardian now handles them; the shared ones change only through test-guardian
  with a founder decision. Shell source-text tests stay (founder, 2026-10-30). Founder's call
  whether to fix the rest.

## 25. Sidekicks that do not yet meet "every Sidekick ships a widget" (raised 2026-11-02, lead session)

Rule: `docs/WIDGETS.md`, "Every Sidekick ships a widget" (founder, 2026-11-02). Found while adding it:

- **To-Do has no widget, and the shell cannot draw its Today yet.** The `reminder:` `when: 'today'`
  source lists only to-dos with a time today; untimed and carried-over to-dos are missing, and
  To-Do's repeat is `recur`, which the source does not read. Needs a new source in the shell
  (`SidekickWidgetFiller.swift`) and an app build. Until then To-Do can ship only a timed-today
  widget, which would look wrong.
- **Reminders and care-reminders have widgets but no Add Widget entry.** Neither has the "?" menu;
  only Water does. Each needs the menu (page change, deploy; personal copies stay as they are).
- **Briefs written before 2026-11-02 have no "Widget" section** (Reminders, care-reminders, Water,
  To-Do). Their widgets exist without a blueprint; writing one after the fact is optional.
- **The Sidekick guardian's rules do not name the widget rule.** It protects an existing widget but
  does not ask a repair to keep the `widget:` records and their `version` in step; the rule reaches
  repair agents only through `{{WIDGETS}}`. Its file is a guard file: founder only.
- **No generator yet.** Make's builder does not exist, so the rule binds the agents that build
  Sidekicks by hand today; the generator must follow it when it is built.

## 26. Custom notification sounds, parked until people ask (raised 2026-11-02, founder)

Founder, 2026-11-02: "Let's not do this, but put it into concerns, and then we'll figure out more
about this if and when people ask for it." Mockup: `docs/mockups/custom-sounds-2026-11-02.html`.
Today every notification plays `.default` (`shell/Midas/NotificationBooking.swift`, `content.sound`)
and repair refuses sound requests (shell limit). Two ideas, neither built:

- **A, one sound per Sidekick, shipped in the app.** `.caf` files in the app bundle; the Sidekick's
  `manifest.json` names one. Each new sound is an app build and App Review; users cannot add their own.
  Open: where the files come from (made by us, supplied by the founder, or a CC0 pack).
- **B, a sound the user picks per reminder.** File picked in the Sidekick → `store.putFile` → shell
  copies it into `Library/Sounds` and books `UNNotificationSound(named:)`; an optional `sound` field
  on `reminder:` (additive, repair-safe). Apple lists `Library/Sounds` of the app container as a
  search location; copying files there at runtime is UNVERIFIED (try once on a device first). aiff,
  wav or caf, Linear PCM / IMA4 / µLaw / aLaw, under 30 s or the default plays; mp3 / m4a would need
  converting by the shell. No recording in a Sidekick (no microphone); no custom vibration (Apple).
- **Order if both:** the reminder's sound, else the Sidekick's, else the iPhone default.
- **Smallest step without new files:** iOS's own sounds a Sidekick could pick by name are only the
  default, the critical default (needs Apple's critical-alerts entitlement, not held) and the ringtone
  default (`defaultRingtone`, iOS 15.2; its rules not checked), plus no sound. iOS's named tones
  (Tri-tone, Chord, ...) cannot be referenced by an app; copying them into the bundle means
  redistributing Apple's files (not checked whether allowed).
- **Plan when it comes back:** shell support generic, Reminders page picker first, repair agents
  (Reminders, To-Do) learn the `sound` field, `docs/NOTIFICATIONS.md` and intel reference N04 updated.

Revisit when a user asks for a sound (a repair ending unsupported for a sound is the signal).

## 27. IMMEDIATE, next build: home tiles keep jiggling after the minus badges go (raised 2026-11-02, founder)

Founder, 2026-11-02, on build 23: press and hold a tile, the tiles jiggle and show the minus
badges. Tap somewhere else: the minus badges go, but the tiles keep jiggling, which should not be
possible. Closing and reopening the app stops it. "A big fucking bug fix ... add this to immediate
changes. Don't make changes." Not fixed; first item of the next build.

Where to look (not verified): the jiggle is `HomeTileJiggle` (`shell/Midas/SettingsView.swift`,
around line 487). It starts a `repeatForever` animation on `isTilted` and stops it by setting
`isTilted = false` inside a new `withAnimation`; in SwiftUI that does not reliably cancel a
repeating animation, so the rotation can keep swinging after `isOn` is false. The badges come from
`showsMinus` in `shell/Midas/SidekickHomeGrid.swift` (lines 85-123), which is why they go while the
jiggle stays. Also check that every way out of arranging (tap elsewhere, "Done", opening a tile,
leaving the home screen) ends the jiggle, and add a test for it.

## 28. Edit (repair) check after the public TestFlight: findings (raised 2026-11-05, lead session)

Founder asked whether Edit was stuck (friends said it was not working). Checked 2026-11-05 on the
Mac mini, read-only except the one founder-approved settle below:

- **Not stuck.** Runner (`com.midas.repair-runner`) up, both servers answer `/health` 200, no report
  `received`, `queued` or `running` on live or staging; `repair_blocked` empty. Live 2026-11-05: three
  edits, all published in 2-7 min (`4c9ec881`, `dbc32614` from new public tester `cTtee9…`;
  `14402759` from `CkL16r…`). Friends' failures did not reach the server: not signed up yet, or the
  phone's send failed and is waiting in its outbox. Open: watch `wrangler tail` (live) while one of
  them sends an edit, to see whether anything arrives.
- **Founder's replies in an edit thread never reach the agent.** Report `0616a34f` (To-Do, "All of
  them", unsupported 2026-11-03): one minute later the founder answered in its Make Inbox thread
  ("The person doesn't want those features so remove them"); nothing sends that to the runner, so the
  edit stayed "Taking a Deeper Look". Today the only ways out are a hand fix or a new edit. Founder's
  call whether a reply should re-run the edit with the answer.
- **`0616a34f` settled by hand, 2026-11-06 (founder: "mark the job as complete").** The two
  statements of `closingStatements` (`backend/src/edit-failed.ts`) were run on live D1:
  `deployed_live` / `fixed`, summary "Sent again as a new edit", user `deployed_live` notice. The
  inbox record `req:PrGgyZ7ZCO7mo3wKxuShcA:edit-0616a34f…` still says `sent`: founder taps Built to
  close the thread (no second notice). Founder sends the clear edit himself: "Remove (or hide) Add
  Subtask, When, Part of Day, Time, Deadline, Repeat and List from this sheet" (remove also drops
  jess's tools for them; hide keeps them).
- **Runner log noise** (`~/Library/Logs/midas-runner/runner.log`, before the restart ~2026-11-04):
  hundreds of `live: jess re-runs failed: 400 bad report id`, and `live: account deletion clean-up:
  deletion list failed: 404` (live server older than the runner's deletion route, or route missing).
  Not seen since the restart; `staging: fetch failed` twice right after it. Not investigated.
- **Reading live D1 from a Claude session** needs the command run outside the sandbox (inside it,
  Cloudflare answers 7403). A multi-statement write also got 7403 once; one statement per call worked.

## 29. Sidekick icons are not customisable from the manifest (raised 2026-11-09, founder)

Founder: "every icon should be highly customisable after build 24 right if not add this to concerns
and will make sure to add support for that".

- **As built (build 24):** a manifest `icon` is only `symbol` (an SF Symbol name), `background` and
  `backgroundDark`. Any custom drawing is hard-coded in Swift per Sidekick id
  (`SidekickArtwork.artwork(forSidekickId:)` in `shell/Shared/SidekickIcon.swift`: `hydration` →
  Glass, `money` → Wallet). A new or changed custom icon therefore needs a new build, and phones on
  older builds fall back to the SF Symbol (founder saw the green tile with a dollar on build 23 for
  Money, 2026-11-09).
- **Required (founder, 2026-11-09: "I fkn want every icon to be customizable"):** every icon, on
  every Sidekick (starters, Water and Money included, and every generated one), fully customisable from its manifest, shipped by a Sidekick
  deploy with no app build (e.g. the manifest carries the artwork as SVG or vector paths plus
  colours, the shell renders it everywhere `SidekickIconView` draws: home grid, Sidekicks folder and
  folder widget, Make, Settings list and delete sheet). Repair and the generator can then change
  icons too.
- **Status:** not designed or built. Founder will add support; design to be discussed first. Until
  then, Money's manifest fallback stays `dollarsign.circle.fill` (founder, 2026-11-09: "its fine").
