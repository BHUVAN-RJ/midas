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

## Recommended design (pending the founder's answers)

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
