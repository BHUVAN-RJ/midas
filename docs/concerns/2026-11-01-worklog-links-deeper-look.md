# Concerns: work log links and "Taking a Deeper Look" (2026-11-01)

Two founder features for build 22, built by the lead session and pushed to main:

- Work log entries are links (founder, 2026-10-31): branch `agent/worklog-links` (`53ba298`),
  merged as `5bb4016`. Mockup `docs/mockups/jess-worklog-links-2026-10-31.html`. Shell suite 1,100
  green, backend 1,254, guard 42 (on the branch; the merge added docs only).
- "Taking a Deeper Look" (founder, 2026-11-01): `cf582bd` on main. Mockup
  `docs/mockups/edit-deeper-look-2026-11-01.html`. Shell suite 1,156 green on Midas Sim 2. Backend
  and guard not re-run (not touched). Decision in `docs/PRODUCT.md` (`30da4bc`) and midas-intel
  design doc (`e1732bd`).

## Open

- **Neither seen in the app.** Both are covered by tests only. Check on a Midas Test build before
  the build 22 upload: tap a done Workdesk card (Reminders, Water, Care), the Volt mark, swipe back
  twice; a failed edit showing Taking a Deeper Look, then Edit done after the founder marks the
  thread Built.
- **Sidekick pages not deployed.** Reminders, Water and Care Reminders `index.html` (data-key rows,
  `store.focus()`) and the new `shell/sdk/midas-store.js` need deploying to staging, then live
  (`docs/DEPLOY.md` §3.3). Until then a tap opens the page with nothing marked.
- **Users' repaired copies get only the new SDK.** `copies/reminders/boomi` has the new SDK block
  but not the data-key rows, so a tap opens boomi's Reminders unmarked. Same for any user copy.
  Pick up with the repair agent or by hand.
- **Work log links, not built from the mockup:** an edit's old value struck through, a deleted
  record as a faded row with Undo, the pressed look on a tapped card. jess itself still opens from
  the bottom (unchanged fullScreenCover).
- **Test-guardian's "can still fail" proof owed** for the three wording assertions it changed
  (`RepairUXUpgradeTests` 180, `Build22EditVoiceTests` 40 and 63; `TEST_CHANGES.md` top entry):
  set `RepairTagCopy.couldntFix` back to the old words, run the shell suite, see them fail, restore.
- **Server notice text still says "Check back in some time."** (`backend/src/repairs.ts`
  `USER_RESULT_TEXT.couldnt_fix`, comment in `backend/src/edit-failed.ts`). The app does not show
  it. Changing it needs test-guardian (`backend/test/edit-failed-store.test.ts` asserts it) and a
  backend deploy.
- **Unused code left:** `RepairTagCopy.tryAgain`, `RepairTagCopy.close` and
  `RepairCenter.tryAgain(clientReportId:)` (existing tests still call it).
- **Main checkout has two untracked mockups** identical to the committed copies
  (`docs/mockups/jess-worklog-links-2026-10-31.html`, `docs/mockups/edit-deeper-look-2026-11-01.html`).
  Delete them before pulling main there, or git refuses.
- **Branch `agent/worklog-links` kept** (merged). Delete when convenient.
