# Concerns: To-Do widget (2026-11-02)

Founder, 2026-11-02: "these look fine, start creating them" (suggested picks of
`docs/mockups/todo-widget-2026-11-02.html`). Built by the todo-widget agent on branch
`agent/todo-widget` (`6734b14` mockup, `32aa255` shell `planned` source, `89b3953` page, tests,
renders, docs). Not merged. Blueprint: `docs/briefs/todo-sidekick.md` section 6.

Tests on the branch: shell suite 1,177 green, backend 1,372 green plus typecheck, guard 42.
midas-intel not run (the guard hook blocks every runnable form from the worktree; branch does not
touch that repo). `scripts/test-all.sh` itself blocked by the guard hook, suites run one by one.

## Open (for the lead)

- **CONCERNS 25 not updated.** §25 lives only in local-main `fad17e8`, not on this branch. At
  merge: mark the To-Do item done for build 22 and add the two gaps below. Moves to
  `docs/CONCERNS.md` 25; lead session.
- **Gap: no "How To-Do Works"** in the page's "?" menu (To-Do has no help page yet).
- **Gap: plain header divider.** The widget's divider takes no colour; the mockup's accent line
  needs a divider `color` in the shell widget builder.
- **Possible conflict in `docs/WIDGETS.md`** when merging with `fad17e8`: the new "To-Do additions"
  section sits just above "Add to Home Screen".
- **Merge with `agent/todo-add-fix`** (same `sidekicks/todo/index.html`): trial `git merge-tree`
  merged clean on 2026-11-02.
- **Not seen in the app; not deployed.** Needs app build 22 (`planned` source), then a To-Do page
  deploy (`docs/DEPLOY.md`). Check on a Midas Test build: widget sizes, tick from widget, midnight
  carry-over, the "?" Add Widget.
