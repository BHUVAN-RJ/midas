# Parallel agents

How several Claude sessions work on this repo at once without overwriting each other.

One task = one git worktree = one branch = one Herdr workspace. A worktree is a second folder
of the same repo, on its own branch. Agents in different worktrees cannot see each other's
unfinished edits; their work meets only when a branch is merged into `main`.

## Layout

| What | Where |
|---|---|
| Main checkout (`main`, the lead session) | `~/Desktop/Midas/midas` |
| Task worktrees | `~/Desktop/Midas/midas-worktrees/<task>` |
| Task branches | `agent/<task>` |

`<task>` is a short kebab-case name, e.g. `sidekick-runtime`, `auth-tests`. Worktrees live
outside the repo folder, so nothing needs to be gitignored.

## Lead session: start a parallel agent

Claude in the main checkout runs these; the founder does not need to.

1. **Check for uncommitted work.** A new worktree starts from the last commit, not from the
   current folder. Run `git status`; if `main` has uncommitted changes the new agent needs,
   tell the founder and commit them first.

2. **Create the worktree and its Herdr workspace.**

   ```bash
   herdr worktree create --cwd ~/Desktop/Midas/midas \
     --branch agent/<task> --base main \
     --path ~/Desktop/Midas/midas-worktrees/<task> \
     --label <task> --no-focus
   ```

   Read the pane ID from `.result.root_pane.pane_id` and the workspace ID from
   `.result.workspace.workspace_id` in the JSON. Do not guess them.

3. **Set it up.** `node_modules` and gitignored files (`.dev.vars`, `.wrangler/`) are not copied.

   ```bash
   herdr pane run <pane_id> 'cd backend && npm install && cd ..'
   # only if the main checkout has one:
   cp ~/Desktop/Midas/midas/backend/.dev.vars ~/Desktop/Midas/midas-worktrees/<task>/backend/
   ```

4. **Start Claude there and give it the task.**

   ```bash
   herdr agent start <task> --kind claude --pane <pane_id>
   herdr agent prompt <task> "<task brief: goal, files it owns, dev port, done = full test suite passes>"
   ```

   Check on it with `herdr agent get <task>` and `herdr agent read <task> --source recent-unwrapped --lines 120`.
   If it is `blocked` on a question or approval, show the founder; do not answer for them.

## Lead session: finish a task

1. In the worktree, the agent's work is committed on `agent/<task>` and `cd backend && npm test` passes.
2. In the main checkout:

   ```bash
   git merge --no-ff agent/<task>
   cd backend && npm test        # full suite again, on main, after the merge
   ```

   If tests fail after the merge, say so and fix before merging anything else.
3. Clean up (`remove` never deletes the branch; it refuses a dirty checkout without `--force`):

   ```bash
   herdr worktree remove --workspace <workspace_id>
   git branch -d agent/<task>
   ```

`herdr worktree list` shows every worktree and its workspace ID.

## Rules for an agent working in a worktree

1. Work only inside your worktree folder. Never `cd` into `~/Desktop/Midas/midas` or another
   agent's worktree to edit files.
2. Edit only the files your task brief gives you. If you need a change elsewhere, stop and say so.
3. Shared files are edited only by the lead session in the main checkout: `CLAUDE.md`,
   `docs/PRODUCT.md`, this file, `backend/package.json`, `backend/package-lock.json`,
   `backend/wrangler.jsonc`. If your task needs a new dependency or config change, ask the lead.
4. Use your own dev port: `npx wrangler dev --port <port>` with the port from your brief
   (main checkout keeps 8787; worktrees use 8788, 8789, ...).
5. Commit small and often on your own branch. Never merge into `main`, never rebase or force-push,
   never touch another agent's branch.
6. Before saying you are done, run the full suite (`cd backend && npm test`), add a test for what
   you built, and report the result honestly, including failures.
