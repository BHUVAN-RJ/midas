# Open concerns: the Reminders widget made with the widget builder (2026-10-26)

Found while building `agent/reminders-widget-builder` (merged `aa892ea`, build 18). Outside the
brief. When the founder asks "is there anything left?", these are on the list.

## 1. Records snapshot holds every Reminders record

The widget refills itself after a tap from the records snapshot in the App Group. With Reminders on
the builder, that snapshot now carries all of the Reminders Sidekick's records (the founder's import
is about 1,449 reminders), written on every publish. Not measured. Check the file size and write
time on a phone with a large import; if it is big, snapshot only the records a widget's sources
read. Pick up: next widget work.

## 2. Ticks waiting from the old widget are dropped

At first launch of build 18 the app deletes the old widget's App Group files
(`RetiredRemindersWidgetFiles`), including taps queued there and not yet written. A tick made on the
old widget just before the upgrade is lost; the person ticks it again. Left as is (one-time, at
upgrade).

## 3. An hourly time ticked before it comes does not count

Ticking a later hourly time early (Pills 4:00 PM at 10:00 AM) leaves it on the widget: the existing
rule ignores a dose done before its time, and the app behaves the same. Tests tick a time already
past. Founder's call whether an early tick should count.
