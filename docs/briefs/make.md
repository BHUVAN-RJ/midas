# Make (working title; founder, 2026-10-23)

A default Sidekick for everyone, like jess, with its own icon and look. For now a chat between each
user and the founder about a problem: the founder asks follow-ups (idea? direction? design
direction?), sends design options as images, the user picks. Each request has a status. The
founder has a founder-only inbox Sidekick, WhatsApp-style: a list of people, each with their thread.
Prototypes first, then build. Nothing approved to build yet.

## Research (2026-10-23, read-only, main `052df5e`)

- Pages reach only their own store; no session, no network to server routes
  (`SidekickContentSecurityPolicy.swift:28-43`, `SidekickStoreChannel.swift:6-19`). HTML
  prototypes can't be embedded in a page (iframes blocked): designs go as images.
- No founder/admin role exists; the only cross-user caller is the runner token
  (`repairs.ts:156-178`). The server already writes ops into a user's store after checking them
  against the schema (`jess-rerun.ts:194-209`).
- Records: `ops` table, append-only, 64 KB per record, backed up (`0004_ops.sql`, `sync.ts:25-28`).
  Files: FILES bucket `<userId>/<fileId>`, 20 MB, owner-only (`files.ts`).
- An open page doesn't see new records until the next pull (launch, foreground, after a local
  write); no push yet.

## Decided (founder, 2026-10-23)

- **One thread per request**, not per person. Make home is a plain list of all requests (not a
  stack); each row shows the request's status, set by the founder by hand ("Figuring out",
  "Looking", "Building", "Built" and the like).
- **The thread uses repair's bottom bar** (B3 floating pill, orb on the left): voice starts on
  open; tapping to type stops listening.
- **Built into the app** (native screen like jess), not a web page. Voice first; typing is there
  too. People never see "web page" ideas: they ask for anything ("build me an app for reminders"),
  and what they get back is an app.
- **No repair on Make or on jess.** The three-finger swipe there says "Repair not available for
  this Sidekick." Each such try is logged (who, which Sidekick, when); if many people try, repair
  may be opened later.
- **Push gets built, no Mac notification.** The founder must hear of every Make message on the
  phone, and the inbox must always be reachable. Push is part of Make.
- **One inbox for staging and live** (only the founder uses staging today; revisit later).
- **No audio kept for now:** speech is transcribed on the phone and only the text is sent (founder,
  2026-10-23). Keeping audio later needs consent, a visible sign while recording (2.5.14), and
  "Audio Data" in the privacy label and policy.

## Recommended design (before the decisions above; storage still holds)

- **Make** = a page Sidekick in `sidekicks/make/`, assigned at sign-up (next to jess in
  `auth.ts:245-250`) and to existing users by script. Voice through jess's native voice screen.
- **Inbox** = a page Sidekick `make-inbox`, assigned only to the founder's accounts; the Worker
  knows the founder by `MAKE_FOUNDER_USER_ID` per environment.
- **Storage (option c):** chats are ordinary records in each side's store (`ops`, no new chat
  database). After a push, the Worker copies the user's Make records into the founder's inbox store
  and the founder's replies and status into that user's Make store (schema-checked, idempotent op
  ids). Images: the Worker copies the R2 object to the other side's id. New: one table
  `make_events` (founder/user notices) for alerts; the runner polls it and shows a Mac
  notification until push exists.
- Records: `make.request:<reqId>` (title, status received/asking/designing/building/ready),
  `make.message:<reqId>.<msgId>` (from, text, files, kind), `make.option:<reqId>.<optId>`
  (label, file), `make.pick:<reqId>.<optId>`.
- Shell: while Make or the inbox is open, pull every few seconds and tell the page records changed.
- jess: a `make.send` tool (Make's `tools.js`), "not for" changes to an existing Sidekick (repair).

## Round 2 picks (founder, 2026-10-23, mockup `docs/mockups/make-2026-10-23.html`)

- Tile: K1 (handwritten "Make") or a fusion of K1 and K4 (the plus); K1 if no fusion works.
- Home: H1 list; its status pill needs a better design. Status style S2 (word plus 4 steps), improved.
- Thread: T1 (bubbles) or T2 (question cards, carousel in the chat) undecided; interactive prototypes of both.
- App built: on opening Make, R2 (Built screen, showing what was built, no "Open") plays, then locks
  into its tile on the home grid. R3 (built card in the thread, openable) also stays, with a small
  "already built" animation.
- Notifications only when needed (founder's questions, app built): P1 plain. Founder side: F1.
- Repair not available: X2 (Volt rim flash plus toast).
- "Repair" is not understood (a friend of the founder's could not follow it): a new word is being
  researched (change, correct, update or other).

## Round 4 and build answers (founder, 2026-10-24)

- Thread: **T2 question cards** (T1 dropped). Tapping an option only selects; a Send button at the
  card's bottom right sends. The carousel swipes both ways. No status inside the thread; status
  shows only in the list. The person can always answer in their own words (the pill bar).
- Question cards are made by Claude skills (designed later), so they come out right every time.
  The record format comes now; the authoring tool comes later.
- Push to the person only for each question card and for "built". The founder gets a push for each
  message from a person.
- Staging: the founder is its only user; keep it simple (no special cross-environment work).
- Everyone gets Make. Docs are updated first, then building starts.

## State and open items (handoff, 2026-10-29)

- **Built and merged** (2026-10-24): server `agent/make-backend` (`a0a15ef`, founder ids in
  `wrangler.jsonc` `281da15`) and app `agent/make-shell` (`3c7b881`), merge `271328e`; contract
  `docs/briefs/make-contract.md`. Suites on the merge: guard 42, backend 990, shell 818, intel 31,
  all passing. Screens checked by unit tests only; nobody has seen them running.
- **Not yet done on staging** (founder; commands in `docs/DEPLOY.md` §3): migrations 0011
  (`push_devices`, `make_events`) and 0012 (`repair_blocked`), server deploy,
  `node scripts/assign-make-to-everyone.mjs --env staging`, then try in Midas Test on the phone.
  Live only after staging, and `assign-make-to-everyone.mjs --env live` only after an app with Make
  is on TestFlight.
- **Push needs the founder:** APNs key (`.p8`, Key ID) from the developer portal; Push
  Notifications capability on `com.bhuvanrj.midas` and `com.bhuvanrj.midas.test`; secrets
  `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` (`ZQ2JPFYL98`) via `wrangler secret put`. Then one
  real send from staging (`scripts/make-card.mjs`) to check that the Worker reaches APNs over
  HTTP/2; if not, the Mac mini runner sends unsent `make_events` rows.
- **Picks still open** (each in one place): status pill Q1/Q2/Q3 (`MakeStatusPill.style`, now plain
  S2); the name the person sees, "Bhuvan" or "Make" (`MakeCopy.senderName` and `MAKE_SENDER_NAME` in
  `make-sidekick.ts`; lead recommended "Make"); the new word for "repair", Change / Edit / Fix
  (`MakeCopy.repairWord`; research 2026-10-24: none of the comparable tools say "Repair"; Google AI
  Studio, Lovable and Replit say "describe the change"; top 3 Change, Edit, Fix). Tile: the written
  "Make" (K1), in place since `6b1ff62`.
- **Backend deviations from the contract** (builder, 2026-10-24): founder messages need the
  person's request; inbox `userId` must match the key; a founder id with no user skips copies;
  same-push ops count for "exists / create only / first answer"; `make` store keys limited to the
  contract shapes; `sent_at` stays NULL when secrets are missing or every send failed (for a
  fallback sender); unlabeled design answer pushes say `Design <n>`; Inbox icon `tray`;
  `PUSH_FETCH` env is for tests only, never in `wrangler.jsonc`.
- **App deviations:** the pill was pulled out of `RepairCanvasView.swift` (not `RepairChromeView`);
  one modifier line in `VoiceCaptureView.swift` for the swipe on jess's Listening screen;
  `aps-environment` = development in both entitlements (export re-signs it).
- **Next build number:** raise `CURRENT_PROJECT_VERSION` in `shell/project.yml` before the next
  TestFlight upload (check the current value; 18 was used 2026-10-26).
