# Open concerns: one widget any Sidekick fills (2026-10-13)

Parked by the founder ("add it to concerns, I'll deal with it later", 2026-10-13) while discussing
a single widget whose inside any Sidekick fills (option C in
`docs/primitives/daily-planner/shell/planner-widget.md`). Not approved to build. When the founder
asks "is there anything left?", these are on the list.

## 1. Stale data

If a Sidekick writes the widget's file only when its page is open, the widget goes stale after the
days the file covers, and after a change made outside the page (a Done from a notification). The
Reminders widget avoids this because the app works out Today from the records itself.

## 2. Refresh budget

WidgetKit: about 40 to 70 reloads a day per widget, timeline entries at least about 5 minutes
apart. Self-updating text (`Text(timerInterval:)`) costs none.

## 3. No scrolling

WidgetKit has no `ScrollView`; arrow buttons page through rows, as the Reminders widget does.

## 4. Lock Screen colours

Accessory families render monochrome or tinted; a Sidekick's colours do not show there.
