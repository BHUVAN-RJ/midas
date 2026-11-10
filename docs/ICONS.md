# Sidekick icons: light and dark (founder, 2026-10-31, build 22)

Every Sidekick tile has a light and a dark variant and follows the phone's appearance, on the
home grid, in widget folders, in Make and in sheets. Whoever builds or changes a Sidekick (the
repair agent, Make's builder) writes both, every time.

## The manifest

```json
"icon": { "symbol": "checklist", "background": "#FF9500", "backgroundDark": "#B36800" }
```

- `symbol`: an SF Symbol name, drawn white on the tile.
- `background`: the tile in light mode, `#RRGGBB`.
- `backgroundDark`: the tile in dark mode, `#RRGGBB`. Same hue as `background`, deeper, so the
  white symbol still reads and the tile does not glare on a dark Home Screen. The deploy gate
  refuses a `backgroundDark` that is not a colour (`backend/scripts/bundle-tools.mjs`).
- Changing the tile colour changes both. A manifest without `backgroundDark` (from before build
  22) still deploys; the shell then derives a deep version of `background`.

## Drawn artwork

Some Sidekicks have artwork the shell draws instead of the symbol (`shell/Shared/SidekickIcon.swift`,
`SidekickArtwork`): Reminders (W2), care-reminders (Size by urgency), Water (Glass), Money (Wallet), jess and Make
(their `JessTile` / `MakeTile` images, each with a dark appearance in `Shared.xcassets`). Each one
has its own light and dark colours there (`RemindersListArtwork.colors(isDark:)`,
`WaterGlassArtwork.colors(isDark:)`, `MoneyWalletArtwork.colors(isDark:)`, `CareUrgencyArtwork.background(isDark:)`). New artwork adds
both palettes in the same change, and the manifest's `background` / `backgroundDark` still match
it (they are the fallback on builds without the artwork).

| Sidekick | Light | Dark |
|---|---|---|
| Reminders | white tile, green tick `#2FA65A`, rows `#3A3A3C` | tile `#1C1C1E`, tick `#30D158`, rows `#E5E5EA` |
| Water | sand `#F4EEE3`, sea `#9CCFD3`, ink `#24343A` | night sand `#0E1A1E`, sea `#2A6970`, ink `#E3EEEF` |
| care-reminders | paper `#FAF8F5`, list-colour tiles, white bell | paper `#1F1D1B`, same tiles and bell |
| Money | tile `#F3F1EA`, wallet `#101210`, bill `#2E9E5B` | tile `#141614`, wallet `#F4F5F2`, bill `#4CC97A` |

Money's Wallet (founder, 2026-11-09, concept C of `docs/mockups/money-icon-options-2026-11-09.html`)
is drawn for 29 pt as well as 60: flat fills only, no outlines, a big bill, a tile-colour gap
between bill and wallet, and a bill at least 3:1 against the tile in both appearances. Before and
after: `docs/mockups/money-icon-wallet-29pt-2026-11-09.png`. Its manifest tile (the fallback, and
the colour the Add to Home Screen sheet shows) is the bill green, `#2E9E5B` / `#1F7A45`.

A repair agent edits only the manifest's colours; drawn artwork is shell code and ships in an
app build.
