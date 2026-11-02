# Capture (TD-ADD)

Capture is how a to-do gets onto the list: the floating +, dragging the + to a spot, an
always-on bar, a tap-to-add row at the end of each section, typed dates and repeats picked out of
the title as it is written, and inserting between two rows. Six patterns, from research
`LOOK-ANALYSIS.md` section 1.4 and `look-group-d.md` section 1.2, with app detail from
`look-group-a.md`, `look-group-b.md` and `look-group-c.md`. Which of TD-ADD-01 to 04 is on is one
field, `settings:self.add` (basic `fab`). Sizes are in pt (1 CSS px in the Sidekick's WKWebView).
Colours are theme tokens, CSS custom properties on `:root` that `recipe.md` will define. The to-do
recipe is not written yet, so the token names here (`--accent`, `--list`, `--bg`, `--bg-raised`,
`--ink`, `--ink-2`, `--line`, `--ok`, `--danger`, `--glass`) are [U] until it fixes them. `--list`
is the open list's `color`, falling back to `--accent`; the basic `--accent` is `#2F6FEB`
(`records.md` section 3). "Checklist N" is item N of research `group-d.md` section 6. "P-new-N" is
item N of `look-group-d.md` Part 2. L1 to L6 are the look items of `LOOK-ANALYSIS.md` section 4.
Screenshot files are in midas-intel `docs/research/todo/shots/` (`LOOK-ANALYSIS.md` section 6).
[U] marks anything not found in the research: an agent's proposal or an unverified fact.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| TD-ADD-01 | Floating + | core | On (`add: fab`): round + at the bottom trailing corner in the list's colour (Reminders, Things) |
| TD-ADD-02 | Drag + to a spot | on request | Off (`add: fab`); with `add: dragFab` the + can be tapped or dragged (Things Magic Plus) |
| TD-ADD-03 | Always-on bar | on request | Off (`add: fab`); with `add: bar` a field is pinned at the bottom (Any.do "I want to...") |
| TD-ADD-04 | Tap-to-add row per section | on request | Off (`add: fab`); with `add: row` a dotted row ends each section (Reminders) |
| TD-ADD-05 | Natural language with live highlight | on request (basic preset turns it on) | On (`parse: true`): recognised words highlighted as typed, tap to undo (Todoist, Reminders) |
| TD-ADD-06 | Insert between | core | No settings field; pinch two rows apart (Clear) in every `add` mode [U] |

Rules for every pattern here:
- No haptics. A Sidekick page has no haptics API; `PRODUCT.md` lists haptics as "later" native reach. Things and TickTick buzz on pickup and on Magic Plus; the page cannot (see `LOOK-ANALYSIS.md` section 5 for the WebKit switch trick, not used [U]).
- Every gesture ignores a touch that starts within 20 pt of the left screen edge, because the shell owns that swipe (back to the home grid; `daily-planner/recipe.md` section 3).
- Motion is cut to instant changes under `prefers-reduced-motion: reduce`.
- Adding never waits for the network (core job P5: Microsoft To Do "took over 10 seconds to add a To-Do item", HN 2025-11-18).

---

### TD-ADD-01 Floating +

**Tag:** core. Every app in the research has a floating or fixed +, and core job P5 is fast
capture. **Variations:**
- Things: blue Magic Plus circle, bottom right (sampled about #5B9AFF [R]). In OS 26 its glass "ever so slightly deforms" when dragged, and buttons "glow and scale" (`look-group-a.md` 1.3).
- Apple Reminders: floating circle "+" bottom right in the list's colour (green on Groceries), no bottom toolbar (`reminders_iphone_1.png`).
- Todoist: red "Dynamic Add" circle that takes the theme colour (green in Kale).
- Google Tasks: + moved from bottom centre to bottom right in September 2026, which users hated for breaking muscle memory.
- TickTick: + that can also be pressed and dragged (TD-ADD-02).

**Default variation:** `add: fab`. A round + at the bottom trailing corner, filled with `--list`.
Tap opens the add card.

**What it is.** One prominent add button that is always in the same place. Tapping it opens a
small add card docked on the keyboard, and the new to-do goes into whatever list or smart list is
open.

**Anatomy.**
- Button: 56 pt circle [U], 20 pt from the trailing edge and 16 pt above the bottom safe area [U]. Fill `--list`. White "+" glyph, 24 pt, semibold [U]. Soft shadow [U].
  - Apple's HIG: one `.prominent` primary action, "on the trailing side"; glass is for the control layer only (`look-group-d.md` 1.7) [C].
  - The fill is solid, not clear glass, so it reads as the one prominent action [U].
- Add card, modelled on the Google Tasks sheet on the keyboard (details, date, Save) and the Things Quick Entry card (title, list picker "Inbox", blue "Save" pill):
  - White card (`--bg-raised`), 16 pt top corners [U], sitting on the keyboard. The list behind is dimmed 20% [U].
  - Title field: 17 pt regular `--ink` [U], placeholder "New To-Do" in `--ink-2`. Wraps up to 4 lines, then scrolls (checklist 56).
  - Chip row under the title, 32 pt tall chips with 8 pt gaps [U]:
    - a date chip ("Today", "Tomorrow" or the date; "No Date" when none);
    - the list chip (the list's emoji or dot plus its name, "Inbox" by default);
    - chips that TD-ADD-05 recognised, in `--accent` tint.
  - "Add" pill at the trailing end of the chip row: 36 pt tall [U], `--list` fill, 15 pt semibold white. Dimmed to 40% and inert while the title is empty.
  - No clear (✕) button inside the field. Things users lose entries by bumping its "gigantic clear button" (`look-group-a.md` 1.6).

**States.**
- No list open (home screen, `home: list` or `tiles`): the + adds to Inbox with no date [U].
- Today open: `list: inbox`, `when` = today. Under `todayModel: fresh`, `inToday` is also set to today (TD-DAY-01).
- Upcoming open: `when` = tomorrow [U].
- A user list open: `list` = that list, `when` null.
- Logbook or search open: + hidden [U].
- With `add: bar` or `add: row`: no floating + (one add method at a time; `records.md` section 3).
- Offline: the same as online. The record goes to the local store and the shell syncs later.
- Write refused by the store (record over 64 KB, schema mismatch): the card stays open with the text kept, and a line "Can't Add To-Do" with "Try Again" (checklist 8).

**Interactions.**
- Tap: the card rises with the keyboard, 250 ms ease-out [U]. The button scales to 0.94 while pressed [U] (Things "glow and scale").
- The tap fires only if the finger lifts inside the button having moved less than 10 pt [U]. A swipe up that passes over the + never adds (Things 4★ 2025-06-07: "if you swipe up anywhere near it, you inadvertently add a new item").
- Return or "Add": saves the to-do and keeps the card open with an empty field for the next one. This is rapid entry, as with the Clear 2 keyboard "next" key [C] and Tweek's "press enter" [C].
- Tap the dimmed list or swipe the card down: closes the card.
  - If the title is not empty, it is added first, so nothing typed is lost [U] (checklist 1, P5).
  - If it is empty, the card simply closes.
- Tap the date chip: Today, Tomorrow, Someday and a native `<input type="date">` [U].
- Tap the list chip: the list picker [U].
- Where the new row goes: the end of the open (not done) to-dos of its list or section, `order` = last open `order` + 1 [U]. Microsoft To Do puts a new task "to the bottom of your list" [C]; Clear's pull-down put it at the top.
- The new row appears at once, before the store answers (L1 feel). If the write is refused, the row is marked and "Try Again" is offered (checklist 8).
- The + never moves on its own (L3). Google Tasks users left over a moved + ("Muscle memory is strong").
- No haptic.

**Words.** "New To-Do" (placeholder) · "Add" · "Today" · "Tomorrow" · "Someday" · "No Date" ·
"Inbox" · error "Can't Add To-Do" / "Try Again".

**Data.**
- Writes `todo:<id>` with:
  - `title` (after TD-ADD-05 removes the recognised words);
  - `list`, `when`, `time`, `deadline`, `repeat`, `part` (as recognised or chosen);
  - `done: false`, `completedAt: null`, `createdAt` (now), `order`, `subtasks: []`, `someday` (true only from the Someday chip), and `inToday` under the fresh model.
- Reads `settings:self.add` and `.todayModel`, plus the open list's `list:<id>.color`.

**Needs.** Page alone. Shell has the store (`store.set`) and sync. A timed to-do needs the
notification engine, and how a `todo:` maps to a `reminder:` is open (`records.md` section 4).

**Edge cases.**
- P5: no network wait.
- Checklist 1: closing the card with text adds the to-do.
- Checklist 8: refused write is shown.
- Checklist 56: a long title wraps in the field and is stored in full.
- P-new-25: the + sits on the trailing side, away from the left-thumb tick area.
- L3: fixed position.
- L6: the card opens only on the person's tap.
- Left-handed people ask for the + on the left (Things 5★ 2025-05-31; Google Tasks "Far right corner is hard to reach with one left hand", 2026-09-18). `settings:self` has no field for the side [U]; open for the founder.

**Tests.**
- Given Today is open on 2026-10-31, when "+" is tapped, "Call mom" is typed and Return is pressed, then a `todo:` record exists with `title` "Call mom", `list` "inbox", `when` "2026-10-31" and `done` false, and the card is still open with an empty field.
- Given the add card with "Buy milk" typed, when the dimmed list is tapped, then a `todo:` with `title` "Buy milk" exists and the card is closed.
- Given the add card with nothing typed, when it is swiped down, then no `todo:` record was written.
- Given a finger lands on the + and moves 30 pt up before lifting, then the add card does not open.
- Given the stand-in store rejects `set`, when "Add" is tapped, then "Can't Add To-Do" and "Try Again" show and the title is still in the field.
- Given the list "Groceries" with `color` "#34C759" is open, then the + fill computes to that colour.
- Given `add: bar`, then no floating + is in the page.

**Evidence.**
- `LOOK-ANALYSIS.md` 1.4, `look-group-d.md` 1.2, `look-group-a.md` 1.2 and 3.2, `look-group-b.md` 1.2 and 4.2.
- Quotes:
  - Things placement hate: 1 (2025-06-07). Left-hand asks: 2 (Things 2025-05-31, Google Tasks 2026-09-18).
  - Google Tasks "Moved the + button for no reason": 1★, 2026-09-21. Todoist freezes on the +: 1–2★, 2026-03.
  - Reminders Control Center quick add love: 5★, 2026-10-18.
- Screenshots: `things_0.jpg`, `reminders_iphone_1.png`, `todoist-macstories-liquidglass-2025.jpg`.

---

### TD-ADD-02 Drag + to a spot

**Tag:** on request. Not a checklist item or a leave reason: 1 love, 2 complaints. **Variations:**
- Things Magic Plus: drag it to a spot in a list, onto the Inbox target at the bottom left, to the far left in a project for a heading, or onto a day in Upcoming to set the start date. Screenshot 5 shows a large blue disc and a grey placeholder slot opening where it will drop (`look-group-a.md` 1.2, 1.3).
- Todoist "Dynamic Add": "Tap or drag the Dynamic Add button" (help updated 2026-09-01).
- TickTick: "press the '+' and drag it", then "release it where you want the task added" [C].

**Default variation:** off in the basic preset (`add: fab`). With `add: dragFab`, the TD-ADD-01 +
keeps its tap and can also be dragged. Drop targets are the gaps between rows in the open list, and
day headers in Upcoming.

**What it is.** The person drags the + itself to exactly where the new to-do should go. On release,
an empty row opens there for typing.

**Anatomy.**
- The + as in TD-ADD-01.
- While dragged:
  - The disc grows to 64 pt [U] and floats 40 pt above the finger [U], so the finger never covers the drop point (the same rule as P-new-10).
  - The rows part to open a placeholder slot, one row tall, with a dashed 1 pt `--line` outline [U] (Things' grey slot), at the gap nearest the disc's centre.
  - Rows slide 150 ms ease-out [U].
- In Upcoming, a day header under the disc tints `--accent` at 12% [U] to show it is the target.
- Headings (Things' far-left drop) are not built: `records.md` has no heading record.

**States.**
- No rows yet: the only slot is the top of the list.
- `doneGoes: stay` or `sink`: slots exist only among open rows [U].
- Logbook and search: + hidden (TD-ADD-01).

**Interactions.**
- The drag begins once the finger has moved 8 pt from the + [U]; a tap without movement is TD-ADD-01.
- Near the top or bottom 60 pt of the list, the list auto-scrolls, faster the closer to the edge [U].
- Release over a slot: an editable row opens there with the keyboard up and the cursor in the title. Return saves it and opens another empty row right below (rapid entry).
- Release over an Upcoming day header: the same, with `when` = that day.
- Release back on the + or outside the list: cancelled. The disc returns over 200 ms [U].
- Discoverability: "Why is the FAB draggable? I can't figure out what to do with it" (Todoist 4★, 2025-04-21). First open teaches it in place (TD-SET-03, P-new-32).
- No haptic. Things uses the Taptic Engine here; the page has none.

**Words.** "New To-Do" (placeholder in the opened row). No other strings.

**Data.** Writes one `todo:<id>`. Its `order` is the midpoint of the two neighbours' `order`
(fractional, one write; `records.md` section 1). `list` is the open list; `when` comes from the
Upcoming day, or from Today as in TD-ADD-01. Reads `settings:self.add`.

**Needs.** Page alone (pointer events, `touch-action: none` on the + while dragging). The haptic on
pickup: the shell lacks it.

**Edge cases.**
- P-new-17: inserts between two rows.
- P-new-16: the new `order` holds after reload and sync.
- Checklist 16: stable order.
- P-new-10: the drop point stays visible above the finger.
- L3.

**Tests.**
- Given `add: dragFab` and rows A (`order` 1), B (`order` 2), when the + is dragged to the gap between A and B and released and "Pay rent" is typed with Return, then a `todo:` with `title` "Pay rent" and `order` 1.5 exists, and a reload shows A, Pay rent, B.
- Given `add: dragFab`, when the + is tapped without moving, then the TD-ADD-01 add card opens, not an inline row.
- Given Upcoming, when the + is dropped on the "Tuesday 4 Nov" header and a title is entered, then the record's `when` is "2026-11-04".
- Given a drag in progress, then the placeholder slot's top edge is above the finger's position.
- Given `add: fab`, when the + is dragged 40 pt, then nothing moves and no slot opens.

**Evidence.**
- `look-group-d.md` 1.2 and its pattern table: "Draggable add button: 1 loved, 2 complaints (placement, unclear)".
  - Love: "life changing. I missed it enough to switch back from Reminders and pay for Things again", 5★, 2025-04-18.
- `look-group-b.md` closing table: 0 quotes for Todoist's or TickTick's drag. `look-group-a.md` pattern table: 0 direct 2025-26 quotes, feature pages and press only.
- Screenshot `things_0.jpg` (Magic Plus).

---

### TD-ADD-03 Always-on bar

**Tag:** on request. **Variations:**
- Any.do: a rounded pill field "I want to..." always visible at the bottom, with a home icon at its left (`anydo_2.jpg`).
- Microsoft To Do: an "Add a task" bar with a "+" at the bottom of each list.
- Superlist: "+ New task" in the keyboard accessory row.
- Tweek: no sheet at all. Tap a blank line under a day and type, press Enter (TD-ADD-04 is closer to this).

**Default variation:** off in the basic preset. With `add: bar`, a field is pinned at the bottom of
every list screen.

**What it is.** Capture that is always one tap away: the field is already on screen, so there is no
button and no sheet.

**Anatomy.**
- Pill field, 48 pt tall [U], 20 pt side margins [U] (kept clear of the shell's left-edge zone), 16 pt above the bottom safe area [U].
- Material `--glass`: this is the control layer, and content scrolls under it (HIG, `look-group-d.md` 1.7) [C].
- Leading "+" glyph 20 pt in `--list` [U]. Placeholder "New To-Do", 17 pt `--ink-2` [U]. Any.do's "I want to..." is not used (`docs/WRITING.md` rule 1: say the action).
- While focused, the bar rides on top of the keyboard. TD-ADD-05 chips show in a row just above it, and an "Add" pill appears at its trailing end (same style as TD-ADD-01).
- The list gets bottom padding equal to the bar height plus 16 pt [U], so the last row is never hidden behind it.

**States.** As TD-ADD-01 for where the to-do goes. With `home: tabs` (TD-NAV-01), the bar sits
directly above the tab bar [U]. Logbook and search: bar hidden [U].

**Interactions.**
- Tap: focus, the keyboard rises.
- Return: adds and keeps focus with the field cleared (rapid entry).
- Blur with text: adds it [U] (checklist 1). Blur with nothing typed: nothing.
- The bar never moves or hides on scroll [U] (L3).

**Words.** "New To-Do" · "Add" · error "Can't Add To-Do" / "Try Again".

**Data.** As TD-ADD-01.

**Needs.** Page alone. iOS keyboard resizing: the bar uses the visual viewport to stay above the
keyboard [U].

**Edge cases.** P5, checklist 1, 8, 56 (the field scrolls sideways for a long title [U]), L3, L6.

**Tests.**
- Given `add: bar` and the list "Errands" open, when "Post office" is typed in the bar and Return pressed, then a `todo:` with `list` = the Errands id exists and the bar is still focused and empty.
- Given `add: bar` and 40 rows, when the list is scrolled to the end, then the last row's bottom edge is above the bar's top edge.
- Given `add: bar`, then no floating + and no dotted add rows exist.

**Evidence.** `look-group-c.md` 2.2 and its table: "Always-visible capture field or inline typing on
a line: Any.do, Tweek, Superlist", Tweek 2 loves. `look-group-b.md` 3.2 (Microsoft To Do bar).
Screenshots `anydo_2.jpg`, `tweek_1.jpg`.

---

### TD-ADD-04 Tap-to-add row per section

**Tag:** on request. **Variations:**
- Apple Reminders: each section ends with an empty dotted circle placeholder row, in Today (Morning, Afternoon, Tonight) and in auto sections like Groceries; tap there to add into that section (`reminders_iphone_1.png`).
- Any.do: a grey "+" at the right of each bucket header (Today, Tomorrow, Upcoming) that "adds straight into that bucket".
- Tweek: empty ruled lines under each day. "Tap to write it down" (2026-01-01); "Just go to the date you want to do a task, and press enter" (2025-03-28).
- Clear 2: tap above or below the items to add, with the keyboard "next" key for the next one.

**Default variation:** off in the basic preset. With `add: row`, a dotted row ends every section
(Reminders).

**What it is.** The add point is inside the list, at the end of each section. Typing happens in the
row itself, with no sheet, and the section decides the new to-do's day, part of day or list.

**Anatomy.**
- Placeholder row, the same height as a TD-ROW row [U]:
  - a dotted circle in place of the checkbox, the same size as the TD-ROW-01 checkbox, 1.5 pt dotted `--ink-2` stroke [U];
  - no text until tapped.
- With `checkbox: square`, the dotted shape is a rounded square. With `checkbox: none`, a "+" glyph in `--ink-2` [U]. With `checkbox: end` (Tweek), the dotted circle sits at the row's end.
- Tapped: the row becomes an editable title field (17 pt, placeholder "New To-Do"); TD-ADD-05 chips show beneath it.

**States.**
- Empty section: the dotted row is the section's only row.
- Sections are those of the open view:
  - Today: one section, or the parts of day when `dayParts: true` (TD-DAY-02);
  - Upcoming: one per day (TD-DAY-03);
  - a user list: one at the end.
- Logbook and search: none.

**Interactions.**
- Tap: inline edit with the keyboard.
- Return: saves, and a new editable row opens right below, still in that section.
- Blur or Esc with text: saves [U]. Blur with nothing typed: back to dotted.
- What the section sets:
  - Today section: `when` = today;
  - part-of-day section: `part` (morning, afternoon, evening);
  - Upcoming day: `when` = that day;
  - list: `list`.
- `order`: after the last open row of the section.
- Start zone: the tap target begins at the row's leading inset (at least 20 pt), so it is clear of the shell's edge [U].

**Words.** "New To-Do" (placeholder while editing).

**Data.** Writes one `todo:<id>` as above. Reads `settings:self.add`, `.dayParts`, `.checkbox`.

**Needs.** Page alone.

**Edge cases.** P5, checklist 1 (blur saves), checklist 8, P-new-17 (end of a section only; between
rows is TD-ADD-06), L3.

**Tests.**
- Given `add: row`, `dayParts: true` and Today open, when the Evening dotted row is tapped and "Read" is typed with Return, then a `todo:` with `when` today and `part` "evening" exists, and a new empty editable row is focused in Evening.
- Given `add: row` and Upcoming, when the dotted row under 3 Nov is used, then the record's `when` is "2026-11-03".
- Given an editable dotted row with no text, when focus leaves, then no record is written and the dotted row is back.

**Evidence.** `look-group-a.md` 3.2 and 3.6 (Reminders' signature: "tap-to-add dotted rows"),
`look-group-c.md` 2.2 and 4.2. Tweek quotes: 2 (2026-01-01, 2025-03-28). Screenshots
`reminders_iphone_1.png`, `anydo_2.jpg`, `tweek_1.jpg`.

---

### TD-ADD-05 Natural language with live highlight

**Tag:** on request by the README rule: not a checklist item and not a leave reason; its absence
draws a single complaint. The basic preset sets `parse: true`, so it is built with the basic
preset; open for the founder. **Variations:**
- Todoist:
  - recognised words get a light orange highlight as you type ("Review contract from Sarah **by Friday 13:00** **p2** **+Alex**") and show as chips below;
  - "tap the word to turn it into plain text";
  - symbols `#` project, `/` section, `p1–p3`, `!` reminder, `{march 30}` deadline, `+` person, `%` label (`todoist_1.jpg`).
- Apple Reminders: "Water the plants **at 7am every day**": the parsed part turns blue, and a grey chip shows "Title: Water the plants".
- TickTick: blue-highlighted keywords; tap them to turn them back into text.
- Superlist: "Call Niklas **every tuesday**": the date words turn blue, and a popover suggests "↻ Weekly on Tuesday ↵" (`superlist_6_crop.jpg`).
- Things: parses only inside the When picker ("tod", "17d", "3rd wed jul"), not in the title.
- Google Tasks: none.

**Default variation:** `parse: true`. Recognised words are highlighted in `--accent` (Reminders,
TickTick and Superlist use blue, close to the basic `#2F6FEB`), shown as chips, and removed from the
title on save. Tapping a highlighted span makes it plain text again.

**What it is.** The person types one line and the dates, times and repeats in it are picked out
live, so a to-do with a date needs no picker.

**Anatomy.**
- Highlighted span: text in `--accent` on a 12% `--accent` background, 4 pt radius [U].
- Chips in the add card's chip row (TD-ADD-01), or above the bar or row: 32 pt tall [U], `--accent` 12% fill, 15 pt `--accent` text, with a leading glyph (calendar, clock, ↻, flag for deadline, list dot). Examples: "Fri 7 Nov", "7:00 AM", "↻ Every Day", "Due Fri".

**What it recognises (English only [U]), and the field it sets:**

| Typed | Field |
|---|---|
| "today", "tomorrow", a weekday ("fri", "friday"), "next week", "7 nov", "nov 7" | `when` |
| "at 7am", "7:30pm", "19:00" | `time` (with no date: today if still ahead, else tomorrow [U]) |
| "every day", "every weekday", "every week", "every month", "every tuesday" | `repeat { every, from: schedule }` (a weekday sets `every: week` and `when` = next one [U]) |
| "after done" with a repeat ("every week after done") | `repeat.from: done` [U] |
| "by friday", "by 7 nov" | `deadline` [U] |
| "#Groceries" (an existing list name) | `list` |
| "morning", "afternoon", "evening" (only when `dayParts: true`) | `part` [U] |

Not recognised: priority, people, labels. `records.md` has no fields for them.

**States.**
- `parse: false`: no highlight; the title is saved as typed.
- Several matches: each is its own span and chip. A later date phrase replaces an earlier one [U].
- A span the person has undone stays plain for the rest of that entry, even if more is typed [U].

**Interactions.**
- Parsing runs on every input event, on the whole field. A match is shown only after the word that ends it is finished (a space or the end of a known token) [U], so "Mon" in "Monica" never lights up.
- Tap a span or its chip ✕: becomes plain text, and the field is cleared.
- Tap a date chip: the native date picker to adjust it [U].
- On save, the recognised words are cut from `title`, and spaces are trimmed.
- No timer advances anything.

**Words.** Chip labels: "Today", "Tomorrow", weekday and date forms ("Fri 7 Nov"), times in the
iOS 12/24-hour setting [U], "↻ Every Day", "↻ Every Weekday", "↻ Every Week", "↻ Every Month",
"After Done", "Due Fri 7 Nov", the list's name.

**Data.** Sets `when`, `time`, `repeat`, `deadline`, `list`, `part` on the new `todo:`. Reads
`settings:self.parse`, `.dayParts`, and the `list:` names.

**Needs.**
- Page alone for parsing.
- A recognised `time` makes a timed to-do. Its notification needs the shell's engine, and the `todo:` to `reminder:` mapping is open (`records.md` section 4).
- Apple Intelligence "Describe" parsing (iOS 27) is not reachable from a page [U].

**Edge cases.**
- Titles that look like dates ("Call May", "Book Friday's show"): the word-end rule and tap-to-undo cover them.
- A repeating to-do from text must still follow the 2 s double-tick rule on completion (`records.md`; P-new-4).
- Checklist 45: a typed time is floating local time (no `timeZone` on `todo:`).
- Checklist 56: long titles are parsed in full.
- L3: parsing never changes what was typed without showing it.

**Tests.**
- Given `parse: true` on Friday 2026-10-31, when "Water plants every day at 7am" is added, then the record has `title` "Water plants", `repeat` `{ every: "day", from: "schedule" }`, `time` "07:00".
- Given `parse: true`, when "Call Monica" is typed, then no span is highlighted.
- Given "Pay rent tomorrow" typed, when the "tomorrow" span is tapped and the to-do is added, then `title` is "Pay rent tomorrow" and `when` is null.
- Given `parse: false`, when "Gym tomorrow" is added, then `title` is "Gym tomorrow" and `when` is null.
- Given a list named "Groceries", when "Eggs #Groceries" is added from Today, then `list` is the Groceries id and `title` is "Eggs".

**Evidence.**
- `LOOK-ANALYSIS.md` 1.4.
- `look-group-d.md` pattern table: Todoist 4 praise mentions. Things' lack draws 1 complaint: "The only thing keeping this app from being a home run… is the lack of Natural Language Processing", 4★, 2026-05-10.
- `look-group-b.md`: NL entry praised 5 times in the earlier file. `look-group-c.md` table: Superlist 0 direct quotes. `look-group-a.md` table: 0 look quotes.
- Screenshots `todoist_1.jpg`, `superlist_6_crop.jpg`.

---

### TD-ADD-06 Insert between

**Tag:** core (P-new-17: "A new item can be inserted between two others, not only at the bottom").
**Variations:**
- Clear: pinch two rows apart; a new row opens in the gap, shown as "Add thought!" (`clear_2.jpg`).
- Things: drag Magic Plus to the spot (TD-ADD-02).
- Apple Reminders: the dotted row, at the end of a section only (TD-ADD-04).
- Clear 2: tap above or below rows.
- Microsoft To Do: cannot. "you also can't insert a task between others" (3★, 2025-10-31).

**Default variation:** no `settings:self` field [U]. Pinch apart between two rows works in every
`add` mode. With `add: dragFab`, TD-ADD-02's drop also inserts. "Add Below" in the long-press menu
(TD-GEST-03) is the visible way [U].

**What it is.** A way to put a new to-do at an exact place in a manually ordered list, written with
one record write.

**Anatomy.**
- While pinching, the two rows move apart with the fingers.
- The gap shows a row-shaped slot on `--bg-raised`, with the placeholder "New To-Do" in `--ink-2` fading in as the gap grows [U].
- At one row height the slot is open [U].

**States.**
- Only in views ordered by `order`: a user list, Inbox, Today and Upcoming within a day [U].
- Off in Logbook and search.
- Off between done rows (`doneGoes: stay`, `sink`) [U].

**Interactions.**
- Two touches on two neighbouring rows moving apart vertically by more than 24 pt [U] start the insert.
  - Release at one row height or more: an editable row stays open with the keyboard.
  - Release below that: the rows close again, 200 ms ease-out [U].
- Return saves. Blur with nothing typed removes the slot.
- Neither touch may start within 20 pt of the left screen edge.
- Page zoom is turned off for this page (viewport `user-scalable=no`, and `gesturestart` default prevented) so the pinch does not zoom the WKWebView [U].
- Pinching together does nothing [U]. In Clear it goes up a level, and that gesture is not copied.
- Discoverability: taught in place on first open (TD-SET-03, P-new-32). Clear's gestures draw complaints that nobody can find them.

**Words.** "New To-Do" (placeholder). "Add Below" (menu item in TD-GEST-03).

**Data.** Writes one `todo:<id>` with `order` = (upper `order` + lower `order`) / 2 and the
section's fields (as TD-ADD-04). When two neighbours' `order` values are too close for a
midpoint, that list is renumbered 1, 2, 3, which takes many writes [U].

**Needs.** Page alone (touch events).

**Edge cases.**
- P-new-17.
- P-new-16: manual order holds after reload and sync.
- Checklist 16: stable order.
- L3.
- Two people editing order on two devices: the last write wins per key in the shell (`ANALYSIS.md` section 5, "LWW per key"). A collision of two inserts at the same midpoint gives equal `order`, broken by `createdAt` [U].

**Tests.**
- Given rows A (`order` 1) and B (`order` 2), when they are pinched 60 pt apart, released, and "Stamps" is entered, then one `todo:` is written with `order` 1.5, A and B are not rewritten, and a reload shows A, Stamps, B.
- Given a pinch of 15 pt released, then no slot remains and nothing is written.
- Given one pinch touch starts at x = 10 pt, then no insert starts.
- Given the Logbook, when two rows are pinched apart, then nothing opens.
- Given two to-dos with equal `order`, then they show in `createdAt` order, every time.

**Evidence.** `LOOK-ANALYSIS.md` 1.4 and section 4 (P-new-17). `look-group-d.md` pattern table:
Clear pinch "marketing [C], 1 confusion". `look-group-a.md` table: 0 direct 2025-26 quotes. Microsoft
To Do quote: 1 (2025-10-31). Screenshot `clear_2.jpg`.

