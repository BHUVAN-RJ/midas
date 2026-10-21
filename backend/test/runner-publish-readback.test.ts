// A repair whose publish went through must end deployed_live, with the user's done notice, even
// when the read-back of the user's current.json fails afterwards (repair 13edb182, staging,
// 2026-10-20: the deploy script wrote the copy and the pointer, the read-back could not read it,
// and the report ended "failed / deploy failed"; lead brief 2026-10-21). The read-back is tried
// again; when it never answers, the deploy script's own "deployed ... for user ..." line on a
// clean exit counts as the publish. A pointer that names other files is still a failure.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { READ_BACK_ATTEMPTS, publishFix, publishedVersionFromOutput } from "../../runner/lib/deploy.mjs";
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

const JOB_ROW = { id: "rep-31", user_id: "user-77", sidekick_id: "reminders", bundle_version: "20261011T065908559Z-1064a312", kind: "bug", transcript: "the title is wrong" };

// The closing lines deploy-sidekick.mjs printed for repair 13edb182 (runner log, deploy-output.txt).
const REAL_OUTPUT = [
  'Creating object "sidekicks/reminders/users/9-GAkqjLqjvn6Hyr9-AbTg/current.json" in bucket "midas-bundles-staging".',
  "Upload complete.",
  "deployed reminders 20261020T055239856Z-b44ec144 for user 9-GAkqjLqjvn6Hyr9-AbTg to staging with 1 script hash(es) and 9 test file(s); base untouched",
].join("\n");

type DeployCall = { checkoutRoot: string; args: string[] };

// readsBeforeAnswer: how many read-backs return null before one answers; Infinity = never answers.
function fakeDeploy({ printsLine, readsBeforeAnswer }: { printsLine: boolean; readsBeforeAnswer: number }) {
  const deployCalls: DeployCall[] = [];
  let pointerReads = 0;
  async function runDeploy({ checkoutRoot, args }: DeployCall) {
    deployCalls.push({ checkoutRoot, args });
    const userId = args[args.indexOf("--user") + 1];
    const output = printsLine ? `Upload complete.\ndeployed reminders v-unread for user ${userId} to live with 1 script hash(es) and 0 test file(s); base untouched` : "Upload complete.";
    return { ok: true, output, exitCode: 0 };
  }
  async function readPointer() {
    pointerReads += 1;
    if (pointerReads <= readsBeforeAnswer) {
      return null;
    }
    const deployed = deployCalls[deployCalls.length - 1];
    const sidekickFolder = deployed.args[deployed.args.indexOf("--dir") + 1];
    return { version: "v-read", contentHash: deployedFolderHash(sidekickFolder), baseVersion: null, scriptHashes: [] };
  }
  function readCount() {
    return pointerReads;
  }
  return { runDeploy, readPointer, readCount };
}

function makeJobFolder() {
  const { scratch, checkout } = makeScratch();
  const jobFolder = join(scratch, "job");
  mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
  writeFileSync(join(jobFolder, "sidekick", "index.html"), "<title>x</title>");
  writeFileSync(join(jobFolder, "sidekick", "manifest.json"), "{}");
  return { checkout, jobFolder };
}

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

describe("publishedVersionFromOutput", () => {
  it("reads the version from the script's closing line for that user and Sidekick only", () => {
    expect(publishedVersionFromOutput({ output: REAL_OUTPUT, sidekickId: "reminders", userId: "9-GAkqjLqjvn6Hyr9-AbTg" })).toBe("20261020T055239856Z-b44ec144");
    expect(publishedVersionFromOutput({ output: REAL_OUTPUT, sidekickId: "reminders", userId: "someone-else" })).toBeNull();
    expect(publishedVersionFromOutput({ output: REAL_OUTPUT, sidekickId: "care-reminders", userId: "9-GAkqjLqjvn6Hyr9-AbTg" })).toBeNull();
    expect(publishedVersionFromOutput({ output: "Upload complete.", sidekickId: "reminders", userId: "9-GAkqjLqjvn6Hyr9-AbTg" })).toBeNull();
    // A base deploy's line names no user and is never taken for a user's publish.
    expect(publishedVersionFromOutput({ output: "deployed reminders v1 to staging with 1 script hash(es) and 9 test file(s)", sidekickId: "reminders", userId: "9-GAkqjLqjvn6Hyr9-AbTg" })).toBeNull();
  });
});

describe("publishFix when the read-back fails", () => {
  it("a read-back that never answers after a clean deploy is a publish, marked unconfirmed", async () => {
    const { checkout, jobFolder } = makeJobFolder();
    const deploy = fakeDeploy({ printsLine: true, readsBeforeAnswer: Infinity });
    const published = await publishFix({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-77", jobFolder, runDeploy: deploy.runDeploy, readPointer: deploy.readPointer });
    expect(published.ok).toBe(true);
    expect(published.version).toBe("v-unread");
    expect(published.readBack).toBe("unconfirmed");
    expect(deploy.readCount()).toBe(READ_BACK_ATTEMPTS);
  });

  it("the read-back is tried again and a later answer is checked as usual", async () => {
    const { checkout, jobFolder } = makeJobFolder();
    const deploy = fakeDeploy({ printsLine: true, readsBeforeAnswer: 1 });
    const published = await publishFix({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-77", jobFolder, runDeploy: deploy.runDeploy, readPointer: deploy.readPointer });
    expect(published.ok).toBe(true);
    expect(published.version).toBe("v-read");
    expect(published.readBack).toBe("matched");
    expect(deploy.readCount()).toBe(2);
  });

  it("without the script's line for this user, an unreadable pointer is still a failure", async () => {
    const { checkout, jobFolder } = makeJobFolder();
    const deploy = fakeDeploy({ printsLine: false, readsBeforeAnswer: Infinity });
    const published = await publishFix({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-77", jobFolder, runDeploy: deploy.runDeploy, readPointer: deploy.readPointer });
    expect(published.ok).toBe(false);
    expect(published.problem).toMatch(/could not be read back/);
  });
});

describe("runJob: a published copy always ends deployed_live", () => {
  it("unreadable pointer after a clean deploy posts deployed_live (the user's done notice) and tells the founder", async () => {
    const { scratch, settings } = makeScratch();
    const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
    openBackend = backendServer;
    const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
    const job = await backend.claimJob();
    const deploy = fakeDeploy({ printsLine: true, readsBeforeAnswer: Infinity });
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

    expect(result.status).toBe("deployed_live");
    expect(result.version).toBe("v-unread");
    const statusNames = backendServer.statuses.map((status) => status.status);
    expect(statusNames).toEqual(["running", "fix_ready", "deployed_live"]);
    expect(statusNames).not.toContain("failed");
    expect(backendServer.statuses[2]).toEqual({ status: "deployed_live", summary: "Renamed the page title to My Reminders.", version: "v-unread" });
    expect(notifications[notifications.length - 1].title).toBe("Fixed and live: reminders");
    expect(notifications[notifications.length - 1].body).toContain("read-back unconfirmed");
    const summary = readFileSync(join(result.logFolder, "summary.md"), "utf8");
    expect(summary).toContain("could not be read back after the deploy");
  });
});
