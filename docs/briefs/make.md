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
