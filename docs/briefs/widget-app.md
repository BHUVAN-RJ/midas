# Brief: widget-app (app side of widget folders)

Founder plan approved 2026-10-11. Product record: `docs/PRODUCT.md` section 6, "Sidekicks outside the
shell". Research: midas-intel `docs/research/2026-10-11-sidekicks-outside-the-shell.md`. Mockups:
https://claude.ai/artifact/6BigRus6CmZAVKHdk5bbcK (sources in midas-intel `docs/prototypes/widgets/`).

A second agent (`widget-extension`) builds the widget itself at the same time. You build what the
app must do so the widget works. The contract between you is already on main and is fixed:
`shell/Shared/WidgetShared.swift` (App Group id, shared list file, `SharedSidekickList`,
`MidasLink`). Do not change it; if it is wrong, stop and tell the lead.

## Build

1. **Write the shared list.** Every time `SidekickDirectory` has a new list from the server, write
   `SharedSidekickList(sidekicks: entries, savedAt: now)` to `WidgetShared.sidekickListFileURL()`
   (atomic write), in home grid order. If the URL is nil (no App Group), do nothing and do not crash.
   Then call `WidgetCenter.shared.reloadAllTimelines()`. Also write it once at launch from the cached
   list, so a widget works before the first refresh.
2. **Open links.** Register URL scheme `midas` (CFBundleURLTypes in the Midas `info.properties` of
   `shell/project.yml`). Handle incoming URLs in the app (`onOpenURL`): `MidasLink(url:)`;
   `.openSidekick(id)` calls `SidekickRouter.open(sidekickId:)` (it already ignores unknown ids);
   `.home` clears the router path. Anything else is ignored. A link that arrives while signed out
   or before the directory has loaded must not crash; opening it later is not required.
3. **App Group entitlement.** Add `com.apple.security.application-groups` with
   `group.com.bhuvanrj.midas` to `shell/Midas/Midas.entitlements`.

## Files you own

`shell/Midas/SidekickDirectory.swift`, `shell/Midas/MidasApp.swift`, `shell/Midas/ShellServices.swift`,
`shell/Midas/Midas.entitlements`, the Midas target's `info` block in `shell/project.yml` (nothing
else in that file: the other agent adds a target there), new files under `shell/Midas/`, new test
files under `shell/MidasTests/`. Anything else: stop and ask the lead.

## Rules

- `docs/PARALLEL-AGENTS.md` rules for a worktree agent; `CLAUDE.md` for tests (existing tests change
  only through test-guardian). Style: `~/.claude/CLAUDE.md` (named steps, descriptive names,
  comments on non-obvious logic). No words on screen are added by this task.
- Signing: never change the team, bundle id, signing style or anything to get around a signing
  error. If a device build needs the App Group registered in the developer portal, stop and write
  the exact steps for the founder.
- Tests (new files): the writer puts the right list at the right place in order and does nothing
  when the URL is nil (inject the URL or file manager); a directory refresh triggers a write; link
  handling opens a known Sidekick, ignores an unknown one, and `.home` empties the path.
- Done = all suites pass from the worktree root (`scripts/test-all.sh`), work committed on
  `agent/widget-app`. Report results honestly, including failures.
