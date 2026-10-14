// The third repair kind, feature (founder, 2026-10-13, docs/briefs/repair-contract.md "Settled"):
// a feature request may be voice only, with no drawing; the agent prompt covers building a new
// feature; a feature the shell or SDK cannot hold ends failed / unsupported and the founder is
// told what is missing.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createBackendClient, normalizeJob } from "../../runner/lib/backend.mjs";
import { listFilesRecursively } from "../../runner/lib/job-folder.mjs";
import { buildSystemPrompt, drawingNote } from "../../runner/lib/prompt.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import {
  AGENT_THAT_FIXES_TITLE,
  RUNNER_TOKEN,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

const FEATURE_JOB_ROW = {
  id: "rep-feature-1",
  user_id: "user-77",
  sidekick_id: "reminders",
  bundle_version: "20261011T065908559Z-1064a312",
  kind: "feature",
  transcript: "I want my reminders to store images as well",
};

// Voice only: the phone sent no drawing and no strokes (a screenshot still comes along).
function voiceOnlyAssets(): Record<string, string | Buffer> {
  const assets = standardAssets();
  delete assets["drawing.png"];
  delete assets["strokes.json"];
  return assets;
}

const AGENT_THAT_SAYS_IMAGES_ARE_UNSUPPORTED = `
import { writeFileSync } from "node:fs";
writeFileSync("outcome.json", JSON.stringify({
  result: "unsupported",
  summary: "Missing: a file store for images. The store takes JSON records under 64 KB only.",
  unsupportedAction: "store images with reminders",
}));
`;

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

async function runFeatureJob(agentSource: string) {
  const { scratch, settings } = makeScratch();
  const backendServer = await startFakeBackend(FEATURE_JOB_ROW, voiceOnlyAssets());
  openBackend = backendServer;
  const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
  const job = await backend.claimJob();
  const notifications: Array<{ title: string; body: string }> = [];
  const result = await runJob(job, {
    backend,
    settings,
    agentCommand: process.execPath,
    agentArgs: [writeStubAgent(scratch, agentSource)],
    runTests: async () => ({ ok: true, output: "81 passed" }),
    notify: async (notification: { title: string; body: string }) => {
      notifications.push(notification);
    },
  });
  return { result, backendServer, notifications, job };
}

describe("feature kind", () => {
  it("the claim reply's kind feature is kept as is", () => {
    const job = normalizeJob({ id: "1", user_id: "u", sidekick_id: "reminders", kind: "feature", transcript: "tags please" });
    expect(job.kind).toBe("feature");
  });

  it("a voice-only feature request runs to fix_ready without a drawing or strokes", async () => {
    const { result, backendServer, job } = await runFeatureJob(AGENT_THAT_FIXES_TITLE);

    expect(job.kind).toBe("feature");
    expect(result.status).toBe("fix_ready");
    expect(backendServer.statuses.map((status) => status.status)).toEqual(["running", "fix_ready"]);

    // The runner asked for the drawing, got 404, and went on.
    expect(backendServer.assetRequests).toContain("drawing.png");
    expect(listFilesRecursively(result.jobFolder)).toEqual([
      "outcome.json",
      "report/report.json",
      "report/screenshot.png",
      "report/transcript.txt",
      "sidekick/index.html",
      "sidekick/manifest.json",
    ]);
    const reportRecord = JSON.parse(readFileSync(join(result.jobFolder, "report", "report.json"), "utf8"));
    expect(reportRecord.kind).toBe("feature");
    expect(reportRecord.files).toEqual(["transcript.txt", "screenshot.png"]);

    const systemPrompt = readFileSync(join(result.logFolder, "system-prompt.md"), "utf8");
    expect(systemPrompt).toContain("Kind hint from the phone: feature");
    expect(systemPrompt).toContain("This report has no drawing, only words and a screenshot");
    expect(systemPrompt).not.toContain("This report has a drawing");
  });

  it("a feature the shell cannot hold ends failed / unsupported and tells the founder what is missing", async () => {
    const { result, backendServer, notifications } = await runFeatureJob(AGENT_THAT_SAYS_IMAGES_ARE_UNSUPPORTED);

    expect(result.status).toBe("failed");
    expect(result.reason).toBe("unsupported");
    // The backend gets the user's own words as detail, nothing more.
    expect(backendServer.statuses[1]).toEqual({ status: "failed", reason: "unsupported", detail: "store images with reminders" });
    // The founder is told what is missing: in the result, the Mac notification and summary.md.
    expect(result.missing).toBe("Missing: a file store for images. The store takes JSON records under 64 KB only.");
    expect(notifications[1].title).toBe("Repair failed: reminders");
    expect(notifications[1].body).toContain("store images with reminders");
    expect(notifications[1].body).toContain("Missing: a file store for images");
    const summaryPath = join(result.logFolder, "summary.md");
    expect(existsSync(summaryPath)).toBe(true);
    const summary = readFileSync(summaryPath, "utf8");
    expect(summary).toContain("- Kind: feature");
    expect(summary).toContain("I want my reminders to store images as well");
    expect(summary).toContain("Result: unsupported");
    expect(summary).toContain("Not supported: store images with reminders");
    expect(summary).toContain("a file store for images");
    expect(summary).not.toContain("## Deploy");
  });

  it("a fix that is not unsupported gets no summary.md on failure, so the unsupported one is deliberate", async () => {
    const { scratch, settings } = makeScratch();
    const assets = voiceOnlyAssets();
    delete assets["bundle.html"];
    const backendServer = await startFakeBackend(FEATURE_JOB_ROW, assets);
    openBackend = backendServer;
    const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
    const job = await backend.claimJob();
    const result = await runJob(job, {
      backend,
      settings,
      agentCommand: process.execPath,
      agentArgs: [writeStubAgent(scratch, AGENT_THAT_FIXES_TITLE)],
      runTests: async () => ({ ok: true, output: "" }),
      notify: async () => {},
    });
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("bundle missing");
    expect(result.missing).toBeNull();
    expect(existsSync(join(result.logFolder, "summary.md"))).toBe(false);
  });
});

describe("the prompt and the drawing", () => {
  it("names the feature case and tells the agent whether a drawing exists", () => {
    const { checkout } = makeScratch();
    const job = { sidekickId: "reminders", kind: "feature", transcript: "I want my reminders to store images as well" };
    const withoutDrawing = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], checkoutRoot: checkout, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
    expect(withoutDrawing).toContain("**A new feature**");
    expect(withoutDrawing).toContain("what is missing");
    expect(withoutDrawing).toContain("This report has no drawing and no screenshot");
    expect(withoutDrawing).toContain("Kind hint from the phone: feature");
    expect(withoutDrawing).not.toContain("{{DRAWING_NOTE}}");

    const withDrawing = buildSystemPrompt({ job, reportFiles: ["transcript.txt", "screenshot.png", "drawing.png", "strokes.json"], checkoutRoot: checkout, intelToolPath: "/r/intel.mjs", checkToolPath: "/r/check.mjs" });
    expect(withDrawing).toContain("This report has a drawing: read report/drawing.png");
  });

  it("drawingNote distinguishes drawing, screenshot only, and words only", () => {
    expect(drawingNote(["transcript.txt", "drawing.png"])).toContain("has a drawing");
    expect(drawingNote(["transcript.txt", "screenshot.png"])).toContain("no drawing, only words and a screenshot");
    expect(drawingNote(["transcript.txt"])).toContain("no drawing and no screenshot");
  });
});
