# Look (TD-LOOK)

The look is how the whole page reads before anything is touched: the page style, light and dark, the accent and list colours, text size, density and font. Six patterns, from research `LOOK-ANALYSIS.md` sections 1.1, 1.7 and 1.8 and the group files `look-group-a.md` (A), `look-group-b.md` (B), `look-group-c.md` (C) and `look-group-d.md` (D). Each pattern is one field of `settings:self` (`records.md` section 3), and the person changes it from the page in TD-SET-01, with no rebuild. Labels: [C] confirmed on a primary source or an inspected screenshot; [R] reported, or pixel-sampled from a marketing screenshot; [U] not in the research (a starting value for the prototype that the founder or a device check settles). Sizes are in pt (1 CSS px in the Sidekick's WKWebView). Colours are tokens (CSS custom properties). They are defined in TD-LOOK-01 and TD-LOOK-02 and move to `recipe.md` when it is written. "Checklist N" is item N of research `group-d.md` section 6, "P-new-N" is item N of `look-group-d.md` Part 2, and "L1"–"L6" are `LOOK-ANALYSIS.md` section 4. Screenshot names are files in research `shots/` (`LOOK-ANALYSIS.md` section 6). Tests assume a fixed clock and a seeded store.

Rules every look follows:
- No look, layout or gesture changes unless the person chooses it (L3; leave reason 1, "redesigns that move things").
- No pop-ups, toasts or banners over the list except the undo toast of TD-DONE-06 (L6).
- Glass (a blurred `backdrop-filter` material) only on the control layer (floating +, tab bar, top buttons), never on rows (HIG Materials "Don't use Liquid Glass in the content layer", "sparingly" [C]).
- No look is locked or paid (leave reason 5: Clear's themes and Tiimo's emoji moved behind a paywall).

| ID | Name | Tag | Default variation |
|---|---|---|---|
| TD-LOOK-01 | Page style | core | `look: paper` (Things/Todoist white paper) |
| TD-LOOK-02 | Light and dark | core | `theme: auto` (follows the system) |
| TD-LOOK-03 | Accent and list colour | core | `accent: #2F6FEB`; a list's own `color` wins inside that list |
| TD-LOOK-04 | Text size | core | `textSize: m` |
| TD-LOOK-05 | Density | on request | `density: comfy` |
| TD-LOOK-06 | Font | on request | `font: system` |

---

### TD-LOOK-01 Page style

**Tag:** core (love 1 "clean and calm", ~25 quotes; leave reason 7 "looking dated"). **Variations:**
- `paper`: white page, whitespace, no row separators, hairlines only under headings, colour only for meaning. Things, Todoist, Google Tasks.
- `notebook`: ruled paper, a hairline under every row, highlighter pills behind titles, tick at the row's end, grotesk sans. Tweek.
- `soft`: off-white canvas, pastel tints, serif display heading, white rounded cards with a soft shadow, a round emoji badge per task. Tiimo.
- `wallpaper`: per-list solid colour or full-screen photo, a large white bold title, white card rows floating on top. Microsoft To Do.
- `heat`: full-bleed rows of equal height, coloured by position from red to amber, no checkbox, no chrome. Clear.
- Not offered (on request): Superlist's decorated page (cover image, squiggle dividers; 3 loves, 1 "waste of space"); TickTick's grouped cards on a tinted background ("cluttered" said 3 times).

**Default variation:** `paper`.

**What it is.** One setting that sets the page's whole surface: the background, how rows are separated, and where colour appears. The other TD-LOOK and TD-ROW settings apply on top of it.

**Anatomy.** Tokens, light mode (dark is in TD-LOOK-02):

| Token | paper | notebook | soft | wallpaper | heat |
|---|---|---|---|---|---|
| `--bg` | #FFFFFF [R, Things] | #FFFFFF ("white paper" [C]) | #FAF7F2 [U] (off-white [C]) | the list's `wallpaper`; `none` = `--accent` solid [U] | #000000 under the done area [C clear_iphone_1] |
| `--surface` (row card) | none, rows sit on `--bg` [C] | none | #FFFFFF, radius 16, shadow 0 2 8 rgba(0,0,0,.06) [U] | #FFFFFF at 92% opacity, radius 10 [U] | the row's heat colour |
| `--ink` (titles) | #1C1C1E [U] (black [C]) | #1C1C1E [U] | #1C1C1E [U] | #1C1C1E on cards; list title #FFFFFF [C] | #FFFFFF bold [C] |
| `--ink-2` (meta, struck text) | #8A8A8E [U] (grey [C]) | #9A9A9A [U] (light grey [C]) | #8A8A8E [U] | #8A8A8E [U] | rgba(255,255,255,.75) [U] |
| `--hair` | #E5E5EA [U], under headings only | #E5E5EA [U], under every row [C] | none | none | none |
| `--panel` (calendar or info card) | #F2F4F5 [R, Things calendar card] | #F2F4F5 | #FFFFFF | #FFFFFF | n/a |
| `--today` | #1F9D55 [U] (green [C, Todoist]) | same; the today header and rule use `--accent` (blue in Tweek [C]) | same | same | n/a |
| `--late` | #E03131 [U] (red [C, Things, Reminders, Todoist]) | same | same | same | n/a |

- Heat rows: `--heat-1` #D8131D (title row), `--heat-2` #DD2B1D, `--heat-3` #D75B1B, `--heat-4` #F2A51E [R, Clear sample]. Row n of N interpolates from `--heat-2` to `--heat-4` by position. With more than 10 rows the steps compress, so the last open row is always `--heat-4` [U]. `--tick-green` #00B612 [R] (TD-DONE-01).
- Notebook pills (TD-ROW-03): pink #FFD6E0, blue #D6E8FF, green #D9F2D0, yellow #FFF1B8 [U] (pink, blue, green and yellow pills [C tweek_1]).
- Soft tints for sections and badges: butter #FFF3C4, blush #FBE3E1, lilac #ECE4F7, sage #E3EEDC [U] (the four tints are [C], the hex values [U]).
- List title: 34 pt bold [U] (large bold title [C], all apps). Section heading: 15 pt semibold [U]. Row title: 17 pt regular [U] (TD-LOOK-04 scales all three). Side gutter: 16 pt [U].
- Soft: list or day title in serif (Tiimo display serif [C]) when `font` is `system`; any other `font` wins (TD-LOOK-06). Part-of-day sections show as tinted pill chips (TD-DAY-02).
- Wallpaper: a list with `wallpaper: none` shows its `color` as a solid background (Microsoft To Do solid colours [C]); a named gradient token fills the page; a `file:` ref shows the photo, `object-fit: cover`, fixed behind the scrolling rows. The list title is white bold on the wallpaper.
- Heat: one large bold line per row, equal height (= density row height), no checkbox (pairs with TD-ROW-01 `none`), and the done area at the bottom is black with grey struck text [C].
- Control layer in every look: the floating + (TD-ADD) and any tab bar (TD-NAV) float above the content, and the content scrolls under them (HIG [C]).

**States.**
- No lists yet: the look's `--bg` with the empty state of TD-SET-05.
- Wallpaper photo still loading: the list's `color` shows first, then the photo fades in over 200 ms [U].
- Wallpaper `file:` ref whose file is gone: renders as `none`, and the record is not rewritten.
- Heat with 1 open row: that row is `--heat-2`. Heat with 30 rows: the gradient runs top to bottom.
- Look changed: applies at once, with no reload, and keeps the scroll position.
- Offline: every look is local; nothing is fetched.

**Interactions.** The look changes only from TD-SET-01, where each option shows a live preview. Change: a 200 ms cross-fade [U]; instant under reduced motion. Choosing a look changes only `look`. The "Heat" preset (TD-SET-02) also sets `checkbox: none` and `swipeRight: complete`; the look alone never changes other fields (L3). Heat keeps a visible + and back control, since Clear 2.6 added visible back and add buttons after users could not find their way [C].

**Words.** Setting "Look": "Paper", "Notebook", "Soft", "Wallpaper", "Heat". Per-list sheet: "Wallpaper", "Color", "Photo", "None".

**Data.** Reads `settings:self.look` (missing record or field → `paper`), `list:<id>.wallpaper` (`none`, a gradient token, or a `file:` ref) and `list:<id>.color`. Writes `settings:self.look` (through TD-SET-01) and `list:<id>.wallpaper`.

**Needs.** Page alone. Photo wallpaper: shell has it (`store.putFile`, `store.fileUrl`). Picking a photo through `<input type="file" accept="image/*">` inside the shell's WKWebView: [U], device check.

**Edge cases.**
- L3: no look change without the person choosing it.
- L6: no pop-ups over the list in any look.
- Checklist 11: a look change never hides or filters a row.
- Checklist 17: an empty list reads as empty in every look.
- P-new-27: the list renders before the wallpaper photo loads.
- Leave reason 5: no look is locked.
- Text on a photo wallpaper sits on white cards, so contrast does not depend on the photo [U].

**Tests.**
- Given no `settings:self` record, when the page opens, then the root has `data-look="paper"` and the list background computes to #FFFFFF in light mode.
- Given `look: paper`, then no row has a bottom border; given `look: notebook`, then every row has a 1 px bottom border in `--hair`.
- Given `look: heat` with 5 open rows, then row 1's background is `--heat-2`, row 5's is `--heat-4`, and the green channel rises strictly from row 1 to row 5.
- Given `look: heat`, then the + button and the back control are visible elements, not gesture-only.
- Given a list scrolled so to-do 30 is at the top, when `look` changes to `soft`, then to-do 30 is still at the top and a page-memory marker set before the change still exists (no reload).
- Given `list:groceries.wallpaper` is a `file:` ref whose file is missing, then the page renders as `none` and the record still holds the ref.
- Given any look, then no row element has a `backdrop-filter`.

**Evidence.** `LOOK-ANALYSIS.md` 1.1: "clean" Things 7 quotes, Todoist 5, Google Tasks 4; Tweek 5 ("as close to a paper planner as it gets"); Tiimo 4 ("not overwhelming/overstimulating"); Microsoft To Do 3 ("I've customized the backgrounds for all my lists"); Superlist 3 plus 1 "waste of space"; Clear loved for feel, hated for discoverability; TickTick "cluttered" 3; Any.do "ugly gradients from 2006" and Google Tasks "old looking" (leave reason 7). Love 6 "a distinct identity". Things glass "breaks the magic… looks tacky" (A, 2025-09-17). Screenshots: `things_iphone_2.png`, `tweek_1.jpg`, `tiimo_3_crop.jpg`, `mstodo-1.png`, `clear_iphone_1.png`, `superlist_3_crop.jpg`, `ticktick-1.png`.

---

### TD-LOOK-02 Light and dark

**Tag:** core (L5 "dark mode is designed, not inverted"). **Variations:**
- `auto`: follows the system. Todoist "Auto Dark Mode" [C].
- `light`, `dark`: fixed. TickTick light/dark toggle ("I love that you can toggle", R).
- Blackout (true black): Superlist offers light, dark and "blackout" [C]; Todoist declined a true-black theme [C]. On request.

**Default variation:** `auto`.

**What it is.** Each look has its own dark version, designed for that look rather than produced by inverting colours.

**Anatomy.** Dark tokens:

| Token | paper | notebook | soft | wallpaper | heat |
|---|---|---|---|---|---|
| `--bg` | #242830 blue-slate, not black [R, Things] | #000000 [C, Tweek dark] | #1E1D1B [U] | the wallpaper, unchanged | rows unchanged; done area #000000 |
| `--surface` | none | none | #2A2927 [U] | #1C1C1E at 92% [U] | row colour |
| `--ink` | #FFFFFF [C, Things "text is white"] | #FFFFFF [C] | #F2F0EC [U] | #FFFFFF | #FFFFFF |
| `--ink-2` | #9AA0AA [U] | #8A8A8E [U] | #A09C96 [U] | #A0A0A5 [U] | rgba(255,255,255,.75) [U] |
| `--hair` | #3A3F4A [U] | #2C2C2E [U] | none | none | none |
| `--panel` | #2E333C [U] | #1C1C1E [U] | #2A2927 [U] | #1C1C1E [U] | n/a |

- Headings keep the accent in dark (Things "Headings stay blue" [C]).
- Notebook keeps the same bright marker pills in dark [C, Tweek].
- Soft pastel tints drop to 30% opacity on the dark canvas [U]; Tiimo's dark look is not described in the research.
- Each look keeps its identity in dark: TickTick's theme vanishing in dark is a complaint ("if I switch to the dark theme my greenery theme disappears", D).

**States.** System appearance changes while the page is open: the page follows within one frame (a `matchMedia('(prefers-color-scheme: dark)')` change listener). The switch never shows a toast (Todoist's theme toast "covers tasks in dark mode", D).

**Interactions.** Setting only, no gesture. Colours change over 200 ms [U]; instant under reduced motion.

**Words.** Setting "Appearance": "Automatic", "Light", "Dark".

**Data.** Reads and writes `settings:self.theme` (missing → `auto`).

**Needs.** Page alone, through `prefers-color-scheme`. Whether the shell's WKWebView passes the system appearance through to the page is [U]; device check.

**Edge cases.**
- L5: no CSS `filter: invert`; every look has its own token set.
- L6: no toast on a theme switch.
- Contrast of `--accent` #2F6FEB on #242830 is unmeasured [U]; check it at build.

**Tests.**
- Given `theme: auto` and a dark system, then `look: paper` computes the background #242830 and titles #FFFFFF.
- Given `theme: light` and a dark system, then the background is #FFFFFF.
- Given `theme: auto`, when the system switches to dark with the page open, then the background changes without a reload and no toast element appears.
- Given `look: notebook` and `theme: dark`, then a pink pill's background equals its light-mode value.
- Given any look in dark, then no element has a computed `filter` containing `invert`.

**Evidence.** Things "a finely tuned Dark Mode" (vendor claim, A). Todoist "only one dark mode" 1, "moonstone in dark mode would be perfection" 1, "Love the new Dark Mode!" 1; TickTick toggle loved 1, theme lost in dark 1 (D 1.6). D pattern table "Dark mode + themes": 4 loved, 3 asks. Screenshot: `todoist-macstories-liquidglass-2025.jpg` (light and dark side by side). Things dark is `things_iphone_7.png`, in group A's folder, not in `shots/`.

---

### TD-LOOK-03 Accent and list colour

**Tag:** core (love 3 "make it mine", ~12 quotes; leave reason 5 paywalled looks). **Variations:**
- Reminders: a list's colour carries through its title, its +, its tile and its checkbox [C].
- Microsoft To Do: the list's theme colour fills the checkbox and tints the rows; 7 colour dots [C].
- Todoist: a theme recolours the add button, the accents and the selected tab, while rows stay neutral; 4 free themes and 4 Pro [C].
- TickTick: 40+ themes. Tweek: about 20 swatches plus a custom HSV picker and a hex field [C].
- Clear: themes paywalled after users had unlocked them (leave reason).

**Default variation:** `accent: #2F6FEB`, with rows neutral as in Todoist. Inside a list whose `color` is set, that colour replaces the accent, as in Reminders.

**What it is.** One colour for the page's own controls, plus an optional colour per list that takes over inside that list.

**Anatomy.**
- The accent (or the list colour, inside that list) is used for: the + button fill, the done checkbox fill (TD-ROW-01), the selected tab or segment, the text caret, links, the list title (Reminders shows its title in the list colour [C]) and the notebook today header and rule.
- Rows, titles and meta lines never take the accent (Todoist "Rows stay neutral" [C]).
- Smart lists (Today, Upcoming, Logbook): the page accent for controls; each row's done fill uses that row's list colour [U].
- Picker (in TD-SET-01 for the accent; in the list sheet for a list): 11 swatches, 36 pt circles 8 pt apart [U]: #2F6FEB blue, #E03131 red, #F2994A orange, #F2C94C yellow, #27AE60 green, #2BB3A8 teal, #56CCF2 sky, #F178B6 pink, #A0785A brown, #6B7280 graphite, #1C1C1E black [U]. Then "Custom", which opens a hex field and `<input type="color">` [U]. The selected swatch has a 3 pt ring [U].
- Text on the accent is #FFFFFF, or `--ink` when the accent's relative luminance is above 0.6 [U].

**States.**
- A list with `color: null` uses the accent.
- A stored colour that is not a valid 6-digit hex renders as the accent, and the record is not rewritten.
- Changing the accent never rewrites any list's `color`.

**Interactions.** Tap a swatch: applies at once, and the sheet stays open. The hex field applies on a valid `#RRGGBB`.

**Words.** "Accent", "Color", "Custom", "Hex".

**Data.** Reads and writes `settings:self.accent` (missing → `#2F6FEB`) and `list:<id>.color`.

**Needs.** Page alone.

**Edge cases.**
- Leave reason 5: every colour is free.
- L3: the accent changes only when the person picks one.
- Contrast: white or `--ink` text on the accent, as above.

**Tests.**
- Given no `settings:self`, then the + button's background is #2F6FEB.
- Given `list:groceries.color` #27AE60, then inside Groceries the + fill and the list title are #27AE60, and in Inbox the + fill is #2F6FEB.
- Given `list:x.color` "zzz", then the list renders with the accent and the record still holds "zzz".
- Given a list with its own colour, when the accent changes to #E03131, then that list's + is still its own colour.
- Given `accent: #F2C94C`, then the + glyph is `--ink`, not white.
- Given a row title, then its colour is `--ink` for any accent.

**Evidence.** Love 3, ~12 quotes. Reminders "I love that I can change the colors and symbols" 1 (A); Microsoft To Do backgrounds 3 (B); TickTick "the pink one is so cute" 1, "customize the colors for free" 1 (B); Todoist "hex code colors" ask 1 (B); Clear paywalled theme 2 (A, 2026-06-27 and 2026-10-05). Screenshots: `reminders_iphone_7.png`, `mstodo-1.png`.

---

### TD-LOOK-04 Text size

**Tag:** core (L4 "text size can change and titles stay readable"). **Variations:** no app in the research is praised for this; it is asked for in Todoist ("different font SIZES"), TickTick and Reminders. Tiimo's OpenDyslexic option belongs to TD-LOOK-06. Values `s`, `m`, `l`, `xl`.

**Default variation:** `m`.

**What it is.** One size for all the page's text, with every row growing to fit.

**Anatomy.** All values [U]:

| Part | s | m | l | xl |
|---|---|---|---|---|
| Row title | 15 | 17 | 20 | 23 |
| Meta line | 12 | 13 | 15 | 17 |
| Section heading (semibold) | 14 | 15 | 17 | 19 |
| List title (bold) | 30 | 34 | 36 | 38 |
| Checkbox drawn size | 20 | 22 | 24 | 26 |

- The checkbox hit area stays at least 44 × 44 at every size [U].
- Row height comes from the content, never a fixed height.

**States.** Long titles wrap (TD-ROW-05) and are never cut off by a size change. At `xl` with `density: compact`, rows grow.

**Interactions.** Setting only. Applies at once; the to-do at the top of the screen stays at the top.

**Words.** Setting "Text Size": "Small", "Medium", "Large", "Extra Large".

**Data.** Reads and writes `settings:self.textSize` (missing → `m`).

**Needs.** Page alone. Following the iOS Dynamic Type setting from inside the page (`font: -apple-system-body`) is [U]; device check.

**Edge cases.**
- L4: titles stay readable at every size.
- P-new-29: a size change never cuts off a name that fitted before.
- Checklist 56: long text is kept in full.
- Leave reason 7: "tiny fonts" (Superlist, Any.do).

**Tests.**
- Given `textSize: xl`, then a row title computes font-size 23px and a meta line 17px.
- Given a 40-character title that fits on one line at `m`, when `textSize` becomes `xl`, then the row shows the whole title (no ellipsis; `scrollHeight` equals `clientHeight` on the title element).
- Given `textSize: s`, then the checkbox hit rectangle is at least 44 × 44.
- Given the list scrolled to to-do 20, when `textSize` changes, then to-do 20 is still the first visible row.

**Evidence.** TickTick "new default smallest font size is too big… Half of my list names or tasks are now cutoff" 2★ 2026-05-17; Todoist "different font SIZES" 3★ 2025-03-28; Reminders "No font size option for desktop" 5★ 2026-10-04 (D 1.6); Superlist "The font size… is tiny" (C); Any.do "INCONSISTENT FONT SIZE" (C). No screenshot.

---

### TD-LOOK-05 Density

**Tag:** on request. No checklist item asks for a density switch; the default spacing is what satisfies P-new-25. **Variations:**
- `comfy`: Any.do rows of about 52 pt [R]; Things 3.22 "wider spacing that feels a bit more relaxed" [C].
- `compact`: TickTick "dense but even" [C].

**Default variation:** `comfy`.

**What it is.** How much room each row gets.

**Anatomy.** All values [U] except the 52 pt row height:
- `comfy`: row minimum height 52 pt [R, Any.do], vertical padding 12 pt, gap between card rows (soft, wallpaper) 8 pt.
- `compact`: row minimum height 44 pt, vertical padding 8 pt, card gap 4 pt.
- Side gutter 16 pt in both. Checkbox hit area 44 × 44 in both, and never overlapping the next row's hit area.
- Heat: every row has the density's minimum height (equal-height rows [C]).

**States.** Compact with `textSize: xl`: rows grow past the minimum.

**Interactions.** Setting only; applies at once, keeping the scroll anchor.

**Words.** Setting "Density": "Comfortable", "Compact".

**Data.** Reads and writes `settings:self.density` (missing → `comfy`).

**Needs.** Page alone.

**Edge cases.**
- P-new-25: the tick target is spaced so a one-handed grip does not hit the wrong row.
- View P3: TickTick widget rows "too close together", which led to wrong check-offs.
- Checklist 49: mis-ticks stay undoable (TD-DONE-06).
- Any.do "poor item spacing" (leave reason 7).

**Tests.**
- Given `density: comfy`, then every one-line row is at least 52 pt tall; given `compact`, at least 44 pt.
- Given `compact` and two adjacent rows, then their checkbox hit rectangles do not intersect.
- Given `compact`, when a tap lands 2 pt below row 1's hit rectangle, then row 2 or nothing toggles, never row 1.

**Evidence.** Any.do "poor item spacing" 2★ 2026-06-22 (C); TickTick widget rows "too close together" (group-d view P3); Things widget "cramped" 1 (A); Google Tasks widget "Too much white space" 1 (D). Screenshots: `anydo_2.jpg`, `ticktick-1.png`.

---

### TD-LOOK-06 Font

**Tag:** on request. **Variations:**
- `system`: SF Pro; almost every app in the research [C].
- `serif`: Tiimo pairs a high-contrast display serif for day names and dates with a sans body [C].
- `rounded`, `mono`: no app in the research [U].
- OpenDyslexic: Tiimo offers "Default or OpenDyslexic" [R]. On request; it needs a bundled font file [U].
- Tweek uses a grotesk sans [C]; `system` stands in for it.

**Default variation:** `system`.

**What it is.** The typeface family of the page.

**Anatomy.**
- `system`: `-apple-system, system-ui` for everything.
- `serif`: `ui-serif` (New York) for the list title, section headings and day headings; rows and meta stay `system` (the Tiimo pairing).
- `rounded`: `ui-rounded` for everything. `mono`: `ui-monospace` for everything.
- That WebKit maps these generic families to Apple's fonts is not in the research [U]; device check.
- Weights: list title 700, section heading 600, row title 400, meta 400 [U]. Things: large bold titles, regular rows, small grey meta [C]. Tiimo: semibold task titles [C].

**States.** Unknown value or unavailable family: falls back to `system`.

**Interactions.** Setting only; applies at once.

**Words.** Setting "Font": "System", "Serif", "Rounded", "Mono".

**Data.** Reads and writes `settings:self.font` (missing → `system`). With `look: soft` and `font: system`, headings are serif (TD-LOOK-01).

**Needs.** Page alone. System fonts only, so nothing is downloaded (bundle rules, `PRODUCT.md` section 5).

**Edge cases.** L4 (together with TD-LOOK-04).

**Tests.**
- Given `font: serif`, then the list title's computed `font-family` starts with `ui-serif` and a row title's does not.
- Given `font: mono`, then a row title's `font-family` starts with `ui-monospace`.
- Given `font: "comic"`, then the page renders `system`.

**Evidence.** Tiimo serif is part of "beautiful" (0 direct quotes, C); Tweek "The simplistic style and font on this app is enough to satisfy me" 1 (C); Todoist "more options in colors and fonts" 1 (B); Clear "+ 100s of fonts" (marketing, A). Screenshots: `tiimo_3_crop.jpg`, `tweek_1.jpg`.

