// Lead item 16 (reviewer B, second pass, 2026-10-20): a stored record whose upgrade fails and that
// moves key (task:9 is upgraded to reminder:9) sits under task:, which has no type, and its upgrade
// is not written; the new-field clash check must still see it under reminder:, so the job's reason
// is the clash ("schema not backward compatible"), not "records do not fit schema".
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
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

// An undated item from before the rework: a task: key, an empty title (its upgrade fails), and a
// priority field the page kept before any schema named it.
const OLD_TASK_WITH_PRIORITY = { key: "task:9", value: { title: "", body: "old notes", priority: "high" } };

const AGENT_THAT_ADDS_PRIORITY = `
import { readFileSync, writeFileSync } from "node:fs";
const manifest = JSON.parse(readFileSync("sidekick/manifest.json", "utf8"));
manifest.types["reminder:"].schema.properties.priority = { type: "integer", minimum: 1, maximum: 3 };
writeFileSync("sidekick/manifest.json", JSON.stringify(manifest, null, 2));
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>Reminders · priority</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Added a priority." }));
`;

describe("16: a failed upgrade that moves key still shows its clash", () => {
  it("checks the stored task:9 under reminder:, the key it upgrades to", () => {
    const before = JSON.parse(readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8"));
    const after = JSON.parse(JSON.stringify(before));
    after.types["reminder:"].schema.properties.priority = { type: "integer" };
    const problems = storedRecordSchemaProblems({ sidekickId: "reminders", records: [OLD_TASK_WITH_PRIORITY], manifestBefore: before, manifest: after });
    expect(problems).toEqual(["reminders.item.priority is new but reminder:9 already holds a priority field"]);
  });

  it("fails the job as schema not backward compatible, not as records do not fit schema", async () => {
    const { scratch, settings } = makeScratch();
    const backendServer = await startFakeBackend({ id: "rep-clash-moved", user_id: "user-1", sidekick_id: "reminders", transcript: "priority" }, standardAssets(), [OLD_TASK_WITH_PRIORITY]);
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
      expect(result.detail).toContain("reminders.item.priority is new but reminder:9 already holds a priority field");
      expect(deploy.deployCalls).toEqual([]);
    } finally {
      await backendServer.close();
    }
  });
});
