// The runner publishes the fix itself (founder, 2026-10-13, docs/briefs/repair-contract.md
// "Settled"): after the check passes it runs deploy-sidekick.mjs for the reporter's copy only,
// reads the user's current.json back from live, compares the content hash, and only then posts
// deployed_live. A failing deploy script or a read-back naming other files posts failed; a read-back
// that never answers after the script reported this user's copy published posts deployed_live
// (founder, 2026-10-21: a published repair is always marked done). Never a base deploy.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { bundleContentHash } from "../scripts/bundle-tools.mjs";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { deployArgs, deployFolderFor, publishFix, verifyPointer } from "../../runner/lib/deploy.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import {
  AGENT_THAT_FIXES_TITLE,
  RUNNER_TOKEN,
  deployedFolderHash,
  fakeFetchWithoutStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

const JOB_ROW = { id: "rep-9", user_id: "user-77", sidekick_id: "reminders", bundle_version: "20261011T065908559Z-1064a312", kind: "bug", transcript: "the title is wrong" };

type DeployCall = { checkoutRoot: string; args: string[] };
type PointerRead = { sidekickId: string; userId: string };

// A stand-in for deploy-sidekick.mjs and the live read-back. "lands" means the pointer read back
// names exactly the files in the job folder; "wrongHash" means live holds something else;
// "scriptFails" means the script exits non-zero and nothing is read back.
function fakeDeploy(mode: "lands" | "wrongHash" | "unreadable" | "scriptFails") {
  const deployCalls: DeployCall[] = [];
  const pointerReads: PointerRead[] = [];
  const runDeploy = async ({ checkoutRoot, args }: DeployCall) => {
    deployCalls.push({ checkoutRoot, args });
    if (mode === "scriptFails") {
      return { ok: false, output: "live deploy refused: wrangler not logged in", exitCode: 1 };
    }
    return { ok: true, output: `deployed reminders v-test for user ${args[args.indexOf("--user") + 1]} to live`, exitCode: 0 };
  };
  const readPointer = async ({ sidekickId, userId }: PointerRead) => {
    pointerReads.push({ sidekickId, userId });
    if (mode === "unreadable") {
      return null;
    }
    if (mode === "wrongHash") {
      return { version: "v-old", contentHash: "0000", baseVersion: null, scriptHashes: [] };
    }
    const deployed = deployCalls[deployCalls.length - 1];
    const sidekickFolder = deployed.args[deployed.args.indexOf("--dir") + 1];
    return { version: "v-test", contentHash: deployedFolderHash(sidekickFolder), baseVersion: null, scriptHashes: [] };
  };
  return { runDeploy, readPointer, deployCalls, pointerReads };
}

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

async function runWithDeploy(mode: "lands" | "wrongHash" | "unreadable" | "scriptFails", jobRow: Record<string, unknown> = JOB_ROW) {
  const { scratch, settings } = makeScratch();
  const backendServer = await startFakeBackend(jobRow as typeof JOB_ROW, standardAssets());
  openBackend = backendServer;
  const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const job = await backend.claimJob();
  const deploy = fakeDeploy(mode);
  const notifications: Array<{ title: string; body: string }> = [];
  const result = await runJob(job, {
    backend,
    settings,
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, AGENT_THAT_FIXES_TITLE)],
    runFetch: fakeFetchWithoutStoredTests().runFetch,
    runTests: async () => ({ ok: true, output: "81 passed" }),
    runDeploy: deploy.runDeploy,
    readPointer: deploy.readPointer,
    notify: async (notification: { title: string; body: string }) => {
      notifications.push(notification);
    },
  });
  return { result, backendServer, deploy, notifications, settings };
}

describe("deployArgs: the reporter's copy only", () => {
  it("builds the live user deploy for the reporter from the staged deploy folder", () => {
    const args = deployArgs({ sidekickId: "reminders", userId: "user-77", deployFolder: "/jobs/rep-9.deploy" });
    // The staged folder holds the page and the copy's tests/ with TEST_CHANGES.md; deploy-sidekick.mjs
    // --dir reads all of it (contract, 2026-10-13; repair-copies merged 2026-10-14). No --tests flag.
    expect(args).toEqual(["scripts/deploy-sidekick.mjs", "reminders", "--env", "live", "--user", "user-77", "--dir", "/jobs/rep-9.deploy"]);
    expect(args).not.toContain("--tests");
    expect(args).not.toContain("--from-base");
    expect(args).not.toContain("staging");
  });

  it("refuses to build a command without a valid reporter id (which would be a base deploy) or a deploy folder", () => {
    expect(() => deployArgs({ sidekickId: "reminders", userId: null, deployFolder: "/jobs/rep-9.deploy" })).toThrow(/never deploys the base/);
    expect(() => deployArgs({ sidekickId: "reminders", userId: "", deployFolder: "/jobs/rep-9.deploy" })).toThrow(/never deploys the base/);
    expect(() => deployArgs({ sidekickId: "reminders", userId: "bad id with spaces", deployFolder: "/jobs/rep-9.deploy" })).toThrow(/never deploys the base/);
    expect(() => deployArgs({ sidekickId: "../etc", userId: "user-77", deployFolder: "/jobs/rep-9.deploy" })).toThrow(/bad Sidekick id/);
    expect(() => deployArgs({ sidekickId: "reminders", userId: "user-77", deployFolder: "" })).toThrow(/no deploy folder/);
  });
});

describe("verifyPointer", () => {
  it("accepts only a pointer whose content hash is the published one", () => {
    expect(verifyPointer({ pointer: { version: "v1", contentHash: "abc" }, expectedHash: "abc" })).toBeNull();
    expect(verifyPointer({ pointer: { version: "v1", contentHash: "abd" }, expectedHash: "abc" })).toMatch(/content hash abd, expected abc/);
    expect(verifyPointer({ pointer: { version: "", contentHash: "abc" }, expectedHash: "abc" })).toMatch(/names no version/);
    expect(verifyPointer({ pointer: null, expectedHash: "abc" })).toMatch(/could not be read back/);
  });
});

describe("publishFix", () => {
  it("runs the deploy from the checkout's backend and reports the live version on a match", async () => {
    const { scratch, checkout } = makeScratch();
    const jobFolder = join(scratch, "job");
    const { mkdirSync, writeFileSync } = await import("node:fs");
    mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
    writeFileSync(join(jobFolder, "sidekick", "index.html"), "<title>x</title>");
    writeFileSync(join(jobFolder, "sidekick", "manifest.json"), "{}");
    const deploy = fakeDeploy("lands");
    const published = await publishFix({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-77", jobFolder, runDeploy: deploy.runDeploy, readPointer: deploy.readPointer });
    expect(published.ok).toBe(true);
    expect(published.version).toBe("v-test");
    expect(published.contentHash).toBe(bundleContentHash("<title>x</title>", "{}"));
    expect(deploy.deployCalls[0].checkoutRoot).toBe(checkout);
    expect(deploy.pointerReads).toEqual([{ sidekickId: "reminders", userId: "user-77" }]);
  });

  it("a hash mismatch on read-back is not a publish", async () => {
    const { scratch, checkout } = makeScratch();
    const jobFolder = join(scratch, "job");
    const { mkdirSync, writeFileSync } = await import("node:fs");
    mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
    writeFileSync(join(jobFolder, "sidekick", "index.html"), "<title>x</title>");
    writeFileSync(join(jobFolder, "sidekick", "manifest.json"), "{}");
    const deploy = fakeDeploy("wrongHash");
    const published = await publishFix({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-77", jobFolder, runDeploy: deploy.runDeploy, readPointer: deploy.readPointer });
    expect(published.ok).toBe(false);
    expect(published.problem).toMatch(/content hash 0000/);
  });
});

describe("runJob publishes after the check", () => {
  it("fix_ready, then deploy for the reporter only, read-back match, deployed_live, notification says it is live", async () => {
    const { result, backendServer, deploy, notifications } = await runWithDeploy("lands");

    expect(result.status).toBe("deployed_live");
    expect(result.version).toBe("v-test");
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "fix_ready", "deployed_live"]);
    expect(backendServer.statuses[2]).toEqual({ status: "deployed_live", summary: "Renamed the page title to My Reminders.", version: "v-test" });

    // Exactly one deploy, for the reporter's copy, from the job folder, never the base.
    expect(deploy.deployCalls).toHaveLength(1);
    const args = deploy.deployCalls[0].args;
    expect(args.slice(0, 4)).toEqual(["scripts/deploy-sidekick.mjs", "reminders", "--env", "live"]);
    expect(args[args.indexOf("--user") + 1]).toBe("user-77");
    expect(args[args.indexOf("--dir") + 1]).toBe(deployFolderFor(result.jobFolder));
    expect(args).not.toContain("--tests");
    expect(args).not.toContain("--from-base");
    expect(existsSync(deployFolderFor(result.jobFolder))).toBe(false);
    expect(deploy.pointerReads).toEqual([{ sidekickId: "reminders", userId: "user-77" }]);

    expect(notifications.map((notification) => notification.title)).toEqual(["Repair request: reminders", "Fixed and live: reminders"]);
    expect(notifications[1].body).toContain("Renamed the page title to My Reminders.");
    expect(notifications[1].body).toContain("live for user-77");

    const summary = readFileSync(join(result.logFolder, "summary.md"), "utf8");
    expect(summary).toContain("Version v-test is live for user user-77");
    expect(summary).toContain("node scripts/deploy-sidekick.mjs reminders --env live --user user-77 --from-base");
    expect(summary).not.toContain("--dir");
    expect(readFileSync(join(result.logFolder, "deploy-output.txt"), "utf8")).toContain("deployed reminders v-test for user user-77");
  });

  it("a read-back hash mismatch ends failed, never deployed_live", async () => {
    const { result, backendServer, notifications } = await runWithDeploy("wrongHash");
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("deploy failed");
    expect(result.detail).toMatch(/content hash 0000/);
    const statusNames = backendServer.statuses.map((status) => status.status);
    expect(statusNames).toEqual(["running", "fix_ready", "failed"]);
    expect(statusNames).not.toContain("deployed_live");
    expect(backendServer.statuses[2].reason).toBe("deploy failed");
    expect(notifications[1].title).toBe("Repair failed: reminders");
    expect(existsSync(join(result.logFolder, "summary.md"))).toBe(false);
  });

  // Founder, 2026-10-21 (docs/PRODUCT.md, "A published repair is always marked done"); bug: repair
  // 13edb182 (2026-10-20) was published, the read-back failed, and it ended failed with no notice.
  it("an unreadable pointer after a clean deploy that reported this user's copy ends deployed_live, never failed", async () => {
    const { result, backendServer, notifications } = await runWithDeploy("unreadable");
    expect(result.status).toBe("deployed_live");
    expect(result.version).toBe("v-test");
    const statusNames = backendServer.statuses.map((status) => status.status);
    expect(statusNames).toEqual(["running", "fix_ready", "deployed_live"]);
    expect(statusNames).not.toContain("failed");
    expect(backendServer.statuses[2]).toEqual({ status: "deployed_live", summary: "Renamed the page title to My Reminders.", version: "v-test" });
    expect(notifications[1].title).toBe("Fixed and live: reminders");
    expect(notifications[1].body).toContain("read-back unconfirmed");
  });

  it("a failing deploy script ends failed with the script's output kept, and nothing is read back", async () => {
    const { result, backendServer, deploy } = await runWithDeploy("scriptFails");
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("deploy failed");
    expect(result.detail).toMatch(/exited with code 1/);
    expect(deploy.pointerReads).toEqual([]);
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "fix_ready", "failed"]);
    expect(readFileSync(join(result.logFolder, "deploy-output.txt"), "utf8")).toContain("wrangler not logged in");
  });

  it("a job without a reporter id never runs the deploy script (no base deploy)", async () => {
    const { result, backendServer, deploy } = await runWithDeploy("lands", { ...JOB_ROW, user_id: "" });
    expect(result.status).toBe("failed");
    expect(result.detail).toMatch(/never deploys the base/);
    expect(deploy.deployCalls).toEqual([]);
    expect(backendServer.statuses.map((status) => status.status)).not.toContain("deployed_live");
  });

  it("a failing check never reaches the deploy", async () => {
    const { scratch, settings } = makeScratch();
    const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
    openBackend = backendServer;
    const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
    const job = await backend.claimJob();
    const deploy = fakeDeploy("lands");
    const result = await runJob(job, {
      backend,
      settings,
      agentCommand: process.execPath,
      agentArgs: [writeStubAgent(scratch, AGENT_THAT_FIXES_TITLE)],
      runFetch: fakeFetchWithoutStoredTests().runFetch,
      runTests: async () => ({ ok: false, output: "FAIL reminders-logic.test.ts" }),
      runDeploy: deploy.runDeploy,
      readPointer: deploy.readPointer,
      notify: async () => {},
    });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("check failed");
    expect(deploy.deployCalls).toEqual([]);
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "failed"]);
  });
});
