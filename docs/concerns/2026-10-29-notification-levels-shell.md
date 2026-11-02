# Concerns: notification levels, shell part (2026-10-29)

Built on branch `agent/notif-levels-shell` (brief `docs/briefs/notification-levels.md`, last commit
`ce9351d`), merged to `main` in `6e16ed9`. `scripts/test-all.sh` passed on the branch: backend 919,
shell 796, midas-intel 31. What is left:

## Needs the founder

- **Time Sensitive capability in the Apple developer portal**, only if Xcode's automatic signing
  does not add it on the first device build. Without it, Time Sensitive and Alarm-fallback
  reminders arrive as plain notifications held by Focus. Steps: Certificates, Identifiers &
  Profiles → Identifiers → `com.bhuvanrj.midas` → Capabilities → tick **Time Sensitive
  Notifications** → Save; then the same for `com.bhuvanrj.midas.test`. AlarmKit and Live
  Activities need no capability. The entitlement is already in `shell/Midas/Midas.entitlements`
  and `shell/Midas/Midas-Test.entitlements`.
- **Try on a real phone (iOS 26), "Midas Test" build:** an Alarm reminder ringing through Silent
  and Focus; Snooze starting the countdown card (look, Done, Stop, rings again 9 minutes later);
  the Time Sensitive label on a Time Sensitive reminder; the AlarmKit permission prompt once, and
  declining it giving Time Sensitive notifications. Only the simulator and unit tests have run.

## Defaults taken (founder may change)

- **Stop on an alarm or its countdown also removes the pending snooze** (`snoozeRemovalPatch` in
  `shell/Midas/RecordWriter.swift`). Without it the alarm rings again. The brief did not say.
- **Snooze is 9 minutes** (`AlarmReminderShared.snoozeSeconds = 540`), read from the mockup's
  "rings again at 11:09".

## Small, for whoever next touches the code

- A snoozed **early alert** shows the reminder's last occurrence at or before the snooze time as
  its time text; checked only for plain snoozes.
- `TEST_CHANGES.md` (2026-10-24, NotificationNotesTests) says "Proof it can still fail: NOT RUN".
  The same body break was caught by `NotificationLevelsTests`, but not run on that test itself.
  Pick up: test-guardian, when the simulator is free.
- The midas-intel design doc section "Notification levels and layout (founder, 2026-10-24)" in
  `docs/designs/jess-personal-assistant-shell.md` was uncommitted when this was built (noted by
  test-guardian). Pick up: whoever works in midas-intel.
