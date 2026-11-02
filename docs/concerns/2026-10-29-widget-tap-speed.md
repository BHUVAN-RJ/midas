# Open concerns: widget taps in the extension (2026-10-29)

Left by the widget-tap-speed agent (commit `5997897`, merged; build 21). `docs/PRODUCT.md`
already records that a widget drink is not backed up and can still be reminded inside the
45-minute quiet until the app runs. Two more items.

## 1. Not yet checked on a phone

The simulator could not place and tap a widget, so the tap-to-redraw time was never measured end
to end. Measured parts: the old path did about 12 ms of Midas work after a 144–167 ms cold launch;
the new path does about 2 ms in the extension. Still to see on the founder's iPhone 16 Pro: that
iOS runs the tap in the extension (no Midas launch) and that the widget redraws at once. Founder,
next TestFlight build 21 try-out.

## 2. A reminder after the goal, until the app runs

Water's goal-met stop (rest of today quiet) also waits for the app. A widget drink that reaches the
goal leaves today's remaining reminders booked until Midas next runs (launch, front, record change
or background refresh). The extension does not touch booked notifications: Water's are daily
repeating triggers, and removing one would also remove later days. Pick up only if the founder
sees it on the phone.
