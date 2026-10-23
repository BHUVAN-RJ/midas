// Repair results reach the user (founder, 2026-10-23, docs/briefs/repair-ux-upgrade.md): the
// Repair tag shows Fixed, Already There or Couldn't Fix, and a tap shows the runner's one-line
// summary. Before this every user notice was the same "done" text, a runner "no change" was
// stored as failed and shown as failed, and a failure never reached the user at all.
import { afterEach, describe, expect, it } from "vitest";
import app from "../src/index";
import { USER_DONE_TEXT, USER_RESULT_TEXT, noticeKind } from "../src/repairs";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { runJob } from "../../runner/lib/run-job.mjs";
import {
  addSignedInUser,
  claimJob,
  createReport,
  eventKinds,
  getReport,
  makeRepairEnv,
  reportRow,
  runnerHeaders,
  sessionHeaders,
  type RepairTestEnv,
} from "./helpers/repair-fixtures";
import {
  RUNNER_TOKEN,
  fakeDeployThatLands,
  fakeFetchWithoutStoredTests,
  makeScratch,
  standardAssets,
  startFakeBackend,
  writeStubAgent,
  type FakeBackend,
} from "./helpers/runner-fixture";

type Notice = { id: string; reportId: string; clientReportId: string | null; sidekickId: string; kind: string; summary: string | null; text: string };

async function postStatus(env: RepairTestEnv, reportId: string, body: Record<string, unknown>) {
  return app.request(`/repairs/${reportId}/status`, { method: "POST", headers: runnerHeaders(), body: JSON.stringify(body) }, env);
}

async function noticesFor(env: RepairTestEnv, token: string): Promise<Notice[]> {
  const response = await app.request("/repairs/notices", { headers: sessionHeaders(token) }, env);
  expect(response.status).toBe(200);
  const reply = (await response.json()) as { notices: Notice[] };
  return reply.notices;
}

async function claimedReport(env: RepairTestEnv, token: string, clientReportId = "c0ffee00-0000-4000-8000-000000000001") {
  const reportId = await createReport(env, token, { clientReportId });
  await claimJob(env);
  return reportId;
}

describe("repair results for the user", () => {
  it("a runner no_change is Already There with its summary, never failed to the user", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await claimedReport(env, token);

    const response = await postStatus(env, reportId, { status: "no_change", summary: "The every 2 hrs option is already there.\nSecond line for the founder." });

    expect(response.status).toBe(200);
    const row = reportRow(env, reportId);
    // The founder's flow is unchanged: status failed, reason "no change", a founder event
    expect(row.status).toBe("failed");
    expect(row.fail_reason).toBe("no change");
    expect(row.result_kind).toBe("already_there");
    expect(eventKinds(env, "founder")).toEqual(["request_received", "failed"]);
    const notices = await noticesFor(env, token);
    expect(notices).toHaveLength(1);
    expect(notices[0]).toMatchObject({ reportId, clientReportId: "c0ffee00-0000-4000-8000-000000000001", sidekickId: "reminders", kind: "already_there", summary: "The every 2 hrs option is already there." });
    expect(notices[0].text).toBe(USER_RESULT_TEXT.already_there);
    expect(notices[0].text.toLowerCase()).not.toContain("fail");
  });

  it("a fix that went live is fixed, carries the runner's summary and the phone's report id", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await claimedReport(env, token);

    await postStatus(env, reportId, { status: "fix_ready", summary: "Added every 2 hrs." });
    expect(await noticesFor(env, token)).toEqual([]);
    await postStatus(env, reportId, { status: "deployed_live", summary: "Added every 2 hrs.", version: "v8" });

    const notices = await noticesFor(env, token);
    expect(notices).toEqual([expect.objectContaining({ reportId, clientReportId: "c0ffee00-0000-4000-8000-000000000001", kind: "fixed", summary: "Added every 2 hrs.", text: USER_DONE_TEXT })]);
    expect(reportRow(env, reportId).result_kind).toBe("fixed");
  });

  it("a failure is Couldn't Fix for the user, and the founder's reason never reaches them", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await claimedReport(env, token);

    await postStatus(env, reportId, { status: "failed", reason: "check failed: reminders-logic.test.ts", summary: "internal detail" });

    const notices = await noticesFor(env, token);
    expect(notices).toEqual([expect.objectContaining({ reportId, kind: "couldnt_fix", summary: null, text: USER_RESULT_TEXT.couldnt_fix })]);
    expect(JSON.stringify(notices)).not.toContain("reminders-logic");
    expect(reportRow(env, reportId).result_kind).toBe("couldnt_fix");
  });

  it("a deploy that fails after fix_ready is Couldn't Fix", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await claimedReport(env, token);
    await postStatus(env, reportId, { status: "fix_ready", summary: "Added it." });

    await postStatus(env, reportId, { status: "failed", reason: "deploy failed" });

    const notices = await noticesFor(env, token);
    expect(notices.map((notice) => notice.kind)).toEqual(["couldnt_fix"]);
  });

  it("no_change is only taken from running", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);

    const beforeClaim = await postStatus(env, reportId, { status: "no_change", summary: "x" });
    await claimJob(env);
    await postStatus(env, reportId, { status: "fix_ready" });
    const afterFixReady = await postStatus(env, reportId, { status: "no_change", summary: "x" });

    expect(beforeClaim.status).toBe(409);
    expect(afterFixReady.status).toBe(409);
    expect(reportRow(env, reportId).status).toBe("fix_ready");
  });

  it("a job whose lease ran out every time tells the user Couldn't Fix", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);
    for (let attempt = 0; attempt < 3; attempt += 1) {
      await claimJob(env);
      env.DB.execute("UPDATE repair_reports SET lease_until = ? WHERE id = ?", Date.now() - 1000, reportId);
    }

    await claimJob(env);

    const notices = await noticesFor(env, token);
    expect(notices).toEqual([expect.objectContaining({ reportId, kind: "couldnt_fix" })]);
  });

  it("the reporter reads the result on the report itself", async () => {
    const env = makeRepairEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await claimedReport(env, token);
    const openReport = (await (await getReport(env, reportId, sessionHeaders(token))).json()) as { result: unknown };
    expect(openReport.result).toBeNull();

    await postStatus(env, reportId, { status: "no_change", summary: "Already there." });

    const report = (await (await getReport(env, reportId, sessionHeaders(token))).json()) as { result: unknown };
    expect(report.result).toEqual({ kind: "already_there", summary: "Already there." });
  });

  it("old rows without a stored kind take it from the event", () => {
    expect(noticeKind("deployed_live", null)).toBe("fixed");
    expect(noticeKind("failed", null)).toBe("couldnt_fix");
    expect(noticeKind("failed", "already_there")).toBe("already_there");
  });
});

const NO_CHANGE_AGENT = `
import { writeFileSync } from "node:fs";
writeFileSync("outcome.json", JSON.stringify({ result: "no_change", summary: "The every 2 hrs option is already there." }));
`;

let openBackend: FakeBackend | null = null;

afterEach(async () => {
  if (openBackend !== null) {
    await openBackend.close();
    openBackend = null;
  }
});

describe("the runner posts nothing-to-change as its own result", () => {
  it("posts no_change with the agent's summary, not failed, and tells the founder", async () => {
    const { scratch, settings } = makeScratch();
    const jobRow = { id: "rep-9", user_id: "user-77", sidekick_id: "reminders", bundle_version: "v1", kind: "change", transcript: "add every 2 hrs" };
    const backendServer = await startFakeBackend(jobRow, standardAssets());
    openBackend = backendServer;
    const backend = createBackendClient({ baseUrl: backendServer.baseUrl, token: RUNNER_TOKEN });
    const job = await backend.claimJob();
    const notifications: Array<{ title: string; body: string }> = [];
    const deploy = fakeDeployThatLands();

    const result = await runJob(job, {
      backend,
      settings,
      agentCommand: process.execPath,
      agentArgs: [writeStubAgent(scratch, NO_CHANGE_AGENT)],
      runFetch: fakeFetchWithoutStoredTests().runFetch,
      runTests: async () => ({ ok: true, output: "passed" }),
      runDeploy: deploy.runDeploy,
      readPointer: deploy.readPointer,
      notify: async (notification: { title: string; body: string }) => {
        notifications.push(notification);
      },
    });

    expect(result.status).toBe("no_change");
    const statusNames = backendServer.statuses.map((status) => status.status);
    expect(statusNames).toEqual(["running", "no_change"]);
    expect(backendServer.statuses[1]).toEqual({ status: "no_change", summary: "The every 2 hrs option is already there." });
    expect(deploy.deployCalls).toHaveLength(0);
    expect(notifications.map((notification) => notification.title)).toEqual(["Repair request: reminders", "Nothing to change: reminders"]);
  });
});
