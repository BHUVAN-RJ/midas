"""The Sidekick test guardian is a guard file (founder, 2026-10-30).

runner/agents/sidekick-test-guardian.md becomes the test-guardian inside every repair job, so an
agent that could edit it could loosen every repair's tests. No agent may change it, the shell
guardian included, the same as .claude/agents/test-guardian.md.
"""

import json
import subprocess
import sys
import unittest
from pathlib import Path

CODE_REPO = Path(__file__).resolve().parents[2]
GUARD_SCRIPT = CODE_REPO / ".claude" / "hooks" / "guard_tests.py"
SIDEKICK_GUARDIAN = CODE_REPO / "runner" / "agents" / "sidekick-test-guardian.md"
REPAIR_PROMPT = CODE_REPO / "runner" / "agents" / "reminders.md"


def run_guard(tool_name, tool_input, agent_type=None):
    hook_input = {"tool_name": tool_name, "tool_input": tool_input, "hook_event_name": "PreToolUse"}
    if agent_type:
        hook_input["agent_type"] = agent_type
    completed = subprocess.run([sys.executable, "-I", str(GUARD_SCRIPT)], input=json.dumps(hook_input),
                               capture_output=True, text=True, check=True)
    if not completed.stdout.strip():
        return "allow"
    return json.loads(completed.stdout)["hookSpecificOutput"]["permissionDecision"]


class SidekickGuardianIsGuarded(unittest.TestCase):
    def test_no_agent_can_edit_the_sidekick_guardian(self):
        for agent_type in (None, "general-purpose", "test-guardian"):
            for tool_name in ("Edit", "Write"):
                decision = run_guard(tool_name, {"file_path": str(SIDEKICK_GUARDIAN)}, agent_type)
                self.assertEqual(decision, "deny", f"{tool_name} by {agent_type or 'main'}")

    def test_shell_commands_that_write_it_are_denied(self):
        for command in ("rm runner/agents/sidekick-test-guardian.md",
                        "echo x > runner/agents/sidekick-test-guardian.md",
                        "sed -i '' 's/a/b/' runner/agents/sidekick-test-guardian.md"):
            for agent_type in (None, "test-guardian"):
                self.assertEqual(run_guard("Bash", {"command": command}, agent_type), "deny", command)

    def test_reading_it_is_allowed(self):
        self.assertEqual(run_guard("Bash", {"command": "cat runner/agents/sidekick-test-guardian.md"}), "allow")

    def test_the_repair_prompts_next_to_it_stay_editable(self):
        # Only the guardian file is guarded; the repair prompts in the same folder are not.
        self.assertEqual(run_guard("Edit", {"file_path": str(REPAIR_PROMPT)}), "allow")


if __name__ == "__main__":
    unittest.main()
