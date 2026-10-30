// A separate test guardian for Sidekicks (founder, 2026-10-30, docs/PRODUCT.md "Plan additions,
// 2026-10-30"). Repair 5700cf94 (Photo Reminders) ended unsupported because the shell's guardian
// refused to let a sidebar-order test move when a list was added. Every repair job now gets the
// Sidekick guardian as its test-guardian; the shell's guardian no longer holds repair rules.
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { SIDEKICK_GUARDIAN_SOURCE, writeAgentSettings } from "../../runner/lib/copy-tests.mjs";
import { REPO_ROOT } from "../../runner/lib/config.mjs";

const SHELL_GUARDIAN_MARKER = "SHELL GUARDIAN: must never reach a repair job";

// A checkout with the hook and settings, and a shell guardian that is easy to recognise.
function makeCheckoutWithShellGuardian(): { checkout: string; jobFolder: string } {
  const scratch = mkdtempSync(join(tmpdir(), "sidekick-guardian-"));
  const checkout = join(scratch, "checkout");
  for (const relativePath of [join(".claude", "settings.json"), join(".claude", "hooks", "guard_tests.py")]) {
    mkdirSync(join(checkout, relativePath, ".."), { recursive: true });
    writeFileSync(join(checkout, relativePath), readFileSync(join(REPO_ROOT, relativePath)));
  }
  mkdirSync(join(checkout, ".claude", "agents"), { recursive: true });
  writeFileSync(join(checkout, ".claude", "agents", "test-guardian.md"), `---\nname: test-guardian\n---\n${SHELL_GUARDIAN_MARKER}\n`);
  const jobFolder = join(scratch, "job");
  mkdirSync(jobFolder, { recursive: true });
  return { checkout, jobFolder };
}

function frontmatterName(markdown: string): string | null {
  const match = markdown.match(/^---\n[\s\S]*?^name:\s*(\S+)\s*$/m);
  return match === null ? null : match[1];
}

describe("a repair job gets the Sidekick guardian, not the shell's", () => {
  it("writes runner/agents/sidekick-test-guardian.md as the job's .claude/agents/test-guardian.md", () => {
    const { checkout, jobFolder } = makeCheckoutWithShellGuardian();
    writeAgentSettings({ jobFolder, checkoutRoot: checkout });
    const jobGuardian = readFileSync(join(jobFolder, ".claude", "agents", "test-guardian.md"), "utf8");
    expect(jobGuardian).toBe(readFileSync(SIDEKICK_GUARDIAN_SOURCE, "utf8"));
    expect(jobGuardian).not.toContain(SHELL_GUARDIAN_MARKER);
  });

  it("still copies the hook and settings from the checkout", () => {
    const { checkout, jobFolder } = makeCheckoutWithShellGuardian();
    writeAgentSettings({ jobFolder, checkoutRoot: checkout });
    const jobHook = readFileSync(join(jobFolder, ".claude", "hooks", "guard_tests.py"), "utf8");
    expect(jobHook).toBe(readFileSync(join(checkout, ".claude", "hooks", "guard_tests.py"), "utf8"));
  });

  it("keeps the name test-guardian inside the job, so the hook and the runner's Agent rule pass it", () => {
    const sidekickGuardian = readFileSync(SIDEKICK_GUARDIAN_SOURCE, "utf8");
    expect(frontmatterName(sidekickGuardian)).toBe("test-guardian");
  });
});

describe("the Sidekick guardian lets the user's request move details, not behaviour", () => {
  const sidekickGuardian = readFileSync(SIDEKICK_GUARDIAN_SOURCE, "utf8");

  it("accepts a test that only pins placement, order, counts or looks the request shifts", () => {
    expect(sidekickGuardian).toContain("**The test pins a detail, not behaviour, and the request moves that detail.**");
    expect(sidekickGuardian).toContain("Accept, even when the\n     request does not say where the new thing goes");
    expect(sidekickGuardian).toContain("Never refuse only because the request did not say where something goes");
  });

  it("still refuses when something the user did not ask about breaks", () => {
    expect(sidekickGuardian).toContain("**The change breaks something the user did not ask about.**");
    expect(sidekickGuardian).toContain("Refuse. Say which behaviour breaks and why.");
    expect(sidekickGuardian).toContain("A rewritten test must\n   still be able to fail");
  });
});

describe("the shell guardian no longer carries repair rules", () => {
  const shellGuardian = readFileSync(join(REPO_ROOT, ".claude", "agents", "test-guardian.md"), "utf8");

  it("has no repair-job or user-copy sections", () => {
    expect(shellGuardian).not.toContain("## Inside a repair job");
    expect(shellGuardian).not.toContain("## User copies (repair)");
  });
});

describe("the repair prompts ask for behaviour tests and tell the guardian about detail-only tests", () => {
  for (const promptName of ["reminders.md", "hydration.md", "care-reminders.md"]) {
    const promptText = readFileSync(join(REPO_ROOT, "runner", "agents", promptName), "utf8");

    it(`${promptName}: new tests check what the copy does, not where things sit`, () => {
      expect(promptText).toContain("**A new test checks what the copy does, not where things sit or how they look**");
    });

    it(`${promptName}: the delegation names detail-only tests`, () => {
      const start = promptText.indexOf("- When an existing test blocks what the user asked for");
      const delegation = promptText.slice(start, promptText.indexOf("\n- ", start + 1));
      expect(delegation).toContain("When the test only pins a position, an order, a count that grows");
    });
  }
});
