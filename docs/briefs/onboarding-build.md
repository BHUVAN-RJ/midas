# Onboarding: build brief (founder, 2026-10-31)

**Final, approved by the founder on 2026-10-31** ("this is the onboarding video we needed, let's
finalize this"). The login flow is complete as three steps: animation → sign in → four cards.

What to build: the first-open animation, then the existing name + passkey screen, then the four
teaching cards (settled on main, ac42aef). Design came from the onboarding design agent; this brief
is for the build agent, who wires all three together.

## Order on a new install

1. **First-open animation** (this brief, sections 1–7). Before sign-in. Plays once per install.
2. **Get Started** on its popup opens the welcome screen (`shell/Midas/WelcomeView.swift`: name,
   then passkey; "Sign In" for returning users). Unchanged.
3. **Teaching cards**, right after sign-in: build exactly as `docs/mockups/onboarding-teach-2026-10-31.html`
   (on main since ac42aef, K4, layout T2 unless the founder picks T1). Four cards, each a looping
   demo in the Add Widget demo style: "Edit Any Sidekick" (three-finger swipe down), "Go Back"
   (swipe from the left edge), "Make a Sidekick", "Delete a Sidekick" (press and hold). No Skip;
   "Next" between cards, "Continue" on the last. Every other word is in that mockup; copy it as-is.
   Not redesigned here.

The founder: "this will come first and come only once per user, and then we will ask them to sign
in." Before sign-in the app does not know who the user is, so "once per user" is built as once per
install: a `UserDefaults` flag set when Get Started is tapped; never shown again once set, and never
shown to anyone already signed in (an existing session skips it, including users who update from a
build without onboarding). A returning user on a new phone sees it once. The teaching cards follow
the same rule: once, right after the first sign-in on that install.

## The chosen mockup

`docs/mockups/onboarding-blackhole-v9-2026-10-31.html` (branch `agent/onboarding-design`). Open it,
press and hold the phone. Its default settings are the approved ones (3 s preset, Silk). The Tune
sliders are for the founder's testing only; build the defaults. History, not to build:
v2–v8, `-swirls-`, `-tails-`, `-variants-` (the pick pages for rounds 6, 9 and 10).

What HTML could not show and the build must do natively: iOS springs, haptics, safe areas,
Reduce Motion, real Liquid Glass. The black hole in the mockup is a WebGL shader; port it to a Metal
shader (SwiftUI `.layerEffect` / `.colorEffect` with `ShaderLibrary`, or an `MTKView`), keeping the
numbers in section 4.

## 1. Every word on screen

| Where | Words | Type |
|---|---|---|
| Waiting screen, centre | Touch and Hold | SF Pro 17 semibold, `ink-2`, breathes (opacity 0.4–1.0, 2.9 s period) |
| Under each icon on the grid | Reminders, Water, Habits, Money, To-Do, Study, Meds, Sleep | SF Pro 12 regular (`.caption`), `ink` |
| Popup, line 1 | Midas | The hand (Caveat Bold, `shell/icon-source/`), 76 pt, `ink` |
| Popup, line 2 | The personal touch your apps needed | SF Pro 17 regular, `ink-2`; no full stop (founder, final) |
| Popup, button | Get Started | SF Pro 17 semibold, `paper` on an `ink` capsule, 52 pt high |

Nothing else: no skip, no hint text. The status bar is the system's.

Open wording point: the founder said "your app needs" once (round 2); the line keeps the
2026-10-11 wording "your apps needed" and he has not changed it since. Ask before shipping.

## 2. The waiting screen

- `paper` background (white light, `#111111` dark), "Touch and Hold" in the centre.
- Eight "before" icons float slowly (drift and a little spin), each a body with mass (section 5).
- "Before" look: **grey, flat**, a plain rounded square (corner 16%, not continuous), chunky filled
  glyph. Light: tile `#E4E4E4`, glyph `#9A9A9A`. Dark: tile `#2A2A2A`, glyph `#6A6A6A`.
- Icons, glyphs and masses: Reminders bell 1.2, Water drop 0.85, Habits ring 1.0, Money card 1.35,
  To-Do check 0.9, Study book 1.25, Meds pill 0.8, Sleep moon 1.1. Start spots (pt):
  (92,168) (300,132) (214,272) (74,352) (318,360) (116,620) (300,650) (206,760).

## 3. The sequence (3 s preset; touch to grid is about 2.5 s)

| Phase | Starts | Lasts | What happens |
|---|---|---|---|
| Hold | finger down | 1.40 s | Hole opens under the finger and follows it (trails it: `1 - e^(-16 dt)`). Grows 6 → 16 pt. Icons pulled in on orbits; screen darkens; screen shakes up to 3 pt. |
| Full | all icons in | 0.18 s | Hole tightens 12%, trembles (5% pulse at ~7 Hz), shake 4.2 pt. |
| Blast into place | | 0.78 s (+0.02 s stagger each) | Hole collapses, white flash, shockwave ripple. Every icon flies **straight from the hole to its own grid slot** (founder, final: no wandering first), fast out of the blast and slowing into place (ease-out quart), spinning upright (from up to ±1.2 rad) as it goes, as grey glass. Each takes its colour over 0.25 s when within 10 pt of its slot, and keeps it. Shake kick 6.6 pt, gone in 0.35 s. Labels fade in over 0.3 s after. |
| Popup wait | icons in place | 0.90 s | Nothing moves. |
| Popup glass | | 1.40 s | Glass slab fades and grows 98.5% → 100%, slow in and out (sine). |
| "Midas" | popup + 0.49 s | 0.70 s | Fades in and rises 6 pt (sine in-out). |
| Line | "Midas" done + 0.35 s | 0.70 s | Fades in and rises 4 pt. |
| Get Started | line done + 0.45 s | 0.90 s fade | Fades in and rises 6 pt, ease in-out. |

Other presets the founder can test (hold / full / blast-into-place / popup glass): 2 s 0.85/0.12/0.62/1.2,
4 s 2.0/0.22/0.92/1.6, 5 s 2.6/0.25/1.06/1.8. The word beats (0.35 s, 0.45 s) are the same in all. Ship 3 s.

**Letting go early:** the hole shrinks away (`e^(-9t)`, 0.6 s), icons inside are spat back out
(320 pt/s, random directions), grey as before, the screen lightens, "Touch and Hold" returns.
Nothing else changes; holding again starts over.

## 4. The black hole (Silk)

Ray traced per pixel, face-on, in units of the horizon radius rs:

- Scale: `rs = holeRadius / 2.6` (the shadow is 2.6 rs). Hole radius 16 pt at full.
- Each pixel near the hole (impact < 20 rs) sends a ray from z = −20 rs, bent by
  `a = −1.5 h² r / |r|⁵` (h = impact × 1), step `clamp(0.09 r, 0.03, 1.2)`, up to 220 steps.
  Falls inside 1 rs: black. Crosses the disc plane between 2.7 and 7 rs: add gas light (below).
  Escapes: sample the screen where its outgoing line meets the plane 6 rs behind (lensing).
  Beyond 20 rs: weak bending, `q − q̂ · (2/|q|) · 6`.
- **Disc:** inner edge 3 rs (hard: smoothstep 2.96–3.1), outer edge 7 rs (6.3–7). Spin per radius
  `t · (0.6 + 1.6 charge) · 9 · r^−1.5` (Keplerian: inner gas laps outer gas).
- **Silk texture:** 4-octave value noise on `(ln r · 14 + turn · 2.2, turn · 5.2)` where
  `turn = angle + spin`, blended with its copy one turn back by `(angle + π)/2π` so there is no seam;
  threads = `smoothstep(0.50, 0.56, noise)`; density = `0.04 + 1.2 · threads`. Hairline white threads,
  nothing else.
- **Light:** thin-disc temperature `T = (3/r)^0.75 (1 − √(3/r))^0.25`, brightness `3.2 (T/0.49)²`,
  redshift `√(1 − 1/r)`, flicker `0.88 + 0.24 · noise(r · 1.3, t · 2.6)`, times `0.35 + 0.65 charge`.
  Colour: white, a touch cool (`#DBE0EB`) where dim. No colour of its own (DESIGN.md: no gold).
- **Darkening:** the screen goes toward `#020202` round the hole, `charge^0.9`, Gaussian radius
  120 → 560 pt with charge, max 98.5%.
- **Whirlpool:** the screen round the hole turns by `1.2 · charge · e^(−d/120 pt)` radians.
- **Burst:** white flash `0.9 · e^(−9t)`, falloff `e^(−d/140 pt)`; shockwave ring travelling
  1,500 pt/s, amplitude 34 pt decaying `e^(−3.2t)`, Gaussian width 30 pt.
- Every press gets a new random seed for the texture; the shape is always the same.

## 5. Physics (fixed 1/120 s step)

- Pull: `a = 2200 (0.25 + 3 c²) / mass · 100 / (d + 30)` toward the hole, plus a swirl term at
  0.42× that, sideways. On press each icon gets a sideways kick `70 / √mass` pt/s so it falls in on
  an orbit. Drag `1 + 2.4 c`. From charge 0.6 the hole wins outright (lerp toward it,
  `((c − 0.6)/0.4)² · 0.06` per step) so the timing always holds. An icon is in at 1.1× hole radius.
- Near the hole an icon shrinks to 30% and stretches toward it (1 + 1.4 n², n = nearness over 130 pt).
- Icons are solid: overlapping ones push apart weighted by mass, restitution 0.8.
- Blast into place: no physics; each icon's position is `lerp(hole, slot, easeOutQuart(p))`,
  p = (t − index · 0.02 s) / 0.78 s, rotation `r0 · (1 − eased)`, size back to 100% the same way.

## 6. The "after" icons and the grid

- Grid as the shell's home (`SidekickHomeLayout`): 60 pt icons, 4 columns, 20 pt sides, 8 pt
  column gap; icon centres at x = 62.25, 154.75, 247.25, 339.75 and y = 190, 293.
- Tile: continuous corners (22.5%), each app its own Midas tile colour (DESIGN.md 2.3, the
  founder's pick "Eight"): Reminders Tomato, Water Turquoise, Habits Lemon, Money Chartreuse, To-Do
  Sage, Study Amber, Meds Cherry, Sleep Charcoal; mark `ink` or `paper` per the table. Flat colour,
  no gradient.
- Glyph in two layers (WWDC25 "Say hello to the new look of app icons": bold, rounded, layered):
  a solid layer in the mark colour and a "glass" layer in the mark colour at 42%. Bell + badge,
  drop with water in its lower half, streak ring three quarters done, two cards (back one tilted
  −14° in glass, magnetic stripe cut out), checkbox in glass with a bold tick, open book (left page
  solid, right glass), capsule (half and half, −45°), crescent with two glass stars. A white sheen
  on the top of every shape (38% → 0 over the top 40%), the glyph casts a small shadow (blur 5%,
  y 2.2%), and the tile's edge catches light at top-left (85%) and bottom-right (45%). Exact paths:
  `polishedLayers()` in the mockup. Build as Icon Composer-style layers or a Canvas; these icons
  exist only in this animation.
- "Grey glass" in flight: the same icons in the grey of section 2 until they land.

## 7. The popup

- A floating glass slab in the middle of the screen: x 24, y 297, 354 × 252 pt, corner 44 (on iPhone
  16 Pro; centre it and keep 24 pt sides on other sizes). Its top edge lies over the second row of
  icons so the glass is seen bending them.
- Native: iOS 26 `.glassEffect(.regular)` in that rounded rectangle, made **less see-through** as
  the founder asked: the mockup washes the frosted scene 72% toward white (light) / 74% toward
  `#1C1C1F` (dark). Match that look: glass with a paper tint at about 70%. Soft shadow below.
- Content top-down: 34 pt padding, "Midas", 4 pt, the line, then the button pinned 22 pt from the
  bottom with 22 pt sides.
- Get Started → welcome screen (name, passkey). The popup and grid do not animate away in the mockup;
  default: cross-fade to the welcome screen over 0.35 s.

## 8. Haptics (default; the founder has not felt these yet)

Core Haptics, one continuous event while holding: intensity `0.15 + 0.85 · charge^1.6`, sharpness
0.2 → 0.6 with charge; at full, intensity 1. At the burst: one transient, intensity 1, sharpness 0.8,
and the continuous event stops. Letting go early: stop at once, no tap. Nothing on landing.
Ask the founder to feel it on the iPhone and tune.

## 9. Reduce Motion (default; not shown to the founder)

With Reduce Motion on: no hole, no physics, no shake, flash or ripple.
- The eight grey icons sit still in their grid slots; "Touch and Hold" in the centre.
- Touch (a tap is enough): "Touch and Hold" fades out, each icon cross-fades grey → colour in place
  (0.3 s, 0.04 s stagger), labels fade in, then the popup fades in (0.6 s, no scale), "Midas" and the
  line with it, "Get Started" 0.6 s later.
- One light haptic tap on touch.

VoiceOver: the waiting screen is one element, "Touch and Hold"; activating it runs the Reduce Motion
version. The popup's button is "Get Started".

## 10. Done when

- First open on a fresh install of **Midas Test** plays the animation; later opens and the welcome
  screen after sign-out do not.
- 3 s timings match section 3 (touch to grid about 2.5 s; Get Started starts to show about 6.1 s after touch).
- Light and dark both match the mockup; Reduce Motion and VoiceOver paths work.
- A test checks the once-per-install flag and the Reduce Motion branch (testing discipline:
  `scripts/test-all.sh`).
- Teaching cards appear right after sign-in, as the teach mockup.

Open for the founder before shipping: the tagline wording (section 1), haptics feel (section 8),
Reduce Motion version (section 9).
