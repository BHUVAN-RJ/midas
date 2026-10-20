// Lead items 15 and 16 (reviewer B, second pass, 2026-10-20).
//   15 the tool link step only ever removes a symbolic link at <linkRoot>/runner-tools; a real
//      file or folder there is refused, never deleted.
//   16 the new-field clash check also sees a stored record whose upgrade fails, so the job's
//      reason is the clash, not "records do not fit schema".
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { linkAgentTools } from "../../runner/lib/agent.mjs";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import { storedRecordSchemaProblems } from "../../runner/lib/user-records.mjs";
import {
  REPO_ROOT,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
} from "./helpers/runner-fixture";

const TOOLS_FOLDER = join(REPO_ROOT, "runner", "tools");

function scratchFolder(): string {
  return realpathSync(mkdtempSync(join(tmpdir(), "midas-link-clash-")));
}

describe("15: the tool link step never deletes a real file or folder", () => {
  it("refuses a real folder at the link path and leaves it and its contents alone", () => {
    const linkRoot = scratchFolder();
    const realFolder = join(linkRoot, "runner-tools");
    mkdirSync(realFolder);
    writeFileSync(join(realFolder, "keep.txt"), "someone's file");
    expect(() => linkAgentTools({ linkRoot, toolsFolder: TOOLS_FOLDER })).toThrow(/is a real folder, not the runner's tool link/);
    expect(lstatSync(realFolder).isDirectory()).toBe(true);
    expect(readFileSync(join(realFolder, "keep.txt"), "utf8")).toBe("someone's file");
  });

  it("refuses a real file at the link path and leaves it alone", () => {
    const linkRoot = scratchFolder();
    const realFile = join(linkRoot, "runner-tools");
    writeFileSync(realFile, "not a link");
    expect(() => linkAgentTools({ linkRoot, toolsFolder: TOOLS_FOLDER })).toThrow(/is a real file, not the runner's tool link/);
    expect(readFileSync(realFile, "utf8")).toBe("not a link");
  });

  it("replaces a link to elsewhere, even one whose target is gone, and keeps that target untouched", () => {
    const linkRoot = scratchFolder();
    const otherTarget = join(scratchFolder(), "other-tools");
    mkdirSync(otherTarget);
    writeFileSync(join(otherTarget, "check.mjs"), "// another clone's tool");
    symlinkSync(otherTarget, join(linkRoot, "runner-tools"), "dir");
    const relinked = linkAgentTools({ linkRoot, toolsFolder: TOOLS_FOLDER });
    expect(realpathSync(relinked.checkToolPath)).toBe(join(TOOLS_FOLDER, "check.mjs"));
    expect(readFileSync(join(otherTarget, "check.mjs"), "utf8")).toBe("// another clone's tool");

    const danglingRoot = scratchFolder();
    const goneTarget = join(scratchFolder(), "gone");
    mkdirSync(goneTarget);
    symlinkSync(goneTarget, join(danglingRoot, "runner-tools"), "dir");
    rmSync(goneTarget, { recursive: true });
    const fromDangling = linkAgentTools({ linkRoot: danglingRoot, toolsFolder: TOOLS_FOLDER });
    expect(existsSync(fromDangling.checkToolPath)).toBe(true);
  });
});

// An old-shape reminder: no $type, epoch-ms at, an empty title (its upgrade fails), and a
// priority field the page kept before any schema named it.
const OLD_SHAPE_RECORD_WITH_PRIORITY = { key: "reminder:1", value: { title: "", at: 1760000000000, priority: "high" } };

const AGENT_THAT_ADDS_PRIORITY = `
import { readFileSync, writeFileSync } from "node:fs";
const manifest = JSON.parse(readFileSync("sidekick/manifest.json", "utf8"));
manifest.types["reminder:"].schema.properties.priority = { type: "integer", minimum: 1, maximum: 3 };
writeFileSync("sidekick/manifest.json", JSON.stringify(manifest, null, 2));
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>Reminders · priority</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Added a priority." }));
`;

describe("16: the clash check sees a stored record whose upgrade fails", () => {
  it("names the clash for the stored record", () => {
    const before = JSON.parse(readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8"));
    const after = JSON.parse(JSON.stringify(before));
    after.types["reminder:"].schema.properties.priority = { type: "integer" };
    const problems = storedRecordSchemaProblems({ sidekickId: "reminders", records: [OLD_SHAPE_RECORD_WITH_PRIORITY], manifestBefore: before, manifest: after });
    expect(problems).toEqual(["reminders.item.priority is new but reminder:1 already holds a priority field"]);
  });

  it("fails the job as schema not backward compatible, not as records do not fit schema", async () => {
    const { scratch, settings } = makeScratch();
    const backendServer = await startFakeBackend({ id: "rep-clash-16", user_id: "user-1", sidekick_id: "reminders", transcript: "priority" }, standardAssets(), [OLD_SHAPE_RECORD_WITH_PRIORITY]);
    try {
      const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
      const job = await backend.claimJob();
      const deploy = fakeDeployThatLands();
      const result = await runJob(job, {
        backend,
        settings,
        agentCommand: process.execPath,
        agentArgs: [writeStubAgent(scratch, AGENT_THAT_ADDS_PRIORITY)],
        runFetch: fakeFetchWithoutStoredTests().runFetch,
        runTests: async function passingTests() {
          return { ok: true, output: "all passed" };
        },
        runDeploy: deploy.runDeploy,
        readPointer: deploy.readPointer,
        notify: async function ignoreNotification() {},
      });
      expect(result.status).toBe("failed");
      expect(result.reason).toBe("schema not backward compatible");
      expect(result.detail).toContain("reminders.item.priority is new but reminder:1 already holds a priority field");
      expect(deploy.deployCalls).toEqual([]);
    } finally {
      await backendServer.close();
    }
  });
});
