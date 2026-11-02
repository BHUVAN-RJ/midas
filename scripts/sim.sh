#!/bin/zsh
# Simulator pool for parallel agents (founder, 2026-10-26).
#
# Every session tests on one of two shared iPhone 17 Pro simulators, "Midas Sim 1" and
# "Midas Sim 2", and leases it first, so two agents never install and run the app on the same
# simulator at once (that crashed shell tests with "signal kill",
# docs/concerns/2026-10-11-reminders-and-widgets.md #7). A session that needs a specific device
# makes a temporary simulator, and it is deleted as soon as the testing is done.
# Never run `xcrun simctl create` yourself; use this script.
#
# Usage:
#   scripts/sim.sh run <command...>                     lease a pool sim, run the command with
#                                                        MIDAS_SIMULATOR set to it, release it
#   scripts/sim.sh run --device "iPhone 15" <command...> same on a temporary sim of that type,
#                                                        deleted when the command ends
#   scripts/sim.sh acquire [--device "<type>"] <owner>  lease for manual work across several
#                                                        commands; prints the simulator name
#   scripts/sim.sh release "<name>"                     give it back (a temporary sim is deleted)
#   scripts/sim.sh reset "<name>"                       erase a sim you hold (app data, permissions)
#   scripts/sim.sh status                               who holds what
#   scripts/sim.sh cleanup                              delete leftover temporary sims, stale leases
#
# Environment: MIDAS_SIM_WAIT (seconds to wait for a free pool sim, default 1800),
# MIDAS_SIM_LEASE (seconds before a manual lease counts as abandoned, default 7200),
# MIDAS_SIM_LOCK_DIR and MIDAS_SIMCTL (tests point these at a temp folder and a fake simctl).
set -u

pool_names=("Midas Sim 1" "Midas Sim 2")
pool_device_type="iPhone 17 Pro"
temp_prefix="Midas Temp"
lock_root="${MIDAS_SIM_LOCK_DIR:-$HOME/Library/Caches/midas-sim-locks}"
wait_seconds="${MIDAS_SIM_WAIT:-1800}"
manual_lease_seconds="${MIDAS_SIM_LEASE:-7200}"
simctl_command=(${(z)${MIDAS_SIMCTL:-xcrun simctl}})
poll_seconds=5

mkdir -p "$lock_root"

lock_dir_for() {
  local simulator_name="$1"
  echo "$lock_root/${simulator_name// /-}"
}

# One line per simulator from `simctl list devices`, e.g. "    Midas Sim 1 (UDID) (Booted) ".
simulator_udid() {
  local simulator_name="$1"
  local device_line
  device_line=$("${simctl_command[@]}" list devices | grep -F "    $simulator_name (" | head -1)
  if [[ "$device_line" =~ "\(([0-9A-Fa-f-]+)\)" ]]; then
    echo "$match[1]"
  fi
}

ensure_pool_simulator() {
  local simulator_name="$1"
  if [[ -z "$(simulator_udid "$simulator_name")" ]]; then
    "${simctl_command[@]}" create "$simulator_name" "$pool_device_type" >/dev/null
  fi
}

delete_simulator() {
  local simulator_name="$1"
  local udid
  udid=$(simulator_udid "$simulator_name")
  if [[ -n "$udid" ]]; then
    "${simctl_command[@]}" shutdown "$udid" >/dev/null 2>&1
    "${simctl_command[@]}" delete "$udid" >/dev/null
  fi
}

# A lease is abandoned when its process is gone, or, for a manual lease with no process,
# when it is older than MIDAS_SIM_LEASE. A lease still being written (no files yet) gets 60 s.
lease_is_stale() {
  local lock_dir="$1"
  local now=$(date +%s)
  if [[ ! -f "$lock_dir/created" ]]; then
    local folder_age=$(( now - $(stat -f %m "$lock_dir") ))
    (( folder_age > 60 ))
    return
  fi
  local holder_pid=$(<"$lock_dir/pid")
  if [[ -n "$holder_pid" ]]; then
    ! kill -0 "$holder_pid" 2>/dev/null
    return
  fi
  local created=$(<"$lock_dir/created")
  (( now - created > manual_lease_seconds ))
}

# mkdir is atomic, so only one session can create the lock folder for a simulator.
try_lease() {
  local simulator_name="$1" owner="$2" holder_pid="$3"
  local lock_dir=$(lock_dir_for "$simulator_name")
  if ! mkdir "$lock_dir" 2>/dev/null; then
    if lease_is_stale "$lock_dir"; then
      rm -rf "$lock_dir"
      mkdir "$lock_dir" 2>/dev/null || return 1
    else
      return 1
    fi
  fi
  echo "$owner" >"$lock_dir/owner"
  echo "$holder_pid" >"$lock_dir/pid"
  date +%s >"$lock_dir/created"
}

release_lease() {
  local simulator_name="$1"
  rm -rf "$(lock_dir_for "$simulator_name")"
}

describe_holders() {
  local simulator_name lock_dir
  for simulator_name in "${pool_names[@]}"; do
    lock_dir=$(lock_dir_for "$simulator_name")
    if [[ -f "$lock_dir/owner" ]]; then
      echo "  $simulator_name: held by $(<"$lock_dir/owner") (pid $(<"$lock_dir/pid"))"
    else
      echo "  $simulator_name: free"
    fi
  done
}

# Prints the leased pool simulator's name, waiting up to MIDAS_SIM_WAIT for one to come free.
lease_pool_simulator() {
  local owner="$1" holder_pid="$2"
  local deadline=$(( $(date +%s) + wait_seconds ))
  local simulator_name
  while true; do
    for simulator_name in "${pool_names[@]}"; do
      if try_lease "$simulator_name" "$owner" "$holder_pid"; then
        ensure_pool_simulator "$simulator_name"
        echo "$simulator_name"
        return 0
      fi
    done
    if (( $(date +%s) >= deadline )); then
      echo "sim.sh: no pool simulator came free within ${wait_seconds}s:" >&2
      describe_holders >&2
      return 1
    fi
    sleep $poll_seconds
  done
}

# Temporary simulators are named "Midas Temp <type> <id>" and leased under that name, so
# cleanup can tell a live one from a leftover.
create_temp_simulator() {
  local device_type="$1" owner="$2" holder_pid="$3"
  local simulator_name="$temp_prefix $device_type $(date +%s)$RANDOM"
  try_lease "$simulator_name" "$owner" "$holder_pid" || return 1
  if ! "${simctl_command[@]}" create "$simulator_name" "$device_type" >/dev/null; then
    release_lease "$simulator_name"
    echo "sim.sh: could not create a \"$device_type\" simulator" >&2
    return 1
  fi
  echo "$simulator_name"
}

give_back() {
  local simulator_name="$1"
  if [[ "$simulator_name" == "$temp_prefix "* ]]; then
    delete_simulator "$simulator_name"
  fi
  release_lease "$simulator_name"
}

run_on_simulator() {
  local device_type=""
  if [[ "${1:-}" == "--device" ]]; then
    device_type="$2"
    shift 2
  fi
  if (( $# == 0 )); then
    echo "usage: scripts/sim.sh run [--device \"<type>\"] <command...>" >&2
    return 2
  fi
  local simulator_name
  if [[ -n "$device_type" ]]; then
    simulator_name=$(create_temp_simulator "$device_type" "run: $1" $$) || return 1
  else
    simulator_name=$(lease_pool_simulator "run: $1" $$) || return 1
  fi
  # Give the simulator back however the command ends, including Ctrl-C.
  trap "give_back '$simulator_name'" EXIT
  trap "give_back '$simulator_name'; trap - EXIT; exit 130" INT TERM
  echo "sim.sh: using $simulator_name" >&2
  MIDAS_SIMULATOR="$simulator_name" "$@"
}

acquire_for_manual_use() {
  local device_type=""
  if [[ "${1:-}" == "--device" ]]; then
    device_type="$2"
    shift 2
  fi
  local owner="${1:?usage: scripts/sim.sh acquire [--device \"<type>\"] <owner>}"
  if [[ -n "$device_type" ]]; then
    create_temp_simulator "$device_type" "$owner" ""
  else
    lease_pool_simulator "$owner" ""
  fi
}

show_status() {
  describe_holders
  local lock_dir
  for lock_dir in "$lock_root"/Midas-Temp-*(N); do
    echo "  ${${lock_dir:t}//-/ }: held by $(<"$lock_dir/owner") (pid $(<"$lock_dir/pid"))"
  done
}

# Deletes temporary simulators whose lease is gone or abandoned, and removes stale pool leases.
clean_up_leftovers() {
  local device_line simulator_name lock_dir
  "${simctl_command[@]}" list devices | grep -F "    $temp_prefix " | while read -r device_line; do
    simulator_name="${device_line%% \(*}"
    lock_dir=$(lock_dir_for "$simulator_name")
    if [[ ! -d "$lock_dir" ]] || lease_is_stale "$lock_dir"; then
      echo "sim.sh: deleting leftover $simulator_name"
      give_back "$simulator_name"
    fi
  done
  for simulator_name in "${pool_names[@]}"; do
    lock_dir=$(lock_dir_for "$simulator_name")
    if [[ -d "$lock_dir" ]] && lease_is_stale "$lock_dir"; then
      echo "sim.sh: releasing abandoned lease on $simulator_name"
      release_lease "$simulator_name"
    fi
  done
}

subcommand="${1:-}"
(( $# > 0 )) && shift
case "$subcommand" in
  run) run_on_simulator "$@" ;;
  acquire) acquire_for_manual_use "$@" ;;
  release) give_back "${1:?usage: scripts/sim.sh release \"<name>\"}" ;;
  reset) "${simctl_command[@]}" shutdown "$(simulator_udid "${1:?usage: scripts/sim.sh reset \"<name>\"}")" >/dev/null 2>&1
         "${simctl_command[@]}" erase "$(simulator_udid "$1")" ;;
  status) show_status ;;
  cleanup) clean_up_leftovers ;;
  *) sed -n '2,25p' "$0" >&2; exit 2 ;;
esac
