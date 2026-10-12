# Brief: widget-extension (the Folder widget)

Founder plan approved 2026-10-11. Product record: `docs/PRODUCT.md` section 6, "Sidekicks outside the
shell". Research: midas-intel `docs/research/2026-10-11-sidekicks-outside-the-shell.md`. Mockups:
https://claude.ai/artifact/6BigRus6CmZAVKHdk5bbcK (sources in midas-intel `docs/prototypes/widgets/`,
boards Main, Medium, Large).

A second agent (`widget-app`) makes the app write the shared Sidekick list and handle `midas://`
links at the same time. The contract is on main and fixed: `shell/Shared/WidgetShared.swift`. Do not
change it; if it is wrong, stop and tell the lead. Icons: `shell/Shared/SidekickIcon.swift`
(`SidekickIconView`), the same view the home grid uses. Use it as is.

## Build

1. **Widget extension target** `MidasWidgets` in `shell/project.yml`: type `app-extension`, bundle id
   `com.bhuvanrj.midas.widgets`, sources `[MidasWidgets, Shared]`, entitlements file
   `shell/MidasWidgets/MidasWidgets.entitlements` with App Group `group.com.bhuvanrj.midas`, embedded
   in the Midas app (Midas target dependency). Same team and signing style as the app; iOS 17.0.
2. **One widget, kind `WidgetShared.folderWidgetKind`**, display name "Sidekicks" (was "Folder" until the founder renamed it, 2026-10-11), description
   "Sidekicks on your Home Screen.", families small, medium, large.
3. **Configuration** (`AppIntentConfiguration`, iOS 17): one parameter titled "Sidekicks", an array
   of a `SidekickEntity` (`AppEntity`) whose `EntityQuery` reads the shared list file. At most 4 in
   small, 8 in medium, 16 in large (use the parameter's per-family size if the SDK has it; otherwise
   cut to the limit when drawing). Tile order = the order the person picked.
4. **Default:** nothing picked = the first 4 / 8 / 16 of the shared list, in home grid order.
   Picked ids no longer in the list are dropped.
5. **Layout** per the mockup: 2x2, 4x2, 4x4 tiles; each tile is `SidekickIconView` plus the name
   underneath (11 pt or larger, one line). Each tile is a `Link` to `MidasLink.openSidekick(id).url`;
   the rest of the widget is `widgetURL(MidasLink.home.url)`. Support the accented (tinted, clear)
   rendering mode so tiles stay readable when iOS removes colour.
6. **Empty:** no shared list or an empty one shows "Open Midas" and opens `MidasLink.home`.
7. **Timeline:** one entry, policy `.never`; the app reloads widgets when the list changes.

Put the pure logic (default fill, dropping unknown ids, the per-family limit, turning a picked list
into tiles) in a new file under `shell/Shared/` so `MidasTests` can test it through the app module.

## Files you own

New `shell/MidasWidgets/` folder, new files under `shell/Shared/`, the new target (and the Midas
target's dependency on it) in `shell/project.yml` (nothing else in that file: the other agent edits
the Midas `info` block), new test files under `shell/MidasTests/`. Anything else: stop and ask.

## Rules

- `docs/PARALLEL-AGENTS.md` rules for a worktree agent; `CLAUDE.md` for tests (existing tests change
  only through test-guardian). Style: `~/.claude/CLAUDE.md`. Words on screen: only the four above
  ("Sidekicks", "Sidekicks on your Home Screen.", "Sidekicks", "Open Midas"); `docs/WRITING.md` rules.
- If `RemindersListIcon` (a SwiftUI `Canvas`) does not render in the widget, stop and tell the lead.
  Do not replace it.
- Signing: never change the team, bundle id, signing style or anything to get around a signing
  error. If a device build needs the new App ID or App Group in the developer portal, stop and write
  the exact steps for the founder. Simulator builds and tests must pass.
- Tests (new files): default fill per family, unknown ids dropped, limits 4/8/16, picked order kept,
  empty list gives the empty state, the entity query returns the shared list's Sidekicks from a
  sample file.
- Done = all suites pass from the worktree root (`scripts/test-all.sh`), work committed on
  `agent/widget-extension`. Report results honestly, including failures.
