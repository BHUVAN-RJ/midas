# Recipe: building a to-do Sidekick

How an agent, or later the generator, puts a to-do Sidekick together from the blocks in this
folder. Written 2026-10-31. The clickable reference for every block and variation is
`docs/mockups/todo-primitive-2026-10-31.html`: when a block doc and the prototype disagree, the
founder decides which wins.

## 1. What a to-do Sidekick is made of

| Part | Where it is specified |
|---|---|
| One HTML page, inline script and style, `midas-store.js` pasted in | `docs/PRODUCT.md` section 5 |
| Records `todo:`, `list:`, `settings:self`, one JSON Schema each in the manifest `types` | `records.md` |
| Agent block in `manifest.json` and `tools.js`: one tool per page action (add, tick, move, edit, delete, search, change a setting) | `CLAUDE.md` "Every Sidekick is agent-connected" |
| The patterns on screen | `blocks/*.md` |
| What a complete to-do list must handle | `checklist.md` |
| Words | `docs/WRITING.md` |

## 2. Basic preset (the default every person starts with)

`settings:self` defaults from `records.md` section 3: paper look, auto light/dark, blue accent,
circle checkbox, details line and date colours on, ding, vibration on, celebrate when all done,
done items stay struck for the day then go to the Logbook, floating +, dates read from the title,
swipe right done and swipe left delete (both with Undo), home as a list, unfinished to-dos carry
over into Today without red, parts of day off.

Other presets (each sets only the fields named in the prototype's `PRESETS`): Paper (Things),
Notebook (Tweek), Soft (Tiimo), Wallpaper (Microsoft To Do), Heat (Clear). Whether a preset may
change behaviour fields (swipes, adding, home, done items, today model) or only look fields is
open: the prototype changes both; `blocks/settings.md` proposes look only (from L3, "no layout or
gesture change without the person choosing it").

## 3. Make it yours

Every variation is one field of `settings:self`, changed on the page in the Make It Yours panel
(TD-SET-01), saved at once, no rebuild. A person asking jess for a change ("make it dark", "no
sound") maps to the same fields through the agent tools. Changes beyond the fields (a new
pattern marked "on request" in the blocks) go through repair or the generator.

## 4. Build order

Each step ends with its tests passing and the whole suite re-run (`scripts/test-all.sh`).

1. **Records:** manifest `types` for `todo:`, `list:`, `settings:self`; read, write, delete;
   repeat next copy; double-tick guard. Tests from `records.md`.
2. **Theme:** TD-LOOK tokens as CSS custom properties per look, light and dark.
3. **Rows and Today:** TD-ROW, TD-DAY-01 (basic: carry over), TD-DONE-01, 05, 06.
4. **Adding:** TD-ADD-01 and 05 (basic), then 02 to 04 and 06.
5. **Gestures:** TD-GEST-01, 02 (drop line above the finger, never nests), 03.
6. **Navigation:** TD-NAV-01 to 04, Logbook, search including done.
7. **Item card:** TD-ITEM-01 to 06.
8. **Make It Yours:** TD-SET-01, 02, then every remaining variation.
9. **Outside:** TD-OUT-01 notifications for timed to-dos (needs the decision in `records.md`
   section 4), TD-OUT-02 widget.
10. **Agent tools** for every action, with tests.
11. **Completeness pass** against `checklist.md`.

Rules at every step: no gesture starts within 20 pt of the left edge (the shell's back swipe); no
localStorage or IndexedDB; every saved thing is a record; undo stack lives in page memory only.
