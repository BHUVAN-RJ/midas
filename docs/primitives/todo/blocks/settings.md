# Make it yours, presets, first open, import, empty states (TD-SET)

This block covers the settings panel where every variation is changed live from the page, the
presets, the first open, the import from Apple Reminders, and what empty and all-done screens say.
Five patterns.

Sources:
- midas-intel `docs/research/todo/`:
  - `LOOK-ANALYSIS.md` sections 1 to 4;
  - `look-group-a.md`, `look-group-b.md`, `look-group-c.md` (the apps each preset is named
    after);
  - `look-group-d.md` 1.4 and Part 2 (P-new-31 to 36), and its L1 to L6;
  - `group-d.md` #17.
- `docs/PRODUCT.md` (2026-10-10, import).
- The built import, `shell/Midas/AppleRemindersImport.swift`.
- The Reminders Sidekick's import words, `sidekicks/reminders/index.html`.

Template: `docs/primitives/daily-planner/README.md`. Records: `../records.md` section 3 (one
`settings:self` record). Theme tokens from `../recipe.md` (not yet written). Values marked [U] are
proposals not found in the research. Written 2026-10-31.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| TD-SET-01 | Make it yours panel | core | Every `settings:self` field on one sheet, applied live; the basic value of each field (records.md 3) |
| TD-SET-02 | Presets | core | Basic (every field at its first value); look-and-feel only, "Reset to Basic" for everything |
| TD-SET-03 | First open | core | Opens straight onto an empty Today; nothing imported or seeded; no tutorial (no `settings:self` field) |
| TD-SET-04 | Import from Apple Reminders | core | Midas's built import (shell sheet, `import:` parts), mapped to `todo:` and `list:` (no `settings:self` field) |
| TD-SET-05 | Empty and all-done states | core | A short headline and one action (WRITING rule 7); "All Done" kept apart from "nothing here" (no `settings:self` field) |

Settings rows are plain grouped lists: `--bg` background, `--surface` cards with 16 pt radius,
44 pt rows, labels 17 pt `--ink`, values 17 pt `--ink-2`, section headers 13 pt `--ink-2`
uppercase (as the daily planner, DP-SET).

---

### TD-SET-01 Make it yours panel

**Tag:** core. Reasons:
- LOOK-ANALYSIS love 3 ("Make it mine", about 12 quotes).
- Leave reason 5: delight taken away or paywalled (Clear's themes, Tiimo's emoji).
- L3: no layout or gesture change without the person choosing it.
- L4: text size can change.
- README item 5: every variation is a setting, changed from the page without a rebuild.

**Variations:**
- **TickTick:** 40+ themes [C].
- **Todoist:** 4 free and 4 Pro themes, Auto Dark Mode, Sync Theme [C].
- **Microsoft To Do:** per-list solid colour or photo, "Color | Photo" tabs and 7 dots [C].
- **Tweek:** about 20 swatches plus a custom HSV picker and hex field [C].
- **Clear:** "nearly 400 Themes", "100s of fonts, sounds and icons" [C].
- **Tiimo:** light, dark or system; a swatch grid; font Default or OpenDyslexic [R].
- **Todoist Display sheet:** "Completed Tasks" toggle, Grouping, Sorting [C].
- **Todoist swipe settings:** left and right each Complete, Schedule, Reminders or Delete [C].

**Default variation:** one sheet holding every `settings:self` field (records.md section 3), each
at its basic value. Every change applies at once to the page behind the sheet. There is no Save.
Nothing is paid.

**What it is.** The one place where the person changes how the list looks and behaves, while
watching the list change.

**Anatomy.**
- **Entry:** "⋯" at the top right of every list → "Make It Yours" [U].
- **Sheet:** half height [U], 16 pt top radius, scrolls. The list stays visible above it so each
  change shows live.
- **Title** "Make It Yours" 17 pt semibold, centred; "✕" at right.
- **First section:** the preset tiles (TD-SET-02).
- **Then one section per block.** Every row maps to one field:

| Section | Row label | Control | Values shown (field value) | Field |
|---|---|---|---|---|
| Look | Style | tiles | Paper (`paper`) · Notebook · Soft · Wallpaper · Heat | `look` |
| Look | Appearance | segmented | Auto · Light · Dark | `theme` |
| Look | Accent | 8 swatches plus a custom picker (`<input type="color">` [U WKWebView support]) | hex | `accent` |
| Look | Text Size | segmented | Small (`s`) · Medium (`m`) · Large (`l`) · Extra Large (`xl`) | `textSize` |
| Look | Density | segmented | Comfortable (`comfy`) · Compact | `density` |
| Look | Font | tiles "Aa" | System · Serif · Rounded · Mono | `font` |
| Rows | Checkbox | tiles | Circle · Square · At End (`end`) · None | `checkbox` |
| Rows | Details Under Title | switch | | `showMeta` |
| Rows | Color Dates | switch | | `dateColors` |
| Done | Sound | segmented | Ding · Chimes · Pop · Off | `tickSound` |
| Done | Haptic | switch | | `haptic` |
| Done | Celebrate | segmented | All Done (`allDone`) · Confetti · Off | `celebrate` |
| Done | Done Items | list | Stay in Place (`stay`) · Move to Bottom (`sink`) · Hide · Move to Logbook (`logbook`) | `doneGoes` |
| Adding | Add Button | list | Floating (`fab`) · Draggable (`dragFab`) · Bar at Bottom (`bar`) · Row in Each Section (`row`) | `add` |
| Adding | Read Dates in Titles | switch | | `parse` |
| Swipes | Swipe Right | list | Complete · Tomorrow · Delete · None | `swipeRight` |
| Swipes | Swipe Left | list | Delete · Tomorrow · Complete · None | `swipeLeft` |
| Home | Home | segmented | List · Tiles · Tabs | `home` |
| Today | Unfinished Items | list | Carry Over (`carry`) · Keep as Overdue (`stay`) · Start Fresh (`fresh`) · Show on Their Day (`gated`) | `todayModel` |
| Today | Parts of Day | switch | | `dayParts` |

- **Last row:** "Reset to Basic" 17 pt `--accent` (TD-SET-02).
- **Tapping a Sound value plays that sound once,** so the choice can be heard [U].
- **Haptic row:** shown only where the hidden-switch trick works (TD-DONE-03, LOOK-ANALYSIS 5).
  Where it doesn't, the row is hidden and the field is kept.

**States.**
- Every field at basic.
- Some changed: no preset tile is marked unless all of its fields match (TD-SET-02).
- A write refused: the control springs back to the stored value and "Can't Save" shows under the
  row [U].
- Reloaded: values from the record.
- Record missing or missing a field: the basic value for that field.

**Interactions.**
- Each control: `store.update('settings:self', { <field>: <value> })` and an immediate re-render
  of the page behind.
- The accent picker writes 300 ms after the last change [U].
- The sheet closes with "✕", by swiping down, or by tapping the list above.
- Under reduced motion, the change is instant with no transition.

**Rules between fields.**
- `checkbox: none` with neither swipe set to `complete` would leave no visible way to tick (Clear's
  undiscoverable gestures, leave reason 6). So choosing `none` then also sets `swipeRight` to
  `complete`, shown in a toast "Swipe Right: Complete" [U].
- The long-press menu always has "Complete" (TD-GEST-03).

**Words.** "Make It Yours" · section headers "Look" · "Rows" · "Done" · "Adding" · "Swipes" ·
"Home" · "Today" · every row label and value above · "Reset to Basic" · "Can't Save" ·
"Swipe Right: Complete".

**Data.**
- Reads and writes `settings:self`, all 20 fields of records.md section 3.
- Writes are merge patches, so fields the page does not know are kept (#9).
- The page never writes `settings:self` on open; a field is written only when changed [U].

**Needs.** Page alone. `<input type="color">` in the shell's WKWebView is not checked [U]; the
swatches work without it.

**Edge cases.**
- **L3:** a field changes only from this panel or a preset the person taps.
- **L4 and P-new-29:** "Extra Large" wraps titles and never cuts them (TD-ROW-05).
- **L5:** each look has its own dark tokens (TD-LOOK-02).
- **L6:** the panel opens only when asked.
- **#9:** unknown fields are kept.
- **Leave reason 5:** no setting is locked.

**Tests.**
- For each of the 20 fields: given the panel open, when its control is set to a non-basic value,
  then `store.update` is called once with exactly `{ <field>: <value> }`, and the page behind
  shows the change before the sheet closes. For example, Checkbox "Square" gives a row checkbox
  whose computed `border-radius` is not 50%.
- Given `settings:self` absent, when the page opens, then every control shows its basic value and
  `store.set`/`store.update` were not called.
- Given `settings:self` `{ look: "notebook", foo: 1 }`, when Text Size is set to Large, then the
  record is `{ look: "notebook", foo: 1, textSize: "l" }`.
- Given `store.update` rejects, when Density is set to Compact, then the control shows Comfortable
  and "Can't Save" shows.
- Given `swipeRight: "delete"` and `swipeLeft: "delete"`, when Checkbox "None" is chosen, then
  `swipeRight` becomes "complete" and "Swipe Right: Complete" shows.
- Given Text Size Extra Large and a 120-character title, then the row's text has no
  `text-overflow: ellipsis` cut and its full text is in the row.

**Evidence.**
- LOOK-ANALYSIS 1.7 (themes, paywalls, text size), 2 (love 3), 3 (leave reasons 1, 5, 6), 4 (L3
  to L6).
- look-group-b 1.2 (Todoist themes, swipes, Display [C]), 3.2 (Microsoft To Do theme picker [C]);
  look-group-c 3.2 (Tiimo [R]), 4.2 (Tweek colour picker [C]); look-group-a 2.2 (Clear themes [C]).
- Screenshots: `shots/mstodo-1.png`, `shots/todoist-macstories-liquidglass-2025.jpg`.

---

### TD-SET-02 Presets

**Tag:** core. Reasons:
- LOOK-ANALYSIS 7.1 names the five look families to prototype.
- Love 6: a distinct identity (Tiimo serif and pastel, Tweek highlighter, Clear heat map).
- README item 3: the basic preset is the default.

**Variations:** one preset per look family in LOOK-ANALYSIS 1.1, each named after its look and
taking its look-and-feel values from the app the look comes from:
- **Paper:** white paper, whitespace, colour only for meaning. Things, Todoist, Google Tasks;
  "clean" is the top praise word.
- **Notebook:** ruled notebook paper, a hairline under each row, highlighter pills, tick at the
  row's end. Tweek, 5 quotes.
- **Soft:** soft pastel cards, a serif date heading, an emoji badge, a black done disc, confetti.
  Tiimo, 4 quotes.
- **Wallpaper:** a per-list solid colour or photo with white card rows; the "ding". Microsoft To
  Do, 3 quotes.
- **Heat:** full-bleed heat-map rows, no checkbox, rising chimes, one large-type line. Clear;
  loved for feel.
- **Basic:** every field at its first value (records.md 3).

**Default variation:** Basic.

**What it is.** One tap that sets a coherent look, which the person can then change field by
field.

**What a preset changes.** A preset sets only the look-and-feel fields (`look`, `theme`, `accent`,
`textSize`, `density`, `font`, `checkbox`, `showMeta`, `dateColors`, `tickSound`, `haptic`,
`celebrate`). It never changes `doneGoes`, `add`, `parse`, `swipeRight`, `swipeLeft`, `home`,
`todayModel` or `dayParts`: gestures, adding, where done items go and the today rule stay as the
person set them [U, from L3 and leave reason 1: "Redesigns that move things and break muscle
memory"]. "Reset to Basic" sets all 20 fields.

| Field | Basic | Paper | Notebook | Soft | Wallpaper | Heat |
|---|---|---|---|---|---|---|
| `look` | paper | paper | notebook | soft | wallpaper | heat |
| `theme` | auto | auto | auto | auto | auto | auto [U] |
| `accent` | #2F6FEB | #5B9AFF (Things Magic Plus [R]) | #2F6FEB [U] (Tweek today blue, no hex sampled) | #000000 [U] (Tiimo black done disc) | #2F6FEB [U] | #D8131D (Clear header [R]) |
| `textSize` | m | m | m | m | m | l (Clear "large-type line" [C]) |
| `density` | comfy | comfy | compact [U] | comfy | comfy | comfy [U] |
| `font` | system | system (SF Pro [C]) | system [U] (Tweek grotesk sans) | serif (Tiimo display serif [C]) | system | system [U] |
| `checkbox` | circle | square (Things [C]) | end (Tweek [C]) | circle (Tiimo [C]) | circle (Microsoft To Do [C]) | none (Clear [C]) |
| `showMeta` | true | true (Things [C]) | false [U] | true | true (Microsoft To Do sub-line [C]) | false (Clear [C]) |
| `dateColors` | true | true (Things red deadline [C]) | false [U] | false [U] | true [U] | false [U] |
| `tickSound` | ding | off (no Things sound documented [U]) | off [U] | pop [U] | ding (Wunderlist ding [R]) | chimes (Clear [C]) |
| `haptic` | true | true (Things Taptic [C]) | true [U] | true (Tiimo [C]) | true [U] | true (Clear [C]) |
| `celebrate` | allDone | off [U] | off [U] | confetti (Tiimo [C]) | off [U] | off [U] |

**Anatomy.**
- In TD-SET-01's first section: a horizontal row of 6 tiles, each 96 × 120 pt [U].
- Each tile is a small live drawing of three rows in that preset's look, with the name under it,
  13 pt `--ink`.
- The selected tile (all its fields match the record) has a 2 pt `--accent` ring.

**States.**
- One preset matches: its tile ringed.
- None matches (a field changed after a preset): no tile ringed.
- Heat chosen while `swipeRight` and `swipeLeft` are both not `complete`: TD-SET-01's rule sets
  `swipeRight` to `complete`.

**Interactions.**
- Tap a tile: one `store.update` with its 12 look-and-feel values; the page re-renders at once.
  A toast with the preset's name and "Undo" [U]; Undo writes the previous 12 values.
- "Reset to Basic": one `store.update` with all 20 basic values; toast "Reset to Basic" with
  "Undo". Undo writes the previous 20 values. There is no confirmation (WRITING rule 8: prefer
  undo).

**Words.** "Basic" · "Paper" · "Notebook" · "Soft" · "Wallpaper" · "Heat" · "Reset to Basic" ·
"Undo".

**Data.** `settings:self` (records.md 3).

**Needs.** Page alone. The Wallpaper photo is a per-list `wallpaper` on `list:` (records.md 2),
set in TD-LOOK; the preset sets only `look`.

**Edge cases.**
- **L3:** behaviour fields untouched.
- **Leave reason 5:** no preset is locked.
- **Leave reason 6:** a way to tick always remains.
- **L5:** each preset's dark look comes from TD-LOOK-02, not an inversion.

**Tests.**
- Given Basic and `swipeRight: "tomorrow"`, `todayModel: "stay"`, when Heat is tapped, then:
  - `look` is "heat", `checkbox` is "none" and `tickSound` is "chimes";
  - `todayModel` is still "stay";
  - `swipeRight` is "complete", because neither swipe completed;
  - the Heat tile is ringed.
- Given Heat, when Font is changed to Mono, then no tile is ringed.
- Given every field changed, when "Reset to Basic" is tapped, then all 20 fields equal the Basic
  column and records.md 3's basic values. When "Undo" is tapped, then all 20 are back.
- Given Soft, then the date heading's computed `font-family` is a serif family.
- Given Paper, when a preset tile is tapped, then `doneGoes`, `add`, `parse`, `home` and
  `dayParts` are unchanged.

**Evidence.**
- LOOK-ANALYSIS 1.1, 1.2, 1.3, 2, 3, 7.1.
- look-group-a 1.4 (Things hex [R]), 2.2 and 2.3 (Clear hex [R], chimes [C]); look-group-b 3.2
  (Microsoft To Do [C/R]); look-group-c 3.2 (Tiimo [C]), 4.2 (Tweek [C]).
- Screenshots: `shots/things_iphone_2.png`, `shots/tweek_1.jpg`, `shots/tiimo_3_crop.jpg`,
  `shots/mstodo-1.png`, `shots/clear_iphone_1.png`.

---

### TD-SET-03 First open

**Tag:** core. Reasons:
- P-new-31: empty and fast, or asks before bringing anything in.
- P-new-32: teaches the core gestures in place.
- Leave reason 4: tutorials and achievements over the list.
- L6: no pop-ups over the list.

**Variations:**
- **Any.do:** "populated with hundreds of items… no easy way to delete them all and just start
  from a blank slate… I'm out" (1★) [R].
- **Todoist:** "a motivational quote followed by a spinning circle… I want to see my tasks"
  (1★) [R].
- **TickTick:** an unskippable intro [R, reminders/group-a].
- **Apple Reminders:** "I went in there for the first time and I saw it was empty… I thought it
  was boring at first" (5★) [R].
- **Things:** "Tutorial on app is atrocious—assumes you already know how to use the app" (1★) [R].
- **Clear (original):** a game-like walkthrough of the controls [C]. Its gestures were judged not
  accessible by a blind user [R].

**Default variation:**
- Opens straight onto Today with the empty state (TD-SET-05).
- No sample to-dos, no import, no intro, no hint text.
- Gestures are taught by never being the only way: every swipe action is also a visible control
  (the checkbox) or a long-press menu item (TD-GEST-03), and every action in the card.
- WRITING rule 4 ("Never explain the interface; fix the interface") is why there is no hint text.
  P-new-32 asks for in-place teaching; this conflict is the founder's to settle.
- Import is offered only in "⋯" (TD-SET-04).

**What it is.** What the person sees the first time the Sidekick opens.

**Anatomy.**
- Today (TD-DAY-01) with TD-SET-05's empty state centred.
- The add control from `settings:self.add` (basic: the floating "+", TD-ADD-01).
- Nothing over the list.

**States.**
- First open: no `todo:`, no `list:`, no `settings:self`.
- Loading: no headline until the store answers; grey row placeholders after 400 ms (DP-SET-03).
- Store failed: TD-SET-05 "Can't Load To-Dos".

**Interactions.**
- The empty state's button and the add control open TD-ADD.
- "⋯" has "Import Apple Reminders" and "Make It Yours".
- Inbox needs no record: `list: "inbox"` is the default (records.md 1).

**Words.** TD-SET-05's "No To-Dos" · "New To-Do". "⋯" menu: "Import Apple Reminders" ·
"Make It Yours".

**Data.** Reads `todo:`, `list:`, `settings:self`. Writes nothing on open.

**Needs.** Page alone.

**Edge cases.**
- **P-new-31:** nothing is brought in unasked.
- **P-new-32:** gestures always have a visible twin.
- **L6:** no pop-ups.
- **#17:** empty says empty, never mixed up with failed.
- **P-new-27:** first paint does not wait on any write.

**Tests.**
- Given no records, when the page opens, then:
  - "No To-Dos" and "New To-Do" show;
  - `store.set`, `store.update` and `store.delete` were called 0 times;
  - no `request:` record exists.
- Given no records, then the page has no text containing "Swipe" or "Tap", and no element with a
  higher z-index than the list except the add control.
- Given a to-do with `swipeRight: "complete"` in settings, when the to-do's long-press menu opens,
  then it lists "Complete".
- Given `store.query` still pending, then "No To-Dos" is not in the page.

**Evidence.**
- look-group-d 1.4 and Part 2 P-new-31, 32 (Any.do, Todoist, Things, Reminders [R]).
- look-group-a 2.3 (Clear walkthrough [C]); LOOK-ANALYSIS 3 (leave reasons 4, 6), 4 (L6).
- WRITING.md rules 4 and 7.
- No screenshot.

---

### TD-SET-04 Import from Apple Reminders

**Tag:** core. Reasons:
- Midas already ships it (PRODUCT.md 2026-10-10: "must ship before the Reminders Sidekick goes to
  others").
- P-new-33 to P-new-36: what other importers lose.
- Checklist #1: nothing written is lost.

**Variations:**
- **Midas, built 2026-10-10, not yet tried on a phone** (PRODUCT.md):
  - The Sidekick writes `request:<id>` `{ kind: "import.apple-reminders" }`.
  - The shell shows its own sheet ("Import Apple Reminders", "Continue" / "Not Now") and the iOS
    Reminders permission.
  - It reads EventKit and writes `import:<id>:<nnnn>` parts under 64 KB each, then sets the
    request's `status` to `done`, `denied`, `cancelled` or `failed`.
  - Matched on Apple's `externalId`; the phone's version wins; Midas-only fields stay; nothing is
    removed. The page deletes the parts after bringing them in.
- **Things importer** [C, article 1477596]:
  - Lists become projects; groups are not imported.
  - Subtasks are flattened; due dates become start dates.
  - Repeats arrive without their schedule.
  - URLs, flags, priorities, location alerts and images are not imported; tags carry over.
  - Completed items come only on request. Copy-only.
- **Things "Reminders Inbox":** deletes each original and skips location, attachment, subtask and
  recurring reminders [C].
- **TickTick:** one-way; can delete the originals [R].
- **A user wants a yes/no on tags** [R, P-new-36].

**Default variation:**
- Midas's built import, with no shell change.
- The to-do page maps the export into `todo:` and `list:` records as below, and shows the result
  with the Reminders Sidekick's words.
- Completed reminders are imported as done.
- Copy-only: nothing in Apple Reminders changes, the shell only reads.

**What it is.** Bringing the person's Apple Reminders lists and reminders into the to-do list, as
often as they like, without duplicates.

**What the export holds** (from `AppleRemindersImport.swift`):
- Lists: `id`, `title`, `color`.
- Reminders: `id`, `externalId`, `listId`, `title`, `notes` (cut to 20,000 characters), `url`,
  `completed`, `completionDate`, `creationDate`, `lastModifiedDate`, `priority`, `due`, `alarms`,
  `recurrence`.
  - `due` is `{ allDay, date, time, timeZone, instant }`.
  - `alarms` are `{ absoluteDate, relativeOffsetSeconds }`.
  - `recurrence` rules are `{ frequency, interval, daysOfWeek, daysOfMonth, …, end }`.
- Not in the export at all: groups, sections, subtasks (no parent), tags, flags, Urgent,
  location, attachments and images. These are lost before the page sees them, as with the
  Things importer (P-new-33).

**Mapping to records.**

| Export | Becomes | Loss |
|---|---|---|
| list `title`, `color` | `list:<id>` `name`, `color`; `emoji` null; `wallpaper` "none"; `order` by export order | none |
| reminder `externalId` | the record key `todo:ar-<externalId>` [U: key characters not checked]. records.md has no `externalId` field, so the key carries it. | none |
| `title` | `title` | none |
| `notes`, `url` | `notes`; a `url` is added on its own last line [U]. records.md has no URL field. | notes past 20,000 characters (shell cut) |
| `listId` | `list` | none |
| `completed`, `completionDate` | `done`, `completedAt` | none |
| `creationDate` | `createdAt` (now when absent) | none |
| `due.date` | `when` (`deadline` stays null) | none |
| `due.time` (when not `allDay`) | `time`; `due.timeZone` dropped, so the time floats (#45) [U] | the zone |
| `priority` | nothing [U] | priority (records.md lacks it) |
| `alarms` | nothing; a timed to-do gets one notification at its time (TD-OUT-01) | early and absolute alarms |
| `recurrence` daily, interval 1 | `repeat { every: "day", from: "schedule" }` | none |
| weekly, interval 1, no days or one day | `{ every: "week" }` | none |
| weekly, interval 1, Monday to Friday | `{ every: "weekday" }` | none |
| monthly, interval 1, no set days | `{ every: "month" }` | none |
| any other rule (yearly, interval over 1, other weekday sets, set days, an end) | `repeat: null`, counted under "Repeats not imported" | the repeat (records.md has no interval, yearly or end) |

- Midas-only fields (`subtasks`, `part`, `deadline`, `emoji`, `color`, `inToday`, `someday`,
  `order`) are set to defaults on first import. A later import never changes them (PRODUCT.md:
  "Midas-only fields… stay").
- `order`: after the last to-do in its list.

**Anatomy.**
- "⋯" → "Import Apple Reminders".
- The shell's own sheet and the iOS prompt.
- While the page reads the parts: a sheet "Importing…".
- Result sheet titled "Imported", with grouped count rows, as the Reminders Sidekick: "Imported",
  "Updated", "Up to date", "Repeats not imported", "Not saved" (when a write failed).
- Each row is a label and a numeral (WRITING rules 5, 12); rows with 0 are hidden [U].

**States.**
- **Pending:** the request is written; the shell sheet is up.
- **`cancelled`:** the person tapped "Not Now". Nothing is shown and the request is removed.
- **`denied`:** "No Access to Reminders" with the line "Settings › Apps › Midas › Reminders › Full
  Access" (Reminders Sidekick words).
- **`failed`:** "Import Failed" and "Try Again".
- **`done`:** the page reads the parts, writes the records, deletes the parts, then shows the
  result.
- **Older shell without the request kind:** the page asks the shell (`{op:"shell"}`) which request
  kinds it supports and hides the menu item (PRODUCT.md widget note) [U, the same check for this
  kind].

**Interactions.**
- "Try Again" writes a new request.
- The result sheet closes with "✕".
- Imported to-dos appear at once in their lists, Today and Upcoming by TD-DAY's rules.
- Done ones go to the logbook only.

**Words.** "Import Apple Reminders" · "Importing…" · "Imported" · "Updated" · "Up to date" ·
"Repeats not imported" · "Not saved" · "No Access to Reminders" · "Import Failed" · "Try Again".
The shell's sheet words ("Import Apple Reminders", "Continue", "Not Now") are the shell's.

**Data.**
- Writes `request:<id>`; reads `import:<id>:<nnnn>`; writes `list:` and `todo:`; deletes the
  `import:` parts and the request.
- The manifest must declare `request:` and `import:` types, as the Reminders Sidekick does [U, not
  checked for this Sidekick].
- Re-import: a `todo:ar-<externalId>` that exists is updated in the imported fields only (the
  phone wins). A to-do whose reminder is gone from Apple stays.

**Needs.** Shell has it (`AppleRemindersImport.swift`). It lacks, for full fidelity: groups,
sections, subtasks, tags, flags, Urgent, location and attachments in the export. records.md lacks:
`url`, `priority`, alarms, and a repeat interval, yearly and end. The founder decides which to add.

**Edge cases.**
- **P-new-33:** the losses are listed above and the repeat losses are counted on screen.
- **P-new-34 and P-new-35:** originals are never deleted (copy-only).
- **P-new-36:** tags are not in the export, so there is no question to ask.
- **#1 and #6:** nothing removed.
- **#9:** unknown fields kept on update.
- **P-new-28:** completed reminders arrive done and never show in Today.
- **P-new-31:** import happens only when asked.
- **Duplicates:** the key from `externalId` makes a second import update rather than duplicate.

**Tests.**
- Given a part with reminder `{ externalId: "E1", title: "Pay rent", due: { allDay: false, date:
  "2026-11-01", time: "09:00" }, recurrence: [{ frequency: "monthly", interval: 1 }] }`, when the
  import finishes, then `todo:ar-E1` has `when` "2026-11-01", `time` "09:00" and `repeat
  { every: "month", from: "schedule" }`.
- Given a yearly reminder, then its `todo:` has `repeat: null` and the result shows
  "Repeats not imported" with 1.
- Given a completed reminder with `completionDate` 2025-03-02, then its `todo:` has `done: true`
  and `completedAt` on 2025-03-02, and it is not in Today on 2026-10-31.
- Given `todo:ar-E1` already imported and then given subtask "Transfer", when a second import has
  E1 with title "Pay rent Nov", then:
  - only one record for E1 exists;
  - its title is "Pay rent Nov";
  - its subtasks still hold "Transfer";
  - the result shows "Updated" 1.
- Given a second import without E1, then `todo:ar-E1` still exists.
- Given a reminder with `url` "https://x.test", then its notes end with "https://x.test".
- Given the import done, then `store.query('import:')` returns `[]`.
- Given the request status `denied`, then "No Access to Reminders" shows and no `todo:` was
  written.
- Given the request status `cancelled`, then no sheet shows.

**Evidence.**
- PRODUCT.md 2026-10-10 (import, wording); `shell/Midas/AppleRemindersImport.swift` (export
  fields); `sidekicks/reminders/index.html` (result and error words).
- look-group-d Part 2 P-new-33 to 36 (Things [C]; TickTick and the tags user [R]);
  WRITING.md rules 5, 6 and the import example.
- No screenshot.

---

### TD-SET-05 Empty and all-done states

**Tag:** core. Checklist #17: the list says why it is empty or unavailable. DP-50: Apple
Calendar's failed load "appears empty" and reads as data loss.

**Variations:**
- **Todoist:** a "#TodoistZero" screen exists [R]; its copy was not found [U].
- **Tiimo:** after the review, "Review done, Everything is handled for today." [R].
- **UK Government Design System:** a cleared list "may be celebratory"; keep "cleared" apart from
  "filter shows nothing" [R].
- **Midas Reminders widget:** "All done" (WIDGETS.md example).
- Exact copy for Things, Todoist, Microsoft To Do and Reminders is not found [U, look-group-d
  "Unverified"].

**Default variation:** a short headline and one action (WRITING rule 7). An "All Done" day is kept
apart from a day with nothing planned. The all-done celebration itself is TD-DONE-04 (`celebrate`).

**What it is.** What each empty screen says, kept distinct from loading, from a failure and from
a list that was cleared.

**Anatomy.**
- Centred in the list area: a glyph 64 pt `--accent` at 40% [U], the headline 22 pt bold `--ink`,
  an optional result line 15 pt `--ink-2`, and one capsule button 44 pt (`--accent` 15% tint,
  `--accent` text 17 pt semibold).
- With `doneGoes` stay or sink, done rows still show under an all-done headline.

**States and words.**

| State | When | Headline | Line | Button |
|---|---|---|---|---|
| Empty list | no open or done to-dos in it, ever | "No To-Dos" | none | "New To-Do" |
| Today, nothing planned | no open to-do in Today and none done today | "Nothing Today" [U] | none | "New To-Do" |
| Today, all done | no open to-do in Today, at least one done today | "All Done" | "Completed 5" [U] | none |
| A list all done | open 0, done ≥ 1 in it | "All Done" | none | "New To-Do" |
| Upcoming empty | no dated to-do after today | "Nothing Upcoming" | none | none |
| Logbook empty | no done to-do | "No Completed To-Dos" [U] | none | none |
| Search, no match | query matches nothing, done included | "No Results" | none | none |
| Loading | `store.query` pending | no headline; grey row placeholders after 400 ms | | |
| Failed read | `store.query` rejects | "Can't Load To-Dos" | none | "Try Again" |

- With `doneGoes: hide` and every to-do done, the screen is "All Done", never "No To-Dos"
  (GOV.UK: keep cleared apart).

**Interactions.**
- "New To-Do" opens TD-ADD (on that list, or Today with `when` today).
- "Try Again" repeats the read.

**Words.** "No To-Dos" · "New To-Do" · "Nothing Today" · "All Done" · "Completed 5" ·
"Nothing Upcoming" · "No Completed To-Dos" · "No Results" · "Can't Load To-Dos" · "Try Again".

**Data.** Reads `todo:` (`done`, `completedAt`, `list`, `when`, `deadline`, `someday`) and
`settings:self.doneGoes`. Writes nothing.

**Needs.** Page alone.

**Edge cases.**
- **#17 and DP-50:** loading, failed and empty are three states.
- **DP-51:** offline reads the local store, so it is not failed.
- **L6:** no pop-up.
- **WRITING rule 7:** 15 words at most.

**Tests.**
- Given no to-dos, when the store answers, then "No To-Dos" and "New To-Do" show.
- Given `store.query` pending, then none of the headlines above is in the page.
- Given `store.query` rejects, then "Can't Load To-Dos" and "Try Again" show and "No To-Dos" does
  not.
- Given 5 to-dos in Today all ticked today and `doneGoes: "hide"`, then "All Done" and
  "Completed 5" show and "No To-Dos" does not.
- Given no to-do in Today and none done today, then "Nothing Today" shows, not "All Done".
- Given a search for "milk" with one done to-do "Milk", then the result lists it and "No Results"
  does not show.

**Evidence.**
- look-group-d 1.4 (Todoist [R], GOV.UK [R]), "Unverified or missing"; look-group-c 3.2 (Tiimo
  [R]); group-d section 2 (first open / empty), #17.
- WRITING.md rule 7; docs/WIDGETS.md ("All done").
- No screenshot.

