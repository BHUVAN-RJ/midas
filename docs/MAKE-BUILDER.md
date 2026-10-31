# Make's builder: building a Sidekick for a Make request

The founder builds each person's first version by hand ("Built by Hand", founder 2026-10-31),
usually with an agent. Whoever builds or changes a Sidekick for a Make request follows these, in
the same change as the page:

1. **Icon, light and dark** (founder, 2026-10-31): `manifest.json` `icon` has `symbol`,
   `background` and `backgroundDark`, both `#RRGGBB`, same hue, the dark one deeper. Artwork the
   shell draws gets both palettes in `shell/Shared/SidekickIcon.swift`. Full rule: `docs/ICONS.md`.
2. **Agent-connected** (founder, 2026-10-21): every action on the page is a tool, the `agent` block
   in `manifest.json` and `tools.js` (CLAUDE.md, "Every Sidekick is agent-connected").
3. **Records** in the unified format only (`$type`, schemas in `manifest.json` `types`).
4. **Words** follow `docs/WRITING.md`; widgets follow `docs/WIDGETS.md`, with light and dark colours.
5. **Repair**: a personal Sidekick gets a repair agent (`runner/agents/<id>.md`), which carries the
   same icon rule through `{{ICONS}}`.

The deploy gate checks the manifest (`backend/scripts/bundle-tools.mjs`, `validateManifest`):
`icon.backgroundDark`, when given, must be a colour.
