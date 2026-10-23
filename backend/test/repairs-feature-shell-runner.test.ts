import { describe, expect, it } from "vitest";
import app from "../src/index";
import { LEASE_MS, USER_DONE_TEXT } from "../src/repairs";
import {
  addSignedInUser,
  claimJob,
  createReport,
  eventKinds,
  getAsset,
  getReport,
  makeReportForm,
  makeRepairEnv,
  postReport,
  reportCount,
  reportRow,
  runnerHeaders,
  sessionHeaders,
  setStatus,
} from "./helpers/repair-fixtures";

// Cross-agent alignment, 2026-10-13 (lead): the third kind `feature`, voice-only reports, the
// shell's extra parts and dedupe on clientReportId, the runner's bundle assets and lease renewal,
// and `failed` with reason `unsupported`.

type ReportJson = Record<string, unknown> & { assets: Record<string, string | null> };

async function reportJson(response: Response): Promise<ReportJson> {
  expect(response.status).toBe(200);
  return (await response.json()) as ReportJson;
}

describe("kind feature, voice only", () => {
  it("accepts a feature request with transcript only and stores no R2 object", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);

    const reportId = await createReport(env, token, {
      kind: "feature",
      transcript: "I want my reminders to store images as well",
      strokes: null,
      screenshot: null,
      drawing: null,
    });

    const row = reportRow(env, reportId);
    expect(row.kind).toBe("feature");
    expect(row.status).toBe("queued");
    expect(row.screenshot_key).toBeNull();
    expect(row.drawing_key).toBeNull();
    expect(row.strokes_key).toBeNull();
    expect(env.BUNDLES.keys()).toEqual([]);

    const claimed = await claimJob(env);
    const job = await reportJson(claimed);
    expect(job.id).toBe(reportId);
    expect(job.assets).toEqual({ screenshot: null, drawing: null, strokes: null });
    const missingAsset = await getAsset(env, reportId, "drawing.png", runnerHeaders());
    expect(missingAsset.status).toBe(404);
  });

  it("still requires the transcript when nothing else is sent", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);

    const response = await postReport(env, token, makeReportForm({ kind: "feature", transcript: null, strokes: null, screenshot: null, drawing: null }));

    expect(response.status).toBe(400);
    expect(reportCount(env)).toBe(0);
  });

  it("stores an unknown kind hint as unknown and keeps a drawing-only change as change", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);

    const oddId = await createReport(env, token, { kind: "wish" });
    const changeId = await createReport(env, token, { kind: "change", transcript: "this tag goes here" });

    expect(reportRow(env, oddId).kind).toBe("unknown");
    expect(reportRow(env, changeId).kind).toBe("change");
  });
});

describe("the shell's parts", () => {
  const WORDS = JSON.stringify([{ word: "reminders", start: 0, end: 400 }, { word: "fire", start: 420, end: 700 }]);

  it("keeps transcriptWords, typedText, bundleScope, iosVersion, appBuild and clientReportId", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);

    const reportId = await createReport(env, token, {
      transcriptWords: WORDS,
      typedText: "also the badge count is wrong",
      clientReportId: "phone-report-0001",
      bundleScope: "user",
      iosVersion: "27.0",
      appVersion: "0.1.0",
      appBuild: "2",
    });

    const report = await reportJson(await getReport(env, reportId, runnerHeaders()));
    expect(report.transcriptWords).toEqual(JSON.parse(WORDS));
    expect(report.typedText).toBe("also the badge count is wrong");
    expect(report.clientReportId).toBe("phone-report-0001");
    expect(report.bundleScope).toBe("user");
    expect(report.iosVersion).toBe("27.0");
    expect(report.appVersion).toBe("0.1.0");
    expect(report.appBuild).toBe("2");
  });

  it("accepts transcriptTimings as the older name for transcriptWords", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);

    const reportId = await createReport(env, token, { transcriptTimings: WORDS });

    const report = await reportJson(await getReport(env, reportId, runnerHeaders()));
    expect(report.transcriptWords).toEqual(JSON.parse(WORDS));
  });

  it("refuses a bundleScope that is neither user nor base", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);

    const response = await postReport(env, token, makeReportForm({ bundleScope: "staging" }));

    expect(response.status).toBe(400);
    expect(reportCount(env)).toBe(0);
  });

  it("stores a retried report (same clientReportId, same user) once; another user gets their own", async () => {
    const env = makeRepairEnv();
    const amoghToken = addSignedInUser(env, "amogh", ["reminders"]);
    const otherToken = addSignedInUser(env, "other", ["reminders"]);

    const firstId = await createReport(env, amoghToken, { clientReportId: "phone-report-7" });
    const retry = await postReport(env, amoghToken, makeReportForm({ clientReportId: "phone-report-7" }));
    const otherId = await createReport(env, otherToken, { clientReportId: "phone-report-7" });

    expect(retry.status).toBe(200);
    const retryReply = (await retry.json()) as { id: string; status: string };
    expect(retryReply.id).toBe(firstId);
    expect(retryReply.status).toBe("queued");
    expect(otherId).not.toBe(firstId);
    expect(reportCount(env)).toBe(2);
    expect(eventKinds(env, "founder")).toEqual(["request_received", "request_received"]);
    expect(env.BUNDLES.keys().length).toBe(6);
  });
});

describe("the runner's bundle assets", () => {
  const USER_HTML = "<!doctype html><title>Reminders (amogh)</title>";
  const BASE_HTML = "<!doctype html><title>Reminders</title>";
  const USER_MANIFEST = JSON.stringify({ id: "reminders", name: "Reminders", icon: { symbol: "bell", background: "#000" }, reads: [] });
  const BASE_MANIFEST = JSON.stringify({ id: "reminders", name: "Reminders", icon: { symbol: "bell", background: "#fff" }, reads: [] });

  function seededEnv() {
    return makeRepairEnv({
      "sidekicks/reminders/current.json": JSON.stringify({ version: "v3", scriptHashes: [] }),
      "sidekicks/reminders/v3/index.html": BASE_HTML,
      "sidekicks/reminders/v3/manifest.json": BASE_MANIFEST,
      "sidekicks/reminders/users/amogh/current.json": JSON.stringify({ version: "v3-amogh-1", scriptHashes: [] }),
      "sidekicks/reminders/users/amogh/v3-amogh-1/index.html": USER_HTML,
      "sidekicks/reminders/users/amogh/v3-amogh-1/manifest.json": USER_MANIFEST,
    });
  }

  it("serves the reporter's own copy when they have one", async () => {
    const env = seededEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);

    const html = await getAsset(env, reportId, "bundle.html", runnerHeaders());
    const manifest = await getAsset(env, reportId, "bundle.manifest.json", runnerHeaders());

    expect(html.status).toBe(200);
    expect(await html.text()).toBe(USER_HTML);
    expect(html.headers.get("X-Midas-Bundle-Scope")).toBe("user");
    expect(html.headers.get("X-Midas-Bundle-Version")).toBe("v3-amogh-1");
    expect(html.headers.get("Content-Type")).toContain("text/html");
    expect(await manifest.json()).toEqual(JSON.parse(USER_MANIFEST));
    expect(manifest.headers.get("X-Midas-Bundle-Scope")).toBe("user");
  });

  it("falls back to the shared page for a reporter without a copy", async () => {
    const env = seededEnv();
    const token = addSignedInUser(env, "other", ["reminders"]);
    const reportId = await createReport(env, token);

    const html = await getAsset(env, reportId, "bundle.html", runnerHeaders());
    const manifest = await getAsset(env, reportId, "bundle.manifest.json", runnerHeaders());

    expect(await html.text()).toBe(BASE_HTML);
    expect(html.headers.get("X-Midas-Bundle-Scope")).toBe("base");
    expect(html.headers.get("X-Midas-Bundle-Version")).toBe("v3");
    expect(await manifest.json()).toEqual(JSON.parse(BASE_MANIFEST));
  });

  it("answers 404 when nothing is deployed, and to another user", async () => {
    const env = makeRepairEnv();
    const amoghToken = addSignedInUser(env, "amogh", ["reminders"]);
    const otherToken = addSignedInUser(env, "other", ["reminders"]);
    const reportId = await createReport(env, amoghToken);

    const nothingDeployed = await getAsset(env, reportId, "bundle.html", runnerHeaders());
    const otherUser = await getAsset(env, reportId, "bundle.html", sessionHeaders(otherToken));

    expect(nothingDeployed.status).toBe(404);
    expect(otherUser.status).toBe(404);
  });
});

describe("the runner's lease and outcomes", () => {
  it("extends the lease on every running -> running post", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);
    await claimJob(env);
    const nearlyExpired = Date.now() + 1000;
    env.DB.execute("UPDATE repair_reports SET lease_until = ? WHERE id = ?", nearlyExpired, reportId);

    const renewed = await setStatus(env, reportId, "running");

    expect(renewed.status).toBe(200);
    const leaseUntil = Number(reportRow(env, reportId).lease_until);
    expect(leaseUntil).toBeGreaterThan(Date.now() + LEASE_MS - 5000);
    const secondRunner = await claimJob(env, "mac-b");
    expect(secondRunner.status).toBe(204);
  });

  it("goes running -> fix_ready -> deployed_live with the runner token and leaves the user one notice", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);
    await claimJob(env);

    const skipped = await setStatus(env, reportId, "deployed_live");
    const fixReady = await setStatus(env, reportId, "fix_ready");
    const live = await setStatus(env, reportId, "deployed_live");

    expect(skipped.status).toBe(409);
    expect(fixReady.status).toBe(200);
    expect(live.status).toBe(200);
    expect(reportRow(env, reportId).status).toBe("deployed_live");
    const notices = await app.request("/repairs/notices", { headers: sessionHeaders(token) }, env);
    const reply = (await notices.json()) as { notices: Array<{ reportId: string; text: string }> };
    expect(reply.notices).toEqual([expect.objectContaining({ reportId, text: USER_DONE_TEXT })]);
  });

  it("records failed with reason unsupported for a feature the platform cannot do, and tells the founder", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token, { kind: "feature", transcript: "store images with my reminders", strokes: null, screenshot: null, drawing: null });
    await claimJob(env);

    const failed = await setStatus(env, reportId, "failed", "unsupported");

    expect(failed.status).toBe(200);
    const row = reportRow(env, reportId);
    expect(row.status).toBe("failed");
    expect(row.fail_reason).toBe("unsupported");
    expect(eventKinds(env, "founder")).toEqual(["request_received", "failed"]);
    const events = await app.request("/repairs/events", { headers: runnerHeaders() }, env);
    const reply = (await events.json()) as { events: Array<{ kind: string; failReason: string | null }> };
    const failedEvent = reply.events.find(findFailedEvent);
    expect(failedEvent?.failReason).toBe("unsupported");
    const notices = await app.request("/repairs/notices", { headers: sessionHeaders(token) }, env);
    const noticeReply = (await notices.json()) as { notices: Array<{ reportId: string; kind: string }> };
    expect(noticeReply.notices).toEqual([expect.objectContaining({ reportId, kind: "couldnt_fix" })]);
  });
});

function findFailedEvent(event: { kind: string }): boolean {
  return event.kind === "failed";
}
