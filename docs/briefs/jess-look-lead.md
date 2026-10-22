# jess look: decisions for the lead

From the jess-look agent (branch `agent/jess-look`). The lead updates `docs/DESIGN.md` and
`docs/PRODUCT.md` from this file.

## Decided

### The jess icon (founder, 2026-10-22)

**"Jess", capital J, written in Caveat Bold exactly as the Midas icon is** (option V1 of round 4,
same as S1 of round 3). The letters are the font's own glyphs: `J`, `e`, `s`, `s`, with no
alternates, no softening, no weight change.

- Same rules as the Midas icon (DESIGN.md §4): ink on paper, the word centred on its ink box, set
  at the Midas icon's size (330 px on a 1024 px canvas), full-bleed square; dark variant paper on
  ink.
- Rejected on the way (2026-10-22): the orb as the tile; "jess" in other hands (32 fonts); a drawn
  smooth "s" in 11 shapes; the last "s" underlining the word; the word in the bottom-right corner;
  Caveat's alternate "s" shapes, thinner weights, softened edges, other spacing.
- Mockups: `docs/mockups/jess-look-2026-10-22.html` (round 2), `-r3.html`, `-r4.html` (V1).

Built on this branch: `JessTileIcon` shows the `JessTile` image (light and dark), drawn by
`shell/icon-source/jess-tile.py` (README there).

Still open for the icon: the one-colour glyph that Control Center, the Action button and the
Shortcuts tile need (iOS takes a symbol there, not a picture). They keep the `mic` symbol for now.

### Listening colour (founder, 2026-10-22)

**While jess listens, the orb's core is Volt in the original jess purple's recipe: `#CEFF00` in
light mode, `#E7FF85` in dark mode** (option F2t of `docs/mockups/jess-look-2026-10-22-r6.html`).
The recipe is the one the original jess purple used in Auto-Apply (`#6A00FF` light, `#B48CFF`
dark): the pure colour in light mode, the same colour with about half white (52%) in dark mode.

- Core only, crisp, no glow (the 2026-10-15 decision stands); ring and body unchanged.
- Idle and thinking keep the black (light) / white (dark) core; done green and not-done red unchanged.
- Known: in light mode `#CEFF00` on the white body has contrast 1.2; the founder chose it after
  seeing that on the page.
- Rejected on the way (2026-10-22): the eight tile colours and the accent shortlist; saturated
  blues, cyan, teal, orange, rose; near-greys; medium-strength blues, teal, rose, clay; a neon set; a
  hue wheel of 25 and 12 named colours. Shortlist before the pick: safety orange, Volt, ice,
  Tiffany, laser green, acid yellow (each as round 5 and in the purple's recipe), blues in the recipe.
- Research behind the rounds (two research agents, 2026-10-22): saturation and lightness drive
  arousal more than hue (Valdez & Mehrabian 1994; Wilms & Oberfeld 2018); "blue = trust" is not
  established (Kosova 2025 review; Elliot 2015); colour-only states are often missed and motion or
  a shape helps (Kunchay & Abdullah 2021; Portnoff et al. 2015).

Built on this branch: `JessOrbPalette.listening` in `shell/Midas/JessOrb.swift`.

## For the lead

1. Add both decisions, dated, to `docs/PRODUCT.md` and `docs/DESIGN.md` §5a (DESIGN.md §5a lists
   the core colours by state; §2 says no colour outside its tables without a dated decision).
2. The existing test `JessOrbTests.testTheCoreAloneCarriesTheResultInBothModes`
   (`shell/MidasTests/VoiceReminderTests.swift`) still says the listening core is black / white.
   test-guardian refused to change it until the decision is in `docs/PRODUCT.md` (logged in
   `TEST_CHANGES.md`). Once PRODUCT.md has it, resend: drop `.listening` from the black/white loop,
   assert `0xCEFF00` / `0xE7FF85`, add `palette.listening` to `testNoPurpleAnywhere`. Until then
   that one test fails on this branch.
