# Brief: a Live Activity for the current task, 2026-10-12

**Status:** Draft, not approved to build. The founder decides whether and when.

Labels: [C] confirmed on a primary source (Apple docs as cited in midas-intel
`docs/research/ios-notifications-reference.md`) or read in this repo's code; [R] reported; [U]
not verified.

## How you work

The four steps of `docs/briefs/notification-engine.md`: say the idea back; ask; propose a plan
and wait for "approved"; then build with tests (`CLAUDE.md`). Read `docs/NOTIFICATIONS.md` and
`ios-notifications-reference.md` (L01 to L10) first (`CLAUDE.md`).

## Goal

The running task's countdown on the Lock Screen and in the Dynamic Island while the planner page
is closed. It appears when expected and goes away after (checklist 45). Extending the task
updates it (21); finishing early ends it (20). Pattern DP-OUT-03, DP-FOC-01 outside the page.
Love 13 (Tiimo 2, inside Structured's ~17); leave reason 9 (Tiimo's Live Activity "invisible 90%
of the time").

## What is already decided (with sources)

- Native features are reached by request records; no bridge (PRODUCT.md 5; NOTIFICATIONS.md 2).
- Native reach now: notifications and widgets (PRODUCT.md 5, 2026-10-07). Live Activities are
  listed in NOTIFICATIONS.md as "what else iOS offers"; "Nothing there is decided for Midas until
  the founder says so."
- care-reminders build option A: "No nag, alarm or live timer for now" (PRODUCT.md 6,
  2026-10-12). That is a choice for that Sidekick, not for planners.

## What exists today

- No ActivityKit code; no `NSSupportsLiveActivities` in either `Info.plist`.
- A widget extension exists (`shell/MidasWidgets/`); a Live Activity needs one [C, L01].
- A `LiveActivityIntent` already runs in the app's process for the Reminders widget tick
  (`shell/Shared/RemindersWidgetIntents.swift`); the same pattern serves Live Activity buttons.
- Deployment target iOS 17.0 (`shell/project.yml`). A scheduled start needs iOS 26 [C, L06].

## Platform facts

From `ios-notifications-reference.md`:
- L01 [C]: Lock Screen card 371 × 84 to 160 pt, 14 pt margins. Needs a widget extension and
  `NSSupportsLiveActivities`; no permission prompt, no entitlement. The person can turn Live
  Activities off per app. 8 h active, up to 12 h on the Lock Screen; 4 KB of data; no network;
  images already on the phone. Concurrent count undocumented (third parties say 5) [U], shared by
  the whole app, scheduled ones included. A Sidekick's HTML cannot render here.
- L02 [C]: Dynamic Island compact, minimal and expanded are all required. Background always black.
- L03 [C]: `Text(timerInterval:)`, `ProgressView(timerInterval:)` and relative dates keep
  counting with no updates and cost no budget.
- L04 [C]: buttons run a `LiveActivityIntent` in the app's process (iOS 17); inactive on a locked
  device until unlock.
- L05 [C]: the app updates it when it runs (foreground or background time); an alerting update
  lights the screen.
- L06 [C]: Scheduled Live Activity (iOS 26, `request(...start:)`): iOS starts it at a date even if
  Midas is in the background; an `AlertConfiguration` is required; it counts toward the concurrent
  limit while waiting.
- L07 [C]: otherwise starting needs the app in the foreground, or a `LiveActivityIntent` from a
  control, Shortcut or the Action button.
- L10 [C]: `staleDate` switches it to a stale look; after it ends it stays up to 4 h unless
  dismissed sooner (HIG: 15 to 30 minutes is adequate).
- Ending at the task's end time while Midas does not run: no local API ends an activity at a set
  time [U]; `staleDate` and a push (L08, server, not built) are the known tools.

Apps [C, ANALYSIS.md 3.9]: Structured mirrors its focus timer; Tiimo's ring must be enabled by
hand and kept counting after an edit (1, A); Akiflow cannot advance without opening the app;
Timepage's seconds called "unnerving".

## A record design to discuss

Two shapes, both records only:

1. **Declarative, like `reminder:`.** The page writes `activity:<taskId>`
   `{ title, icon, colour, start, end, taskId }`. The shell keeps one Live Activity per such record:
   creates it when `start` ≤ now < `end` and Midas runs (or schedules it, iOS 26), updates it on
   rewrite, ends it on delete or when `end` passes and Midas runs. `start` and `end` are ISO 8601
   instants with an offset. A shell-owned type (`midas.activity`) in `shell/sdk/shell-types.js`,
   as `widget:` and `request:`, checked at write time by the same validator.
2. **Request records, like the import.** `request:<id>` with `kind` `live-activity.start`,
   `live-activity.update`, `live-activity.end`; the shell answers with `status` (`running`,
   `ended`, `disabled`, `failed`).

Values fit in 4 KB: title up to 200 characters, one emoji, a colour, two instants.

## Open questions for the founder

1. Declarative record or request records.
2. Start only from the page's focus screen (app in front), or also at each task's start time with
   a scheduled start (iOS 26 only; an alert each time; counts toward the concurrent limit).
3. Buttons ("+5 min", "Done") in the first version, or view only.
4. One activity at a time for all of Midas, or one per Sidekick (the concurrent limit is shared).
5. Tasks longer than 8 h (a work shift): end at 8 h, or not offered.

## App Review

- **4.7.2** [C] The layout is the shell's own SwiftUI; the page supplies values through records.
  No native API is exposed to the page.
- **4.7.3** [C] No permission is involved (no prompt). Data shown is the Sidekick's own; no other
  Sidekick reads it.
- **5.1.1** [C] No data is requested.
- **4.5.3** (no spam via push or Live Activities) and **2.5.18** (no ads) [C,
  ios-notifications-reference.md] apply to content.

## How a Sidekick reaches it (records only)

The page writes and deletes `activity:<taskId>` (shape 1) or `request:` records (shape 2) when the
person starts focus, extends, finishes or leaves. It reads its own record back for the status. It
never calls ActivityKit. The page must stay correct when Live Activities are off: the record's
status says `disabled`, and the page's own focus screen still works.

## Tests that can fail for their reason

With a fake activity controller in `MidasTests`:
- An `activity:` record with start ≤ now < end produces exactly one activity with that end.
- Rewriting `end` 5 minutes later updates the same activity; the count stays one (checklist 21).
- Deleting the record ends and dismisses the activity (checklist 20).
- A record whose `end` has passed, on the next engine run, ends the activity; none is left
  showing "0 min left".
- Live Activities turned off: no activity, status `disabled`, no error to the page.
- A record from Sidekick A never changes Sidekick B's activity.
- A value over 4 KB is refused at write time with its reason.
- iOS 17 to 25: a future `start` is not scheduled (no iOS 26 API called); iOS 26: it is.

## Done when

The founder approves a plan; on the iPhone, a focus started in a planner shows on the Lock Screen
and in the Dynamic Island, follows an extension, and goes away after the task; the full suite
passes; results reported honestly.
