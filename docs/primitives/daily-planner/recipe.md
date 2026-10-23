# Recipe: building a daily planner Sidekick

How an agent, or later the generator, puts a daily planner Sidekick together from the blocks in
this folder. Written 2026-10-12. Docs only: building any Sidekick from this recipe still goes
through "discuss, the founder approves, then build" (`CLAUDE.md`) and the Sidekick design process
(midas-intel `docs/process/sidekick-design-process.md`).

## 1. What a planner Sidekick is made of

| Part | Where it is specified |
|---|---|
| One HTML page, inline script and style only, `midas-store.js` pasted in | `docs/PRODUCT.md` section 5, `docs/NOTIFICATIONS.md` 4.1 |
| Records `task:`, `reminder:`, `settings:planner`, `exception:`, plus the extras listed there | `records.md` |
| The patterns on screen | `blocks/*.md` |
| Native pieces the page cannot do | `shell/*.md` (drafts, none approved) |
| What a complete planner must handle | `checklist.md` |
| Words | `docs/WRITING.md` |

Manifest, as for every Sidekick: `id`, `name`, `icon` (SF Symbol plus background colour), `reads`
(empty unless a cross-app read is approved). A planner's own data is `task:` and friends; it
reads another Sidekick's records only through the consent flow (PRODUCT.md D7).

## 2. The core set (every planner, day one)

The 36 patterns tagged **core**: 31 in the nine page blocks and 5 in `blocks/outside.md`. Of the
5 outside the page, only DP-OUT-05 (per-task notifications) runs on what the shell has today;
01 to 03 need a draft shell brief, and 04 (Watch) has no brief. Built together they give a planner that does the
core jobs and avoids the main reasons users leave (research `ANALYSIS.md` sections 5 and 6).

| Block | Core patterns |
|---|---|
| Day view | DP-DAY-01 timeline of bubbles, DP-DAY-06 all-day row |
| Time | DP-TIME-01 now, 02 progress fill, 03 time remaining, 04 gap labels, 06 capacity, 08 overlaps |
| Navigation | DP-NAV-01 week strip, 03 week view, 04 month view, 08 jump to today |
| Item | DP-ITEM-01 colour, 03 time and duration, 04 completion, 05 tasks vs events |
| Capture | DP-ADD-01 add sheet, 02 duration and time pickers, 05 inbox, 06 drag onto a time |
| Rescheduling | DP-RES-01 drag and resize, 02 replan, 03 roll-over and overdue, 04 shift the rest |
| Focus | DP-FOC-02 extend and overtime, 05 end-of-task alarm |
| Feedback | DP-FB-01 completion animation, 04 undo |
| Settings | DP-SET-01 onboarding, 03 empty states, 07 time settings |
| Outside the app | DP-OUT-01 Home Screen widget, 02 Lock Screen / Up Next, 03 Live Activity, 04 Apple Watch, 05 per-task notifications |

The tags are a proposal from the research. The founder edits them.

## 3. Build order

Each step ends with its tests passing (the **Tests** lines of each pattern), and the whole suite
re-run (`scripts/test-all.sh`).

1. **Records first.** `task:` read, write, delete; `settings:planner` with defaults; the
   `task:` → `reminder:` derivation (`records.md`). Tests: a task with alerts produces the right
   `reminder:` records; editing moves them; deleting removes them; Done written back by the shell
   marks the task done.
2. **Theme.** The tokens in section 5 as CSS custom properties on `:root`, light and dark.
3. **Day view skeleton.** DP-NAV-01 week strip, DP-DAY-06 all-day row, DP-DAY-01 timeline,
   DP-ITEM-03 rows, DP-ITEM-04 completion. Empty states DP-SET-03.
4. **Time.** DP-TIME-01, 02, 03 (one shared clock: refresh every 30 s and on
   `visibilitychange`), DP-TIME-04 gaps, DP-TIME-08 overlaps, DP-TIME-06 capacity.
5. **Capture.** DP-ADD-01 add sheet with DP-ADD-02 pickers (native `<input type="time|date">`),
   DP-ITEM-01 colour, DP-ADD-05 inbox, DP-ADD-06 drag onto a time.
6. **Change.** DP-RES-01 drag and resize, DP-RES-04 shift the rest, DP-FOC-02 extend, DP-FB-04
   undo, DP-RES-03 overdue, DP-RES-02 replan.
7. **Bigger views.** DP-NAV-03 week, DP-NAV-04 month, DP-NAV-08 today.
8. **Alerts.** DP-FOC-05 and the default alerts through `reminder:` records, inside the shared
   64-slot budget (`records.md`).
9. **First open.** DP-SET-01 onboarding, DP-SET-07 time settings.
10. **Completeness pass.** Every `checklist.md` item marked "page alone" or "shell has it" has its
    test; items marked "shell lacks it" are listed for the founder, not worked around.

Rules that hold at every step:

- No gesture starts within 20 pt of the left screen edge: the shell owns that swipe (back to the
  home grid).
- No haptics, no native drag between views, no Live Activity, no widget from the page: those are
  shell pieces (`shell/`).
- No localStorage, no IndexedDB; every saved thing is a record. Page-memory state (undo stack,
  copied day) is lost on reload, by design.
- No user data in any prompt (PRODUCT.md, 2026-10-07).

## 4. Presets

A preset is a set of choices over the blocks: which variation each pattern uses, which on-request
patterns are added, the theme values and the words. Variations are named in each pattern's
**Variations** line.

### 4.1 Structured preset (the first one, for the founder's friend, 2026-10-12)

Source: midas-intel `docs/research/daily-planner/structured-ui-teardown.md`, the iOS 26 look
(version 4.3 onward).

- **Core set,** with each pattern's Structured variation where the block names one.
- **Added on-request patterns:** DP-ITEM-02 icon per item (monochrome icon on the bubble; the
  block's default is emoji, the preset differs), DP-ITEM-06 subtask chip, DP-NAV-02 pull down for
  the week, DP-RES-06 swipe right to complete and left to delete (inbox rows), DP-RES-07 long-press
  a date, DP-FOC-01 focus screen, DP-SET-04 Full / Simplified / Minimal.
- **Capacity (DP-TIME-06):** Structured uses an energy ring; its points per level and daily limit
  are not settled (blocks/time.md). Until they are, the preset uses the block default (time
  capacity).
- **Layout:** grey header with "13. May 2026 ›" (day bold, year in the accent), week strip, white
  timeline sheet with a grabber, floating tab bar pill (Inbox, Timeline, Settings; Structured's AI
  tab is left out) and a separate round "+" button.
- **Words:** Midas words under `docs/WRITING.md` (the blocks list each string). Whether this preset
  may use Structured's playful gap lines ("You've got 1h 35m 'til kickoff.") is open.

### 4.2 Other presets (named, not specified)

Each would be written the same way when a user asks for one: Tiimo-style (part-of-day sections
DP-DAY-03, no hour scale), Sunsama-style (capacity counter and daily ritual), Readdle-style
(timeline plus task sheet DP-DAY-05), Llama-style (list with end time DP-TIME-05 and play-through
DP-FOC-03).

## 5. Theme tokens

Every block uses these names. Values are the Structured preset (teardown section 2; light mode
confirmed, dark mode unconfirmed in the research).

| Token | Light | Dark | Use |
|---|---|---|---|
| `--accent` | `#F49F99` | `#F49F99` | year in header, selected day, "+" button, selected chips |
| `--accent-tint` | open | open | pressed and selected backgrounds (no value in the research) |
| `--bg-header` | `#F2F2F5` | `#000000` | header and week strip |
| `--bg-sheet` | `#FFFFFF` | `#1C1C1E` | timeline sheet, cards |
| `--ink` | `#000000` | `#FFFFFF` | titles |
| `--ink-2` | `#8A8A8E` | `#8E8E93` | times, durations, captions |
| `--line-future` | `#EBEBEB` | `#3A3A3C` | the line between future bubbles |
| `--bubble-future` | `#EBEBEB` | `#2C2C2E` | future bubble fill (icon in the task colour) |
| `--danger` | `#FF3B30` | `#FF453A` | delete, overtime |
| `--ok`, `--warn` | open | open | capacity under 80% / 80 to 100% (blocks/time.md) |
| `--palette-1` … `--palette-12` | `#F49F99` `#F19C74` `#EAA93B` `#91BE6C` `#6085A8` `#3A8564` `#974667` `#2B5073` `#6983A5` `#9FE0E8` `#D1E6BA` `#EF8583` | same | task colours, in Structured's preset order |

Dark values other than `--accent` and the palette are iOS system dark colours, not measured from
Structured. Font: SF Pro through `font-family: -apple-system, system-ui`; titles 17 pt semibold,
time lines 13 pt regular in `--ink-2`.

## 6. Open, for the founder

Collected from the block agents' reports, 2026-10-12. Each is written into the block it concerns;
this list is the index.

1. Core tags that differ from a literal reading of the rule: DP-DAY-02 and DP-DAY-05 (on request),
   DP-ADD-03 natural language (on request although PRODUCT.md calls it baseline), DP-FOC-01 focus
   screen (on request despite about 25 Structured mentions), DP-ITEM-02 icon (on request).
2. Defaults the research did not settle: new-task start time (next free 15-minute mark), overdue
   handling (nothing moves by itself; repeats never roll over), shift amounts (5m, 15m, 30m, 1h),
   undo (6 s toast, lost on reload), streak rule, onboarding (wake and bedtime set the day bounds).
3. Numbers chosen by agents: bubble height curve (57 pt at 15 min, 130 pt at 60 min, capped at
   240 pt), 500 ms long-press, 20 pt left-edge zone, 30 s refresh, capacity thresholds 80% and
   100%, swipe thresholds 25% and 50%.
4. Words: Midas wording in place of Structured's in several places ("1h 30m free", "Tasks
   overlap", "No Inbox Tasks"); the Structured preset's playful copy.
5. Energy ring: points per level and the daily limit.
6. Whether SF Symbols may be drawn inside a Sidekick page (icon set for DP-ITEM-02).
7. Not covered by any shell brief yet: nag until done, Time Sensitive alerts, AlarmKit, custom
   sounds, haptics, weather and travel time.
8. Apple Watch (DP-OUT-04) is core under the rule (a missing Watch is a leave reason) and has no
   shell brief.
9. From `records.md` (agent choices): alert keys `reminder:<taskId>~<alertKey>`, at most 3 alerts
   per task, notification text with absolute times ("Starts at 9:30 AM"), size caps on notes and
   subtasks, write order (stale alerts, then tasks, then new alerts).
10. Engine facts found in the Swift code (`records.md`, `shell/*.md`): a done occurrence of a repeat
    cannot stop its own alerts today (concern 3); Done on one alert of a task does not stop its
    other alerts until the page opens; an alert written in the past fires at once as "missed";
    a repeating alert cannot be pinned to a time zone.
11. Contradictions between docs and code, to settle in the docs that own them: NOTIFICATIONS.md
    section 7 says records are not synced, but `RecordSync.swift` syncs them per account; PRODUCT.md
    says query supports single-field equality, but `midas-store.js` sends a prefix only.
