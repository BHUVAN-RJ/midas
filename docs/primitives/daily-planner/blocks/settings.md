# Settings, onboarding and empty states (DP-SET)

This block covers the first open, the items present on day one, what empty screens say, how much
the day shows, appearance, which calendars show, and time settings. Seven patterns, from research
`ANALYSIS.md` section 3.10. Structured preset values come from `structured-ui-teardown.md` (T)
sections 1.4, 1.10, 1.11 and 2.5. Screenshot paths are relative to the base folder in
`ANALYSIS.md` section 8. Theme tokens are defined in `recipe.md`.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| DP-SET-01 | Onboarding that plans today | core | Structured steps 5 to 12: wake, bedtime, first task |
| DP-SET-02 | Seeded anchors | on request | Structured "Rise and Shine" and "Wind Down" |
| DP-SET-03 | Empty-state copy | core | A short headline and one action (WRITING rule 7) |
| DP-SET-04 | Density modes | on request | Structured Full / Simplified / Minimal |
| DP-SET-05 | Appearance and accessibility | on request | Structured Customization screen, without haptics |
| DP-SET-06 | Which calendars show | on request | Apple's calendars sheet, by account |
| DP-SET-07 | Time settings | core | Structured first day of week, plus 12/24-hour, day end and per-task zone |

Settings screens are plain grouped lists: `--bg-header` background, white `--bg-sheet` cards with
16 pt radius, 44 pt rows, 17 pt `--ink` labels, values 17 pt `--ink-2`, section headers 13 pt
`--ink-2` uppercase. Pickers use `<select>`, `<input type="time">` and `<input type="date">`,
which open the real iOS pickers in WKWebView with no bridge. Every setting is a field of the one
`settings:self` record (`planner.settings`).

---

### DP-SET-01 Onboarding that plans today

**Tag:** core (checklist 48 and 49; leave reason 7). **Variations:**
- Structured: 14 steps: welcome, "When did you wake up?", bedtime, first task title, time, duration, colour, summary, notification warm-up, paywall [R for steps 7 to 14] (T 1.11).
- Sunsama, Morgen, Akiflow: need a computer or the web to start (B, D).

**Default variation:** Structured steps 5 to 12, shortened: "Plan Today", wake-up time, bedtime,
first task through the DP-ADD-01 sheet, then the day. Not built: the welcome slides (Midas shows
the Sidekick, not a sales pitch), the notification warm-up (the shell asks for notification
permission the first time any Sidekick writes a `reminder:`), the paywall (Sidekicks sell
nothing). Sign-in is the shell's (name and passkey, on the phone).

**What it is.** The first open of an empty planner builds today.

**Anatomy.**
- Step screen: `--bg-header` background; a progress bar 4 pt tall in `--accent` at the top with "←" and "Skip" 17 pt `--accent`.
- Headline 28 pt bold `--ink`, the key word in `--accent` ("When did you **wake up**?").
- Time picker: a wheel as DP-ADD-02 with the selection as an `--accent` capsule "⏰ 8:00 AM"; or `<input type="time">` (Detailed).
- "Continue": full-width `--accent` capsule, 56 pt, 17 pt semibold white.

**States.** First open (no `reminder:` task and no `settings:self` record); skipped (goes straight
to an empty day, DP-SET-03); done (never shown again: a `settings:self` record exists).

**Interactions.** "Plan Today" or "Plan Tomorrow" chooses the day. "Continue" advances; "←" goes
back; "Skip" ends onboarding and writes default settings. Steps slide 300 ms; reduced motion:
instant.

**Words.** "Plan Today" · "Plan Tomorrow" · "When did you wake up?" · "When do you go to bed?" ·
"Continue" · "Skip". The first task uses DP-ADD-01 words.

**Data.** Writes `settings:self`: day start = wake time, day end = bedtime (a bedtime after
midnight sets a day end past midnight, checklist 27), week start and 12/24-hour from the locale,
default duration 15, default alerts: the start notification only (`defaultAlerts` absent; the end
alert is not mapped, `../records.md` 12). Writes the first `reminder:` task. With DP-SET-02 built,
writes the anchors.

**Needs.** Shell has sign-in and the notification permission prompt (asked when first needed).
Page alone for the rest.

**Edge cases.** 48 (no other device), 49 (no permission asked by the page), 9 (first task
default start near now).

**Tests.**
- Given no records, when the page opens, then the first screen is "Plan Today" and no `reminder:` exists.
- Given wake 7:00 and bedtime 1:00, when onboarding ends, then `settings:self` has day start 07:00 and day end 01:00 (next day).
- Given "Skip" on the first screen, then `settings:self` exists and the empty day shows.
- Given onboarding done, when the page reloads, then onboarding does not show.

**Evidence.** DP-SET-01; setup on a computer: Sunsama 1, Akiflow 1, Morgen 2 (B, D). Screenshots
`agent/lazyweb/lw_onboarding_4.png`, `agent/lazyweb/lw_paywall.png`.

---

### DP-SET-02 Seeded anchors

**Tag:** on request (not a checklist item or leave reason). **Variations:**
- Structured: repeating "Rise and Shine" and "Wind Down", plus four onboarding tasks with subtasks ("Get Started with Structured!") (T).

**Default variation:** Structured anchors only. The four onboarding tasks are not built: they
explain the interface (WRITING rule 4).

**What it is.** Two repeating items, at wake-up and bedtime, present from day one.

**Anatomy.** Zero-duration tasks drawn as 57 pt circles (DP-DAY-01): "Rise and Shine" with an
alarm-clock glyph in `--palette-1` [#F49F99]; "Wind Down" with a moon glyph in `--palette-8`
[#2B5073].

**States.** Present; edited (any field); deleted (does not come back).

**Interactions.** As any task. Changing day start or end in settings does not move them; they are
ordinary tasks.

**Words.** "Rise and Shine" · "Wind Down".

**Data.** Two `reminder:` tasks, duration 0, `repeat: { every: 'day' }`, `at` = wake and bedtime.
No early alerts by default. A dated task always notifies at `at`, so each anchor notifies daily
and holds 1 booked slot; a silent anchor is not mapped (`../records.md` 12).

**Needs.** Page alone.

**Edge cases.** 25 (a bedtime after midnight puts "Wind Down" at the end of the planner day, which
runs past midnight by the day end, DP-SET-07), 30 (wall-clock repeat).

**Tests.**
- Given onboarding with wake 7:00 and bedtime 23:00, then two daily `reminder:` tasks exist with `at` 07:00 and 23:00, duration 0 and no `alerts`.
- Given "Wind Down" deleted, when the page reloads, then it is not recreated.

**Evidence.** DP-SET-02; no loves or complaints found. Screenshot `agent/lazyweb/lw_home.png`.

---

### DP-SET-03 Empty-state copy

**Tag:** core (checklist 50). **Variations:**
- Structured Inbox: "Your Unstructured Thoughts" with "⊕ New Inbox Task" (T).
- Tiimo: "What's on your morning list?" (A).
- NotePlan: "What's planned for Thu, Jan 23? Type here..." (A).
- Sunsama: dashed placeholder cards and "Fill in your work for today" (B).

**Default variation:** a short headline and one action, per `docs/WRITING.md` rule 7, with
Structured's glyph-and-button layout.

**What it is.** What an empty day, empty inbox or empty search says, kept distinct from loading
and from a failure.

**Anatomy.** Centred in the sheet: glyph 120 pt in `--accent` at 40%; headline 22 pt bold
`--ink`; a capsule button 44 pt, `--accent` 15% tint, `--accent` text 17 pt semibold. On an empty
day the time gutter and line stay, so the screen still reads as a day.

**States.**
- Empty day: "No Tasks" / "Add Task".
- Empty inbox: "No Inbox Tasks" / "New Task".
- Empty search: "No Results".
- Loading: the sheet with no rows and no headline; after 400 ms, grey row placeholders. Never the empty headline before the store answers.
- Failed read: "Can't Load Tasks" / "Try Again".

**Interactions.** The button opens DP-ADD-01 (empty day, on that date), or the inbox add; "Try
Again" repeats the read.

**Words.** "No Tasks" · "Add Task" · "No Inbox Tasks" · "New Task" · "No Results" · "Can't Load
Tasks" · "Try Again".

**Data.** Reads `reminder:` tasks via `store.query('reminder:')`. Nothing written.

**Needs.** Page alone.

**Edge cases.** 50, 51 (offline still reads the local store, so offline is not "failed").

**Tests.**
- Given a day with no tasks, when the store answers, then "No Tasks" and "Add Task" show.
- Given `store.query` still pending, then "No Tasks" is not in the page.
- Given `store.query` rejects, then "Can't Load Tasks" and "Try Again" show, and "No Tasks" does not.

**Evidence.** DP-SET-03; Apple empty week read as data loss 1 (E). Screenshots
`agent/lazyweb/lw_inbox.png`, `b/web/sunsama_guided_daily_planning.png`.

---

### DP-SET-04 Density modes

**Tag:** on request (not a checklist item or leave reason; loves #10). **Variations:**
- Structured: Full / Simplified / Minimal (T).
- Timepage: Day View modules ordered by "Edit", stack or hours (C).
- TickTick: modules on or off (D).
- Ellie: "Simple by default" (A).

**Default variation:** Structured three layouts.

**What it is.** One setting for how much the day shows.

**Anatomy.** Settings › Customization: "Layout" with a segmented control "Full · Simplified ·
Minimal", selected segment an `--accent` capsule; a live preview card above (mini week strip and
three rows).
- Full: times in the gutter, gap prompts and "Add Task" pills (DP-TIME-04), mini bubbles in the week strip (DP-NAV-01).
- Simplified: no gap prompts (only "⏱ 3h 15m"), no week-strip bubbles.
- Minimal: also no gutter times.

**States.** One of three; the preview updates at once.

**Interactions.** Tap a segment: applies at once.

**Words.** "Layout" · "Full" · "Simplified" · "Minimal". Structured's caption is not used.

**Data.** `settings:self.layout`.

**Needs.** Page alone.

**Edge cases.** None from the checklist.

**Tests.**
- Given "Minimal", when the day renders, then no gutter time labels are in the page.
- Given "Simplified", then gap rows show only the duration and no "Add Task" pill.

**Evidence.** DP-SET-04; TickTick opt-in modules 1 (RG-A via D). Screenshot
`agent/help/354306_2.png`.

---

### DP-SET-05 Appearance and accessibility

**Tag:** on request (not a checklist item or leave reason; Motion has no dark mode). **Variations:**
- Structured: app colour (does not recolour tasks), System / Light / Dark, OpenDyslexic, sound and haptic toggles, Reduced Motion respected (T 1.10).
- Tiimo: dyslexia-friendly font, theme colour, 5 profiles (A).
- Timepage: 60+ themes (C). TickTick: 40+ themes (D).

**Default variation:** Structured Customization, without the haptics toggle (no haptics API).
Reduced motion is respected in every block regardless of this screen.

**What it is.** The planner's own look: accent colour, light or dark, font, sound.

**Anatomy.**
- "App Color": a row of the 12 `--palette-*` swatches, 36 pt circles, selected with a 3 pt white inner ring. Changing it sets `--accent`; task colours do not change.
- "Background Color": three tiles "System · Light · Dark".
- "Font": tiles "Aa 123" for "System" and "OpenDyslexic".
- "Sound Effects": toggle "In-App Sound".
- Dark tokens (T 2.5, recommended values [U]): `--bg-header` #000000, `--bg-sheet` #1C1C1E, cards #2C2C2E, `--line-future` #3A3A3C, `--ink` #FFFFFF, `--ink-2` #8E8E93; `--accent` and the palette unchanged.

**States.** System follows `prefers-color-scheme`; Light and Dark force it. OpenDyslexic loaded or
not available.

**Interactions.** Each control applies at once.

**Words.** "App Color" · "Background Color" · "System" · "Light" · "Dark" · "Font" ·
"OpenDyslexic" · "Sound Effects" · "In-App Sound". Structured's caption about task colours is not
used.

**Data.** `settings:self` `theme`, `accent`, `font`, `sound` (`../records.md` 4).

**Needs.** Page alone, except the OpenDyslexic font file: it must ship in the bundle, and files
larger than a record are not built (`CONCERNS.md` concern 4); its size against the bundle rules is
not checked. App icon choice (Structured) is not available: the icon is the Sidekick's manifest
icon, set by the shell.

**Edge cases.** None from the checklist.

**Tests.**
- Given "Dark", then `--bg-sheet` computes to #1C1C1E on the sheet.
- Given App Color set to `--palette-5`, then `--accent` is #6085A8 and a task coloured `--palette-1` is still #F49F99.
- Given `prefers-reduced-motion: reduce`, when a task is checked, then no transition longer than 0 ms runs.

**Evidence.** DP-SET-05; Timepage 3 design quotes (C); Motion no dark mode 2 (B); Fantastical
Liquid Glass 1 (C). Screenshots `agent/help/354306_1.png`, `c/timepage/appstore_8.png`.

---

### DP-SET-06 Which calendars show

**Tag:** on request (it exists only with calendar access, which the shell lacks; checklist 36 is
met by the page working on its own tasks). **Variations:**
- Routine: "Active" (writable) and "Passive" (context) calendars (B).
- Apple: calendars sheet by account (C).
- Google: drawer toggles (C).
- Morgen: source avatars as filters (D).

**Default variation:** Apple's sheet: calendars grouped by account, a toggle each, all read-only.

**What it is.** The choice of which phone calendars appear on the day.

**Anatomy.** Settings › "Calendars": a grouped list per account (header 13 pt `--ink-2`), rows
with a 12 pt dot in the calendar's colour, the name 17 pt, a toggle at right. Above the list,
"Show Calendars" master toggle.

**States.**
- No access asked yet: one row "Show Calendars" that, when turned on, writes the request record; the shell shows its own sheet and the iOS prompt.
- Full access: the list.
- Write-only access: "Can't Read Calendars" with "Open Settings" (checklist 37: write-only cannot read).
- Denied: "No Calendar Access" with "Open Settings".
- Off: the planner shows its own tasks only.

**Interactions.** Toggles apply at once. "Open Settings" is a shell action through the same
request record.

**Words.** "Calendars" · "Show Calendars" · "No Calendar Access" · "Can't Read Calendars" ·
"Open Settings".

**Data.** The chosen calendar ids in `settings:self.calendars`. Events come from the shell, not
from `reminder:` tasks.

**Needs.** Shell lacks calendar read: `shell/calendar-access.md`. Sync per account (checklist 40)
is the shell's record sync.

**Edge cases.** 36, 37, 40.

**Tests.**
- Given no calendar access, when the day opens, then the page's own tasks show and no error shows.
- Given write-only access reported by the shell, then "Can't Read Calendars" shows, not "No Calendar Access".
- Given a calendar toggled off, then none of its events are on the day.

**Evidence.** DP-SET-06; Morgen "many calendars" 1 (D); Apple holidays cannot be thinned (C).
Screenshots `b/appstore/routine_8.jpg`, `c/applecal/appstore_3.jpg`.

---

### DP-SET-07 Time settings

**Tag:** core (checklist 16, 17, 27, 28, 29). **Variations:**
- Structured: first day of week; per-task "Set Timezone", floating by default (T, E).
- Notion: time-zone columns (C).
- Sunsama (152 votes, Closed) and Tiimo users: an end-of-day setting asked for (E).

**Default variation:** Structured first day of week and floating tasks with an optional zone per
task, plus a 12/24-hour choice and a day end.

**What it is.** Clock format, week start, when "today" ends, and time zones.

**Anatomy.** Settings › "Time":
- "Week Starts On": `<select>` Sunday to Saturday.
- "Clock": `<select>` "System · 12-Hour · 24-Hour".
- "Day Starts": `<input type="time">` (timeline top, onboarding wake time).
- "Day Ends": `<input type="time">`; a value before "Day Starts" means after midnight ("1:00 AM, next day").
- In the task editor "•••": "Set Time Zone" opens a `<select>` of zones; the time row then shows "7:00 AM GMT+1".

**States.** Defaults from the locale (`Intl`); changed; a task with a zone shown after travel.

**Interactions.** Each change applies at once to every view.

**Words.** "Time" · "Week Starts On" · "Clock" · "System" · "12-Hour" · "24-Hour" · "Day Starts" ·
"Day Ends" · "1:00 AM, next day" · "Set Time Zone".

**Data.** `settings:self` week start, 12/24h, day start, day end. A task's time is its `at` read
in its `timeZone`; with `zone` absent the task floats (checklist 28): the page keeps its wall-clock
time in the phone's zone and rewrites `at` and `timeZone` after a zone change (`../records.md`
3.8). A pinned task has `zone` (IANA name, equal to `timeZone`); it is shown in local time
(checklist 29). A pinned repeating task is not mapped (`../records.md` 12).

**Needs.**
- Page alone for display.
- The native `<input type="time">` picker shows 12 or 24 hours by the iOS setting, not by "Clock"; whether `Intl` "System" follows the iOS 24-hour switch in WKWebView is unverified [U].
- Shell has wall-clock repeats across zones and DST (`NOTIFICATIONS.md` 4.4).
- Shell lacks a floating one-time alert: a one-time `reminder:` is an exact moment, so a floating 7:00 task's `at` fires at the old instant after travel until the page reopens: `shell/local-time-alerts.md`.

**Edge cases.** 16, 17, 27, 28, 29, 30, 31.

**Tests.**
- Given "24-Hour", then a 19:00 task's row reads "19:00–19:15", and given "12-Hour", "7:00–7:15 PM".
- Given "Week Starts On" Monday, then the week strip's first column is Monday.
- Given "Day Ends" 3:00 AM and an unfinished task at 23:00 on 12 Oct, when the page opens at 2:00 AM on 13 Oct, then today is 12 Oct and the task is not in "Overdue"; at 3:01 AM it is.
- Given a floating task at 07:00 and the phone's zone changed from New York to Los Angeles, then the row still reads 7:00.
- Given a task pinned to America/New_York at 09:00 and the phone in Los Angeles, then the row reads 6:00.

**Evidence.** DP-SET-07; Fantastical time zones 1 (C); Structured stuck on 24-hour 1, Notion zone
does not update 1; time zones 40, midnight 35, DST 9 negative hits (E). Screenshot
`c/notioncal/appstore_2.png`.
