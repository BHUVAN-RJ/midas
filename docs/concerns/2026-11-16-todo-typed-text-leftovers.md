# Concerns: To-Do typed text, leftovers (2026-11-16)

From the session that built To-Do (2026-10-31) and fixed "a new to-do typed in the row is not
saved" (founder, 2026-11-02; `467a586`, merged `54c801b`). The fix, the new rule 6 in
`docs/MAKE-BUILDER.md` ("Typed text is never lost") and `shell/MidasTests/TodoSidekickTests.swift`
are on main. Four things were left open.

1. **Rule 6 is not checked in the other Sidekicks.** Reminders, Water, care-reminders and every
   Sidekick built since (Money, Sounds, ...) were not checked for the same loss: text typed in a
   field and then tapped away, the keyboard closed, Add tapped again or the page redrawn. Each needs
   the check and a real web view test like `TodoSidekickTests.swift`. Pick up: lead, or the next
   session that touches each Sidekick.
2. **jess may pick the wrong Sidekick for a to-do.** Every account has Reminders and To-Do
   (`e81e6cd`), and both keep `reminder:` records. Which one jess routes "add milk" to was not
   checked. Pick up: whoever works on the jess router next.
3. **Stale untracked To-Do files in the main checkout** (`~/Desktop/Midas/midas`):
   `sidekicks/todo/`, `docs/primitives/todo/`, `docs/briefs/todo-sidekick.md`,
   `docs/mockups/todo-primitive-2026-10-31.html`, `runner/agents/todo.md` and
   `backend/test/todo-*.test.ts`, `backend/test/runner-todo-prompt.test.ts`. All are on origin
   since `299e28e`; the copies here are older. `git pull` on main refuses to overwrite them. Pick
   up: lead, before the next pull on main (delete them; origin has the current ones).
4. **Worktree `midas-worktrees/todo-add-fix` and branch `agent/todo-add-fix`**: merged
   (`54c801b`), clean, no simulator lease, so safe to remove under the 2026-11-02 rule. Pick up:
   lead.
