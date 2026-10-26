// User copies kept by hand in the repo (founder, 2026-10-25, first: Boomi's Reminders,
// copies/reminders/boomi/). Each one is staged the way it deploys (scripts/stage-user-copy.mjs) and
// checked the way the repair runner checks a repair before it publishes (runner/lib/check.mjs): the
// deploy gate, then every test the copy carries, run against the copy's own page in a sandbox
// checkout. So the full suite fails when a base test the copy carries no longer passes on it, or
// when the copy's page breaks its own tests.
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { REPO_ROOT, readCopyDescription, stageUserCopy } from "../scripts/stage-user-copy.mjs";
import { checkSidekick } from "../../runner/lib/check.mjs";

const COPIES_ROOT = join(REPO_ROOT, "copies");
const workFolder = mkdtempSync(join(tmpdir(), "midas-user-copies-"));

afterAll(function removeWorkFolder() {
  rmSync(workFolder, { recursive: true, force: true });
});

// Every copies/<sidekick-id>/<copy-name>/ that has a copy.json
function userCopies() {
  const found: Array<{ sidekickId: string; copyName: string }> = [];
  if (!existsSync(COPIES_ROOT)) {
    return found;
  }
  for (const sidekickId of readdirSync(COPIES_ROOT).sort()) {
    const sidekickFolder = join(COPIES_ROOT, sidekickId);
    for (const copyName of readdirSync(sidekickFolder).sort()) {
      if (existsSync(join(sidekickFolder, copyName, "copy.json"))) {
        found.push({ sidekickId, copyName });
      }
    }
  }
  return found;
}

describe("stage-user-copy.mjs", () => {
  it("finds Boomi's Reminders copy", () => {
    expect(userCopies()).toContainEqual({ sidekickId: "reminders", copyName: "boomi" });
  });

  it("stages the page, the base tests copy.json names, the copy's own tests and the test log", () => {
    const outDir = join(workFolder, "deploy-boomi");
    const staged = stageUserCopy({ sidekickId: "reminders", copyName: "boomi", outDir });
    const description = readCopyDescription(REPO_ROOT, "reminders", "boomi");
    for (const fileName of description.baseTests) {
      expect(staged).toContain(fileName);
    }
    expect(staged).toContain("boomi-pages.test.ts");
    expect(staged).toContain("boomi-tools.test.ts");
    expect(staged).not.toContain("reminders-tools.test.ts");
    expect(readdirSync(outDir).sort()).toEqual(["index.html", "manifest.json", "tests", "tools.js"]);
    expect(readdirSync(join(outDir, "tests"))).toContain("TEST_CHANGES.md");
    const stagedPage = readFileSync(join(outDir, "index.html"), "utf8");
    const copyPage = readFileSync(join(COPIES_ROOT, "reminders", "boomi", "sidekick", "index.html"), "utf8");
    expect(stagedPage).toBe(copyPage);
  });

  it("refuses a copy.json base test that is not one of that Sidekick's tests", () => {
    const fakeRoot = join(workFolder, "fake-repo");
    const copyFolder = join(fakeRoot, "copies", "reminders", "someone");
    mkdirSync(join(fakeRoot, "backend", "test"), { recursive: true });
    mkdirSync(copyFolder, { recursive: true });
    writeFileSync(join(copyFolder, "copy.json"), JSON.stringify({ sidekick: "reminders", baseTests: ["hydration-logic.test.ts"] }));
    expect(function readBadCopy() {
      readCopyDescription(fakeRoot, "reminders", "someone");
    }).toThrow(/not a reminders test/);
  });
});

describe("each user copy passes the repair runner's check", () => {
  for (const copy of userCopies()) {
    it(`${copy.sidekickId} copy ${copy.copyName}: deploy gate and every test it carries`, async () => {
      const jobFolder = join(workFolder, `job-${copy.sidekickId}-${copy.copyName}`);
      stageUserCopy({ sidekickId: copy.sidekickId, copyName: copy.copyName, outDir: jobFolder, pageFolderName: "sidekick" });
      const result = await checkSidekick({ checkoutRoot: REPO_ROOT, sidekickId: copy.sidekickId, jobFolder });
      expect(result.problems, result.testOutput).toEqual([]);
      expect(result.ok).toBe(true);
      // The copy's tests really ran: vitest printed its file count
      expect(result.testOutput).toMatch(/Test Files\s+\d+ passed/);
    }, 180000);
  }
});
