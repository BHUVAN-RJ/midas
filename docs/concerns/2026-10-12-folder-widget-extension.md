# Open concerns: Sidekicks (Folder) widget extension (widget-extension agent, 2026-10-12)

Left by the `widget-extension` worktree after its brief (`docs/briefs/widget-extension.md`) was
built and merged (commit `35a16b8`, merged into `main` on 2026-10-11). The floating-tiles item and
the "Folder" name are already handled on `main` (`664d09d`) and in
`2026-10-11-reminders-and-widgets.md` item 6. Mark an item done here (with the commit) when it
is checked or shipped.

## 1. Not yet seen by eye: the Reminders icon and the tinted / clear looks in the widget

Files: `shell/MidasWidgets/FolderWidget.swift` (`FolderTileView`), `shell/Shared/SidekickIcon.swift`.

The brief's stop condition, "if `RemindersListIcon` (a SwiftUI `Canvas`) does not render in the
widget, stop", was never exercised: the agent could only build and run the tests. Two checks on
the simulator or the phone, with the merged `main` build the lead installed on 2026-10-11:

- The Reminders tile shows the drawn icon (white tile, green tick, two rows), not a blank square.
- In the tinted and clear Home Screen looks, icons are marked `.widgetAccentable()` and names stay
  in the primary colour; both must stay readable (mockups: midas-intel `docs/prototypes/widgets/`).

Who: the founder, on the next widget check. If the Canvas icon is blank, the lead decides the
replacement; the brief forbids the agent from swapping it.

## 2. Judgement call in the code, not in the brief: picked Sidekicks all gone

File: `shell/Shared/FolderWidgetLayout.swift` (`content(pickedIds:sharedList:family:)`).

When the person picked Sidekicks in the widget's configuration and every picked id has since left
the shared list, the widget shows the default fill (the first 4 / 8 / 16 in home grid order)
instead of an empty grid. The brief only says unknown ids are dropped. Test:
`FolderWidgetLayoutTests.testPickedIdsAllGoneFallBackToTheDefaultFill`.

Who: the lead or the founder confirms, or says what the widget should show instead.

## 3. Style nit the test guard would not let the author fix

File: `shell/MidasTests/FolderWidgetLayoutTests.swift`,
`testRowsFollowTheFamilyColumnsAndTheLastRowMayBeShort`.

Two assertions use an inline closure (`map { row in row.map(\.id) }`), against the style rule in
`~/.claude/CLAUDE.md`. The guard hook blocked the author's edit to its own uncommitted new file.
Cosmetic; the test is correct. Only test-guardian may change it.
