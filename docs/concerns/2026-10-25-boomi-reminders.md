# Concerns: Boomi's Reminders (2026-10-25)

Founder, 2026-10-25: a Reminders for a friend, Boomi, with three pages only: Today, then Next 7 Days,
then Scheduled, each pulled up from the one before. Mockup: `docs/mockups/boomi-reminders-2026-10-25.html`.
Built as her own copy of the `reminders` Sidekick (option B in the mockup), kept in
`copies/reminders/boomi/`. The founder said "build it" without answering the mockup's four
questions, so each one took the mockup's default:

1. **Missed reminders:** stay at the top of Today, red, with their day, until done. Reminders with no
   date (jess can add one; Details can take a date away) go at the bottom of Today. Without this
   they would be on no page.
2. **Lists:** none. No drawer, no List button or Details row, no list tools for jess (`move`,
   `create_list`, `move_list` removed; `add` takes no list).
3. **Built as:** her copy of `reminders` (same records, same notifications in the shell, no new
   app build). A new Sidekick id would need shell changes: `reminders` is named in
   `shell/Midas/ReminderRecord.swift`, `RecordWriter.swift`, `ReminderExpansion.swift`.
4. **Name and tile:** "Reminders", orange checklist, unchanged.

Also removed on 2026-10-25: Import Apple Reminders / Import File and the "More" menu that held only
those. **Back on 2026-10-26** (founder: "it's a reminders feature"): the base's More menu with both,
on every page. Her copy has no lists, so an import leaves Apple's lists behind: every reminder comes
in with no list and lands on Today, Next 7 Days or Scheduled by its date; the summary has no Lists
line (`leaveListsBehind` in the page; `boomi-import.test.ts`). The empty Sidekick still shows its
pages, not the base's empty-state Import screen, so `reminders-wording.test.ts` stays left out.

## Open

- **Base fixes do not reach her copy by themselves.** A base deploy updates only untouched copies;
  hers is not one. A Reminders fix she should get: apply it in `copies/reminders/boomi/sidekick/`
  too, then stage and deploy her copy again. Base tests her copy carries are read from
  `backend/test` at staging time (`copy.json` `baseTests`), so test fixes follow on the next deploy.
- **Repair pill on iPhone 15:** `RepairPillTypingTests` `testLongWordsGrowToThreeLinesAndKeepTheNewestInView`
  and `testTypedWordsCarryOnAfterTheSpokenWordsInsideThePill` fail on an iPhone 15 simulator
  (393 pt wide) and pass on iPhone 17 (402 pt), same commit. Not caused by this change (no shell
  code changed). If Boomi's phone is an iPhone 15, the Repair pill's typed text may lay out wrong
  for her. Default: leave for a separate shell fix.
- **Her user id:** needed for the deploy (`--user`); she has to sign up in Midas first.
