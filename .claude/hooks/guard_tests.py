#!/usr/bin/env python3
"""PreToolUse guard: existing tests change only through the test-guardian agent.

Rules, checked on every Edit, Write, NotebookEdit and Bash call, from any agent:

1. Guard files (this hook, the guardian's definition, project settings, the git hook) cannot
   be changed by any agent, the guardian included. Only the founder edits them by hand.
2. An existing test file, or TEST_CHANGES.md, can be changed or deleted only when the caller is
   the test-guardian subagent (hook input field agent_type == "test-guardian").
3. A new test file may be created by anyone.

Bash is checked by pattern: a command that names a protected path is denied unless it is a
read or test-run command. That is a heuristic; the git pre-commit hook is the backstop.
Deny is reported as JSON on stdout with exit 0; allow is silent exit 0.
"""

import json
import re
import sys
from pathlib import Path

GUARDIAN_AGENT = "test-guardian"
CODE_REPO = Path(__file__).resolve().parents[2]
INTEL_REPO = Path.home() / "code" / "midas-intel"

TEST_LOCATIONS = [
    CODE_REPO / "backend" / "test",
    CODE_REPO / "shell" / "MidasTests",
    CODE_REPO / "tests",
    CODE_REPO / "scripts" / "test-all.sh",
    CODE_REPO / "TEST_CHANGES.md",
    INTEL_REPO / "intel" / "tests",
]
GUARD_LOCATIONS = [
    CODE_REPO / ".claude" / "hooks",
    CODE_REPO / ".claude" / "settings.json",
    CODE_REPO / ".claude" / "agents" / "test-guardian.md",
    CODE_REPO / ".githooks",
]

# Path fragments a shell command would use to reach a protected location.
TEST_FRAGMENTS = ["backend/test", "MidasTests", "tests/", "test-all.sh", "TEST_CHANGES", "intel/tests", "/test/"]
GUARD_FRAGMENTS = [".claude/hooks", ".claude/settings", "test-guardian.md", ".githooks", "core.hooksPath", "guard_tests"]

# Commands that only read files or run the suites.
READ_ONLY_COMMAND = re.compile(
    r"^\s*(cat|head|tail|less|grep|rg|ls|wc|diff|file|stat|find|"
    r"sed -n|git (diff|log|show|status|blame|ls-files)|"
    r"npm (test|run test|run typecheck)|npx (vitest|tsc)|"
    r"xcodebuild( .*)? test|python3( -I)? -m unittest|scripts/test-all\.sh|\./scripts/test-all\.sh|"
    r"(cd \S+ && )+(npm test|python3 -m unittest|xcodebuild))\b"
)
# Anything that can write, move or delete, even inside an otherwise read-only command.
WRITE_TOKENS = re.compile(r"(>|\btee\b|\brm\b|\bmv\b|\bcp\b|\bsed\s+-i|\bperl\s+-i|\btruncate\b|"
                          r"\bgit\s+(rm|mv|checkout|restore|reset|stash|apply)|\bchmod\b|\bln\b|"
                          r"\bpython3?\b(?!\s+(-I\s+)?-m\s+unittest)|\bnode\b|\bswift\b|\bed\b|\bdd\b|-delete|-exec)")


def is_inside(path: Path, location: Path) -> bool:
    return path == location or location in path.parents


def is_guard_path(path: Path) -> bool:
    return any(is_inside(path, location) for location in GUARD_LOCATIONS)


def is_test_path(path: Path) -> bool:
    return any(is_inside(path, location) for location in TEST_LOCATIONS)


def deny(reason: str) -> None:
    decision = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(decision))
    sys.exit(0)


GUARD_REASON = ("This file is part of the test guard. No agent may change it; the founder edits it "
                "by hand. Tell the user what change you need and why.")
DELEGATE_REASON = ("Existing tests change only through the test-guardian agent. Delegate with the Agent "
                   "tool (subagent_type: test-guardian): name the test, the change, and the decision or "
                   "bug that requires it. New test files may be created directly.")


def check_file_tool(tool_name: str, tool_input: dict, caller: str) -> None:
    raw_path = tool_input.get("file_path") or tool_input.get("notebook_path")
    if not raw_path:
        return
    target = Path(raw_path).expanduser().resolve()
    if is_guard_path(target):
        deny(GUARD_REASON)
    if not is_test_path(target):
        return
    creating_new_file = tool_name == "Write" and not target.exists() and target.name != "TEST_CHANGES.md"
    if creating_new_file or caller == GUARDIAN_AGENT:
        return
    deny(DELEGATE_REASON)


def check_bash(command: str, caller: str) -> None:
    names_guard = any(fragment in command for fragment in GUARD_FRAGMENTS)
    names_test = any(fragment in command for fragment in TEST_FRAGMENTS)
    if not names_guard and not names_test:
        return
    looks_read_only = READ_ONLY_COMMAND.match(command) is not None and WRITE_TOKENS.search(command) is None
    if looks_read_only:
        return
    if names_guard:
        deny(GUARD_REASON)
    if caller != GUARDIAN_AGENT:
        deny(DELEGATE_REASON + " Shell commands that touch test paths are limited to reading and running tests.")


def main() -> None:
    hook_input = json.load(sys.stdin)
    tool_name = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input") or {}
    caller = hook_input.get("agent_type") or "main"

    if tool_name in ("Edit", "Write", "NotebookEdit"):
        check_file_tool(tool_name, tool_input, caller)
    elif tool_name == "Bash":
        check_bash(tool_input.get("command", ""), caller)


if __name__ == "__main__":
    main()
