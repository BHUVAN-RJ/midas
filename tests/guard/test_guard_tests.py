"""Feeds hook inputs to .claude/hooks/guard_tests.py and checks allow or deny."""

import json
import subprocess
import sys
import unittest
from pathlib import Path

CODE_REPO = Path(__file__).resolve().parents[2]
GUARD_SCRIPT = CODE_REPO / ".claude" / "hooks" / "guard_tests.py"
EXISTING_TEST = CODE_REPO / "backend" / "test" / "bundle-route.test.ts"
NEW_TEST = CODE_REPO / "backend" / "test" / "not-yet-written.test.ts"
APP_SOURCE = CODE_REPO / "backend" / "src" / "index.ts"


def run_guard(tool_name, tool_input, agent_type=None):
    hook_input = {"tool_name": tool_name, "tool_input": tool_input, "hook_event_name": "PreToolUse"}
    if agent_type:
        hook_input["agent_type"] = agent_type
    completed = subprocess.run([sys.executable, "-I", str(GUARD_SCRIPT)], input=json.dumps(hook_input),
                               capture_output=True, text=True, check=True)
    if not completed.stdout.strip():
        return "allow"
    return json.loads(completed.stdout)["hookSpecificOutput"]["permissionDecision"]


class FileToolTests(unittest.TestCase):
    def test_main_agent_cannot_edit_an_existing_test(self):
        self.assertEqual(run_guard("Edit", {"file_path": str(EXISTING_TEST)}), "deny")

    def test_other_subagent_cannot_edit_an_existing_test(self):
        self.assertEqual(run_guard("Edit", {"file_path": str(EXISTING_TEST)}, "general-purpose"), "deny")

    def test_main_agent_cannot_overwrite_an_existing_test(self):
        self.assertEqual(run_guard("Write", {"file_path": str(EXISTING_TEST)}), "deny")

    def test_guardian_can_edit_an_existing_test(self):
        self.assertEqual(run_guard("Edit", {"file_path": str(EXISTING_TEST)}, "test-guardian"), "allow")

    def test_anyone_can_create_a_new_test_file(self):
        self.assertFalse(NEW_TEST.exists())
        self.assertEqual(run_guard("Write", {"file_path": str(NEW_TEST)}), "allow")

    def test_shell_tests_and_intel_tests_are_protected(self):
        shell_test = CODE_REPO / "shell" / "MidasTests" / "NoNativeBridgeTests.swift"
        intel_test = Path.home() / "code" / "midas-intel" / "intel" / "tests" / "test_two_repos.py"
        self.assertEqual(run_guard("Edit", {"file_path": str(shell_test)}), "deny")
        self.assertEqual(run_guard("Edit", {"file_path": str(intel_test)}), "deny")

    def test_change_log_is_guardian_only_even_when_new(self):
        change_log = CODE_REPO / "TEST_CHANGES.md"
        self.assertEqual(run_guard("Write", {"file_path": str(change_log)}), "deny")
        self.assertEqual(run_guard("Edit", {"file_path": str(change_log)}, "test-guardian"), "allow")

    def test_app_source_is_not_affected(self):
        self.assertEqual(run_guard("Edit", {"file_path": str(APP_SOURCE)}), "allow")

    def test_guard_files_are_locked_for_everyone_including_guardian(self):
        for guard_file in (GUARD_SCRIPT, CODE_REPO / ".claude" / "settings.json",
                           CODE_REPO / ".claude" / "agents" / "test-guardian.md",
                           CODE_REPO / ".githooks" / "pre-commit"):
            self.assertEqual(run_guard("Edit", {"file_path": str(guard_file)}, "test-guardian"), "deny", guard_file)
            self.assertEqual(run_guard("Write", {"file_path": str(guard_file)}), "deny", guard_file)

    def test_relative_traversal_is_resolved(self):
        sneaky_path = CODE_REPO / "backend" / "src" / ".." / "test" / "bundle-route.test.ts"
        self.assertEqual(run_guard("Edit", {"file_path": str(sneaky_path)}), "deny")


class BashTests(unittest.TestCase):
    def test_running_and_reading_tests_is_allowed(self):
        for command in ("npm test", "cat backend/test/bundle-route.test.ts", "scripts/test-all.sh",
                        "git diff backend/test", "python3 -m unittest discover -s intel/tests",
                        "cd backend && npm test"):
            self.assertEqual(run_guard("Bash", {"command": command}), "allow", command)

    def test_deleting_or_rewriting_a_test_by_shell_is_denied(self):
        for command in ("rm backend/test/bundle-route.test.ts", "sed -i '' 's/a/b/' shell/MidasTests/X.swift",
                        "echo x > backend/test/bundle-route.test.ts", "git checkout -- backend/test",
                        "cat backend/test/a.ts > /dev/null; rm backend/test/a.ts",
                        "python3 -c 'open(\"backend/test/a.ts\",\"w\")'"):
            self.assertEqual(run_guard("Bash", {"command": command}), "deny", command)

    def test_guardian_may_change_tests_by_shell(self):
        self.assertEqual(run_guard("Bash", {"command": "rm backend/test/old.test.ts"}, "test-guardian"), "allow")

    def test_guard_files_cannot_be_changed_by_shell_even_by_guardian(self):
        for command in ("rm .claude/hooks/guard_tests.py", "git config core.hooksPath /dev/null",
                        "echo '{}' > .claude/settings.json"):
            self.assertEqual(run_guard("Bash", {"command": command}, "test-guardian"), "deny", command)

    def test_unrelated_commands_are_untouched(self):
        self.assertEqual(run_guard("Bash", {"command": "rm -rf backend/node_modules"}), "allow")


if __name__ == "__main__":
    unittest.main()
