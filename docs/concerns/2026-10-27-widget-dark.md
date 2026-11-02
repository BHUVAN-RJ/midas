# Concerns: light and dark widgets (2026-10-27)

Built on `agent/widget-dark` (4a12bc6), merged to main (4ee5410), shipped in build 21. What the
founder asked for is in `docs/PRODUCT.md` ("Widget builder: light and dark for every widget"); the
rule for pages is in `docs/WIDGETS.md` ("Light and dark"). Renders:
`docs/mockups/widget-dark-light-2026-10-27.png`, `docs/mockups/widget-dark-dark-2026-10-27.png`.

## Open

- **The tint has no dark colour of its own** (recorded 2026-10-29). The server checks widget
  records with `shell/sdk/shell-types.js`, where `tint` is a string of up to 40 characters, so
  `tint` stays one colour and the shell works out its dark version. Pages give dark colours on each
  piece instead. A `{ light, dark }` tint needs `shell-types.js` changed, the backend deployed, and
  a shell build that reads it. Pick up only if a widget needs it.
- **Older builds get only part of it.** Pages write three versions: full pairs, then pairs only on
  background and fill, then plain. The middle one needs a build from 2026-10-25 on; older builds
  get the plain widget, which uses system colours.
- **At night Water's grey text is nearly as bright as its main text** (`#D4DFE0` beside
  `#E3EEEF`). It has to reach a contrast of 4.5 over the night sea `#2A6970`. To make it dimmer,
  darken the night sea.
- **Two changes in how existing widgets look. Not yet seen on a phone:**
  - A symbol coloured `primary` or `secondary` now uses ink, not the accent.
  - Button labels pick white or dark ink by contrast, so Care Reminders' light sage buttons may now
    have dark labels.

  Check both on build 21 in light and dark.
