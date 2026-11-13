// How the runner gets a copy's tests and sends them back up, against what repair-copies built
// on main (merged 2026-10-14): tests come down with scripts/fetch-sidekick-copy.mjs into
// <out>/tests/ (plus an index.json the runner leaves out), and deploy-sidekick.mjs --dir <path>
// reads <path>/index.html, manifest.json and tests/. No tests asset, no --tests flag.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { TEST_LOG_FILE, fetchArgs, fetchCopyTests, fetchFolderFor, readFetchedTests } from "../../runner/lib/copy-tests.mjs";
import { deployArgs, deployFolderFor, publishFix, stageDeployFolder } from "../../runner/lib/deploy.mjs";
import { listFilesRecursively } from "../../runner/lib/job-folder.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import {
  AGENT_THAT_FIXES_TITLE,
  REPO_ROOT,
  RUNNER_TOKEN,
  fakeDeployThatLands,
  makeScratch,
  remindersBundle,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

const JOB_ROW = { id: "rep-f1", user_id: "user-77", sidekick_id: "reminders", bundle_version: "v1", kind: "bug", transcript: "the title is wrong" };

const COPY_TEST = 'import { describe, expect, it } from "vitest"; describe("copy", () => { it("is", () => { expect(1).toBe(1); }); });\n';

// A stand-in for fetch-sidekick-copy.mjs: writes what the real script writes into --out.
function fakeFetch(mode: "withTests" | "noStoredTests" | "fails" | "badName") {
  const calls: Array<{ checkoutRoot: string; args: string[] }> = [];
  const runFetch = async ({ checkoutRoot, args, outFolder }: { checkoutRoot: string; args: string[]; outFolder: string }) => {
    calls.push({ checkoutRoot, args });
    if (mode === "fails") {
      return { ok: false, output: "live has no version of reminders for user user-77 and no base" };
    }
    mkdirSync(join(outFolder, "tests"), { recursive: true });
    writeFileSync(join(outFolder, "index.html"), "<title>stored</title>");
    writeFileSync(join(outFolder, "manifest.json"), "{}");
    writeFileSync(join(outFolder, "version.json"), "{}");
    if (mode === "withTests") {
      writeFileSync(join(outFolder, "tests", "reminders-copy.test.ts"), COPY_TEST);
      writeFileSync(join(outFolder, "tests", TEST_LOG_FILE), "- copy log\n");
      writeFileSync(join(outFolder, "tests", "index.json"), JSON.stringify({ files: ["reminders-copy.test.ts", TEST_LOG_FILE] }));
    } else if (mode === "badName") {
      writeFileSync(join(outFolder, "tests", ".hidden.test.ts"), COPY_TEST);
      writeFileSync(join(outFolder, "tests", "index.json"), JSON.stringify({ files: [".hidden.test.ts"] }));
    } else {
      writeFileSync(join(outFolder, "tests", "index.json"), JSON.stringify({ files: [] }));
    }
    return { ok: true, output: `fetched reminders v1 into ${outFolder}` };
  };
  return { runFetch, calls };
}

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

describe("fetching the copy's tests", () => {
  it("builds the fetch command for the reporter's live copy into a folder beside the job", () => {
    expect(fetchArgs({ sidekickId: "reminders", userId: "user-77", outFolder: "/jobs/rep-f1.fetch" })).toEqual([
      "scripts/fetch-sidekick-copy.mjs", "reminders", "--env", "live", "--user", "user-77", "--out", "/jobs/rep-f1.fetch",
    ]);
    expect(fetchFolderFor("/jobs/rep-f1")).toBe("/jobs/rep-f1.fetch");
  });

  it("takes the stored tests and the log, leaves the index out, and removes the fetch folder", async () => {
    const { scratch, checkout } = makeScratch();
    const jobFolder = join(scratch, "job");
    const fetch = fakeFetch("withTests");
    const result = await fetchCopyTests({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-77", jobFolder, runFetch: fetch.runFetch });
    expect(result.source).toBe("user copy");
    expect(Object.keys(result.files).sort()).toEqual([TEST_LOG_FILE, "reminders-copy.test.ts"]);
    expect(result.files["reminders-copy.test.ts"]).toBe(COPY_TEST);
    expect(fetch.calls[0].checkoutRoot).toBe(checkout);
    expect(fetch.calls[0].args[fetch.calls[0].args.indexOf("--out") + 1]).toBe(fetchFolderFor(jobFolder));
    expect(existsSync(fetchFolderFor(jobFolder))).toBe(false);
  });

  it("a copy with no stored tests gets the base Sidekick's tests from the checkout", async () => {
    const { scratch, checkout } = makeScratch();
    const jobFolder = join(scratch, "job");
    const result = await fetchCopyTests({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-77", jobFolder, runFetch: fakeFetch("noStoredTests").runFetch });
    expect(result.source).toBe("base checkout");
    const names = Object.keys(result.files);
    expect(names).toContain(TEST_LOG_FILE);
    expect(names.some((name) => name.startsWith("reminders-") && name.endsWith(".test.ts"))).toBe(true);
    expect(existsSync(fetchFolderFor(jobFolder))).toBe(false);
  });

  it("a failing fetch script throws with the script's last words, and a bad file name is refused", async () => {
    const { scratch, checkout } = makeScratch();
    const jobFolder = join(scratch, "job");
    await expect(fetchCopyTests({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-77", jobFolder, runFetch: fakeFetch("fails").runFetch })).rejects.toThrow(/fetch-sidekick-copy failed: live has no version/);
    await expect(fetchCopyTests({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-77", jobFolder, runFetch: fakeFetch("badName").runFetch })).rejects.toThrow(/bad file name/);
    expect(existsSync(fetchFolderFor(jobFolder))).toBe(false);
  });

  it("readFetchedTests reads an empty or missing tests folder as no files", () => {
    const { scratch } = makeScratch();
    expect(readFetchedTests(join(scratch, "nowhere"))).toEqual({});
    mkdirSync(join(scratch, "out", "tests"), { recursive: true });
    writeFileSync(join(scratch, "out", "tests", "index.json"), "{}");
    expect(readFetchedTests(join(scratch, "out"))).toEqual({});
  });
});

describe("staging the deploy folder", () => {
  it("holds exactly index.html, manifest.json and tests/ without the index, and deployArgs points --dir at it", () => {
    const { scratch } = makeScratch();
    const bundle = remindersBundle();
    const jobFolder = join(scratch, "job");
    mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
    mkdirSync(join(jobFolder, "tests"), { recursive: true });
    mkdirSync(join(jobFolder, "report"), { recursive: true });
    writeFileSync(join(jobFolder, "sidekick", "index.html"), bundle.html);
    writeFileSync(join(jobFolder, "sidekick", "manifest.json"), bundle.manifestText);
    writeFileSync(join(jobFolder, "tests", "reminders-copy.test.ts"), COPY_TEST);
    writeFileSync(join(jobFolder, "tests", TEST_LOG_FILE), "- log\n");
    writeFileSync(join(jobFolder, "tests", "index.json"), "{}");
    writeFileSync(join(jobFolder, "report", "transcript.txt"), "words");

    const deployFolder = deployFolderFor(jobFolder);
    expect(deployFolder).toBe(`${jobFolder}.deploy`);
    stageDeployFolder({ jobFolder, deployFolder });
    expect(listFilesRecursively(deployFolder)).toEqual(["index.html", "manifest.json", "tests/TEST_CHANGES.md", "tests/reminders-copy.test.ts"]);
    expect(readFileSync(join(deployFolder, "index.html"), "utf8")).toBe(bundle.html);

    expect(deployArgs({ sidekickId: "reminders", userId: "user-77", deployFolder })).toEqual([
      "scripts/deploy-sidekick.mjs", "reminders", "--env", "live", "--user", "user-77", "--dir", deployFolder,
    ]);
    expect(deployArgs({ sidekickId: "reminders", userId: "user-77", deployFolder })).not.toContain("--tests");
    expect(() => deployArgs({ sidekickId: "reminders", userId: "user-77", deployFolder: "" })).toThrow(/no deploy folder/);
  });

  it("publishFix stages, deploys from the staged folder, and removes it whether the deploy lands or not", async () => {
    const { scratch, checkout } = makeScratch();
    const bundle = remindersBundle();
    const jobFolder = join(scratch, "job");
    mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
    mkdirSync(join(jobFolder, "tests"), { recursive: true });
    writeFileSync(join(jobFolder, "sidekick", "index.html"), bundle.html);
    writeFileSync(join(jobFolder, "sidekick", "manifest.json"), bundle.manifestText);
    writeFileSync(join(jobFolder, "tests", "reminders-copy.test.ts"), COPY_TEST);
    const deployFolder = deployFolderFor(jobFolder);

    const seen: string[] = [];
    const deploy = fakeDeployThatLands();
    const published = await publishFix({
      checkoutRoot: checkout,
      sidekickId: "reminders",
      userId: "user-77",
      jobFolder,
      runDeploy: async (call: { checkoutRoot: string; args: string[] }) => {
        seen.push(...listFilesRecursively(call.args[call.args.indexOf("--dir") + 1]));
        return deploy.runDeploy(call);
      },
      readPointer: deploy.readPointer,
    });
    expect(published.ok).toBe(true);
    expect(seen).toEqual(["index.html", "manifest.json", "tests/reminders-copy.test.ts"]);
    expect(existsSync(deployFolder)).toBe(false);

    const failed = await publishFix({ checkoutRoot: checkout, sidekickId: "reminders", userId: "user-77", jobFolder, runDeploy: async () => ({ ok: false, output: "refused", exitCode: 1 }), readPointer: deploy.readPointer });
    expect(failed.ok).toBe(false);
    expect(existsSync(deployFolder)).toBe(false);
  });

  it("the real deploy script on this branch reads --dir the way the runner stages it (usage check, no network)", () => {
    const script = readFileSync(join(REPO_ROOT, "backend", "scripts", "deploy-sidekick.mjs"), "utf8");
    expect(script).toContain("--dir");
    expect(script).toContain("readDirectoryTestFiles");
    expect(script).not.toContain('"--tests"');
    const fetchScript = readFileSync(join(REPO_ROOT, "backend", "scripts", "fetch-sidekick-copy.mjs"), "utf8");
    expect(fetchScript).toContain("--out");
  });
});

describe("runJob with the fetch step", () => {
  async function runWithFetch(mode: "withTests" | "noStoredTests" | "fails") {
    const { scratch, settings } = makeScratch();
    const backendServer = await startFakeBackend(JOB_ROW, standardAssets());
    openBackend = backendServer;
    const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
    const job = await backend.claimJob();
    const fetch = fakeFetch(mode);
    const deploy = fakeDeployThatLands();
    const testRuns: string[][] = [];
    const result = await runJob(job, {
      backend,
      settings,
      agentCommand: process.execPath,
      agentArgs: [writeStubAgent(scratch, AGENT_THAT_FIXES_TITLE)],
      runFetch: fetch.runFetch,
      runTests: async ({ sandboxBackend }: { sandboxBackend: string }) => {
        testRuns.push(listFilesRecursively(join(sandboxBackend, "test")));
        return { ok: true, output: "ok" };
      },
      runDeploy: deploy.runDeploy,
      readPointer: deploy.readPointer,
      notify: async () => {},
    });
    return { result, backendServer, fetch, deploy, testRuns };
  }

  it("fetches the reporter's copy tests first, runs them, and deploys them from the staged folder", async () => {
    const { result, fetch, deploy, testRuns } = await runWithFetch("withTests");
    expect(result.status).toBe("deployed_live");
    expect(fetch.calls).toHaveLength(1);
    expect(fetch.calls[0].args.slice(0, 6)).toEqual(["scripts/fetch-sidekick-copy.mjs", "reminders", "--env", "live", "--user", "user-77"]);
    expect(listFilesRecursively(join(result.jobFolder, "tests"))).toEqual(["PERSON_NOTES.md", TEST_LOG_FILE, "reminders-copy.test.ts"]);
    expect(testRuns[0]).toEqual([TEST_LOG_FILE, "reminders-copy.test.ts"]);
    const args = deploy.deployCalls[0].args;
    expect(args[args.indexOf("--dir") + 1]).toBe(deployFolderFor(result.jobFolder));
    expect(args).not.toContain("--tests");
    expect(existsSync(deployFolderFor(result.jobFolder))).toBe(false);
    expect(existsSync(fetchFolderFor(result.jobFolder))).toBe(false);
    expect(readFileSync(join(result.logFolder, "fetch-output.txt"), "utf8")).toContain("fetched reminders v1");
    const report = JSON.parse(readFileSync(join(result.logFolder, "tests-report.json"), "utf8"));
    expect(report.source).toBe("user copy");
  });

  it("a copy with no stored tests runs and deploys the base tests", async () => {
    const { result, testRuns } = await runWithFetch("noStoredTests");
    expect(result.status).toBe("deployed_live");
    expect(testRuns[0].some((name) => name.startsWith("reminders-") && name.endsWith(".test.ts"))).toBe(true);
    const report = JSON.parse(readFileSync(join(result.logFolder, "tests-report.json"), "utf8"));
    expect(report.source).toBe("base checkout");
  });

  it("a failing fetch ends the job as tests missing before the agent runs", async () => {
    const { result, backendServer, deploy } = await runWithFetch("fails");
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("tests missing");
    expect(result.detail).toContain("fetch-sidekick-copy failed");
    expect(existsSync(join(result.logFolder, "agent-stream.jsonl"))).toBe(false);
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "failed"]);
    expect(deploy.deployCalls).toEqual([]);
  });
});
