"""Runs .githooks/pre-commit in a scratch git repo and checks what it accepts."""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

CODE_REPO = Path(__file__).resolve().parents[2]
PRE_COMMIT = CODE_REPO / ".githooks" / "pre-commit"


class PreCommitTests(unittest.TestCase):
    def setUp(self):
        self.scratch_repo = Path(tempfile.mkdtemp())
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "test")
        hooks_dir = self.scratch_repo / ".githooks"
        hooks_dir.mkdir()
        shutil.copy(PRE_COMMIT, hooks_dir / "pre-commit")
        self.git("config", "core.hooksPath", ".githooks")
        self.write("backend/test/a.test.ts", "original")
        self.write("backend/src/index.ts", "original")
        self.write("TEST_CHANGES.md", "# Test changes\n")
        self.git("add", ".")
        self.assertEqual(self.commit(), 0, "initial commit with new tests must pass")

    def tearDown(self):
        shutil.rmtree(self.scratch_repo)

    def git(self, *arguments):
        return subprocess.run(["git", *arguments], cwd=self.scratch_repo, capture_output=True, text=True)

    def write(self, relative_path, text):
        target = self.scratch_repo / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def commit(self):
        return self.git("commit", "-q", "-m", "change").returncode

    def test_modifying_a_test_without_a_log_entry_is_rejected(self):
        self.write("backend/test/a.test.ts", "weakened")
        self.git("add", ".")
        self.assertNotEqual(self.commit(), 0)

    def test_deleting_a_test_without_a_log_entry_is_rejected(self):
        self.git("rm", "-q", "backend/test/a.test.ts")
        self.assertNotEqual(self.commit(), 0)

    def test_modifying_a_test_with_a_log_entry_is_accepted(self):
        self.write("backend/test/a.test.ts", "changed")
        self.write("TEST_CHANGES.md", "# Test changes\n\n## entry\n")
        self.git("add", ".")
        self.assertEqual(self.commit(), 0)

    def test_adding_a_new_test_needs_no_entry(self):
        self.write("backend/test/b.test.ts", "new")
        self.git("add", ".")
        self.assertEqual(self.commit(), 0)

    def test_changing_app_code_needs_no_entry(self):
        self.write("backend/src/index.ts", "changed")
        self.git("add", ".")
        self.assertEqual(self.commit(), 0)


if __name__ == "__main__":
    unittest.main()
