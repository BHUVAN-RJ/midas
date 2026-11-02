# Completeness checklist: to-do list primitive

The items a complete to-do Sidekick must handle, from midas-intel `docs/research/todo/`:
`group-d.md` section 6 (items 1–58, view P items for the personal list), `look-group-d.md` Part 2
(P-new-1 to 37) and `LOOK-ANALYSIS.md` section 4 (L1–L6). Each block's **Edge cases** line names the
items it covers, and its **Tests** line proves them. This file is the index; the item wording is in
the research files. Written 2026-10-31.

| Area | Items | Blocks | Proved in the prototype checks |
|---|---|---|---|
| Nothing is lost (survives reload, update, import) | 1–6, P-new-12, P-new-28 | records.md, TD-SET-04 | settings and records survive reload |
| A tick lands at once and can be undone, with its name shown | L1, L2, 49, P-new-22, P-new-26 | TD-DONE-01, 06 | undo after tick |
| Done is kept as history; done items can be found and reused | 5, 52, P-new-18, P-new-21 | TD-DONE-05, 07, TD-NAV-04 | Logbook mode; search finds done; Add Again |
| Repeats: schedule or after done, next copy, double tick safe, subtasks reset | 48, P-new-1 to 7 | TD-ITEM-04 | repeat next copy; double tick ignored |
| Subtasks stay under the parent; drag never nests | P-new-8 to 12 | TD-ITEM-03, TD-GEST-02 | — (needs a real-pointer test) |
| Lists: reorder, insert between, order holds | P-new-13 to 17 | TD-NAV-03, TD-ADD-06, TD-GEST-02 | order between neighbours |
| Search everywhere, fast, incl. done | P-new-18 to 21 | TD-NAV-04 | search finds done |
| Deletes: undo for one, warning for many | 50, P-new-23, P-new-24 | TD-ITEM-06, TD-SET | delete then undo; list delete asks first |
| Overdue without shame; today model chosen | 40–44 | TD-DAY-01, 04 | all four today models |
| No change to layout or gestures the person did not choose | L3 | TD-SET-02 | — (open: presets, see recipe.md section 2) |
| Text size, long titles, dark mode, no pop-ups over the list | L4–L6, 55, 56, P-new-29, P-new-30 | TD-LOOK, TD-ROW-05 | every preset and view renders |
| First open fast and empty or asks; gestures also exist as controls | P-new-31, P-new-32 | TD-SET-03 | — |
| Import from Apple Reminders loses nothing silently | P-new-33 to 36 | TD-SET-04 | — (Sidekick build) |
| Widget, notifications, tinted Home Screen | P-new-37, TD-OUT | TD-OUT-01 to 03 | — (shell) |
| Titles shown as text, never run | — | TD-ROW | HTML title escaped |

Open gaps found while writing the blocks (for the founder): no trash field (item 50), no
`externalId` for re-import matching, no day-end setting (item 44), no "who completed it" field
(item 52), repeat cannot hold yearly / every N / chosen weekdays / end dates, the widget's
Today source works only for `reminder:` records.
