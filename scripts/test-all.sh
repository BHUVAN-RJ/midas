#!/bin/zsh
# Runs every test suite: the test guard, backend, shell, and the plan-consistency tests in midas-intel.
# Usage: scripts/test-all.sh   (from anywhere). Exits non-zero if any suite fails.
set -u
repo_root="${0:A:h:h}"
intel_root="$HOME/code/midas-intel"
# With no simulator given, lease one from the pool (scripts/sim.sh sets MIDAS_SIMULATOR and runs us again).
if [[ -z "${MIDAS_SIMULATOR:-}" ]]; then
  exec "$repo_root/scripts/sim.sh" run "$repo_root/scripts/test-all.sh"
fi
simulator_name="$MIDAS_SIMULATOR"
failed_suites=()

echo "== test guard"
(cd "$repo_root" && python3 -I -m unittest discover -s tests/guard) || failed_suites+=(test-guard)

echo "== backend"
(cd "$repo_root/backend" && npm test --silent && npm run typecheck --silent) || failed_suites+=(backend)

echo "== shell"
(cd "$repo_root/shell" && xcodegen generate --quiet \
  && xcodebuild test -project Midas.xcodeproj -scheme Midas \
       -destination "platform=iOS Simulator,name=$simulator_name" 2>&1 \
     | grep -E "error:|Test Case.*failed|TEST (SUCCEEDED|FAILED)|Executed [0-9]+ tests" | tail -3 ; exit ${pipestatus[1]}) || failed_suites+=(shell)

if [[ -d "$intel_root" ]]; then
  echo "== midas-intel"
  (cd "$intel_root" && python3 -m unittest discover -s intel/tests) || failed_suites+=(midas-intel)
else
  echo "== midas-intel: not checked out at $intel_root, skipped"
fi

if (( ${#failed_suites} > 0 )); then
  echo "FAILED: ${failed_suites[*]}"
  exit 1
fi
echo "ALL SUITES PASSED"
