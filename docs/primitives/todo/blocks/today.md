# Today, parts of day, Upcoming, overdue (TD-DAY)

This block covers what Today shows, what happens to an unfinished to-do when the day changes,
splitting the day into parts, the Upcoming view by day, and how overdue to-dos show without
building into a pile of shame. It has four patterns.

Sources, all in midas-intel `docs/research/todo/`:
- `group-a.md` section 1: the five today models.
- `group-a.md` sections 2 to 6: Microsoft To Do, Things, Todoist, Superlist and Apple Reminders.
- `group-a.md` section 10: leave reasons.
- `look-group-a.md` 1.2 and 3.2: Things and Reminders screens.
- `look-group-c.md` 2.2, 3.2 and 4.2: Any.do, Tiimo and Tweek.
- `group-d.md` P2 and checklist #42 to #48.

Template: `docs/primitives/daily-planner/README.md` ("Block template"). Records:
`../records.md`. Screenshots are in midas-intel `docs/research/todo/shots/`. Theme tokens
(`--bg`, `--surface`, `--ink`, `--ink-2`, `--line`, `--accent`) belong to `../recipe.md`, which
is not written yet. Values marked [U] are proposals not found in the research. Written
2026-10-31.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| TD-DAY-01 | Today model | core | `todayModel: carry` (unfinished to-dos show in Today on the next day) |
| TD-DAY-02 | Parts of day | on request | `dayParts: false` (off) |
| TD-DAY-03 | Upcoming by day | core | Things-style day blocks for the next 7 days, then by month (no `settings:self` field) |
| TD-DAY-04 | Overdue without shame | core | In `stay` only: one "Overdue" group at the top with "Move to Today" (no `settings:self` field) |

Rules for every pattern here:
- **"Today" is the phone's local date** (`YYYY-MM-DD` from the phone's clock and zone).
- **The day changes at local midnight.** A day-end hour (checklist #44, DP-27) has no
  `settings:self` field, so it is not mapped.
- **`when` and `deadline` are day strings, not instants.** They are compared as strings and never
  parsed through UTC, so a zone change or a DST change never moves a to-do to another day (#46).
- **No model deletes, archives or hides a to-do for good** (#42, P1). The fifth model in the
  research, discard (MacIver "Day Plan"), is listed but not built.
- **The day change writes nothing.** Models differ only in what the page shows, so switching
  models is lossless and instant (L3).

---

### TD-DAY-01 Today model

**Tag:** core. Reasons:
- Checklist #42: unfinished items are kept and offered again, never dropped.
- P2: show the right "today" every day.
- group-a leave reason 1: overdue builds into shame, 5 sources.
- group-a leave reason 6: automated roll-over is unreliable.

**Variations** (group-a section 1):
- **`carry`, carry over (copy forward).** Unfinished items come into the next day's list.
  - Ivy Lee (by hand), kgeist's daily markdown file, al3rez's todo.txt, Obsidian daily-note
    plug-ins, Sunsama.
  - Tweek: "if something's left, we'll roll it to tomorrow. No task left behind." [C,
    look-group-c 4.2]
- **`stay`, stay until done.** The item stays in Today, in an Overdue group, and builds up.
  - Todoist Today (Overdue).
  - Apple Reminders: "shows reminders that are due today and reminders that are overdue" [C].
  - Superlist: "Any task that's due today or overdue appears in Today automatically" [C].
- **`fresh`, reset.** Microsoft To Do My Day "resets every night, so you have a blank slate";
  unfinished tasks "will be saved to your Tasks list" and offered as suggestions the next day [C].
  Tasks due today are added to My Day automatically [R].
- **`gated`, date-gated.** The item is hidden until its date, then shows in Today.
  - Things: Upcoming to-dos "transform into actionable items in Today" [C].
  - Obsidian Tasks start and scheduled dates; Taskwarrior `wait`.
  - What Things does with items left at midnight has no primary source [U, group-a 11].
- **Discard (not built).** MacIver's Day Plan throws the list away each day. It would delete
  to-dos, against #42 and P1.

**Default variation:** `carry` (basic preset, records.md section 3).

**What it is.** The rule for which to-dos Today shows, and so what happens to an unfinished to-do
when the day changes.

**Anatomy.**
- Header: "Today" 34 pt bold `--ink` [U]. Under it, the date 15 pt `--ink-2` ("Sat 31 Oct"),
  as Microsoft To Do's My Day subtitle [C, look-group-b 3.2].
- Then, top to bottom:
  - The Overdue group (`stay` only, TD-DAY-04) or the Suggestions group (`fresh` only).
  - Today's rows (TD-ROW), or the parts of the day (TD-DAY-02).
  - Done to-dos, per `doneGoes` (TD-DONE-05).
- Suggestions (`fresh`): a group under the rows, heading 13 pt semibold `--ink-2`. Each row has
  an "Add to Today" control at the right (a ⊕ in `--accent`, 44 pt target [U]).

**What Today shows, by model.** Every model leaves out to-dos with `done: true`, except those
ticked today (`completedAt` today), which follow `doneGoes`. Every model leaves out
`someday: true`.

| Model | In Today |
|---|---|
| `carry` | `when` ≤ today, plus `deadline` ≤ today. Past-`when` items show as ordinary rows; no Overdue group. |
| `stay` | The same set. Items with `when` or `deadline` before today go in the Overdue group (TD-DAY-04). |
| `fresh` | `inToday` = today, plus `when` = today, plus `deadline` = today. Items with `inToday` or `when` before today, not done, go under Suggestions. |
| `gated` | The same set as `carry`, with no overdue label (Things [U]). A to-do with `when` after today is also hidden from its own list and from All; it shows only in Upcoming until its day. |

Other rules:
- In every model except `gated`, a future-dated to-do shows in its list.
- An undated to-do (`when` null) always shows in its list and in All (#11).
- An undated to-do is never in Today, except in `fresh` once picked (`inToday`).

**States.**
- **Loading:** no headline until `store.query('todo:')` answers (TD-SET-05).
- **Empty, or all done:** TD-SET-05.
- **One item, many items.** A Today list of 25 or more stops being used (Things, GTD forum [R]).
  No cap is built; the count shows in the header ("12") [U].
- **Day changes while open:** at local midnight, and on `visibilitychange` back to visible, the
  page re-renders Today for the new date. Nothing is written.
- **Offline:** reads the local store as usual. Offline is not a failure (DP-51).
- **Model switched:** the view changes at once, and no `todo:` record changes.

**Interactions.**
- The model is chosen in TD-SET-01, under "Today": "Unfinished Items".
- `fresh`:
  - "Add to Today" on a suggestion writes `inToday` = today.
  - The long-press menu (TD-GEST-03) has "Remove from Today", which writes `inToday: null`.
- Other models: a to-do comes into Today by setting `when` (TD-ITEM-05, TD-ADD).
- The rows are re-ordered by `order` with drag (TD-GEST-02).
- Motion: rows entering Today on a re-render fade in over 150 ms [U]; instant under
  `prefers-reduced-motion: reduce`.

**Words.** "Today" · "Sat 31 Oct" · "Suggestions" · "Add to Today" · "Remove from Today".

Setting words (TD-SET-01): "Unfinished Items" · "Carry Over" (`carry`) · "Keep as Overdue"
(`stay`) · "Start Fresh" (`fresh`) · "Show on Their Day" (`gated`) [U].

**Data.**
- Reads `todo:` `when`, `deadline`, `done`, `completedAt`, `someday`, `inToday`, `list`, `order`.
- Reads `settings:self.todayModel`.
- Writes only `inToday` (`fresh`). The day change writes nothing in any model.

**Needs.** Page alone.

**Edge cases.**
- **#42:** no model removes a to-do; `fresh` moves it to Suggestions, never away.
- **#43 and DP-23:** a carried to-do ticked on a later day gets `completedAt` = the tick time,
  because `when` is never rewritten to fake a day.
- **#44:** local midnight only; a day-end hour is not mapped.
- **#46:** day strings, no UTC parse.
- **#11:** undated to-dos always show in their list.
- **P-new-28:** a to-do done on an earlier day is never in Today, in any model.
- **P-new-27:** opening the page makes no writes, so startup does not grow with old items.
- **group-a leave reason 6:** there is no roll-over job to forget or run twice.

**Tests.**
- Given `carry` and a to-do with `when` 2026-10-30, not done, when the page opens on 2026-10-31,
  then:
  - it is in Today;
  - the page has no "Overdue" text;
  - `store.get` still gives `when` 2026-10-30.
- Given `stay` and the same to-do, when the page opens on 2026-10-31, then it is under
  "Overdue".
- Given `fresh` and a to-do with `inToday` 2026-10-30, not done, when the page opens on
  2026-10-31, then:
  - it is not among Today's rows and is under "Suggestions";
  - tapping "Add to Today" writes `inToday` 2026-10-31.
- Given `gated` and a to-do in list `home` with `when` 2026-11-02:
  - on 2026-10-31 it is not in the Home list's rows, and it is in Upcoming;
  - on 2026-11-02 it is in Today and in Home.
- Given any model and a to-do with `done: true` and `completedAt` 2026-10-30, when the page
  opens on 2026-10-31, then it is not in Today (P-new-28).
- Given `carry` and an unfinished to-do with `when` 2026-10-28, when it is ticked on 2026-10-31
  at 09:00, then `completedAt` is on 2026-10-31 (#43).
- Given 300 `todo:` records, 290 of them done, when the page opens, then `store.set`,
  `store.update` and `store.delete` are each called 0 times.
- Given `stay`, when the person switches to `carry`, then no `todo:` record changes; only
  `settings:self.todayModel` is written.
- Given the page open at 23:59:30 on 2026-10-31, when the clock passes 00:00, then the header
  reads "Sun 1 Nov" with no reload.
- Given a to-do with `when` 2026-10-31 and the phone's zone changed from America/New_York to
  America/Los_Angeles, when Today renders on 2026-10-31, then the to-do is in Today (#46).

**Evidence.**
- group-a 1 (model table), 2 (Microsoft To Do [C]; jmbwell "mountain of shame" [C]; major505
  "all that red" [C]), 3 (Things [C]), 4 (Todoist "snowballing" [R]), 5 (Superlist [C]),
  6 (Reminders [C]), 8f (MacIver [C]), 9 (fresh start loved, 6 sources), 10 (leave reasons 1, 6, 8).
- look-group-c 4.2 (Tweek roll-over [C]); group-d P2 and #42 to #46.
- Screenshots: `shots/things_iphone_2.png`, `shots/mstodo-1.png`, `shots/anydo_2.jpg`.

---

### TD-DAY-02 Parts of day

**Tag:** on request. Several loved apps have it, but not every app, and it is not a checklist
item or a leave reason.

**Variations:**
- **Apple Reminders Today:** small grey section headings "Morning, Afternoon, Tonight". Each
  section ends with a dotted placeholder row to add into it [C, look-group-a 3.2,
  `reminders_iphone_1`].
- **Tiimo:** collapsible tinted chips "ANYTIME (1)", "MORNING (2)", "DAY (2)", "EVENING (1)",
  each with a line icon, a count and a chevron [C, look-group-c 3.2].
- **Things:** one "This Evening" section with a blue crescent moon, at the bottom of Today [C,
  look-group-a 1.2]. A GTD user moves items into it every morning [R, group-a 3].

**Default variation:** `dayParts: false` (off). When on: Anytime, Morning, Afternoon, Evening, in
that order. That is Tiimo's order, with Reminders' three parts and Things' word "Evening".

**What it is.** Today's rows split into parts of the day, so a to-do can be planned for the
evening without a clock time.

**Anatomy.**
- Section heading: a glyph (Anytime ◷, Morning ☀︎, Afternoon ◐, Evening ☾) [U], the label
  13 pt semibold `--ink-2`, the count of open to-dos 13 pt `--ink-2`, and a collapse chevron at
  the right (Tiimo).
- A hairline `--line` under each heading (Things).
- With `add: row`, each section ends in the tap-to-add row (TD-ADD-04).
- An empty section shows only its heading (Midas Reminders Next 7 Days precedent, PRODUCT.md
  2026-10-11).

**Which section a to-do goes in.**
1. `part` set: that section.
2. `part` null and `time` set: by time. Morning before 12:00, Afternoon 12:00 to 16:59, Evening
   17:00 and later [U: Reminders places by time, but its boundaries are not in the research].
3. Neither: Anytime.

**States.**
- Off: no headings. `part` values are kept and not shown.
- On: four sections.
- A collapsed section shows its heading and count only. It is never collapsed by default.
  Collapse is not saved across opens: there is no field for it, and localStorage is not allowed.

**Interactions.**
- Tap a heading: collapse or expand, 200 ms [U]; instant under reduced motion.
- Drag a row into another section (TD-GEST-02): writes `part` for that section and keeps `time`.
  An explicit `part` wins over the time rule for display [U].
- Add inside a section: the new to-do gets that section's `part` (null for Anytime) and
  `when` = today.

**Words.** "Anytime" · "Morning" · "Afternoon" · "Evening". Setting (TD-SET-01): "Parts of Day".

**Data.**
- Reads `todo:` `part`, `time`, `when`, `order`.
- Reads `settings:self.dayParts`.
- Writes `part` (drag, add).

**Needs.** Page alone.

**Edge cases.**
- **L3:** turning the setting off or on changes no `todo:` record.
- **#46:** `part` and `time` are wall-clock, so a DST change does not move a to-do between
  sections.
- **P-new-17:** insert between two rows works inside a section (TD-ADD-06).

**Tests.**
- Given `dayParts: true` and a to-do with `time` 18:30 and `part` null, then it is under
  "Evening".
- Given `dayParts: true` and a to-do with `part` "morning" and `time` 18:30, then it is under
  "Morning".
- Given `dayParts: false`, then the page has no "Morning", "Afternoon", "Evening" or "Anytime"
  text.
- Given a to-do under "Anytime", when it is dragged into "Evening", then its record has `part`
  "evening" and its `time` unchanged.
- Given `dayParts` turned off and then on again, then every `todo:` record is unchanged.
- Given "Add" tapped in "Afternoon" on 2026-10-31, when "Call bank" is entered, then the new
  record has `part` "afternoon" and `when` 2026-10-31.

**Evidence.**
- look-group-a 3.2 and 3.6 (Reminders sections; the signature idea), 1.2 (This Evening).
- look-group-c 3.2 (Tiimo chips); group-a 3 (GTD forum quote); LOOK-ANALYSIS 1.6 ("Time buckets
  as sections").
- Screenshots: `shots/reminders_iphone_1.png`, `shots/tiimo_3_crop.jpg`,
  `shots/things_iphone_2.png`.

---

### TD-DAY-03 Upcoming by day

**Tag:** core. Every loved app has a later view: Things Upcoming, Todoist Upcoming, Reminders
Scheduled, Any.do buckets, Tweek week. It is one of the TD-NAV-02 smart lists.

**Variations:**
- **Things Upcoming:** each day starts with a large bold day number ("10"), a grey label
  ("Tomorrow", "Thursday") and a hairline. A repeating to-do shows ↻ in place of the checkbox.
  Drag a to-do to another day to reschedule it [C, look-group-a 1.2, `things_iphone_3`].
- **Any.do:** big bold buckets "Today", "Tomorrow", "Upcoming" (and Someday), each with a grey
  "+" that adds into that bucket [C, look-group-c 2.2].
- **Todoist Upcoming:** "Only tasks with a date appear in Today and Upcoming" [C, group-a 4].
- **Apple Reminders Scheduled:** reminders "grouped by date" [C, group-a 6].
- **Tweek:** days stacked vertically. Day header "27 Jan" in bold, "Mon" in light grey at the
  right; today's header and rule are blue [C, look-group-c 4.2].
- **Midas Reminders "Next 7 Days"** (founder-approved, PRODUCT.md 2026-10-11): day headers
  "Tomorrow 12 Oct"; an empty day shows only its header; a reminder added in a day is due that
  day.

**Default variation:** Things day blocks for the next 7 days (tomorrow to 7 days out), each day
shown even when empty (header only, as Midas Next 7 Days). Then later to-dos grouped by month
[U]. Today is not repeated in Upcoming [U].

**What it is.** Every dated to-do after today, in day order, so the person sees what is coming and
can move it.

**Anatomy.**
- Day block: the day number 28 pt bold `--ink`, then the label 15 pt `--ink-2` ("Tomorrow",
  then weekday names), then the month 13 pt `--ink-2` at the right ("Nov") [U], then a hairline
  `--line`.
- Rows (TD-ROW) under it. A repeating to-do shows ↻ in its meta line (Things).
- A to-do with `deadline` and no `when` shows on its deadline day [U].
- After day 7: month headings ("December") 20 pt bold, with their rows by date and the date in
  each row's meta line [U].
- With `add: row`, each day ends in a tap-to-add row (Any.do "+", TD-ADD-04).

**States.**
- Nothing upcoming: TD-SET-05 ("Nothing Upcoming").
- Day with nothing: header only.
- `someday: true`: never in Upcoming (records.md).
- Done: a to-do ticked here follows `doneGoes` for the session and then leaves Upcoming.

**Interactions.**
- Tap a row: TD-ITEM-01.
- Drag a row onto another day's header or rows (TD-GEST-02): writes `when` for that day and keeps
  `time`. Lift and drop 200 ms ease-out [U]; instant under reduced motion.
- Tap a day's add row: a new to-do with `when` that day.
- Swipe actions follow TD-GEST-01 ("tomorrow" sets `when` to the day after the row's current
  `when` [U]).

**Words.** "Upcoming" · "Tomorrow" · weekday names ("Monday") · month names ("November") ·
"Nothing Upcoming".

**Data.**
- Reads `todo:` `when`, `deadline`, `done`, `someday`, `repeat`, `time`, `order`.
- Writes `when` (drag) and new `todo:` records (add).

**Needs.** Page alone.

**Edge cases.**
- **#46:** headers built from the day string, never from `new Date('YYYY-MM-DD')`, which parses
  as UTC and shows the day before west of Greenwich [U implementation note].
- **#48:** a repeat exists only as its next open copy (records.md section 1), so it shows once and
  a missed repeat never duplicates.
- **P-new-7:** several to-dos, repeating or not, can be moved one by one by drag. The bulk move is
  TD-DAY-04.

**Tests.**
- Given today 2026-10-31 and a to-do with `when` 2026-11-01, then the first day block reads
  "Tomorrow" and holds it.
- Given no to-do on 2026-11-03, then Upcoming shows that day's header and no rows under it.
- Given a to-do with `someday: true` and `when` null, then it is not in Upcoming.
- Given the to-do on 2026-11-01, when it is dragged onto Wednesday's block, then `when` is
  2026-11-04 and `time` is unchanged.
- Given the phone in America/Los_Angeles and a to-do with `when` 2026-11-01, then it renders
  under 1 Nov, not 31 Oct.
- Given a daily repeating to-do ticked on 2026-11-01, then Upcoming shows exactly one open copy of
  it, on 2026-11-02.

**Evidence.**
- look-group-a 1.2 (Things Upcoming [C]); look-group-c 2.2 (Any.do [C]), 4.2 (Tweek [C]).
- group-a 4 and 6; PRODUCT.md 2026-10-11 (Next 7 Days); group-a 5 (Superlist week view asked
  for [R]).
- Screenshots: `shots/anydo_2.jpg`, `shots/tweek_1.jpg`; Things Upcoming is `things_iphone_3`
  (look-group-a; not in `shots/`).

---

### TD-DAY-04 Overdue without shame

**Tag:** core. Reasons:
- group-a leave reason 1, 5 sources: "mountain of shame" (jmbwell), "all that red… Today I just
  carry a small notebook and a pen" (major505), the "UGH field" (MacIver), an indie developer's
  "guilt", Todoist's own "avalanche of overdue tasks".
- Checklist #42.

**Variations:**
- **Todoist:** an Overdue section in Today. Overdue dates show red ("Yesterday", "Oct 2") [C].
  A Reschedule button moves every overdue task to a new date at once [R]. On iOS the Overdue
  section can look empty while it holds tasks [R].
- **Apple Reminders:** overdue in Today, with the time and repeat in red [C].
- **Microsoft To Do:** no overdue pile in My Day (the reset), credited as the cure [C]. It still
  shows "clean up overdue tasks" on opening [R].
- **No overdue label at all:** the indie developer's app [R, title only].
- **Rescheduling with no guilt by hand:** "I reschedule all my tasks I didn't get done, with
  absolutely zero guilt!" [R, r/todoist via snippet].

**Default variation:**
- `stay` only: one "Overdue" group at the top of Today, never collapsed, with one "Move to Today"
  action. There is no red heading, no badge, and no count on the home tiles or app.
- Overdue dates in the meta line use TD-ROW-03's past colour when `dateColors` is on. This block
  adds no colour of its own.
- `carry` and `gated` have no overdue group (the to-do is simply in Today).
- `fresh` uses Suggestions (TD-DAY-01).
- A passed `deadline` puts the to-do in Today in every model (TD-DAY-01) and in the Overdue group
  under `stay`.

**What it is.** How to-dos whose day has passed show, so they can be dealt with in one tap and do
not pile up as a red wall.

**Anatomy.**
- Group heading "Overdue" 13 pt semibold `--ink-2` (not red), the count in `--ink-2`, and at the
  right "Move to Today" 15 pt `--accent`.
- Rows are TD-ROW; the meta line shows the planned day ("Yesterday", "Wed 28 Oct").
- No row tint and no icon.

**States.**
- None overdue: no group.
- One or more: the group with every overdue to-do. It never collapses on its own; it collapses
  only if the person taps the heading, and the count stays visible (Todoist iOS bug [R]).
- After "Move to Today": the group is gone; the to-dos are among Today's rows.

**Interactions.**
- "Move to Today": writes `when` = today on every to-do in the group, one `store.update` each.
  Then a toast "Moved 4" with "Undo" (TD-DONE-06). Undo writes back each old `when`.
- Per to-do: swipe "tomorrow" (TD-GEST-01), the long-press menu, or the card (TD-ITEM-05).
- The page never asks why a to-do was not done and never prompts on open (L6; Microsoft To Do's
  clean-up prompt [R]).

**Words.** "Overdue" · "Move to Today" · "Moved 4" · "Undo" · "Yesterday" · "Wed 28 Oct".
Variation word "Earlier" in place of "Overdue" [U].

**Data.**
- Reads `todo:` `when`, `deadline`, `done`.
- Writes `when`. "Move to Today" does not change `deadline`.

**Needs.** Page alone.

**Edge cases.**
- **#42 and DP-22:** a one-tap move, nothing dropped.
- **#43:** `completedAt` is the real tick time.
- **P-new-7:** repeating copies move with the rest, since each is a plain record.
- **#46.**
- **P-new-28:** done to-dos are never in the group.
- **L6:** no pop-up over the list.

**Tests.**
- Given `stay` and 3 unfinished to-dos with `when` before today, then "Overdue" shows with 3 rows.
- When "Move to Today" is tapped, then:
  - all 3 have `when` = today;
  - the page shows "Moved 3".
- Given that toast, when "Undo" is tapped, then each `when` is back to its old value.
- Given `stay` and an Overdue group, then the heading's computed colour is not #FF3B30 and no
  element in the page shows the overdue count in red.
- Given `stay` and 2 overdue to-dos, when the page opens, then the group is expanded.
- Given `carry` and the same to-dos, then the page has no "Overdue" text.
- Given `stay` and a to-do with `when` null and `deadline` 2026-10-30, on 2026-10-31, then it is
  in the Overdue group.
- When "Move to Today" runs on that to-do, then `when` is 2026-10-31 and `deadline` stays
  2026-10-30.

**Evidence.**
- group-a 2 (jmbwell, major505 [C]), 4 (Todoist [C/R]), 8f (MacIver [C]), 10 (leave reason 1).
- look-group-b 1.2 (Todoist coloured dates [C]), 3.2 (Microsoft To Do on opening [R]);
  look-group-a 3.2 (Reminders red overdue [C]).
- Screenshot: `shots/todoist-macstories-liquidglass-2025.jpg`.

