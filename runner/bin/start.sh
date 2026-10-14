#!/bin/zsh
# launchd entry point: sets PATH so node, npx and claude are found, then runs the loop.
# Settings come from ~/.midas-runner/env (read by runner.mjs itself).
set -u
runner_dir="${0:A:h:h}"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
cd "$runner_dir/.." || exit 1
exec node "$runner_dir/bin/runner.mjs"
