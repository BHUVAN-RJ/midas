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
