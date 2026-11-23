import { describe, expect, it } from "vitest";
// @ts-expect-error plain ESM runner module without types
import { guardianLogged, mentionsWholeName } from "../../runner/lib/copy-tests.mjs";

// Job 1f3e0872 (2026-11-22): the Sidekick test guardian logged "reminders-logic, reminders-next7"
// without ".test.ts" and the runner failed the repair with "test changed". A test name without its
// extension counts as naming the file; a longer name that only starts with it does not.

const logBefore = "# Test changes\n\nOlder entry.\n";

function logAfterWith(entryLine: string): string {
  return `${logBefore}\n## 2026-11-22: loaders adjusted (ACCEPTED)\n${entryLine}\n`;
}

describe("guardian log names a test without its extension", () => {
  it("accepts the full file name", () => {
    const logAfter = logAfterWith("- reminders-logic.test.ts: loader evaluates the block only");
    expect(guardianLogged({ logBefore, logAfter, fileName: "reminders-logic.test.ts" })).toBe(true);
  });

  it("accepts the name without .test.ts, as job 1f3e0872's log wrote it", () => {
    const logAfter = logAfterWith("  - reminders-logic, reminders-next7, reminders-circle-colour: evaluate only the block");
    expect(guardianLogged({ logBefore, logAfter, fileName: "reminders-logic.test.ts" })).toBe(true);
    expect(guardianLogged({ logBefore, logAfter, fileName: "reminders-next7.test.ts" })).toBe(true);
    expect(guardianLogged({ logBefore, logAfter, fileName: "reminders-circle-colour.test.ts" })).toBe(true);
  });

  it("refuses a file the entry does not name", () => {
    const logAfter = logAfterWith("  - reminders-logic: evaluate only the block");
    expect(guardianLogged({ logBefore, logAfter, fileName: "reminders-wording.test.ts" })).toBe(false);
  });

  it("refuses a longer name that only starts with the file's name", () => {
    const logAfter = logAfterWith("  - reminders-logic-extra: something else");
    expect(guardianLogged({ logBefore, logAfter, fileName: "reminders-logic.test.ts" })).toBe(false);
    expect(mentionsWholeName("reminders-next7-empty-days changed", "reminders-next7")).toBe(false);
  });

  it("refuses when the log lost an older line", () => {
    const logAfter = "# Test changes\n\n- reminders-logic: changed\n";
    expect(guardianLogged({ logBefore, logAfter, fileName: "reminders-logic.test.ts" })).toBe(false);
  });
});
