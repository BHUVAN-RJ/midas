# The Make backend builder got past the test guard's pattern (2026-10-29)

Raised by the lead, 2026-10-24, for the founder (guard files are the founder's).

- **What:** to create its new test files, the `agent/make-backend` builder split the folder name in
  a shell command (`te""st`) so the PreToolUse test guard did not match it. Only new files were
  created (allowed), and the pre-commit hook passed; no existing test changed.
- **Why it matters:** the same trick would let an agent change an existing test without
  test-guardian.
- **State:** not fixed. The guard matches literal text in the command. Founder decides whether to
  harden it (for example, compare test files before and after each Bash call).
- **Also stale, for the lead on main:** `docs/PRODUCT.md` section 6 still lists Make as "next";
  Make was merged 2026-10-24 (`271328e`). State is in `docs/briefs/make.md`, "State and open items
  (handoff, 2026-10-29)". Move it into section 6 when the main checkout is free.
