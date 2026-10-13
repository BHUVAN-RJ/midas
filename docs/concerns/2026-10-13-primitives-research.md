# Primitives research: birthdays, notes, alarms (session of 2026-10-11)

Handoff from the lead session that ran the research. Recording only; nothing here is decided.

## 1. Research done, status not yet in PRODUCT.md

- 2026-10-11, founder: calendar and split on hold; birthdays, notes and an alarm app next, starting
  with primitives research plus a new "what makes the app complete" study. Recorded in
  `docs/PRODUCT.md` (section 2, "Changed 2026-10-11") and the midas-intel design doc.
- All three are finished and pushed in midas-intel (commits 580f60d, dcee638, f5fdf91):
  `docs/research/birthdays/` (10 apps, 44-item checklist), `docs/research/notes/` (12 apps,
  checklist), `docs/research/alarms/` (10 apps, AlarmKit facts, 48-item checklist). Each has
  `APPS.md` and `ANALYSIS.md`.
- To move: the lead adds "Done 2026-10-11, results in midas-intel `docs/research/<category>/`" to
  that PRODUCT.md paragraph. Not done here because PRODUCT.md held another session's uncommitted
  edits on 2026-10-13.

## 2. Waiting on the founder

- Birthdays: go to stage 7 (founder describes his own app, as with Reminders) or run the
  remaining stages first. Asked 2026-10-11, no answer.
- Notes and alarms: no next step chosen.

## 3. Facts the research found that touch the shell (for whoever plans each Sidekick)

- Birthdays: the engine fires a Feb 29 yearly repeat in leap years only; Contacts import not
  built; 100 birthdays x 2 alerts fill the 48 slots for only about 88 days.
- Notes: the store is last-write-wins per key and a pending offline edit wins, the pattern behind
  Keep and Obsidian data loss; no save/sync status for the page; every save adds a full note copy
  to the server log.
- Alarms: Midas notifications today cannot ring through Silent or Focus or for longer than 30 s;
  this needs AlarmKit (not built), which repeats weekly only, always shows Stop, and has an open
  late-firing bug (iOS 26.0 to 27.0 RC, no workaround).

## 4. Subagents cannot write report files

- 2026-10-11: the harness refused subagents' Write of `.md` report files ("Subagents should
  return findings as text, not write report files"). All three `ANALYSIS.md` files came back as
  text and the lead saved them unchanged. Future research briefs should say "return the file
  text; the lead saves it" instead of "write the file".
