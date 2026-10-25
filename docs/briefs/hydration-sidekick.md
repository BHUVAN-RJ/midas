# Hydration Sidekick for Amogh: implementation plan (2026-10-25)

Status (2026-10-25): **built and merged to `main`**. Approved by the founder on 2026-10-25.
- Shell work: `agent/hydration-shell`, merged in `5ec5ac6`.
- The Sidekick: `agent/hydration-sidekick`, merged in `a3aa119`.
- Then the cross-check test (`shell/MidasTests/HydrationWidgetCrossCheckTests.swift`) and Water's
  repair agent (`runner/agents/hydration.md`).

Next: staging, then Midas Test on the founder's phone, then TestFlight, then live and assign to
Amogh (section 4). Final syntax as built: `docs/WIDGETS.md`, `docs/NOTIFICATIONS.md`.

Decided (founder):
- 2026-10-24: logging, ml/L/oz, accurate reminders, streaks, a visual widget that logs water. No paywall.
- 2026-10-25: look **E. Tide** (`docs/mockups/hydration-2026-10-24.html`). Amogh sets the daily
  goal on first open.
- 2026-10-25: **Water has repair.** Every personal Sidekick gets a repair agent; only jess and Make
  have none.

Sources:
- Research: midas-intel `docs/research/2026-10-24-hydration-apps.md`.
- Code read 2026-10-25 on `main` `271328e`. Line numbers below are from that commit.

## 1. Correction to what was said on 2026-10-24

The earlier draft said the Sidekick page could stop the rest of a day's reminders by setting
`doneThrough`. It can't:
- The planner never reads `doneThrough`, `lastDoneAt` or `slotsDone`. Only `done` and `snoozedUntil`
  matter (`ReminderPlanner.swift:83`, `:92`).
- `done: true` stops the reminder forever.
- `snoozedUntil` adds an extra notification; it never removes a booked one.
- Hourly times are iOS repeating triggers, which have no "skip today".

So **accurate reminders need an engine change whether Amogh logs on the page or on the widget.**
Option A ("Sidekick only") can't meet the reminder requirement and is dropped. This plan is
Option B.

## 2. What gets built

### 2.1 Shell: widget builder (4 additions)

| # | Addition | Where | Behaviour |
|---|---|---|---|
| W1 | **Day keys**: `{today}` in a source `record` key and in a tap key | Filler `singleRecordValue` (`SidekickWidgetFiller.swift:113`) and tap keys (`:465`); publisher `write()` (`SidekickWidgetPublisher.swift:141`); one shared helper | Resolved to the local date (`YYYY-MM-DD`) for each look, so the midnight look (`:26-30`) reads and writes the new day. Resolved again at tap time from the tap's `tappedAt`. Queued taps keep `tappedAt` (today it is dropped at `:239`), so a 23:59 tap applied at 00:05 lands on the right day. One calendar for filler, publisher and widget. |
| W2 | **Unit format on text**: `format: 'ml' \| 'l' \| 'oz'` | Checker text case (`SidekickWidgetDescription.swift:244`); `interpolate` (`:531`) | Number bindings in that text are read as ml and shown as "1,250 ml", "1.25 L" or "42 oz". Today numbers are rounded to one decimal (`:524`), so 1.25 would show as "1.3". Other pieces are unchanged. |
| W3 | **Streak source**: `{ records: 'water:', streak: { field: 'ml', goal: '$settings.goalMl', dayGoalField: 'goalMl' } }` | Checker sources (`:94-127`); filler `sourceValue` (`:62-77`) | Gives `days`: consecutive days with `ml >= goal`, using the day's own `goalMl` when present, else the current goal. Today counts once it's met; an unmet today doesn't break the streak until it's over. |
| W4 | **`fill` piece + widget background** | New case in checker, filler, shared `WidgetPiece` (`SidekickWidgetShared.swift:153`), drawing in `SidekickWidget.swift:142`; top-level `background` colour (today fixed at `:93`) | `{ fill: { value, of }, color, edge: 'wave', content: { … } }`: a colour that rises from the bottom to `value/of` with a still wave edge, with `content` drawn on top (the text and buttons). Counts toward the 150-piece and 12-deep limits. Widgets don't animate on iOS, so the wave doesn't move. |

No change to the protected-prefix rule: widget taps still can't write `reminder:`.

### 2.2 Shell: notification engine (2 additions)

| # | Addition | Where | Behaviour |
|---|---|---|---|
| N1 | **Window for hourly reminders**: `endTime: 'HH:MM'` with `everyHours` | `ReminderExpansion.timesOfDay` (`:87-100`) | Times run from `at`'s time to `endTime`, not around the clock. 9:00–21:00 every 2 h = 7 times = 7 slots (today: 12, through the night). |
| N2 | **Reminders that listen to a record**: `listen: { key: 'water:{today}', field: 'ml', goal: 'settings:main.goalMl', dayGoalField: 'goalMl', quietMinutes: 45 }` | Engine store observer (`NotificationEngine.swift:59-66`, today `reminder:` keys only); planner (`ReminderPlanner.swift:165-175`) | (a) Goal met: no more of today's times; tomorrow's come back. (b) Any write to the listened record (a drink logged on the page or the widget): times in the next 45 minutes are skipped. Works by computing a "quiet until" moment and reusing the planner's existing path for a repeat whose first occurrence is later than its trigger (`:171`): those times are booked one by one until quiet ends, then switch back to iOS repeating triggers on the next run. The engine already re-runs after every widget tap (`MidasApp.swift:43`); the observer is extended to listened keys so page logs re-run it too. |

Both are general: any reminder in any Sidekick can use them (coffee, meds taken, pushups).

Not in this plan, can be added later: a "+250 ml" button on the notification (per-Sidekick
buttons; `NotificationBooking.swift:26-34`).

### 2.3 Sidekick `sidekicks/hydration/`

**Manifest**
- `id: hydration`, name **"Water"**, SF Symbol `drop.fill`, tile **Turquoise `#30D5C8`** (DESIGN.md palette).
- Types (namespace `hydration.*`):

| Key | `$type` | Fields |
|---|---|---|
| `water:<YYYY-MM-DD>` | `hydration.day` | `ml` (required, the day's total); `goalMl`; `entries` [{ `at`, `ml` }] |
| `settings:main` | `hydration.settings` | `goalMl`, `unit` (`ml`/`l`/`oz`), `presetsMl` [3], `remindStart`, `remindEnd`, `everyHours` (2/3/4), `remindersOn` |
| `reminder:water` | `hydration.reminder` | Engine fields + `endTime` + `listen`. Leaves room for `reminderType` (notification levels, CONCERNS §17, in progress in another session). |

- Only `ml` is required on a day, so the first widget tap of a day (increment from 0) passes the
  schema check. The shell stamps `$type`.

**Screens** (Tide, light and a night version for dark mode; words per `docs/WRITING.md`)
- **First open**: daily goal (wheel, in the chosen unit) and unit. One button, "Start".
- **Today**: the rising sea, amount and "of 2.5 L", 3 presets, a custom amount, the week strip,
  the streak, "Next 2:00 PM" or "Done for today". After a log: "Added 250 ml" and "Undo".
- **Log**: today's entries (removable); earlier days. Widget taps add to `ml` without an entry,
  so the difference shows as one line, "From widget".
- **Settings**: goal, unit, presets, reminders on/off, from, to, every 2/3/4 hours.

**Defaults** (Amogh can change all of them)
- Reminders on, 9:00–21:00, every 2 hours.
- Quiet for 45 minutes after a drink.
- Presets 250/500/750 ml, or 8/16/24 oz.

**Tools** (`tools.js`, every page action is a tool):
- `hydration.log`, `hydration.undo`, `hydration.today`
- `hydration.set_goal`, `hydration.set_unit`, `hydration.set_reminders`

**Widgets** (written by the page with `store.set`):
- `widget:today` (small, medium): the sea fill with amount, goal, streak and preset buttons
  (`increment` on `water:{today}`).
- `widget:week` (medium, large): the week strip (chart) and today's sea.

The page rewrites them when the unit or presets change. If a phone's app build is too old for the
new pieces, `store.set` is refused; the page then writes a plain fallback widget (ring + buttons).

**care-reminders**: unchanged. Its "Water" list stays (see 4.1).

## 3. Steps, each with tests; the full suite (`scripts/test-all.sh`) after every step

Two worktrees, run in parallel once the contract in section 2 is approved:
`agent/hydration-shell` (W1–W4, N1–N2) and `agent/hydration-sidekick` (2.3). Both run on Opus.

| Step | Work | New tests (each must fail without the change) |
|---|---|---|
| 1 | W1 day keys | Midnight look reads and writes the next day's key; a queued 23:59 tap applied after midnight lands on the old day; increment creates a missing day record with `$type` stamped. |
| 2 | W2 unit format | 1250 → "1,250 ml" / "1.25 L" / "42 oz"; texts without `format` are unchanged. |
| 3 | W3 streak | Gap breaks it; unmet today doesn't; met today counts; a goal change mid-week uses each day's own `goalMl`. |
| 4 | W4 fill + background | Checker accepts and refuses; filler clamps 0…1; the file round-trips; render PNGs light/dark into `docs/mockups/`. |
| 5 | N1 window | 9:00–21:00 every 2 h → 7 times, 7 slots; no window → today's behaviour exactly. |
| 6 | N2 listen | Goal met → no bookings left today, tomorrow's back; a write → nothing in the next 45 min; the next run after quiet ends → back to repeating triggers; a widget tap and a page write both re-plan; a reminder without `listen` → no change. |
| 7 | Sidekick page, manifest, tools | `backend/test/hydration-*.test.ts` (travels with the bundle): schemas, ml↔L↔oz rounding, streak math, every tool against real-shaped records, the tools gate. Shell `HydrationSidekickTests.swift`: page under the real CSP, tools in JavaScriptCore. |
| 8 | Widget records | The page's real `widget:today` / `widget:week` pass the shell checker and fill correctly at 0%, 50% and 110%. |
| 8b | Repair agent `runner/agents/hydration.md` + its entry in `TEMPLATE_BY_SIDEKICK` (`runner/lib/prompt.mjs:13-16`), modelled on `runner/agents/care-reminders.md` | Template lookup finds `hydration`; a repair job for Water builds its prompt (new test next to `runner-loop-config-prompt.test.ts`). Done after the other session's runner changes (uncommitted on 2026-10-25) are merged, on top of them. |
| 9 | Docs | `docs/WIDGETS.md` (W1–W4), `docs/NOTIFICATIONS.md` (N1–N2), `docs/PRODUCT.md`. |

Existing tests that list Sidekicks by hand (`record-types-manifests`, `sidekick-tools-gate`,
`SidekickToolsTests.swift:118`) aren't edited. Hydration gets its own new tests (only test-guardian
may change existing ones).

## 4. Shipping

1. Staging: deploy the Sidekick (`deploy-sidekick.mjs hydration --env staging`), assign it to
   "test", and build **Midas Test** onto the founder's phone. Check:
   - log on the page and on the widget;
   - a tap just before and just after midnight;
   - reaching the goal from the widget stops the reminders;
   - a drink holds the next reminder back;
   - unit switch;
   - light and dark.
2. New TestFlight build (W1–W4 and N1–N2 are native code). Amogh installs it.
3. Live (founder runs): `deploy-sidekick.mjs hydration --env live`, then
   `assign-sidekick.mjs "Amogh" hydration --env live`.

### 4.1 Open, with defaults so work doesn't wait
- **care-reminders "Water" list**: if Amogh has water reminders there too, both fire. Default:
  leave it alone and tell Amogh.
