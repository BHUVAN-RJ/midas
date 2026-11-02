# App Store and TestFlight submission drafts (2026-10-31)

Drafts for the founder (build 22 brief, row `edit-failed-store`). Updated 2026-11-02 with the founder's
decisions of 2026-11-01/02 (`docs/PRODUCT.md`, "Plan additions, 2026-11-02"). Every other statement comes from the code
at commit `604aff3`; sources are listed under each section. "check" marks a claim not settled by
the code. Nothing here is submitted; the founder pastes and submits.

Live host (the app's live server, `shell/Midas/PlatformConfig.swift:4`, `shell/project.yml:68`,
`backend/src/auth.ts:21`): `https://midas-api.midas-backend.workers.dev`

- Privacy policy URL: `https://midas-api.midas-backend.workers.dev/privacy`
- Support URL: `https://midas-api.midas-backend.workers.dev/support`

Served by `backend/src/public-pages.ts` (branch `agent/edit-failed-store`); live once the founder
deploys the server (`docs/DEPLOY.md`). The page words live in that file; change both together.

---

## 1. Privacy policy page (`/privacy`)

Copy the block below into the page verbatim.

<!-- BEGIN PRIVACY PAGE TEXT -->
```text
Midas Privacy Policy
Effective 2026-10-31

What Midas keeps

- Account: the name you type when you start, and your passkey's public key. Midas has no email, phone number or password for you. The private part of your passkey stays in your iCloud Keychain.
- Sidekicks: everything you add in your Sidekicks (lists, reminders, drinks, notes, photos you attach) is backed up to Midas so it comes back on a new phone.
- Apple Reminders: if you tap Import, Midas reads your Apple Reminders on your iPhone (lists, titles, notes, links, due dates, alerts, repeats, priority, done or not) and saves them in your Reminders Sidekick. Midas never changes Apple Reminders.
- Notifications: your iPhone's push token, so Midas can send you notifications.
- Device details: iPhone model, iOS version and Midas version, sent with voice requests and Edit requests.

Voice

- Your voice is turned into text on your iPhone. Audio never leaves your iPhone.
- The text is sent to Midas, with your time zone and the names and a short summary of what is in your Sidekicks, to work out what you asked.
- To understand the text, Midas sends it through OpenRouter to a language model provider. Midas asks OpenRouter to use only providers that do not keep or train on the data.
- Midas keeps a log of each voice request (the text, the answer and the device details) to see what worked. The log is kept while your account exists and deleted with it.

Edit

When you swipe down with three fingers and send an Edit, Midas receives:
- what you said (as text) and anything you typed
- a screenshot of the Sidekick, your drawing and its strokes
- your iPhone model, iOS version and Midas version

Edits are made by Anthropic's Claude coding assistant on a Midas server. Your request and that Sidekick's data are copied to that server and sent to Anthropic so the change can be made. Midas keeps every Edit request and its result.

Make

What you write in Make goes to the person who makes Midas, who reads it and answers.

Who sees your data

- The person who makes Midas, to run Midas, answer Make requests and fix problems.
- Cloudflare, which stores Midas's data. Cloudflare's server logs may include IP addresses and are kept 7 days.
- OpenRouter and the model provider it picks, for voice requests (not kept by them).
- Anthropic, for Edit requests.
- Apple, to deliver notifications.

Midas has no ads, does no tracking across other apps or websites, and never sells your data.

Delete your account

In Midas: Settings, then Delete Account. Your account and all your data are deleted within 7 days. To ask for deletion another way, email bhuvanrj73@gmail.com.

Changes

This page shows the date of the latest version.

Contact

bhuvanrj73@gmail.com
```
<!-- END PRIVACY PAGE TEXT -->

Notes on the text (not for the page):

- Founder, 2026-11-02: the Edit line ("on a Midas server", not "Midas's own computer"), the voice
  log kept while the account exists and deleted with it, and the Cloudflare server logs (IP
  addresses, 7 days) are decided. They are in the block above and not yet in
  `backend/src/public-pages.ts`; change both together. The deletion paths behind "deleted within
  7 days" are being built (`agent/account-deletion`).

- No founder's name on the page (a placeholder must not go live); add one in `public-pages.ts` if wanted.
- "Midas keeps every Edit request": the repair log is never shortened
  (`backend/migrations/0005_repairs.sql`, comment above `repair_events`). How this squares with
  deletion within 7 days is an open point (section 6).
- Word list (midas-intel `docs/word-list.md`) bans "Cloudflare", "model" and "agent" in public
  copy. A privacy policy has to name who processes the data, so they are named here; founder's call.

Sources:
- Account: `backend/src/auth.ts:243-249` (users row: id, name; passkeys row: credential id, public
  key, counter, transports), `backend/migrations/0001_auth.sql`; sessions keep only a token hash
  (`auth.ts:179`, `hashToken`).
- Records backup: `backend/src/sync.ts:10-12`; files (photos, 20 MB): `backend/src/files.ts:5-9`,
  `shell/Midas/FileStore.swift:3-6`; file picker in `sidekicks/reminders/index.html`.
- Apple Reminders import: `shell/Midas/AppleRemindersImport.swift:4-13`, fields at lines 15-76;
  permission text `shell/Midas/Info.plist:60-61`.
- Push token: `backend/src/push.ts:8`, `backend/migrations/0011_make_push.sql` (`push_devices`);
  APNs host `backend/src/apns.ts:11`.
- On-device speech: `shell/Midas/VoiceTranscriber.swift:256`, `:322`, `:455`
  (`requiresOnDeviceRecognition = true`).
- Voice text to OpenRouter: `backend/src/voice-route.ts:31`, `:125`; `backend/src/jess-route.ts:154`;
  what goes in the prompt: `backend/src/jess.ts:244-283` (transcript, time zone, each Sidekick's
  `context` summary); `backend/src/voice-route.ts:11-12` (transcript, clock, time zone, list names);
  model `deepseek/deepseek-v4-flash` (`backend/src/voice.ts:10`); `data_collection: "deny"`
  (`backend/src/voice.ts:1197`, `backend/src/jess.ts:388`).
- Voice log: `backend/migrations/0006_voice_logs.sql` (transcript, lists, reply, device, iOS, app
  version), `0007_voice_logs_router.sql`.
- Edit report: `backend/migrations/0005_repairs.sql`, `backend/src/repairs.ts:7-12`, device info
  `shell/Midas/RepairReport.swift:68`.
- Edit processed on the founder's Mac by Claude Code: `runner/README.md:1-30` (job folder with
  transcript, screenshot, drawing, strokes, the copy; `GET /repairs/<id>/records` reads the
  reporter's records), `runner/README.md:21` (`claude -p`), `:58` (`CLAUDE_CODE_OAUTH_TOKEN`).
- Make goes to the founder: `backend/src/make.ts:19-25`.
- No analytics or ad SDK in the shell (searched `shell/Midas`, `shell/project.yml` for Firebase,
  Sentry, Crashlytics, Mixpanel, Amplitude, PostHog, ATTrackingManager: none).
- Account deletion within 7 days: `docs/briefs/build-22-2026-10-31.md`, "Settings and delete".

---

## 2. Support page (`/support`)

<!-- BEGIN SUPPORT PAGE TEXT -->
```text
Midas Support

Help
Email bhuvanrj73@gmail.com

Edit a Sidekick
Open it. Swipe down with three fingers. Say or draw the change. Tap Send.

Delete a Sidekick
On the home screen, press and hold its tile. Tap the minus. Tap Delete.

Delete your account
Tap your initial, top right of the home screen. Tap Delete Account.
Your account is deleted within 7 days.
```
<!-- END SUPPORT PAGE TEXT -->

Sources: three-finger swipe down `shell/Midas/ThreeFingerSwipeRecognizer.swift:4`; delete by press
and hold, Settings by the initial (E1), Delete Account (A1, X1): `docs/briefs/build-22-2026-10-31.md`,
"Settings and delete" (being built in the `settings-delete` worktree; check the final wording there).
"Send" as the Edit button: `docs/briefs/build-22-2026-10-31.md`, "Words" (check the button label).

---

## 3. TestFlight Test Information

| Field | Draft |
|---|---|
| Beta App Description | Midas: personal software. Say what you need in your own words; your Sidekicks do it. Ask Make for a new Sidekick. Swipe down with three fingers on a Sidekick to change it. |
| What to Test | 1. Touch and hold the first screen, type a name, tap Get Started, use Face ID. 2. Tap the orb and say a reminder, for example "remind me to call Mom at 6". 3. Open a Sidekick, swipe down with three fingers, say what to change, tap Send. 4. Ask Make for a Sidekick you need. 5. Tap your initial, top right, to see Settings. |
| Feedback Email | bhuvanrj73@gmail.com |
| Marketing URL | `https://midas-api.midas-backend.workers.dev/support` (optional field; check whether a separate page is wanted) |
| Privacy Policy URL | `https://midas-api.midas-backend.workers.dev/privacy` |
| Beta App Review contact: first name, last name | founder fills |
| Phone | founder fills |
| Email | bhuvanrj73@gmail.com |
| Sign-in required | No (an account is made in the app; see section 4) |

Notes: "jess" is on the word list (not public yet), so the description says "the orb", not jess.
Step 3 works on a fresh account: every account gets Reminders, Water and To-Do (`e81e6cd`, 2026-11-01).

Sources: `shell/Midas/WelcomeView.swift:4-8`; `backend/src/auth.ts` (new account gets jess,
Make, Reminders, Water and To-Do since `e81e6cd`); word list midas-intel `docs/word-list.md`; Make sender "Make", Settings E1:
`docs/briefs/build-22-2026-10-31.md`.

---

## 4. Review notes (App Review Information, Notes)

```text
Sign-in: no demo account is needed. On first open, touch and hold the screen; after a short animation a card shows a name field. Type any name, tap Get Started, then confirm with Face ID. This creates a passkey and a new account. Names are unique: if "that name is taken" appears, type another name. "Sign In" is for an existing passkey.

A new account opens with five Sidekicks: jess (say what you need), Make (ask for a new Sidekick), Reminders, Water and To-Do. Edit works on Reminders, Water and To-Do.

Edit: open a Sidekick and swipe down with three fingers. Say or draw the change and tap Send. The change is made and shows up in that Sidekick. Edit is not available on jess and Make. The gesture conflicts with VoiceOver and Zoom three-finger gestures.

Sidekicks (guidelines 4.7 and 2.5.2): each Sidekick page is HTML5 and JavaScript served by our server and shown in a WKWebView. The web view has no script message handlers and no injected scripts, uses a non-persistent data store, and cancels any navigation away from the Sidekick's own origin. Its Content Security Policy allows scripts only by per-page hash and network connections only to our server. No native code is downloaded or executed. A Sidekick's tool functions (tools.js) run in JavaScriptCore; they get records as JSON and return changes as JSON, with no network or native access. Changes to a Sidekick (Edit) change only its HTML and JavaScript, for that one person.

Native features (Apple Reminders import, notifications, alarms, widgets) are run by the app itself after the person asks; a Sidekick page cannot call them.

Each person sees only Sidekicks assigned to their account; there is no public directory.
```

Facts behind each line:

| Line | Fact | Source | State |
|---|---|---|---|
| Sign-in | Name (1-50 chars, unique, case-insensitive), then passkey registration; the button is "Get Started" | `backend/src/auth.ts:32`, `:105-128`, `shell/Midas/WelcomeView.swift:4-8`, `shell/Midas/PasskeyAuthenticator.swift` | verified |
| Face ID | iOS shows its own passkey sheet; Face ID or passcode | iOS behaviour | check: reviewer device needs iCloud Keychain on |
| New account content | jess, Make, Reminders, Water, To-Do assigned at sign-up; existing accounts by `assign-starter-sidekicks-to-everyone.mjs` | `backend/src/auth.ts`, `e81e6cd` | verified 2026-11-02 |
| Three-finger swipe | Swipe down, passive recogniser; X2 toast on jess, Make, Inbox | `shell/Midas/ThreeFingerSwipeRecognizer.swift:4-9`, `shell/Midas/RepairUnavailableSwipe.swift:5-8` | verified |
| VoiceOver/Zoom | Clash noted in the code | `ThreeFingerSwipeRecognizer.swift:9` | verified |
| No message handlers, no user scripts, non-persistent store, `javaScriptCanOpenWindowsAutomatically = false` | | `shell/Midas/SidekickWebViewFactory.swift:3-15` | verified (no `addScriptMessageHandler` or `addUserScript` in `shell/Midas`) |
| Navigation guard | Only `sidekick://<own id>` allowed | `SidekickWebViewFactory.swift:21-35` | verified |
| CSP | `default-src 'none'`, `script-src` hashes only, `connect-src` platform origin plus own `sidekick://` origin | `shell/Midas/SidekickContentSecurityPolicy.swift:27-45` | verified |
| tools.js in JavaScriptCore | Pure handlers, JSON in and out; deploy gate checks no network, store or code loading | `shell/Midas/SidekickToolsEngine.swift:32-37`, `backend/scripts/bundle-tools.mjs` | verified; check Apple's current 2.5.2 / 4.7 text on JavaScriptCore |
| Native features via request records | A page writes `request:<id>`; the shell asks the person, then runs EventKit | `shell/Midas/AppleRemindersImport.swift:4-11`; `docs/PRODUCT.md` §5 (4.7.2 note) | verified; 4.7.2 fit is check |
| Edit changes only that person's copy | Runner deploys only the reporter's copy, never the base | `runner/README.md:1-5` | verified |
| No directory | Pages resolve only for assigned members | `docs/PRODUCT.md` §5 ("4.7.4 index") | check: 4.7 also asks for a report mechanism and blocking |

Do not use in the notes (`docs/PRODUCT.md` §5): app builder, app maker, native iOS apps, code export,
App Store submission.

---

## 5. App Privacy answers (App Store Connect)

Tracking: **No** for every type (no ad or analytics SDK, no data shared with data brokers, no IDFA).
Every collected type is **linked to the user** (stored under the account id).

| Apple data type | Collected | Linked | Tracking | Purposes | What it is | Source |
|---|---|---|---|---|---|---|
| Contact Info: Name | Yes | Yes | No | App Functionality | Account name | `auth.ts:243` |
| Contact Info: Email, Phone, Address | No | | | | | `0001_auth.sql` |
| Health & Fitness: Health | check | Yes | No | App Functionality | Water Sidekick drink log; Apple may count hydration as health data | `sidekicks/hydration/` |
| Location (precise, coarse) | No | | | | Time zone only (check whether Apple counts it) | `voice-route.ts:11-12` |
| Contacts | No | | | | | no Contacts framework in `shell/Midas` |
| User Content: Photos or Videos | Yes | Yes | No | App Functionality | Photos attached in Reminders | `files.ts:5-9`, `sidekicks/reminders/index.html` |
| User Content: Audio Data | No | | | | Speech recognised on the phone | `VoiceTranscriber.swift:455` |
| User Content: Customer Support | Yes | Yes | No | App Functionality | Edit requests (text, screenshot, drawing); Make messages | `0005_repairs.sql`, `make.ts:19-25` |
| User Content: Other User Content | Yes | Yes | No | App Functionality | Sidekick records, imported Apple Reminders, voice request text | `sync.ts:10-12`, `AppleRemindersImport.swift`, `0006_voice_logs.sql` |
| Identifiers: User ID | Yes | Yes | No | App Functionality | Account id, passkey credential id | `auth.ts:243-244` |
| Identifiers: Device ID | check (Yes if the push token counts) | Yes | No | App Functionality | APNs device token | `0011_make_push.sql` |
| Usage Data: Product Interaction | Yes | Yes | No | Analytics, App Functionality | Voice request outcomes, blocked Edit tries | `0006`/`0007_voice_logs*.sql`, `0012_repair_blocked.sql` |
| Diagnostics: Performance Data | Yes | Yes | No | Analytics | Voice timings (`total_ms`, `listen_ms`, steps) | `0006_voice_logs.sql` |
| Diagnostics: Other Diagnostic Data | Yes | Yes | No | Analytics, App Functionality | Device model, iOS version, app version and build | `0006_voice_logs.sql`, `0005_repairs.sql` |
| Diagnostics: Crash Data | No | | | | No crash SDK | `shell/project.yml` |
| Purchases, Financial Info, Sensitive Info, Browsing History, Search History, Other Data | No | | | | | |

---

## 6. Open points (not settled by the code)

1. Delete Account and the 7-day promise: the deletion paths are being built (`agent/account-deletion`,
   2026-11-02); the voice log is deleted with the account (founder, 2026-11-02). The repair log and `ops` are append-only by design ("never shortened",
   `0005_repairs.sql`; `sync.ts:11`), and the runner keeps job logs on the Mac
   (`~/Library/Application Support/midas-runner/log/<id>/`). Which of these the founder deletes for
   a deleted account, and whether Cloudflare D1 backups (Time Travel) are covered by "within 7 days".
2. Settled 2026-11-01: a fresh account has Reminders, Water and To-Do, so the reviewer can try Edit
   (`e81e6cd`).
3. Name uniqueness: settled 2026-11-02, stays as is; the review notes tell the reviewer to type
   another name.
4. Founder's legal name on the privacy page and in the contact fields.
5. Public use of "Cloudflare", "OpenRouter", "Anthropic", "jess" against the word list.
6. Hydration (Water) as Health data, the push token as Device ID: Apple's definitions decide.
7. Retention: voice log kept while the account exists, deleted with it (founder, 2026-11-02); Edit
   reports and records have no period in the code.
8. Cloudflare Worker logs (`observability.enabled: true`, `backend/wrangler.jsonc`): settled
   2026-11-02, the page says they may include IP addresses and are kept 7 days. From 2026-12-01 Workers
   Logs are billed as Observability (Free 0.5 GB/day, 7 days, no overage; Paid 50 GB/month included,
   then $0.25/GB ingested, $0.10/GB-month); Midas's volume is far below.
9. Settled 2026-11-01: `NSMicrophoneUsageDescription` is "Midas listens when you speak a request or
   an edit." (`8300bc7`).
10. Age rating and whether children may use Midas: nothing in the code.
11. Marketing URL: support page reused, or none.
12. Guideline texts (2.5.2, 4.7, 4.7.2, 5.1.1(v)) quoted as known in June 2026; read Apple's current
    pages before submitting.
13. Moved from the review notes' check markers (2026-11-02): whether request records for native
    features satisfy 4.7.2, and whether 4.7 asks for a report and block mechanism even with no
    public directory. Read Apple's current 4.7 text before submitting.
