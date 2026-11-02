# Navigation (TD-NAV)

Navigation is how the person moves around the to-do Sidekick: the home screen (a list, tiles or a
tab bar), the fixed smart lists (Today, Upcoming, All, Logbook), the person's own lists, and search
that works from every screen and finds done items too. Four patterns, from research
`LOOK-ANALYSIS.md` section 1.6, `look-group-d.md` sections 1.5 and 1.7, and the app files
`look-group-a.md` to `-c.md`. Changing navigation in an update is a leave reason: Google Tasks
September 2026 and Clear's 2026 navigation. So the home style changes only when the person changes
it (L3). The shell owns the swipe from the left screen edge (back to the home grid), so going back
inside the page is always a visible button, never an edge swipe. Sizes are in pt. Colours are theme
tokens that `recipe.md` will define. The token names (`--accent`, `--list`, `--bg`, `--bg-raised`,
`--ink`, `--ink-2`, `--line`, `--glass`) are [U] until it does. "Checklist N" is `group-d.md`
section 6. "P-new-N" is `look-group-d.md` Part 2. L1 to L6 are `LOOK-ANALYSIS.md` section 4.
Screenshots are in midas-intel `docs/research/todo/shots/`. [U] marks anything not in the research.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| TD-NAV-01 | Home style | core | `home: list`: one home list, smart lists on top, then Lists (Things) |
| TD-NAV-02 | Smart lists | core | No settings field; Today, Upcoming, All, Logbook, fixed and in that order [U] |
| TD-NAV-03 | User lists | core | No settings field; flat lists with emoji and colour, Inbox first [U] |
| TD-NAV-04 | Search everywhere, done included | core | No settings field; a search button at the bottom of every screen (HIG, Todoist) [U] |

Rules for every pattern here:
- No in-page gesture starts within 20 pt of the left screen edge (`daily-planner/recipe.md` section 3).
- Clear users mourned the "invisible back button… much better than swiping or using the glass buttons" (3★, 2026-07-21), and Clear brought a visible back button back (2.6.0). Every pushed screen here has a visible "‹" back button.
- No haptics. Motion becomes instant under `prefers-reduced-motion: reduce`.
- Glass (`--glass`, CSS `backdrop-filter` [U]) is used only on the control layer (buttons, tab bar, search), never on rows: "Don't use Liquid Glass in the content layer" (HIG, `look-group-d.md` 1.7) [C].

---

### TD-NAV-01 Home style

**Tag:** core. Every app has a home, and moving it is a leave reason. **Variations:**
- **List** (`list`):
  - Things: "Quick Find" pill, then Inbox, Today, Upcoming, Anytime, Someday, Logbook (each a coloured glyph, a bold title and a grey count), then Areas and Projects (`things_0.jpg`).
  - Microsoft To Do: My Day, Important, Planned, Assigned to me, Flagged email, Tasks, then lists and groups.
  - Superlist: sidebar with Search, Inbox, Updates, Tasks, Today, Lists, Favorites.
- **Tiles** (`tiles`):
  - Apple Reminders: a 2-column grid of solid-colour smart-list tiles, each with a white glyph top-left, a big bold count top-right and the name bottom-left (Today blue, Scheduled red, All black, Flagged orange, Urgent pink-red), then "My Lists" as an inset grouped card (`reminders_iphone_7.png`).
- **Tabs** (`tabs`):
  - Todoist iOS 26: a floating glass tab bar "Inbox · Today · Upcoming · Browse", with Search as a separate round glass button to its right. The selected tab sits in a glass bubble that slides (`todoist-macstories-liquidglass-2025.jpg`).
  - TickTick: a customisable bottom tab bar.
  - Tiimo: a glass tab bar.
- Not offered:
  - Google Tasks list tabs across the top: the hamburger was removed in September 2026, and users have to swipe sideways ("I absolutely despise that the little hamburger menu was taken away").
  - Clear: levels you pinch between.

**Default variation:** `home: list`. One scrolling home screen: the smart lists, a gap, then
"Lists". The page opens on Today [U].

**What it is.** The screen every list is reached from, and the shape of moving between Today, other
smart lists and the person's lists.

**Anatomy.**
- **List** (default), on `--bg`:
  - No large title on home [U]. The search button is TD-NAV-04.
  - Smart-list rows, 44 pt tall [U]:
    - a 22 pt glyph in its colour [U]: Today yellow star (Things #FFD400 [R]), Upcoming red calendar, All `--ink` stack [U], Logbook green check-book (Things);
    - the name, 17 pt semibold `--ink`;
    - the count at the trailing end, 15 pt `--ink-2`.
  - A 24 pt gap [U], then a "Lists" heading (13 pt semibold caps `--ink-2` [U]) and the TD-NAV-03 rows.
  - "New List" at the end, 17 pt `--accent` with a "+" glyph [U].
  - No row separators. Hairlines only between groups (Things).
- **Tiles**:
  - 2 columns, 12 pt gap, 16 pt side margins (the grid starts at 20 pt to keep the edge zone clear) [U].
  - Tiles 80 pt tall, 14 pt radius [U], solid fill:
    - Today: Reminders blue, #0088FE sampled [R];
    - Upcoming: red [U value];
    - All: `--ink` (black in light; a dark grey in dark, L5 [U]);
    - Logbook: green [U value].
  - On each tile: a white 24 pt glyph top-left, the count 28 pt bold white top-right, and the name 15 pt semibold white bottom-left [U].
  - Below: "Lists" heading and the TD-NAV-03 rows on a `--bg-raised` inset card, 12 pt radius [U] (Reminders "My Lists").
- **Tabs**:
  - A floating glass capsule, 56 pt tall [U], 20 pt from the left and bottom safe area [U], with tabs "Today", "Upcoming" and "Lists", each a 22 pt glyph over an 11 pt label [U].
  - The selected tab sits in a glass bubble that slides between tabs over 250 ms ease-out [U] (Todoist).
  - The round 56 pt glass search button sits to the bar's right (Todoist; HIG "a dedicated search tab at the trailing end") [C].
  - The + (TD-ADD-01) floats above the search button [U].
  - Content scrolls under the bar (HIG) [C].
  - "Lists" shows the list-style home without Today and Upcoming rows, starting with All and Logbook [U].
  - The bar does not shrink on scroll [U]. HIG allows it, but it would be a layout change without the person choosing it (L3).
- **A list screen** (all three styles):
  - A glass "‹" circle back button, 44 pt, top-left at 20 pt from the edge [U] (Things and Reminders use a glass back chevron), and a "•••" circle top-right.
  - The title large and bold, 34 pt [U], in the list's colour (Reminders).
  - With `home: tabs`, Today and Upcoming have no back button: they are tabs.

**States.**
- First open with no to-dos: Today opens with its empty state (TD-SET-05). The home counts read 0, or nothing [U].
- Many lists: home scrolls. Smart lists stay at the top and are not pinned [U].
- Dark (`theme`): tiles and glyphs keep their hue, rows are on the dark `--bg` (L5).

**Interactions.**
- Tap a row or tile: pushes that list. It slides in from the right, 300 ms ease-in-out [U].
- "‹": pops back with the reverse slide.
- Tap a tab: switches view, cross-fade 150 ms [U], keeping each tab's scroll position in page memory [U].
- Tap the active tab again: scrolls to top [U].
- No swipe between lists (the Google Tasks complaint), and no edge-swipe back (the shell owns it).
- `home` changes only in TD-SET-01 (L3).

**Words.** "Today" · "Upcoming" · "All" · "Logbook" · "Inbox" · "Lists" · "New List". Back button
has no label (accessibility label "Back" [U]).

**Data.** Reads `settings:self.home` and `.theme`. Counts come from the loaded `todo:` records
(TD-NAV-02 rules) and the `list:` records (TD-NAV-03). Writes nothing.

**Needs.** Page alone. The shell owns the left-edge swipe back to its home grid. The page's
"‹" is the only in-page back.

**Edge cases.**
- Checklist 14: returning after days shows open to-dos, because the page opens on Today.
- Checklist 17: an empty view says why (TD-SET-05).
- L3 (no style change without the person), L5 (dark tiles designed, not inverted), L6 (nothing pops over home).

**Tests.**
- Given `home: list`, when the page opens, then Today is shown, and "‹" goes to a home with rows Today, Upcoming, All, Logbook, then "Lists".
- Given `home: tiles` and 3 open to-dos in Today, then the Today tile shows "3".
- Given `home: tabs`, then a tab bar with exactly "Today", "Upcoming", "Lists" and a separate search button is on screen, and Today has no back button.
- Given a pushed list, when a touch starts at x = 8 pt and moves right 200 pt, then the page does not go back (the shell's gesture, not the page's).
- Given `home: tabs`, Upcoming scrolled 400 pt, when Today then Upcoming is tapped, then Upcoming is still at 400 pt.

**Evidence.**
- `LOOK-ANALYSIS.md` 1.6, 1.8 and section 3 item 1.
- `look-group-b.md` table: Google Tasks list tabs 3 complaints after September 2026 (`look-group-d.md` table: 4); TickTick tab bar 1 complaint; Liquid Glass tab bar 2 loves ("Y'all cooked", 2025-09-21; MacStories).
- `look-group-d.md` 1.5: Clear back button (3★ 2026-07-21; 5★ 2026-08-10).
- Screenshots `things_0.jpg`, `reminders_iphone_7.png`, `todoist-macstories-liquidglass-2025.jpg`, `tiimo_3_crop.jpg`.

---

### TD-NAV-02 Smart lists (Today, Upcoming, All, Logbook)

**Tag:** core (checklist 11, 42, 52; P-new-28). **Variations:**
- Things: Inbox, Today, Upcoming, Anytime, Someday, Logbook. Today "is the list for to-dos that you want to start before the day ends"; Upcoming to-dos "automatically move over to Today" on their start date (`group-a.md` 3) [C].
- Apple Reminders: Today ("due today and… overdue"), Scheduled ("grouped by date"), All, Flagged, Completed, Assigned, and Urgent since iOS 26.4 (`group-a.md` 6) [C].
- Todoist: Inbox, Today, Upcoming. "Only tasks with a date appear in Today and Upcoming" [C].
- Microsoft To Do: My Day, Important, Planned, Assigned to me, Flagged email, Tasks.
- Any.do: Today, Tomorrow, Upcoming, Someday as sections of one list (`anydo_2.jpg`).
- Superlist: Inbox, Updates, Tasks, Today.

**Default variation:** no `settings:self` field. Four fixed smart lists, in this order:
1. Today
2. Upcoming
3. All
4. Logbook

They cannot be removed, renamed or reordered [U]. Inbox is the first of the person's lists
(TD-NAV-03), not a smart list.

**What it is.** Views over every list at once, chosen by date or by done, so the person never has to
open each list to see what is due.

**Anatomy.** Each is a list screen (TD-NAV-01) with its glyph and title, using TD-ROW rows.
- Today: TD-DAY-01 and 02 layout.
- Upcoming: day sections (TD-DAY-03).
- All: one section per list, headed by the list's emoji and name in its colour, in list `order` [U].
- Logbook: one section per local day of `completedAt`, newest first, headed "Today", "Yesterday", then "Wed 29 Oct" [U] (TD-DONE-07).
- Each row's meta line shows its list name when the view spans lists (TD-ROW-02; Things, Microsoft To Do).

**What each shows:**

| Smart list | Shows | Count on home |
|---|---|---|
| Today | Per `todayModel` (basic `carry`; TD-DAY-01): open to-dos with `when` ≤ today and `someday` false. Done today per `doneGoes`. | Open in Today |
| Upcoming | Open to-dos with `when` > today and `someday` false, by day (TD-DAY-03) | Open in Upcoming |
| All | Every open to-do, dated or not, Someday included (marked as Someday [U]) | Open, all lists |
| Logbook | Every to-do with `done` true, by `completedAt` day | None [U] |

- Deadline today or past: Things shows a red badge with the count beside Today's count [C]. The colour and shame rules are TD-DAY-04's.

**States.**
- Empty: each says why and offers one action (TD-SET-05; checklist 17), never a blank list.
  - "Nothing for Today" with the + [U].
  - Kept apart from "everything done" (TD-DONE-04 `allDone`; `look-group-d.md` 1.4: keep "cleared" separate from "filter shows nothing").
- Very long Logbook (years): renders the latest 30 days, then loads 30 more days when scrolled near the end [U] (checklist 55).
- Day change while open: Today and Upcoming re-sort at local midnight and on `visibilitychange` [U] (checklist 44).

**Interactions.**
- Tap from home or tab: opens it (TD-NAV-01).
- Rows act as everywhere (TD-GEST, TD-DONE).
- A + in Today, Upcoming or All adds as TD-ADD-01 says. Logbook has no +.
- Ticking in Logbook (reopen) moves the to-do back to its views at once.

**Words.** "Today" · "Upcoming" · "All" · "Logbook" · "Someday" (meta in All) · "Yesterday" · day
headings "Wed 29 Oct" [U] · empty headlines per TD-SET-05.

**Data.**
- Reads every `todo:` (one `store.query('todo:')` at open, kept in memory). `midas-store.js` sends a prefix only, so filtering is in the page.
- Fields used: `when`, `someday`, `done`, `completedAt`, `inToday`, `part`, `deadline`, `list`, `order`.
- Reads `settings:self.todayModel`, `.doneGoes`, `.dayParts`, and the `list:` records.
- Writes nothing itself.

**Needs.** Page alone. The shell syncs records (`ANALYSIS.md` section 5). There is no change event
in `midas-store.js`, so the page re-queries on `visibilitychange` to pick up another device's
writes [U] (checklist 13).

**Edge cases.**
- Checklist 11: undated to-dos always show in All and their list, never hidden.
- Checklist 42: unfinished items stay (TD-DAY-01).
- Checklist 52: Logbook keeps every done to-do with its `completedAt`, and search reaches it (TD-NAV-04).
- P-new-6: each finished copy of a repeat is its own done record, so repeats show in Logbook.
- P-new-28: Today never shows a to-do with `done` true unless its `completedAt` is today, so an update can never drag old done items into Today (Reminders: "it drags over 580 completed reminders from as far as three years ago").
- Checklist 14, 17, 44, 55, L2 (a ticked row stays visible in Today per `doneGoes` long enough to undo).

**Tests.**
- Given a done to-do with `completedAt` 2023-05-01 and `when` 2023-05-01, when Today is opened on 2026-10-31, then it is not shown.
- Given an open to-do with no `when` in list "Ideas", then it is in All under "Ideas" and in neither Today nor Upcoming.
- Given `someday` true and `when` null, then it shows in All and not in Upcoming.
- Given an open to-do with `when` 2026-11-03, then it is in Upcoming under 3 Nov, and Upcoming's home count includes it.
- Given 3 to-dos completed on 2026-10-29 and 1 today, then Logbook shows "Today" (1) above "Wed 29 Oct" (3).
- Given 4,000 done to-dos over 3 years, when Logbook opens, then the first screen of rows renders within 300 ms [U] and scrolling to the end loads older days.
- Given the clock passes local midnight with Today open, then Today's contents follow `todayModel` for the new day without a reload.

**Evidence.**
- `LOOK-ANALYSIS.md` 1.6; `look-group-d.md` 1.5 and P-new-28 (Reminders 1★, 2026-10-24); `group-a.md` sections 3, 4, 6.
- `look-group-d.md` pattern table: "Single home list with smart lists on top: Things, Reminders, MS To Do", [C] screenshots.
- Screenshots `things_0.jpg`, `reminders_iphone_7.png`, `reminders_iphone_1.png` (Reminders Today), `anydo_2.jpg`.

---

### TD-NAV-03 User lists

**Tag:** core. Every app has lists. P-new-13 (reorder lists), P-new-15 (search list names) and
P-new-24 (warn before a whole-list delete) are checklist items. **Variations:**
- Apple Reminders: each list has a colour and a symbol or emoji, carried through its title, its + and its tile. Groups have a disclosure chevron (`reminders_iphone_7.png`).
- Microsoft To Do: emoji in the list name, a per-list colour (7 dots) or full-screen photo, and list groups. A new list "must first be generically added, and then dragged to the intended Group" (complaint).
- Things: Areas holding Projects, with pie-progress circles.
- Superlist: emoji icon and a cover image per list (`superlist_3_crop.jpg`).
- Todoist: projects with a coloured `#`, folders.
- Google Tasks: lists as top tabs, and lists cannot be reordered on the phone (4 reviews).

**Default variation:** no `settings:self` field. Flat lists with no groups, each a `list:<id>`
`{ name, emoji, color, wallpaper, order }` (`records.md` section 2). Inbox is first and fixed [U].
Lists are reordered by drag (TD-GEST-02). Groups are not mapped in `records.md`.

**What it is.** The person's own lists, each with a name, emoji, colour and optional wallpaper, made
and arranged by them.

**Anatomy.**
- List row (home), 44 pt [U]:
  - a 30 pt circle in the list's `color` holding its emoji (or a white list glyph when none) [U] (Reminders);
  - the name, 17 pt `--ink`, one line, cut at the end with "…";
  - the open count, 15 pt `--ink-2`, then a chevron [U].
- Inbox row: tray glyph on `--accent` [U] (Things' Inbox is a blue tray).
- New or edit list sheet, `--bg-raised`, 16 pt top corners [U]:
  - a big preview circle in the chosen colour with the emoji, 64 pt [U];
  - a name field, placeholder "List Name";
  - an "Emoji" button that opens the keyboard's emoji set;
  - 12 colour dots of 32 pt, with the chosen one ringed [U count and size] (Microsoft To Do uses 7, Tweek adds a custom hex picker);
  - wallpaper choice per TD-LOOK-01 when `look: wallpaper`;
  - "Add" for a new list, "Save" for an edit, at top-right. "Cancel" at top-left.
- List screen: title in the list colour, + in the list colour (TD-ADD-01), wallpaper behind the rows when `look: wallpaper` (TD-LOOK-01).

**States.**
- Inbox: always present, cannot be deleted or renamed [U]. A to-do with `list` "inbox" belongs to it, and no `list:` record is needed [U].
- Empty list: shows TD-SET-05's empty state.
- Many lists (hundreds; Reminders user with "maybe hundreds"): home scrolls, and search finds list names (TD-NAV-04, P-new-15).
- Very long name: one line with "…" on rows, wraps on the list screen title up to 2 lines [U] (checklist 56).

**Interactions.**
- "New List": opens the sheet with the name focused. "Add" writes the list and opens it [U].
- On a list screen, "•••": "Edit List", "Delete List" [U].
- Drag a list row on home (400 ms hold, TD-GEST-02 mechanics): reorders lists, one `order` write (P-new-13). Inbox stays first [U].
- "Delete List":
  - With to-dos: an alert, title "Delete List?", message "12 to-dos" [U wording], buttons "Delete" (destructive) and "Cancel" (`docs/WRITING.md` rule 8 and its "Delete List?" example). This warning is required because whole-list loss is unexpected (P-new-24: HIG "Warn people when they initiate a task that can cause data loss that's unexpected and irreversible").
  - Empty list: deletes at once with an undo toast, no alert [U].
- Moving a to-do between lists is TD-ITEM-06 or the TD-GEST-03 menu.

**Words.** "Lists" · "New List" · "List Name" (placeholder) · "Emoji" · "Add" · "Save" · "Cancel" ·
"Edit List" · "Delete List" · alert "Delete List?" / "12 to-dos" / "Delete" / "Cancel" · toast
`Deleted "Groceries"` / "Undo" · error "Can't Save List" / "Try Again".

**Data.**
- Writes `list:<id>` `{ name, emoji, color, wallpaper, order }`. A photo `wallpaper` is a `file:` ref from `store.putFile`, so the record stays under 64 KB.
- Reorder: one `update` of `order`.
- Delete: `store.delete('list:<id>')`, then a delete of each `todo:` with that `list`.
  - Done to-dos of that list are deleted too, so they leave Logbook [U]; open for the founder, since checklist 52 wants history kept.
  - There is no trash record, so the deleted values are held in page memory for the toast's undo only [U] (checklist 50 not met).
  - Write order: the to-dos first, then the list. A failure part-way leaves the list with fewer to-dos, never to-dos without a list [U].
- Reads the `todo:` records for counts.

**Needs.** Page alone. The shell has `putFile` for photo wallpapers and syncs the records.

**Edge cases.**
- P-new-13 (reorder lists), P-new-15 (list names in search), P-new-16 (list order holds after reload and sync), P-new-24 (warn on whole-list delete).
- P-new-14 (create a list straight into a group): groups are not mapped [U].
- Checklist 1 (lists survive restart), 8 (a refused write shows "Can't Save List"), 50, 52, 56, L3, L5 (list colours keep contrast on dark).

**Tests.**
- Given "New List" with name "Groceries", emoji "🛒" and a colour chosen, when "Add" is tapped, then `list:<id>` exists with those fields and the list screen opens with the title in that colour.
- Given lists A, B, C, when C is dragged above A, then only C's record is written and the order after reload is Inbox, C, A, B.
- Given a list with 12 to-dos, when "Delete List" is chosen, then "Delete List?" shows with "Delete" and "Cancel", and "Cancel" leaves the list and its 12 to-dos.
- Given that alert, when "Delete" is tapped, then `list:<id>` and its 12 `todo:` records are gone and no other `todo:` changed.
- Given an empty list, when it is deleted and "Undo" tapped, then `list:<id>` exists again with the same fields.
- Given Inbox, then "•••" offers neither "Delete List" nor rename.

**Evidence.**
- `LOOK-ANALYSIS.md` 1.6 and section 2 item 3 ("Make it mine": ~12 quotes).
- `look-group-a.md` 3.4: "I love that I can change the colors and symbols that go with each list" (2026-10-08).
- `look-group-b.md` 3.3: "I've customized the backgrounds for all my lists" (2026-04-19).
- `look-group-d.md` P-new-13 (4 reviews), P-new-14 (1), P-new-15 (1), P-new-24 (Reminders, Todoist, Clear: 3 quotes).
- Screenshots `reminders_iphone_7.png`, `mstodo-1.png`, `superlist_3_crop.jpg`.

---

### TD-NAV-04 Search everywhere, done included

**Tag:** core (P-new-18, 19, 20, 21, 15; checklist 52). **Variations:**
- Things: pull down in any list for Quick Find. A "Quick Find" pill is at the top of home. "Continue Search" extends the search to the Logbook, notes and checklists.
- Todoist iOS 26: a separate round glass Search button to the right of the tab bar, "expanding horizontally when tapped with a bouncy animation".
- Apple HIG [C]:
  - "Place search at the bottom if there's room".
  - Search as a button-style tab "brings focus to the search field and displays the keyboard".
  - "start search immediately when a person types".
- Tweek: "Swipe down to search through your tasks."
- Superlist: a Search pill at the top of the sidebar.
- Failures:
  - Microsoft To Do: search only at the top level ("you have to be at top level list view"), and it lags on 1,400 tasks.
  - Apple Reminders iOS 26: misses items ("it might return 2 results when I easily had 25").
  - Google Tasks: no search on iOS.

**Default variation:** no `settings:self` field. A round glass search button at the bottom of every
screen: at the leading corner opposite the + with `home: list` or `tiles` [U], and to the right of
the tab bar with `home: tabs` (Todoist). Results include done to-dos and list names at once, with no
"Continue Search" step [U]. Pull down to search (Things, Tweek) is a variation, not built by default [U].

**What it is.** One search, reachable from every screen, that finds any to-do ever written (open or
done) and any list, quickly, even with years of data. A found done item can be added again.

**Anatomy.**
- Button: 48 pt glass circle with a magnifier glyph in `--ink` [U].
  - List/tiles: 24 pt from the left edge and 16 pt above the bottom safe area [U]. The tap target starts at 24 pt, clear of the 20 pt zone.
  - Tabs: beside the tab bar (TD-NAV-01).
- Open state:
  - The button stretches into a full-width glass field at the bottom, 20 pt side margins [U], over 250 ms with a slight overshoot [U] (Todoist's "bouncy").
  - The keyboard rises (HIG). Placeholder "Search", a clear ✕ inside the field when there is text, and "Cancel" to its right.
- Results fill the screen above the field, on `--bg`, in up to three sections in this order:
  1. "Lists": list rows (TD-NAV-03 style) whose name matches.
  2. "To-Dos": open matches, as TD-ROW rows with the list name in the meta line.
  3. "Done": done matches, struck through, meta "Done Wed 29 Oct · Groceries" [U], with an "Add Again" pill (28 pt, `--accent` tint) at the trailing end.
- The matched text is bold in each row [U].

**States.**
- Empty field: no results, just the field and keyboard [U].
- No match: "No Results" (`docs/WRITING.md` rule 7).
- Many matches: sections capped at 50 rows each with "Show All" [U].
- Offline: the same; search reads the page's loaded records.

**Interactions.**
- Tap the button, or press "/" (TD-GEST-04): opens with the keyboard.
- Results update on every keystroke with no delay [U] (HIG "start search immediately").
- Matching: case- and accent-insensitive substring over `title`, `notes` and each `subtasks[].title`, and over `list:` `name` [U].
- Tap a list result: opens the list. Tap an open to-do: opens its detail card (TD-ITEM-01) [U].
- Tap a done result's checkbox: reopens it (`done` false).
- "Add Again": writes a new open to-do copying `title`, `list`, `emoji`, `color` and `notes`, with `subtasks` copied and set not done, `when` null [U]. The done one stays in Logbook (grocery reuse, P-new-21). Toast `Added "Milk"` with "Undo" [U].
- "Cancel" or Esc: closes and returns to the screen and scroll position it was opened from.
- Swiping a result (TD-GEST-01) is off [U].

**Words.** "Search" (placeholder) · "Cancel" · "Lists" · "To-Dos" · "Done" · "Done Wed 29 Oct" ·
"Add Again" · "Show All" · "No Results" · toast `Added "Milk"` / "Undo".

**Data.**
- Reads the in-memory `todo:` set loaded by TD-NAV-02 (`store.query('todo:')` returns all, by prefix) and the `list:` records.
- Search does not query the store per keystroke. It filters a lowercased, accent-stripped copy of each title, notes and subtask text built once at load and updated on every write [U].
- "Add Again" writes one `todo:`. Reopen writes `done` false and removes `completedAt`.

**Needs.** Page alone. The store query is by prefix only (`midas-store.js`), so filtering is
necessarily in the page. Siri search across Reminders (iOS 27) does not reach a Sidekick [U].

**Edge cases.**
- P-new-18: done items are found, in the "Done" section.
- P-new-19: the button is on every screen, including lists and smart lists, not only home.
- P-new-20: speed with years of data (test below).
- P-new-21: "Add Again".
- P-new-15: list names.
- Checklist 52 (the Logbook is searchable), 55, 56 (long titles in results: 2 lines, then "…" [U]).
- P-new-27: building the search copy at load must not slow opening with thousands of records; it is built after the first screen renders [U].
- L6: results show only while the person has search open.

**Tests.**
- Given 25 to-dos titled "Milk" (24 done over two years, 1 open), when "milk" is typed, then "To-Dos" shows 1 and "Done" shows 24 (the Reminders "2 results when I had 25" failure).
- Given 5,000 `todo:` records, 4,000 done, when one letter is typed, then results render within 100 ms of the keystroke [U].
- Given a pushed list "Work", when the search button is tapped, then the field is focused, and "Cancel" returns to "Work" at the same scroll position.
- Given a list named "Groceries", when "groc" is typed, then "Lists" shows "Groceries".
- Given a done "Eggs" in Groceries, when "Add Again" is tapped, then a new open `todo:` with `title` "Eggs" and `list` Groceries exists, and the done one still has `done` true.
- Given a subtask titled "passport" inside "Pack", when "passport" is typed, then "Pack" is in the results.
- Given "café" stored, when "cafe" is typed, then it is found.
- Given "zzzz" typed, then "No Results" shows and nothing else.

**Evidence.**
- `LOOK-ANALYSIS.md` 1.6 and section 4 (search items).
- `look-group-d.md` 1.7 (HIG search) and P-new-18 to 21 quotes:
  - Reminders 2025-12-17 and 2026-08-23;
  - MS To Do 2026-05-23, 2026-10-22, 2025-07-19, 2026-10-28;
  - Google Tasks 2025-04-10;
  - Reminders grocery 2025-12-12 and 2025-01-11.
- Pattern table: "Search at bottom / always reachable: 6 complaints (MS To Do, Reminders)".
- `look-group-b.md` 1.2 (Todoist search button); `look-group-c.md` 4.2 (Tweek); `look-group-a.md` 1.3 (Things Quick Find).
- Screenshots `things_0.jpg` (Quick Find), `todoist-macstories-liquidglass-2025.jpg` (search button beside the tab bar).
