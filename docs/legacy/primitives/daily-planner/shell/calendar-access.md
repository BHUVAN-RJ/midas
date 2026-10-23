# Brief: calendar access for Sidekicks (EventKit events), 2026-10-12

**Status:** Draft, not approved to build. The founder decides whether and when.

Labels: [C] confirmed on a primary source (Apple docs or App Review Guidelines, as cited in
midas-intel `docs/research/daily-planner/category-and-completeness.md` 2.6 or
`docs/research/ios-notifications-reference.md`), or read in this repo's code; [R] reported by a
secondary source; [U] not verified.

## How you work

The four steps of `docs/briefs/notification-engine.md`: go through the idea and say it back;
ask the founder; propose a plan and wait for "approved"; only then build, with tests. "Discuss,
the founder approves, then build" (`CLAUDE.md`).

## Goal

A daily planner Sidekick can show the person's calendar events on its timeline next to its own
tasks, and, if the founder chooses, create and change events. Checklist items (planner
`../checklist.md`): 4 (events and tasks on one timeline), 37 (what write-only access can do,
stated clearly), 38 (events match the calendar within minutes), 39 (two-way: an edit on either
side appears on the other). Patterns: DP-ITEM-05, DP-DAY-02, DP-DAY-05, DP-SET-06, DP-RES-05,
DP-ADD-06, DP-RES-01. Love 1 ("tasks and calendar events in one place") and leave reason 3
("calendar sync that falls short", 515 and 394 negative hits) sit here.

## What is already decided (with sources)

- A Sidekick has no native API and no bridge. Native features are reached by request records:
  the page writes a request, the shell does the native work and writes the result back
  (PRODUCT.md 5, architecture discussion 2026-10-07; NOTIFICATIONS.md 2).
- 4.7.3 consent per instance applies to request records (PRODUCT.md 5, 2026-10-07).
- Permission prompts belong to the shell, asked once, for all of Midas (NOTIFICATIONS.md 2).
- The precedent: Apple Reminders import (PRODUCT.md 5, 2026-10-10, built and merged). The page
  writes `request:<id>` `{kind: "import.apple-reminders", status: "pending"}`; the shell shows its
  own sheet ("Import Apple Reminders", "Continue" / "Not Now"), asks the iOS Reminders
  permission, reads EventKit, writes `import:<id>:<nnnn>` parts under 64 KB each into that
  Sidekick only, and sets the request's `status` to `done`, `denied`, `cancelled` or `failed`
  with `finishedAt` (`shell/Midas/AppleRemindersImport.swift`).
- Records are at most 64 KB (PRODUCT.md 5, 2026-10-10).
- Calendar events, if read, come from EventKit, not from the planner's own records (ANALYSIS.md
  7.1, research framing, not a founder decision).
- Words: `docs/WRITING.md` (permission screen: title and "Continue" plus "Not Now"; no
  explaining lines; usage string one full sentence).

## What exists today

- `shell/Midas/EventKitRemindersSource.swift` reads EventKit **reminders** only. No code reads or
  writes **events**.
- `Info.plist` has `NSRemindersFullAccessUsageDescription` only. No
  `NSCalendarsFullAccessUsageDescription`, no `NSCalendarsWriteOnlyAccessUsageDescription`.
- `SidekickStoreChannel` hands every `request:` write to `AppleRemindersImportCenter`, which marks
  any other `kind` as `failed` with `error: "unknown request"`. A new kind needs a router.
- Every record the shell writes into a Sidekick's store goes through the outbox and syncs to the
  server (`RecordSync.swift`). Import parts did; "their rows stay in the server's append-only
  history" (PRODUCT.md 5). Record values are stored unencrypted until encryption returns
  (PRODUCT.md 5, 2026-10-09).
- Deployment target iOS 17.0 (`shell/project.yml`), so the iOS 17 access levels apply.

## Platform facts

EventKit [C, category-and-completeness.md 2.6, Apple "Accessing the event store",
`requestWriteOnlyAccessToEvents`, TN3153]:
1. Since iOS 17 an app requests write-only access to events, full access to events, or full
   access to reminders. There is no read-only level: "To read events or reminders from the event
   store, your app needs full access."
2. Write-only "lets your app create new events but doesn't let it read any events or other
   calendar information, including events your app created." The calendar list is "a single
   virtual calendar". New events go to a calendar "chosen by the person".
3. The out-of-process EventKitUI editor needs no access: "Your app can use EventKitUI without
   requesting write-only or full calendar access." It saves to the calendar the person picks.
4. Usage strings: `NSCalendarsWriteOnlyAccessUsageDescription` or
   `NSCalendarsFullAccessUsageDescription`. With neither, or only the old `NSCalendarsUsageDescription`,
   "iOS automatically denies any access request."
5. Write-only to full: the first read call prompts once. If denied, "any further calls don't
   prompt the user for access again"; the person must change it in Settings › Privacy &
   Security › Calendars.
6. Repeating events: edits apply to `thisEvent` or `futureEvents` only (`EKSpan`). No "all".
7. An item with a `nil` time zone is floating.
8. `predicateForEvents` returns events "in the default time zone" and matches "only those events
   within a four-year time span".
9. Authorization states for events on iOS 17: not determined, restricted, denied, write-only,
   full access [C, `EKAuthorizationStatus`].
10. EventKit posts `EKEventStoreChanged` when the store changes while the app runs [U, not in
    the research files].
11. Which identifier survives a calendar's sync round trip (`eventIdentifier`,
    `calendarItemIdentifier`, `calendarItemExternalIdentifier`) differs by account type [U].

Apps [C, ANALYSIS.md]: Structured imports Apple Calendar one-way (Pro); its board's Two-Way
Calendar Sync has 3.1k votes. Routine shows "Active" (writable) vs "Passive" calendars. Things
shows events as one read-only card. Tiimo syncs per device (1★, 2026-07-24). Fantastical was
criticised for a write-only state that read as "no access" (2★, 2025-12-14).

## A request-record design to discuss

Modelled on the import. Every kind uses `request:<id>` with `status: "pending"`; the shell
answers with `status` and `finishedAt`, keeping the page's fields.

| Kind | Page writes | Shell does | Shell writes back |
|---|---|---|---|
| `calendar.status` | nothing else | reads the authorization status; no sheet, no prompt | `access`: `notDetermined`, `restricted`, `denied`, `writeOnly`, `full` |
| `calendar.access` | `level`: `full` or `write` | shows its sheet, then the iOS prompt | `access` as above; `status` `done`, `denied` or `cancelled` |
| `calendar.calendars` | nothing else | lists calendars (full access only) | `calendars:<requestId>` with `[{ id, title, colour, account, writable }]` |
| `calendar.read` | `from`, `to` (`YYYY-MM-DD`), `calendars` (ids) | reads events in the range | parts `event:<requestId>:<nnnn>` under 64 KB each, `parts`, `prefix` |
| `calendar.write` | `op`: `create`, `update`, `delete`; `event`; `eventId`; `span`: `this` or `future` | saves through EventKit (write-only or full), or opens the EventKitUI editor (no access) | `eventId` when known |

One event in a part: `{ id, calendarId, title, start, end, allDay, timeZone (null = floating),
recurring, colour }`. `start` and `end` are ISO 8601 with offset. About 250 bytes each, so a part
holds about 250 events.

The page reads the parts and deletes them, as with the import, or keeps the latest read as its
cache. Calendar events are not `task:` records.

## Open questions for the founder

1. **Which access levels.** Read only through full access; write through write-only access; or
   the EventKitUI editor with no access at all (fact 3). Each gives different checklist coverage:
   full covers 4, 37, 38, 39; write-only covers creating events only; EventKitUI covers creating
   with no prompt.
2. **What "each instance" means for 4.7.3 here.** The import shows a sheet each time. A planner
   reads the calendar every time it opens. Options: a sheet once per Sidekick (a grant kept by
   the shell, like the cross-app consent screen of PRODUCT.md 5), or per request.
3. **Do calendar events go to the server.** As records, they sync per account and are stored
   unencrypted. Alternatives: a local-only record kind the outbox skips; parts the page deletes
   at once (their ops still reach the server log, as with the import).
4. **Freshness (checklist 38).** Read on every page open only; or the shell also refreshes on
   `EKEventStoreChanged` while Midas runs and on background refresh.
5. **Two-way scope (checklist 39).** Move and resize only, or full edits; how a repeat edit maps to
   `thisEvent` / `futureEvents` (no "all").
6. **Which Sidekicks may ask.** Any Sidekick, or those whose manifest declares it.

## App Review

- **4.7.2** "Your app may not extend or expose native platform APIs or technologies to the
  software without prior permission from Apple." [C] The design keeps EventKit in the shell; the
  page writes and reads records only.
- **4.7.3** "Your app may not share data or privacy permissions to any individual software
  offered in your app without explicit user consent in each instance." [C] Calendar data reaching
  one Sidekick is sharing data with individual software; see open question 2.
- **5.1.1(iii)** "Apps should only request access to data relevant to the core functionality ...
  Where possible, use the out-of-process picker or a share sheet rather than requesting full
  access" [C]. EventKitUI is that out-of-process path for writing.
- **5.1.1(iv)** "Where possible, provide alternative solutions for users who don't grant consent."
  [C] Checklist 36: the planner works with its own tasks when access is none or denied.
- **5.1.1(ii)** (via `docs/WRITING.md` rule 10): the usage string "must clearly and completely
  describe" the use.

## How a Sidekick reaches it (records only)

1. Page writes `request:<id>` `{ kind: "calendar.status", status: "pending" }` and reads it back
   until `status` is not `pending`.
2. If `access` is `notDetermined`, the page offers a button; on tap it writes
   `{ kind: "calendar.access", level: "full", status: "pending" }`. The shell shows its sheet.
3. Page writes `{ kind: "calendar.read", from, to, calendars, status: "pending" }`, then
   `store.query('event:<id>:')` once `status` is `done`.
4. No fetch to any native function, no script message handler, no injected script.

## Tests that can fail for their reason

- A `calendar.read` request from Sidekick A writes parts only into A's store; B's
  `store.query('event:')` is empty.
- With access `denied`, a `calendar.read` request ends `denied` and writes no part.
- With `writeOnly`, `calendar.status` reports `writeOnly`, and `calendar.read` ends `denied`, not
  `done` with zero events (checklist 37: never shown as "no access" or as an empty calendar).
- 600 events in range produce parts each at most 65,536 bytes by `RecordSync.valueByteCount`,
  and their union has exactly 600 ids.
- A floating event comes back with `timeZone: null`; a New York event with its zone.
- A write with `span: "this"` on one occurrence changes that occurrence only (EventKit fake).
- An unknown `kind` still ends `failed` with `unknown request`, and the import kind still works.
- A request written while no one is signed in does not show a sheet.
- Without the usage string in `Info.plist`, a guard test fails (the request would be auto-denied,
  fact 4).

## Done when

The founder approves a plan; the chosen kinds work on the iPhone against a real calendar; the
planner shows events beside tasks, with the stated access level; the full suite
(`scripts/test-all.sh`) passes; results reported honestly.
