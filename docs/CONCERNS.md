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

Records are capped at 64 KB (decided 2026-10-10). The founder wants a reminder that shows a
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

## 11. A Sidekick scrolls while the circle is drawn (raised 2026-10-15, founder)

The circle is passive (it never stops the Sidekick's own touches, guideline 4.7.2), so on a page
that scrolls, drawing the circle also scrolls it, and the frozen screen shows where the page ended
up, not where the circle started. Accepted for now (founder, 2026-10-15). The founder's idea for
the fix, in his words: "2 finger for scrolling (dont implement yet)". Not built.
