#!/bin/zsh
# launchd entry point: sets PATH so node, npx and claude are found, then runs the loop.
# Settings come from ~/.midas-runner/env (read by runner.mjs itself).
set -u
runner_dir="${0:A:h:h}"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
# Node installed with nvm is not on launchd's PATH: add nvm's default version when no node is found.
if ! command -v node >/dev/null 2>&1 && [ -r "$HOME/.nvm/alias/default" ]; then
  nvm_default="$(cat "$HOME/.nvm/alias/default")"
  nvm_versions="$HOME/.nvm/versions/node"
  nvm_bin="$nvm_versions/$nvm_default/bin"
  # The alias may be a prefix ("22") rather than an exact version: take the newest match.
  if [ ! -x "$nvm_bin/node" ]; then
    nvm_matches=("$nvm_versions"/v${nvm_default#v}*(N/On))
    if (( ${#nvm_matches} > 0 )); then
      nvm_bin="${nvm_matches[1]}/bin"
    fi
  fi
  if [ -x "$nvm_bin/node" ]; then
    export PATH="$nvm_bin:$PATH"
  fi
fi
cd "$runner_dir/.." || exit 1
exec node "$runner_dir/bin/runner.mjs"
