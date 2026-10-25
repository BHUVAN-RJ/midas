# Brief: notification levels and layout A (founder, 2026-10-24)

Two agents, two worktrees, started by the lead session in `~/Desktop/Midas/midas`:

| Task | Branch | Worktree |
|---|---|---|
| Shell | `agent/notif-levels-shell` | `~/Desktop/Midas/midas-worktrees/notif-levels-shell` |
| Reminders Sidekick | `agent/notif-levels-reminders` | `~/Desktop/Midas/midas-worktrees/notif-levels-reminders` |

The founder has approved building this (2026-10-24). Every shared decision is below; do not ask the
founder again about anything settled here. A new question goes to the lead, not to the founder,
with the default you will use meanwhile.

## 0. Read first

- `CLAUDE.md`, `docs/PARALLEL-AGENTS.md` ("Rules for an agent working in a worktree").
- `docs/NOTIFICATIONS.md` (the engine as built), `docs/WRITING.md` (every word on screen).
- midas-intel `~/code/midas-intel/docs/research/ios-notifications-reference.md`: N02 Subtitle,
  N23 Time Sensitive, A01 AlarmKit alarm, A02 AlarmKit countdown, "Apple Reminders Urgent".
- Mockup: `docs/mockups/notification-levels-2026-10-24.html` in the main checkout
  (`~/Desktop/Midas/midas/docs/mockups/`, read only; not committed yet). Section 2 layout A and
  section 3 levels L2, L3, L5, L7.
- Never read anything under `docs/legacy/`.

## 1. Why

Repair `3365bd8a` (2026-10-24): "Even though they are time they don't come under time sensitive".
The shell books every notification at the default (Active) level, with no subtitle; a reminder
without notes shows one line, and nothing says which Sidekick sent it.

## 2. Decisions (founder, 2026-10-24)

1. **Layout A.** Title = the reminder's title. Subtitle = the Sidekick's name as the person sees it
   (today the manifest `name`, as on the home tile; the person will name their own Sidekicks later,
   and that name then becomes the subtitle). Body = the time, then the notes. Every notification the
   item makes (its own, snoozes, early alerts, hourly times, missed) gets the subtitle.
   Layout F (Sidekick tile as a round picture) is parked: do not build it.
2. **New record field `reminderType`** on `reminder:` records, values `"normal"`, `"timeSensitive"`,
   `"alarm"`. Absent means `"timeSensitive"`. This is not the record's `$type`.
3. **Every timed reminder is Time Sensitive** unless the person picks otherwise, including records
   saved before this change (no migration: absent = Time Sensitive). Undated reminders notify nobody,
   as now.
4. **Levels the shell builds:**
   - `"normal"` → L2 Active (today's `UNNotificationInterruptionLevel.active`).
   - `"timeSensitive"` → L3 `.timeSensitive`. Entitlement
     `com.apple.developer.usernotifications.time-sensitive` in all four app and test entitlement
     files of the app target (`shell/Midas/Midas.entitlements`, `Midas-Test.entitlements` and the
     other two the app uses; check `shell/project.yml`).
   - `"alarm"` → L5 AlarmKit alarm (iOS 26+), with L7: the countdown card after Snooze (AlarmKit
     countdown, a Live Activity in `shell/MidasWidgets/`).
   - Not built: L1 Passive, L4 Critical, L6 Nag.
5. **Where the person picks:** one choice per timed reminder, words **Normal / Time Sensitive /
   Alarm**, in the Reminders page, and as an optional `reminderType` argument of jess's add and edit
   tools. Shown only when the reminder has a time. Care (`sidekicks/care-reminders`) gets the field
   in its schema but no picker yet; its reminders use the default.
6. **Defaults for edge cases** (`docs/CONCERNS.md` §17 in the main checkout):
   - Early alerts, snoozes, hourly times, missed notices: same level as their reminder, except an
     Alarm reminder's early alerts and missed notice, which are Time Sensitive notifications.
   - Alarm repeats: AlarmKit repeats only never or weekly. A weekly-or-daily repeat that AlarmKit
     can hold natively uses its schedule; every other repeat (every N days, monthly, yearly,
     `until`) is booked as a one-time alarm for the next occurrence and re-booked on each engine
     run. If Midas does not run before it, it fires as a Time Sensitive missed notification.
   - Alarm buttons: Stop (iOS) and Snooze (secondary; starts the L7 countdown). The L7 card has Done
     and Stop. Done and Snooze write the record the same way the notification buttons do
     (`ReminderChange` in `shell/Midas/RecordWriter.swift`, `docs/NOTIFICATIONS.md` §4.5).
   - Permission: AlarmKit asks once, when the first `"alarm"` reminder needs booking. Declined, or
     iOS older than 26: the reminder is booked as a Time Sensitive notification.
   - The person turns Time Sensitive off in iOS Settings: it arrives as Active; Midas shows nothing.
   - Alarms do not count against the 48 notification bookings.

## 3. Shell task (`agent/notif-levels-shell`)

Owns: `shell/Midas/` (record parsing, planner, engine, booking, a new AlarmKit adapter, the alarm
button handling), `shell/MidasWidgets/` (the L7 Live Activity), the entitlement files,
`shell/project.yml` (Info.plist keys such as `NSAlarmKitUsageDescription`, Live Activity support),
`shell/sdk/` only if the reminder check in `shell/sdk/record-schema.js` or the shell's
`ReminderRecord` validation needs `reminderType`, new test files in `shell/MidasTests/`, and
`docs/NOTIFICATIONS.md` (keep §4.2, §5, §7 true).

- `ReminderRecord` reads `reminderType`; a bad value is refused with
  `reminder.reminderType must be normal, timeSensitive or alarm`.
- `PlannedBooking` carries the subtitle and the level; `NotificationBooking` sets
  `content.subtitle` and `content.interruptionLevel`.
- The Sidekick name comes from wherever the home grid gets it (`SidekickDirectory.swift`); the
  planner stays pure (pass the names in).
- `NSAlarmKitUsageDescription` follows `docs/WRITING.md` rule 10: one active sentence, e.g.
  "Midas rings your alarm reminders even when your iPhone is on silent or in Focus."
- Builds for trying: the "Midas Test" scheme only, staging, a free simulator.
- If the founder must do something in the Apple developer portal (capability on the App IDs),
  say so in your final report with the exact steps; do not guess.

## 4. Reminders Sidekick task (`agent/notif-levels-reminders`)

Owns: `sidekicks/reminders/` (`index.html`, `manifest.json`, `tools.js`),
`sidekicks/care-reminders/manifest.json` (schema field only), and new tests for them wherever the
existing Reminders and Care tests live (look before adding).

- Both manifests: optional `reminderType` enum on the reminder item type.
- Reminders page: the picker on a reminder with a time; new and edited timed reminders without a
  choice keep the field absent (= Time Sensitive). Words from §2.5; follow `docs/WRITING.md`.
- `tools.js` and the manifest `agent` block: `reminders.add` and `reminders.edit` take an optional
  `reminderType`; descriptions and examples say "alarm" and "not time sensitive" phrasings
  (CLAUDE.md "Every Sidekick is agent-connected").
- Do not deploy the Sidekick; the lead and the founder deploy.

## 5. Rules for both

- Edit only the files your section names. Need anything else: stop and ask the lead.
- Never edit `CLAUDE.md`, `docs/PRODUCT.md`, `docs/PARALLEL-AGENTS.md`, `backend/package*.json`,
  `backend/wrangler.jsonc`.
- Tests are guarded: add new tests freely; an existing test that must change goes through the
  `test-guardian` agent with this brief's dated decision. A new test must be able to fail for the
  reason it exists.
- Run the full suite with `scripts/test-all.sh` after every change; report the result honestly,
  including failures.
- Code style: `~/.claude/CLAUDE.md` (no chained one-liners in JS, descriptive names, no inline
  anonymous functions in chains, comments above non-obvious logic) and the surrounding code.
- Commit small and often on your own branch. Never merge into `main`, rebase or force-push.
  Conflicts with other branches (`agent/make-shell` also changes `shell/`) are resolved later by
  another agent: do not resolve them.
- Subagents you start run on Opus (`model: "opus"`).
- Done = the task's part built, tests added, `scripts/test-all.sh` result reported, a short report
  for the lead: what was built, test results, what is left, any founder step.
