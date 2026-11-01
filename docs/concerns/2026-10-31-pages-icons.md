# Concerns: build 22 pages and icons (2026-10-31)

Brief: `docs/briefs/build-22-2026-10-31.md`, row "Pages, shell widget filler and icons".
Branch `agent/pages-icons`, commits `ddc83b4` and `c51218a`, merged into main as `36caec1`.
Suites at hand-back: backend 1213/1213, typecheck clean, guard 42/42, shell 1039/1039 (Midas Sim 2).

## Open

- **Apple "Urgent" not imported as Alarm.** The iOS 27 SDK's EventKit has no Urgent flag:
  `EKReminder` gives only `priority` (0–9) and `EKAlarm`. Nothing built. Needs a founder pick:
  leave it, or map a priority value instead.
- **Early hourly tick still rings.** A Done on an hourly time before it comes now counts in Today,
  the widget and care-reminders (`ReminderChange.slotDoneMoment`). The notification booked as an
  iOS repeating trigger still rings at that time, as early ticks did before. Fix, if wanted: the
  notification engine skips or re-books that one occurrence (`docs/NOTIFICATIONS.md`).
- **Water remove built in the base, not a copy.** The brief says "in his copy"; there is no
  `copies/hydration/amogh`, and Amogh is Water's only live user, so it went into
  `sidekicks/hydration`. Lift into a copy only if another person gets Water.
- **"Always write both" icon colours is enforced by prompts, not the gate.** `icon.backgroundDark`
  is optional in `backend/scripts/bundle-tools.mjs` so old manifests still deploy. Make it
  required once every manifest has one.
- **Toolbar Alert label width.** "Time Sensitive" ends in "…" on narrow phones. Left as standard
  behaviour.
- **`scripts/test-all.sh` targets a simulator named "iPhone 17"**, not the pool ("Midas Sim 1/2"),
  so the suites were run one by one. midas-intel's suite was not run from this worktree.

## For the lead (files a worktree may not edit, and deploy steps)

- `docs/PRODUCT.md` (~line 1046) still lists the 0 L Water widget as an open founder pick. Record
  option A (`floor` 0.1, sent by the page; `docs/WIDGETS.md`). Lead moves it.
- `docs/CONCERNS.md`: §19 (Water remove) is built; §17's "Not built" line is half built (toolbar
  Alert done, Urgent not possible, see above). Lead updates both.
- `CLAUDE.md` may point to `docs/MAKE-BUILDER.md` and `docs/ICONS.md`. Lead decides.
- `CURRENT_PROJECT_VERSION` is still 21; raise for build 22.
- Deploy to staging, then live: `hydration`, `reminders`, `care-reminders` and Boomi's copy
  (`copies/reminders/boomi`). The floor and dark tiles need the build 22 app.
- New jess tool `hydration.remove`; `backend/scripts/jess-golden.json` has no sentence for it yet.
