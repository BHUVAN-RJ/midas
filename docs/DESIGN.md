# Midas design language

Decided by the founder on 2026-10-11 after the icon research and mockups (midas-intel
`docs/research/2026-10-11-brand-modern-ancient.md`, `2026-10-11-ios-app-icon-rules.md`,
`2026-10-11-handwritten-brands.md`). This file is the record. Change it only with a founder decision,
dated. Words on screen follow `docs/WRITING.md`; this file covers colour, type, the mark and motion.

## 1. The idea

Midas is plain. The Sidekicks are the colour. The shell is black ink on white paper, the wordmark is a
hand, and every colour on the home screen belongs to a Sidekick. Uber's colour is the map, Nike's is
the shoe, Apple's is the product photo; Midas's is the Sidekicks.

## 2. Colour

### 2.1 Shell palette (light)

| Token | Hex | Use |
|---|---|---|
| `paper` | `#FFFFFF` | every screen background |
| `ink` | `#111111` | text, icons, primary button fill, the wordmark |
| `ink-2` | `#6B6B6B` | secondary text, captions |
| `ink-3` | `#BDBDBD` | disabled text, hairlines when a hairline is needed |
| `rule` | `rgba(17,17,17,0.12)` | dividers, tile borders |
| `paper-2` | `#F3F2EF` | a raised or pressed surface when one is needed; warm grey, never blue grey |

Primary button: `ink` fill, `paper` text. Secondary button: `paper` fill, `ink` text, `rule` border.
Links: `ink`, underlined. Focus ring: `ink`. Toggles and selection: `ink` (set the tint; iOS defaults
to green). Destructive actions: iOS system red, which is the platform's, not ours.

### 2.2 The accent, held in reserve

Tomato light `#FF6347` is the third colour. Its only use so far is the repair pen (below). The founder
assigns it per use case when a case comes up ("I will tell per use case"). Until then every screen
is black and white. Do not add it to a button, a link, a badge or a state on your own.

Assigned uses:

- **The repair pen** (founder, 2026-10-13: "keep it tomato for now, or we can change it if it looks
  bad"). The strokes a user draws over a frozen Sidekick. Code: `RepairPen` in
  `shell/Midas/RepairSession.swift`.

Shortlist if it ever changes: cherry `#C41E3A`, tomato `#FF3B30` (Apple's system red), tangerine
`#FF8A00`, amber `#FFBF00`, lemon `#FFE600`, turquoise `#30D5C8`, chartreuse `#C9F24D`, or no
accent at all.

Rejected for the brand: brown, purple, blue, gradients, metallic gold.

### 2.3 Sidekick tile palette (fixed eight)

A Sidekick's manifest carries one tile colour. The generator picks from these eight and nothing
else, so the home grid always reads as one set. Letters and symbols on a tile are `ink` or `paper`,
whichever contrasts (listed).

| Name | Hex | Mark on it |
|---|---|---|
| Tomato light | `#FF6347` | paper |
| Amber | `#FFBF00` | ink |
| Lemon | `#FFE600` | ink |
| Chartreuse | `#C9F24D` | ink |
| Turquoise | `#30D5C8` | ink |
| Sage | `#9CAF88` | ink |
| Cherry | `#C41E3A` | paper |
| Charcoal | `#2E2E2E` | paper |

The founder may swap a colour in or out; keep the count at eight. The existing Reminders tile
colour moves to the nearest of these when the palette lands in the generator (open).

### 2.4 Dark mode (defined now, ships later)

Same structure, inverted. Not in build 2.

| Token | Hex |
|---|---|
| `paper` | `#111111` |
| `ink` | `#FFFFFF` |
| `ink-2` | `#A3A3A3` |
| `ink-3` | `#5C5C5C` |
| `rule` | `rgba(255,255,255,0.14)` |
| `paper-2` | `#1C1C1C` |

Tile palette is unchanged in dark mode. Tomato light stays `#FF6347` on both.

## 3. Type

- **The hand.** The wordmark and the icon are handwritten. Until the founder's own handwriting is
  traced (a written sheet is pending), the hand is Caveat Bold, SIL Open Font Licence, included in
  `shell/icon-source/`. It appears in exactly three places: the icon, the wordmark on the welcome
  screen, and the home screen title. Nowhere else.
- **Everything else is SF Pro**, the system font, at system sizes. No serif, no second display face.
- **Sidekick names** on the home grid are SF Pro, not the hand. Sidekick pages are built by the
  generator and follow their own kind; the shell does not impose the hand on them.

## 4. The mark

- **Icon:** the written word "Midas", centred, `ink` on `paper`, full-bleed square; the system rounds
  the corners and adds the iOS 26 glass edge. 1024 x 1024 PNG, no alpha. Dark variant: `paper` on
  `ink`. Tinted variant: white on black (grayscale). Files and regeneration:
  `shell/icon-source/README.md`. Catalog: `shell/Midas/Assets.xcassets/AppIcon.appiconset/`.
- **Shortlist kept** if the icon changes: lowercase "midas" centred; a small "m" with an underline
  at bottom-right.
- **Wordmark:** the same written "Midas". Never typeset in SF Pro. Minimum height 24 pt.
- **Never:** a crown, a coin, a hand, a king, gold imagery, a yellow oval (Midas auto service).

## 5. Motion

One brand motion: **cycle, then lock.**

1. Μίδας is shown in a Greek serif (Cormorant Garamond or system serif), holds 1.0 s.
2. Each letter, left to right, cycles through Greek capitals at 70 ms for 420 ms, then locks into
   the handwritten Latin letter. 260 ms between letters. Total about 2.5 s.
3. Ends on the written "Midas", static.

Where it plays: app open (once per launch) and the welcome screen. Nowhere else. With Reduce Motion
on, "Midas" appears at once. The icon never animates. Prototype: the "Iteration three" page from
2026-10-11 (Claude artifact), section 03.

Not used: marquee, grain or paper texture, blur reveals, spring bounces, confetti.

## 5a. jess's orb (founder, 2026-10-15)

jess's orb is the one voice mark across Midas: voice reminders, repair and every later voice
feature use the same shared component. From the founder's Job Autopilot orb, recoloured.

- **Light mode:** white body with a soft glow, `ink` ring with a hard offset shadow, a crisp solid
  black core.
- **Dark mode:** black body with a soft white glow, dark ring, a crisp solid white core.
- **The core has no halo** (founder, 2026-10-15, after tuning: glow max, spread 0, "this is the
  crisp look I want"). The only glow is the body's soft glow around the whole orb.
- **States:** idle (faint core), listening (outline ripples with the voice, core grows slightly),
  thinking (an arc sweeps the rim and pushes the wall out), added (core flat green: `#00873A` light,
  `#3DDC84` dark), not added (core flat red: `#E00000` light, `#FF5C5C` dark). Green and red never
  glow and never touch the ring. No tick, no dashed ring.
- **Never purple or violet.** The glow is the one exception to "no glows" in this file.
- Text around it is SF Pro. Reference mockup: `docs/mockups/jess-orb-2026-10-15.html`
  (https://claude.ai/artifact/WXTN62LXVWfTYHGcC3PeuV), variation "Neon core".

## 6. Planned, not now

**The first-open touch screen** (founder, 2026-10-11): before the public TestFlight, not build 2.
On first open the screen says Midas and asks the user to touch. At the touch point the screen shakes
and gathers energy, the app tiles are pulled in, after a few seconds the energy bursts and the same
tiles float back out. Then: "The personal touch your apps needed." Open: duration, haptics,
reduced-motion fallback, skip on later opens, hand-over to sign-in.

## 7. Checks

- `tests/guard/test_app_icon.py`: icon is 1024 x 1024, no alpha, dark and tinted variants declared.
- A screen that introduces a colour outside sections 2.1 and 2.3 is a bug unless this file was
  updated with a dated founder decision.

## 8. How we got here (2026-10-11, one day)

Kept so anyone revisiting knows what was tried and why it was dropped. Every page below is saved in
midas-intel `docs/prototypes/brand/` (with live links in its README); research in midas-intel
`docs/research/2026-10-11-*.md`.

1. **Brief: "modern but ancient".** The founder's first direction: light brownish-white paper, serif
   lettering, characters that move. Page 01 built it: parchment #EDE6D8, three serifs (Instrument
   Serif, Fraunces, Cormorant), four motions, three temperatures (parchment and ink, the coin, the
   inscription). Research then read 2,540 YC sites, 100 funded startups and 60 big companies from
   live CSS. Finding: cream plus serif is the default AI-startup look of 2025-26 (about 65 full
   fits; eight YC sites use Anthropic's exact #faf9f5; Instrument Serif on 40+). Only the brown and
   the moving letters were open ground. **Dropped** because the look is crowded; the founder also
   decided he hates brown.
2. **Six alternatives drawn** (page 02): fingerprint M, handwritten word, manila folder, gold leaf on
   ink, a mascot dot, and the sharpened brown-paper version. Compared on own-able, 29 px legibility,
   drawable by hand, dark mode, distance from the field, fit with "personal, private".
   **Chosen: handwritten.** Fingerprint and folder were the runners-up; mascot rejected as a persona
   (the plan demoted personas); gold leaf rejected as fintech territory.
3. **Handwritten pack** (page 03): 12 icon shapes, 9 hands, accents without blue (the founder
   dislikes blue), 6 theme packs, 8 animations. Research on handwriting in tech: handwriting is an
   annotation layer almost everywhere (Todoist, Miro, Buffer); a real hand in a 2026 tech logo is
   Granola only; a handwritten letter as an iOS icon is Pinterest's P and little else; write-on
   animation of a wordmark was found on nobody. **Kept:** the written word on a square and the
   lowercase signature m. **Chosen motion idea:** Greek first, then each letter changes on its own.
4. **Iteration two** (page 04): 14 word placements, 12 m marks, ten black-white-plus-one packs, five
   per-letter Greek-to-English motions (paper clippings swap, tear-off, flip card, cycle then lock,
   strike and rewrite). **Chosen:** centred written "Midas" (leading), lowercase "midas", small m
   with underline bottom-right as the shortlist; motion: cycle then lock. Brown and purple rejected
   for colour ("purple is the AI colour"), gradients rejected.
5. **Iteration three** (page 05): 24 classy hands, 24 more accents with the big brand nearest each
   hex. Founder's accent shortlist: tomato, cherry, tomato light, tangerine, amber, lemon,
   turquoise, charcoal, chartreuse. Research on who owns which accent: green most crowded, red next;
   turquoise and charcoal had no tech owner. Tomato #FF3B30 chosen first, then the founder asked
   about pure black and white (Uber, Nike, Apple). **Decided:** the shell is black and white, the
   Sidekick tiles are the colour (fixed palette of eight), Tomato light #FF6347 is the third colour
   held in reserve. Dark mode defined now, ships later.
6. **Icon shipped** the same day: written "Midas" in Caveat Bold as a placeholder for the founder's
   own hand, black on white, with dark and tinted variants. The handwriting sheet is still pending;
   when it arrives, trace it, replace the font in `shell/icon-source/`, regenerate, and keep this
   file's section 4 true.

What stays open: the founder's handwriting sheet; where Tomato light first appears; which existing
Reminders tile colour maps to the palette of eight; the first-open touch screen (section 6).
