# Row (TD-ROW)

A row is one to-do in a list: its checkbox, its title, the meta line under it, its colour and its icon, and what happens when the title is long. Five patterns, from research `LOOK-ANALYSIS.md` section 1.2 and the group files `look-group-a.md` (A), `look-group-b.md` (B), `look-group-c.md` (C) and `look-group-d.md` (D). Labels, sizes, "Checklist N", "P-new-N", "L1"–"L6", screenshot names and tokens are as in `blocks/look.md`. [U] marks anything not in the research. Text sizes are the `textSize: m` values; TD-LOOK-04 scales them.

Row order, left to right: checkbox (TD-ROW-01; at the right with `end`), emoji badge (TD-ROW-04), then a text column holding the title (TD-ROW-05) and the meta line (TD-ROW-02), then the right side (a deadline flag). Tap the checkbox to tick (TD-DONE-01). Tap anywhere else to open the detail card (TD-ITEM-01). Swipe and long press are TD-GEST.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| TD-ROW-01 | Checkbox shape | core | `checkbox: circle` |
| TD-ROW-02 | Meta line | core | `showMeta: true` (Reminders/Things grey line) |
| TD-ROW-03 | Colour as meaning | core | `dateColors: true`; an item's `color` as a highlighter pill when set |
| TD-ROW-04 | Emoji or icon | on request | no setting; `todo.emoji` as a badge when set, never auto-picked |
| TD-ROW-05 | Long titles | core | no setting; wrap to 3 lines, full text in the detail card |

---

### TD-ROW-01 Checkbox shape

**Tag:** core (every app has a completion control; L1; P-new-25). **Variations:**
- `circle`: Reminders, Todoist, Microsoft To Do, Google Tasks, Any.do, Tiimo [C].
- `square` (rounded): Things, TickTick, Superlist [C].
- `end`: a tick inside a circle at the row's right end. Tweek [C].
- `none`: no checkbox; complete by swipe. Clear [C].
- Colour of the done mark: Microsoft To Do and Reminders fill with the list colour; Superlist solid red; Tiimo a black disc; Google Tasks and Any.do grey; Things blue with a white check [R]. Todoist tints the ring by priority (no priority field in `records.md`, so not mapped).

**Default variation:** `circle`.

**What it is.** The control that marks a to-do done, and its shape and position.

**Anatomy.**
- `circle`: 22 pt drawn, 1.5 pt stroke in `--ink-2` [U], left of the text, vertically centred on the title's first line.
- `square`: the same size, corner radius 6 pt [U].
- `end`: the same circle with a faint ✓ inside, at the row's right edge [C, Tweek]. Done: a filled `--ink-2` disc with a white ✓ [C, Tweek "filled grey tick"].
- `none`: no element.
- Done (circle and square): filled with the list's `color`, or `--accent`, plus a white ✓ 13 pt [U] (Microsoft To Do [C]). Soft look: done is a solid `--ink` disc with a white ✓ [C, Tiimo].
- Hit area: 44 × 44 pt centred on the drawn box [U], never overlapping the next row's (TD-LOOK-05).
- Subtasks in the detail card always use circles (Things: to-dos square, checklist items circles [C]).

**States.**
- To do; pressed (scale 0.9 for 100 ms [U]); done; done then undone.
- Repeat lock: for 2 s after a repeat tick, taps are ignored (TD-DONE-01).
- `none`: done shows as the green row of TD-DONE-01.

**Interactions.**
- Tap the checkbox: TD-DONE-01.
- Tap the title or meta: opens the detail card, never ticks.
- `none`: completing is swipe right with `swipeRight: complete`, or the long-press menu (TD-GEST-03), which always has "Complete" whatever the swipe settings, so a way to complete always exists [U].
- With `none`, first open (TD-SET-03) shows the swipe in place (P-new-32).

**Words.** None on screen. VoiceOver: `role="checkbox"`, the label is the title, `aria-checked` follows `done`. With `none`, the row gets an accessibility action "Complete". Setting "Checkbox": "Circle", "Square", "At End", "None".

**Data.** Reads `settings:self.checkbox` (missing → `circle`), `todo.done`, and `list:<id>.color` for the fill.

**Needs.** Page alone.

**Edge cases.**
- P-new-25: Microsoft To Do's left-side checkbox is hit by the grip; `end` puts it at the right.
- Checklist 49: a mis-tick is undoable (TD-DONE-06).
- L1: the tick responds under about 100 ms.
- P-new-32: Clear's gestures were judged not accessible by a blind user, so `none` still exposes "Complete" to VoiceOver.

**Tests.**
- Given no settings, then each row's checkbox has `border-radius: 50%` and sits before the title in the DOM.
- Given `checkbox: square`, then the radius is 6px; given `end`, then the checkbox is the row's last child.
- Given `checkbox: none`, then no checkbox element exists, and the long-press menu contains "Complete".
- Given `checkbox: none` and `swipeRight: delete`, `swipeLeft: delete`, then the long-press menu still contains "Complete".
- Given any setting, then the checkbox hit rectangle is at least 44 × 44.
- Given a tap on the title, then `todo.done` is unchanged.
- Given a done to-do in a list with `color` #27AE60, then the checkbox background is #27AE60.

**Evidence.** `LOOK-ANALYSIS.md` 1.2 (shapes and fills). Thumb reach: "I constantly touch the check off buttons, which are located on the left side" MS To Do 1★ 2025-11-02; "Should work well for right-handed users, though" 5★ 2025-11-12; "WAY too easy to accidentally hit the circle" 2026-08-29 (D, group-d P3). Screenshots: `reminders_iphone_1.png` (circle), `things_iphone_2.png` (square), `tweek_1.jpg` (end), `clear_iphone_1.png` (none), `mstodo-1.png` (list-colour fill), `superlist_3_crop.jpg` (red fill), `tiimo_3_crop.jpg` (black disc).

---

### TD-ROW-02 Meta line

**Tag:** core (every loved app has one). **Variations:**
- Reminders: a grey line "Family Tasks 9:00 AM ⟳ Daily"; overdue time and repeat in red; tags inline in blue [C].
- Things: the project or area name under the title; small grey glyphs for notes, checklist and tag; a deadline right-aligned in red "⚑ today" [C].
- Todoist: a calendar icon and a date coloured by meaning, ↻, label and alarm time; a one-line grey description; the project `#` on the right [C].
- TickTick: the time in blue, right-aligned [C]. Google Tasks: outlined pill chips [C]. Any.do: an outlined time pill [C]. Microsoft To Do: a grey sub-line naming the source list, a star on the right [C].

**Default variation:** `showMeta: true`, a single grey line in the Reminders and Things style.

**What it is.** One small line under the title that says where the to-do belongs and when it is.

**Anatomy.**
- 13 pt regular, `--ink-2`, 2 pt below the title, one line with an end ellipsis [U].
- Parts, in order, separated by " · ":
  1. The list name, with its emoji, only in smart lists and search (Reminders [C]).
  2. The day from `when`: "Today", "Tomorrow", "Yesterday", the weekday within the next 6 days, otherwise "Oct 2". It is left out in Today, where it is implied.
  3. The time from `time`, in the device's 12- or 24-hour format [U].
  4. Repeat: "↻ Daily", "↻ Weekdays", "↻ Weekly", "↻ Monthly" (from `repeat.every`).
  5. Subtasks: "1/3" (done/total) (Things chip "1/24" [C]).
  6. A ≡ glyph when `notes` is not empty (Things [C]).
- Right side: a deadline flag "⚑ Fri", 13 pt. It is `--late` when the deadline is today or past, otherwise `--ink-2` [U] (Things red deadline [C]).
- `showMeta: false`: no meta line; the deadline flag stays.

**States.**
- No parts to show: no meta element at all (no empty line).
- Done row: the meta line in `--ink-2` with no date colours.
- Someday (`someday: true`): "Someday" in place of a date [U].

**Interactions.** The meta line is not tappable on its own; a tap opens the detail card, where every control (date, repeat) is reachable however long the title is (P-new-30).

**Words.** "Today", "Tomorrow", "Yesterday", weekday names ("Friday"), "Oct 2", "9:00 AM", "↻ Daily", "↻ Weekdays", "↻ Weekly", "↻ Monthly", "1/3", "Someday", "Inbox", "⚑ Fri".

**Data.** Reads `todo.list` (→ `list:<id>.name`, `.emoji`), `when`, `time`, `deadline`, `repeat`, `subtasks`, `notes`, `someday`, and `settings:self.showMeta` (missing → `true`).

**Needs.** Page alone.

**Edge cases.**
- P-new-30: controls reachable with a long title (through the detail card).
- Checklist 56 and P-new-29: the meta line truncates, the title wraps (TD-ROW-05).
- Checklist 11: hiding the meta line never hides the to-do.

**Tests.**
- Given a to-do in list "Family" with `when` today, `time` 09:00, `repeat {every: day}`, when shown in Today, then the meta line reads "Family · 9:00 AM · ↻ Daily".
- Given the same to-do inside the Family list, then the meta line reads "9:00 AM · ↻ Daily".
- Given 3 subtasks with 1 done, then the meta line contains "1/3".
- Given a to-do with no date, repeat, subtasks or notes, inside its own list, then the row has no meta element.
- Given `showMeta: false` and a deadline today, then there is no meta element and the right side shows "⚑ Today" in `--late`.

**Evidence.** Things "If you have a long task name, you cannot easily get to the exact place to click to make a task recurring" 3★ 2025-09-14 (D); Reminders asks for "clear date divisions when sorting lists by date" 1 (A). The rest is screenshot anatomy. Screenshots: `reminders_iphone_1.png`, `things_iphone_2.png`, `todoist-macstories-liquidglass-2025.jpg`, `ticktick-1.png`, `anydo_2.jpg`.

---

### TD-ROW-03 Colour as meaning

**Tag:** core (calm palette with "colour only for meaning", D pattern table; Reminders users ask to colour single reminders). **Variations:**
- Todoist: the date coloured by urgency (green today, red overdue, purple later, orange or brown this week) and the ring by priority [C].
- Reminders: overdue in red [C]. Things: a red deadline and a yellow Today star [C].
- Tweek: a highlighter pill behind the title per item (pink, blue, green, yellow, plus custom hex) [C].
- Clear: colour by position, the heat map (TD-LOOK-01 `heat`).
- List colour on the checkbox: Microsoft To Do, Reminders (TD-LOOK-03).
- Any.do: coloured tag bars, Premium only [C].

**Default variation:** `dateColors: true`: today's date in `--today`, overdue dates and times in `--late`, every other date in `--ink-2`. Purple for later dates (Todoist) is not used [U]. Separately, an item's own `color` shows as a highlighter pill behind its title whenever it is set (Tweek).

**What it is.** Colour on a row only when it means something: when the to-do is, or a mark the person chose.

**Anatomy.**
- Date colour: on the day and time text of the meta line (TD-ROW-02) and on the deadline flag.
- Pill: behind the title text, radius 6 pt, padding 1 × 4 pt, `box-decoration-break: clone` so a wrapped title is highlighted on each line [U]. The title stays `--ink`. Colours are the notebook pill tokens (TD-LOOK-01) or a custom hex.
- Colour is never the only signal: an overdue date still reads "Yesterday" or "Oct 2".

**States.**
- `dateColors: false`: all dates `--ink-2`.
- Done row: no date colour; the pill at 50% opacity [U].
- Invalid `color`: no pill, and the record is not rewritten.

**Interactions.** The item colour is set in the detail card (TD-ITEM-01): a swatch row and "None". No gesture on the row.

**Words.** Swatch labels (VoiceOver): "Pink", "Blue", "Green", "Yellow", "Custom", "None".

**Data.** Reads `settings:self.dateColors` (missing → `true`), `todo.when`, `time`, `deadline`, `color`, `done`. Writes `todo.color` from the detail card.

**Needs.** Page alone.

**Edge cases.**
- TD-DAY-04 (overdue without shame): the red date text is the only overdue mark on the row; there is no badge, no count and no "Overdue" word [U].
- Checklist 42: carried-over items keep their colour.
- Colour-blind readers: the date text carries the meaning.

**Tests.**
- Given `dateColors: true` and a fixed clock of 2026-10-31, then a to-do with `when` 2026-10-31 shows its date in `--today`, one with 2026-10-30 in `--late`, and one with 2026-11-03 in `--ink-2`.
- Given `dateColors: false`, then all three show `--ink-2`.
- Given `todo.color` #FFD6E0, then the title element has background #FFD6E0; given "zzz", then no pill and the record still holds "zzz".
- Given a done to-do dated yesterday, then its date is `--ink-2`.

**Evidence.** Reminders "It would be nice if you could color code individual reminders" (2026-10-10) and "Wish I could color code things" (2026-09-27): 2 asks (A). Tweek colour coding 3 loves, paywalled colours 1 hate (C). Clear "the gradual ombré" 1 (A). Todoist: 0 direct quotes, part of "polished" praise (B). Screenshots: `todoist-macstories-liquidglass-2025.jpg`, `tweek_1.jpg`, `clear_iphone_1.png`.

---

### TD-ROW-04 Emoji or icon

**Tag:** on request (inline emoji already works as plain title text; the badge field is extra). **Variations:**
- Inline emoji in the title: everywhere (Any.do "Buy flowers for Sarah 💐", Reminders, Tweek) [C].
- A round tinted badge per task holding an emoji or 3D icon: Tiimo [C].
- An emoji or glyph per list: Reminders (colour, symbol or emoji), Microsoft To Do, Superlist [C].
- Tiimo's AI auto-picking emoji, colour and tags ("cluttered and busy", 1★) and its emoji moved behind the paywall (leave reason): not used.

**Default variation:** no setting. `todo.emoji` shows as a badge before the title when set; nothing shows when it is null. It is never auto-picked. `list.emoji` shows before the list's name in navigation and in its title.

**What it is.** An optional picture that makes a to-do or a list quicker to spot.

**Anatomy.**
- Paper, notebook, wallpaper, heat: the emoji at 20 pt, no circle, 8 pt before the title [U].
- Soft: a round 36 pt badge in the row's tint (TD-LOOK-01 soft tints, or the list colour at 20%) holding the emoji at 20 pt [U] (Tiimo [C]).
- Done: the badge at 40% opacity [U] (Tiimo "the icon badge fades" [C]).

**States.** Null (no badge); set; a multi-part emoji (family, flag, skin tone) is stored whole as one grapheme.

**Interactions.** Set in the detail card (TD-ITEM-01): an "Icon" field that takes one emoji from the keyboard, and "Remove". Lists: the list sheet.

**Words.** "Icon", "Remove".

**Data.** Reads and writes `todo.emoji` and `list:<id>.emoji`. Keeps only the first grapheme (`Intl.Segmenter`) [U].

**Needs.** Page alone. Whether the iOS emoji keyboard opens normally in a WKWebView text field: [U].

**Edge cases.**
- Leave reason 4: no AI filling the editor.
- Leave reason 5: nothing is paid.
- Checklist 9: fields the page does not know are kept on update.

**Tests.**
- Given `todo.emoji` "🧺", then a badge element containing "🧺" comes before the title.
- Given `emoji: null`, then the row has no badge element.
- Given `look: soft`, then the badge is a 36 × 36 circle.
- Given the input "👩‍👩‍👧x", then `todo.emoji` is saved as "👩‍👩‍👧".
- Given a new to-do "Buy milk" is added, then its `emoji` is null (no auto-pick).

**Evidence.** Tiimo: "The pictures reduce cognitive load while reading the calendar" 1; badge 2 loves plus 1 hate when it was paywalled or AI-picked (C pattern table); "now behind the premium pay wall" (Bete Noire, 2026-10-23). Reminders "change the colors and symbols" 1 (A). Screenshots: `tiimo_3_crop.jpg`, `anydo_2.jpg`, `reminders_iphone_7.png`.

---

### TD-ROW-05 Long titles

**Tag:** core (checklist 56; P-new-29; P-new-30; L4). **Variations:**
- Wrap: Google Tasks shows the title in up to 2 lines [C].
- One-line truncation: Todoist cuts the description to one line [C]; widgets cut titles (complaints).
- Middle ellipsis: HIG, "an ellipsis in the middle of text can make an item easier to distinguish" [C].
- HIG: "Keep item text succinct… to minimize truncation and wrapping" [C].

**Default variation:** no setting. The title wraps to 3 lines [U], then an end ellipsis; the full text is in the detail card.

**What it is.** How a title that does not fit on one line is shown, without losing any of it.

**Anatomy.**
- Title: `-webkit-line-clamp: 3` [U], `overflow-wrap: anywhere` so a long URL breaks.
- The checkbox stays aligned to the first line. The meta line sits below the last line. The deadline flag is top-aligned on the right.
- The row grows with the title; the row height is never fixed.
- Middle ellipsis is used only in one-line places that show a title: the undo toast (TD-DONE-06).

**States.**
- 1 line; 2–3 lines; more than 3 lines (clamped with an ellipsis).
- An unbroken string longer than the row (breaks, no horizontal scroll).
- A very long title, such as the 10,147-character task subject in Claude Code issue #103442.

**Interactions.** Tap the title: the detail card shows the full text and every control (P-new-30). No inline expand [U].

**Words.** None.

**Data.** `todo.title`, stored in full. The record limit is 64 KB, so the title field stops accepting input at 20,000 characters [U].

**Needs.** Page alone.

**Edge cases.**
- Checklist 56: kept in full, shown truncated.
- P-new-29: a text-size change never cuts a title that fitted.
- P-new-30: controls stay reachable with a long name.
- Checklist 57: the title is rendered as text (`textContent`), never as HTML, so it cannot inject markup or codes.

**Tests.**
- Given a 600-character title, then the row shows at most 3 lines and the detail card shows all 600 characters.
- Given the title `<b>x</b>`, then the row shows the literal characters and has no `<b>` element.
- Given a 300-character unbroken URL as a title, then the page has no horizontal scroll (`scrollWidth` equals `clientWidth`).
- Given `textSize: xl` and a 3-line title with a time, then the meta line is visible below the title.
- Given a 10,147-character title, when saved and reloaded, then `todo.title` has length 10,147.

**Evidence.** TickTick names "cutoff" after a size change, 2★ 2026-05-17; Things long name hides the recurring control, 3★ 2025-09-14; the Microsoft To Do widget's large font "cuts off a large amount of the tasks", 3★ 2025-08-12 (D 1.6, 1.7, Part 2 items 29–30); HIG Lists and tables [C]. No screenshot.

