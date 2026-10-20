// Fixtures for the repair runner tests: a fake backend (claim, assets, records, status) in-process, a
// throwaway checkout holding the Reminders Sidekick and the deploy gate, and stub agents.
import { createServer, type Server } from "node:http";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { bundleContentHash } from "../../scripts/bundle-tools.mjs";

export const REPO_ROOT = fileURLToPath(new URL("../../../", import.meta.url));
export const RUNNER_TOKEN = "runner-secret";

export type FakeJobRow = {
  id: string;
  user_id: string;
  sidekick_id: string;
  bundle_version?: string;
  kind?: string;
  transcript?: string;
};

export type FakeBackend = {
  baseUrl: string;
  statuses: Array<Record<string, unknown>>;
  claims: number;
  recordRequests: number;
  assetRequests: string[];
  close: () => Promise<void>;
};

// Serves one job once; 204 afterwards. Assets come from `assets` (404 when missing).
// GET /repairs/<id>/records (runner-only, founder 2026-10-19) answers `{ records }` from `records`.
export async function startFakeBackend(
  job: FakeJobRow | null,
  assets: Record<string, string | Buffer>,
  records: Array<{ key: string; value: unknown }> = [],
): Promise<FakeBackend> {
  const statuses: Array<Record<string, unknown>> = [];
  const assetRequests: string[] = [];
  let pendingJob = job;
  let claims = 0;
  let recordRequests = 0;
  const server: Server = createServer((request, response) => {
    if (request.headers.authorization !== `Runner ${RUNNER_TOKEN}`) {
      response.writeHead(401);
      response.end();
      return;
    }
    if (request.method === "POST" && request.url === "/repairs/jobs/claim") {
      claims += 1;
      if (pendingJob === null) {
        response.writeHead(204);
        response.end();
        return;
      }
      const body = JSON.stringify(pendingJob);
      pendingJob = null;
      response.writeHead(200, { "content-type": "application/json" });
      response.end(body);
      return;
    }
    const assetMatch = /^\/repairs\/([^/]+)\/assets\/(.+)$/.exec(request.url ?? "");
    if (request.method === "GET" && assetMatch !== null) {
      const assetName = decodeURIComponent(assetMatch[2]);
      assetRequests.push(assetName);
      const asset = assets[assetName];
      if (asset === undefined) {
        response.writeHead(404);
        response.end();
        return;
      }
      response.writeHead(200);
      response.end(asset);
      return;
    }
    const recordsMatch = /^\/repairs\/([^/]+)\/records$/.exec(request.url ?? "");
    if (request.method === "GET" && recordsMatch !== null) {
      recordRequests += 1;
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ records }));
      return;
    }
    const statusMatch = /^\/repairs\/([^/]+)\/status$/.exec(request.url ?? "");
    if (request.method === "POST" && statusMatch !== null) {
      let body = "";
      request.on("data", (chunk) => {
        body += chunk;
      });
      request.on("end", () => {
        statuses.push(JSON.parse(body));
        response.writeHead(200, { "content-type": "application/json" });
        response.end("{}");
      });
      return;
    }
    response.writeHead(404);
    response.end();
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  const port = typeof address === "object" && address !== null ? address.port : 0;
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    statuses,
    get claims() {
      return claims;
    },
    get recordRequests() {
      return recordRequests;
    },
    assetRequests,
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}

export function remindersBundle(): { html: string; manifestText: string } {
  const html = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "index.html"), "utf8");
  const manifestText = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8");
  return { html, manifestText };
}

export function standardAssets(): Record<string, string | Buffer> {
  const bundle = remindersBundle();
  return {
    "bundle.html": bundle.html,
    "bundle.manifest.json": bundle.manifestText,
    "screenshot.png": Buffer.from("PNG-screenshot"),
    "drawing.png": Buffer.from("PNG-drawing"),
    "strokes.json": JSON.stringify([[10, 20, 0], [30, 40, 50]]),
  };
}

// The three guard files the runner copies into every job folder (contract, 2026-10-13, "Tests
// move every copy forward"): the agent's session gets the test guard and the test-guardian.
export const GUARD_FILES = [
  join(".claude", "settings.json"),
  join(".claude", "hooks", "guard_tests.py"),
  join(".claude", "agents", "test-guardian.md"),
];

// Two of the base Reminders tests (backend/test/reminders-*.test.ts), sorted: what a copy's tests
// fall back to until intake serves them. A fixed pair, so the job-folder listings stay exact and
// runner-copy-tests.test.ts (which seeds the same two) agrees.
export function baseRemindersTestFiles(): string[] {
  return ["reminders-logic.test.ts", "reminders-wording.test.ts"];
}

// A scratch folder with a checkout that has what the runner reads: the Reminders Sidekick, the
// deploy gate, the two docs the prompt embeds, the three guard files and the base Reminders
// tests (the fallback for a copy's tests). The test runner itself is stubbed.
export function makeScratch(): { scratch: string; checkout: string; settings: Record<string, unknown> } {
  const scratch = mkdtempSync(join(tmpdir(), "midas-runner-test-"));
  const checkout = join(scratch, "checkout");
  mkdirSync(join(checkout, "sidekicks"), { recursive: true });
  cpSync(join(REPO_ROOT, "sidekicks", "reminders"), join(checkout, "sidekicks", "reminders"), { recursive: true });
  mkdirSync(join(checkout, "backend", "scripts"), { recursive: true });
  cpSync(join(REPO_ROOT, "backend", "scripts", "bundle-tools.mjs"), join(checkout, "backend", "scripts", "bundle-tools.mjs"));
  mkdirSync(join(checkout, "backend", "test"), { recursive: true });
  for (const testName of baseRemindersTestFiles()) {
    cpSync(join(REPO_ROOT, "backend", "test", testName), join(checkout, "backend", "test", testName));
  }
  for (const guardFile of GUARD_FILES) {
    mkdirSync(join(checkout, guardFile, ".."), { recursive: true });
    cpSync(join(REPO_ROOT, guardFile), join(checkout, guardFile));
  }
  mkdirSync(join(checkout, "docs"), { recursive: true });
  cpSync(join(REPO_ROOT, "docs", "WRITING.md"), join(checkout, "docs", "WRITING.md"));
  cpSync(join(REPO_ROOT, "docs", "NOTIFICATIONS.md"), join(checkout, "docs", "NOTIFICATIONS.md"));
  const settings = {
    jobsRoot: join(scratch, "jobs"),
    logsRoot: join(scratch, "log"),
    checkoutRoot: checkout,
    claudeConfigDir: join(scratch, "claude-config"),
    claudeCommand: "claude",
    model: "opus",
    maxTurns: 50,
    jobTimeoutMs: 60_000,
    heartbeatIntervalMs: 60_000,
  };
  return { scratch, checkout, settings };
}

export type DeployCall = { checkoutRoot: string; args: string[] };

// A stand-in for deploy-sidekick.mjs and the live read-back that always lands: the pointer read
// back names exactly the files in the --dir folder of the last deploy call (founder, 2026-10-13:
// the runner publishes the fix itself).
export function fakeDeployThatLands() {
  const deployCalls: DeployCall[] = [];
  const runDeploy = async ({ checkoutRoot, args }: DeployCall) => {
    deployCalls.push({ checkoutRoot, args });
    const userId = args[args.indexOf("--user") + 1];
    return { ok: true, output: `deployed reminders v-test for user ${userId} to live`, exitCode: 0 };
  };
  const readPointer = async () => {
    const deployed = deployCalls[deployCalls.length - 1];
    const sidekickFolder = deployed.args[deployed.args.indexOf("--dir") + 1];
    const html = readFileSync(join(sidekickFolder, "index.html"), "utf8");
    const manifestText = readFileSync(join(sidekickFolder, "manifest.json"), "utf8");
    return { version: "v-test", contentHash: bundleContentHash(html, manifestText), baseVersion: null, scriptHashes: [] };
  };
  return { runDeploy, readPointer, deployCalls };
}

export type FetchCall = { checkoutRoot: string; args: string[]; outFolder: string };

// A stand-in for scripts/fetch-sidekick-copy.mjs (repair-copies, merged 2026-10-14): writes
// what the real script writes into --out: the copy's page files and tests/ with an index.json
// naming the test files. `storedTests` is what the copy has stored; with none, the runner falls
// back to the base tests in the scratch checkout (contract, "Tests move every copy forward").
export function fakeFetchWithStoredTests(storedTests: Record<string, string>) {
  const calls: FetchCall[] = [];
  const runFetch = async ({ checkoutRoot, args, outFolder }: FetchCall) => {
    calls.push({ checkoutRoot, args, outFolder });
    const testsFolder = join(outFolder, "tests");
    mkdirSync(testsFolder, { recursive: true });
    writeFileSync(join(outFolder, "index.html"), "<title>stored</title>");
    writeFileSync(join(outFolder, "manifest.json"), "{}");
    writeFileSync(join(outFolder, "version.json"), "{}");
    for (const [name, content] of Object.entries(storedTests)) {
      writeFileSync(join(testsFolder, name), content);
    }
    writeFileSync(join(testsFolder, "index.json"), JSON.stringify({ files: Object.keys(storedTests) }));
    return { ok: true, output: `fetched reminders v1 into ${outFolder}` };
  };
  return { runFetch, calls };
}

// A copy with no stored tests: the fetch lands but tests/ holds only an empty index.
export function fakeFetchWithoutStoredTests() {
  return fakeFetchWithStoredTests({});
}

// A stub "claude": a node script run in the job folder. `body` is its source.
export function writeStubAgent(scratch: string, body: string): string {
  const agentPath = join(scratch, "stub-agent.mjs");
  writeFileSync(agentPath, body);
  return agentPath;
}

export const AGENT_THAT_FIXES_TITLE = `
import { readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>My Reminders</title>"));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Renamed the page title to My Reminders." }));
`;

export const AGENT_THAT_ADDS_EXTERNAL_SCRIPT = `
import { readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("</head>", '<script src="https://cdn.example/x.js"></script></head>'));
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Added a library." }));
`;

export const AGENT_THAT_WRITES_OUTSIDE = `
import { readFileSync, writeFileSync } from "node:fs";
const page = readFileSync("sidekick/index.html", "utf8");
writeFileSync("sidekick/index.html", page.replace("<title>Reminders</title>", "<title>X</title>"));
writeFileSync("notes.txt", "scratch");
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Changed title." }));
`;

export const AGENT_THAT_SAYS_UNSUPPORTED = `
import { writeFileSync } from "node:fs";
writeFileSync("outcome.json", JSON.stringify({ result: "unsupported", summary: "iOS has no wiggling notifications.", unsupportedAction: "a notification that wiggles" }));
`;

export const AGENT_THAT_CLAIMS_FIX_BUT_CHANGES_NOTHING = `
import { writeFileSync } from "node:fs";
writeFileSync("outcome.json", JSON.stringify({ result: "fixed", summary: "Done." }));
`;
