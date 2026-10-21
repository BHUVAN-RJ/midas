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
