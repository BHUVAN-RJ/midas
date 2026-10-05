#!/bin/zsh
# Midas intel runner. Usage: intel/run.sh daily|weekly|baseline
#
# daily:    deterministic source collector (App Store, Hacker News, YC, Reddit), then headless
#           Claude Code triages it, searches the web and writes docs/intel/<date>-<am|pm>.md
# weekly:   headless Claude Code summarizes the week into docs/intel/weekly/<year>-W<week>.md
# baseline: one-time review of the full candidate set into docs/intel/baseline/
#
# Output lives in this repo (docs/intel/). gbrain indexes the repo; jobs never write to gbrain.
# Claude Code may only write under docs/intel/ and intel/state/; it cannot run shell commands.

set -u

run_mode="${1:-daily}"
intel_dir="${0:A:h}"
repo_root="${intel_dir:h}"

export PATH="$HOME/.bun/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

run_date="$(date +%F)"
# am before noon, pm after.
if [ "$(date +%H)" -lt 12 ]; then run_label="am"; else run_label="pm"; fi
# MIDAS_RUN_LABEL overrides it for manual test runs, so a test does not take a scheduled slot.
run_label="${MIDAS_RUN_LABEL:-$run_label}"
log_dir="$HOME/Library/Logs/midas-intel"
log_file="$log_dir/$run_date-$run_mode-$run_label.log"
lock_dir="$intel_dir/state/.$run_mode.lock"

mkdir -p "$log_dir" "$intel_dir/state" "$intel_dir/collected" \
  "$repo_root/docs/intel/weekly" "$repo_root/docs/intel/baseline"
exec >>"$log_file" 2>&1

# Skip if the same mode is still running (mkdir is atomic).
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "[$(date)] previous $run_mode run still active, skipping"
  exit 0
fi
trap 'rmdir "$lock_dir"' EXIT

echo "=== midas intel $run_mode $run_date $run_label $(date) ==="

prompt_text="$(cat "$intel_dir/$run_mode-prompt.md")

Today is $run_date; ISO week is $(date +%G-W%V).
DATE=$run_date
RUN=$run_label"

if [ "$run_mode" = "daily" ]; then
  echo "--- source collector"
  collected_file="$intel_dir/collected/$run_date-$run_label.md"
  python3 "$intel_dir/collect_sources.py" > "$collected_file" 2>&1
  cat "$collected_file"
  prompt_text="$prompt_text

=== Source collector output ===
$(cat "$collected_file")"
fi

if [ "$run_mode" = "baseline" ]; then
  echo "--- baseline candidate set"
  inputs_file="$intel_dir/collected/inputs-$run_date.md"
  (cd "$intel_dir" && python3 baseline_inputs.py) > "$inputs_file" 2>&1
  prompt_text="$prompt_text

=== Candidate set ===
$(cat "$inputs_file")"
fi

# Turn budget per mode.
case "$run_mode" in
  daily) max_turns=80 ;;
  weekly) max_turns=80 ;;
  baseline) max_turns=150 ;;
  *) echo "unknown mode: $run_mode"; exit 1 ;;
esac

echo "--- Claude Code pass"
# Reads anywhere in the repo are allowed by default; writes only to the intel output and state.
# The gbrain plugin tools are allowed for read-only context when installed.
cd "$repo_root" && claude -p "$prompt_text" \
  --allowedTools "WebSearch" "WebFetch" "Skill" "mcp__plugin_gbrain_gbrain" \
    "Edit(docs/intel/**)" "Edit(intel/state/**)" \
  --disallowedTools "Bash" \
  --max-turns "$max_turns"

echo "=== done $(date) ==="
