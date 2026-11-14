// Publish first (founder, 2026-11-13; docs/briefs/repair-lanes.md W7), the runner's side: the
// upload runs alongside the checks that protect the person, the pointer flips only when they pass,
// the slow checks run after and roll the person back at once when they fail; the shield splits into
// a fast and a slow part; the runner waits on a long poll instead of a 30 s poll.
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { bundleContentHash } from "../scripts/bundle-tools.mjs";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { checkAfterPublish, checkBeforePublish } from "../../runner/lib/check.mjs";
import { runLoop, waitFromEnvironments } from "../../runner/lib/loop.mjs";
import { afterPublish, createStepTimer, flipToVersion, planVersion, publishFirst, rollBackVersion, timingsTable, uploadVersion } from "../../runner/lib/publish-first.mjs";
import { PART_CHECK_IDS, pageRunsFor, runShield, viewActions } from "../../runner/core-checks/shield.mjs";
import { plannedSteps } from "../../runner/core-checks/page-open.mjs";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";
import { NOW, repoRoot, sidekickCopy, todoRecords, withPageScript, type Copy } from "./repair-shield-fixtures";

const WEBKIT_TIMEOUT_MS = 180_000;
const todo = sidekickCopy("todo");
const records = todoRecords();
const todoActions = viewActions(JSON.parse(todo.manifestText), JSON.parse(todo.manifestText));
// A page whose first view is fine but whose search view throws when its control is tapped: only the
// slow part can see it
const BREAKS_ON_SEARCH_TAP = "document.addEventListener('click', function (event) { if (event.target.closest('[data-action=\"go-search\"]')) { throw new Error('search broke'); } }, true);";

function pause(milliseconds: number) {
  return new Promise(function waitAWhile(resolve) {
    setTimeout(resolve, milliseconds);
  });
}

// Resolves for every caller once `count` callers have arrived; rejects when they arrive one after
// the other instead (the last never comes while the first waits)
function makeBarrier(count: number) {
  let arrived = 0;
  let release: () => void = function notYet() {};
  const everyoneHere = new Promise<void>(function holdOpen(resolve) {
    release = resolve;
  });
  async function arrive() {
    arrived += 1;
    if (arrived >= count) {
      release();
    }
    const tooLate = pause(2000).then(function failSequential() {
      throw new Error(`only ${arrived} of ${count} ran at the same time`);
    });
    await Promise.race([everyoneHere, tooLate]);
  }
  return { arrive };
}

type PageStep = { name: string; action: string | null; report: Record<string, unknown> };

// A stand-in for WebKit that honours the kinds of step asked for, and records every call
function makePageOpener(options: { onCall?: () => Promise<void>; brokenAfterTap?: string | null; afterHtml?: string } = {}) {
  const calls: Array<{ actions: string[]; kinds: string[]; html: string }> = [];
  async function openPageStandIn({ html, actions, kinds, records: pageRecords }: { html: string; actions: string[]; kinds: string[]; records: unknown[] }) {
    calls.push({ actions, kinds, html });
    if (options.onCall) {
      await options.onCall();
    }
    const steps = plannedSteps({ records: pageRecords, actions, kinds });
    return steps.map(function stepReport(step: { name: string; action: string | null }): PageStep {
      const isNewPage = options.afterHtml !== undefined && html === options.afterHtml;
      const broken = isNewPage && step.action !== null && step.action === options.brokenAfterTap;
      const errors = broken ? ["uncaught: search broke"] : [];
      const report = { errors, writes: [], written: {}, visibleElements: 5, textLength: 5, action: step.action === null ? null : { found: true } };
      return { name: step.name, action: step.action, report };
    });
  }
  return { calls, openPageStandIn };
}

function writeCopy(folder: string, copy: Copy) {
  mkdirSync(folder, { recursive: true });
  writeFileSync(join(folder, "index.html"), copy.html);
  writeFileSync(join(folder, "manifest.json"), copy.manifestText);
  if (copy.toolsText !== null) {
    writeFileSync(join(folder, "tools.js"), copy.toolsText);
  }
}

// A job folder with the repaired copy and its tests, and the "before" snapshot beside it
function makeJob(after: Copy, withTests = true) {
  const scratch = mkdtempSync(join(tmpdir(), "midas-publish-first-"));
  const jobFolder = join(scratch, "job");
  writeCopy(join(jobFolder, "sidekick"), after);
  if (withTests) {
    mkdirSync(join(jobFolder, "tests"), { recursive: true });
    writeFileSync(join(jobFolder, "tests", "todo-logic.test.ts"), "it('adds', () => {});\n");
    writeFileSync(join(jobFolder, "tests", "TEST_CHANGES.md"), "");
  }
  const beforeFolder = join(scratch, "log", "before");
  writeCopy(beforeFolder, todo);
  return { jobFolder, beforeFolder };
}

async function passingTests() {
  return { ok: true, output: "tests passed" };
}

// ---- the Worker, in process, for the end-to-end runs ---------------------------------------------

const RUNNER_TOKEN = "runner-token-publish-first";
const USER_ID = "amogh";
const OLD_VERSION = "20261101T000000000Z-aaaaaaaa";
const OWN_POINTER_KEY = `sidekicks/todo/users/${USER_ID}/current.json`;

function makeWorkerEnv() {
  const oldPointer = { version: OLD_VERSION, scriptHashes: [], contentHash: "0".repeat(64), baseVersion: null, tools: "tools.js" };
  const env = {
    DB: makeMigratedD1(),
    BUNDLES: makeFakeR2({ [OWN_POINTER_KEY]: JSON.stringify(oldPointer) }),
    REPAIR_RUNNER_TOKEN: RUNNER_TOKEN,
  };
  const token = `token-${USER_ID}`;
  const sessionHash = createHash("sha256").update(token).digest("hex");
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", USER_ID, USER_ID);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sessionHash, USER_ID, Date.now() + 3_600_000);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'todo', 'now')", USER_ID);
  return { env, token };
}

function backendFor(env: ReturnType<typeof makeWorkerEnv>["env"]) {
  async function fetchThroughWorker(url: string, init?: RequestInit) {
    const path = url.replace("https://worker.test", "");
    return app.request(path, init, env);
  }
  return createBackendClient({ baseUrl: "https://worker.test", token: RUNNER_TOKEN, environment: "staging", fetchImplementation: fetchThroughWorker });
}

async function claimedJob(env: ReturnType<typeof makeWorkerEnv>["env"], token: string) {
  const form = new FormData();
  form.set("sidekickId", "todo");
  form.set("kind", "change");
  form.set("transcript", "make the search bigger");
  form.set("bundleVersion", OLD_VERSION);
  const created = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form }, env);
  expect(created.status).toBe(201);
  const backend = backendFor(env);
  const job = await backend.claimJob();
  expect(job).not.toBeNull();
  return { backend, job };
}

async function personVersion(env: ReturnType<typeof makeWorkerEnv>["env"]): Promise<string | null> {
  const stored = await env.BUNDLES.get(OWN_POINTER_KEY);
  if (stored === null) {
    return null;
  }
  const pointer = (await stored.json()) as { version: string };
  return pointer.version;
}

// ---- timing ---------------------------------------------------------------------------------------

describe("step timer", () => {
  it("keeps each step's start and length, failed ones marked, and prints them as a table", async () => {
    let fakeNow = 1000;
    function fakeClock() {
      return fakeNow;
    }
    const timer = createStepTimer(fakeClock);
    await timer.time("upload", async function upload() {
      fakeNow += 250;
    });
    await expect(timer.time("flip", async function flip() {
      fakeNow += 40;
      throw new Error("no");
    })).rejects.toThrow("no");
    expect(timer.list()).toEqual([
      { name: "upload", startMs: 0, endMs: 250, durationMs: 250, ok: true },
      { name: "flip", startMs: 250, endMs: 290, durationMs: 40, ok: false },
    ]);
    expect(timingsTable(timer.list())).toContain("flip (failed) | 0.25 s | 0.04 s");
  });
});

// ---- before the person sees it ------------------------------------------------------------------

describe("publishFirst", () => {
  it("runs the upload alongside the checks, and flips only after both", async () => {
    const barrier = makeBarrier(2);
    const order: string[] = [];
    async function upload() {
      await barrier.arrive();
      order.push("uploaded");
    }
    async function checks() {
      await barrier.arrive();
      order.push("checked");
      return { ok: true, problems: [] };
    }
    async function flip() {
      order.push("flipped");
      return { version: "v2", previousVersion: "v1" };
    }
    const result = await publishFirst({ timer: createStepTimer(), upload, checkBeforePublish: checks, flip });
    expect(result.status).toBe("published");
    expect(order[2]).toBe("flipped");
  });

  it("never flips when a check fails, cannot run, or the upload fails", async () => {
    const flips: string[] = [];
    async function flip() {
      flips.push("flipped");
      return {};
    }
    async function uploadFine() {
      return {};
    }
    async function uploadBroken() {
      throw new Error("R2 down");
    }
    async function checksRefuse() {
      return { ok: false, problems: ["shield tools: todo.add answers differently"] };
    }
    async function checksThrow() {
      throw new Error("WebKit gone");
    }
    async function checksPass() {
      return { ok: true, problems: [] };
    }
    const refused = await publishFirst({ timer: createStepTimer(), upload: uploadFine, checkBeforePublish: checksRefuse, flip });
    expect(refused.status).toBe("refused");
    const unrunnable = await publishFirst({ timer: createStepTimer(), upload: uploadFine, checkBeforePublish: checksThrow, flip });
    expect(unrunnable).toMatchObject({ status: "failed", reason: "check failed" });
    const notUploaded = await publishFirst({ timer: createStepTimer(), upload: uploadBroken, checkBeforePublish: checksPass, flip });
    expect(notUploaded).toMatchObject({ status: "failed", reason: "deploy failed" });
    expect(flips).toEqual([]);
  });
});

// ---- after publishing ---------------------------------------------------------------------------

describe("afterPublish", () => {
  it("keeps the update when the slow checks pass, and rolls back and marks failed when they do not", async () => {
    const actions: string[] = [];
    async function rollBack(reason: string) {
      actions.push(`roll back: ${reason}`);
      return { rolledBack: true };
    }
    async function markRolledBack(reason: string) {
      actions.push(`marked ${reason}`);
    }
    async function slowPasses() {
      return { ok: true, problems: [] };
    }
    async function slowFails() {
      return { ok: false, problems: ["shield widget-record: widget:today is no longer written"] };
    }
    const kept = await afterPublish({ timer: createStepTimer(), checkAfterPublish: slowPasses, rollBack, markRolledBack });
    expect(kept.status).toBe("kept");
    expect(actions).toEqual([]);
    const rolled = await afterPublish({ timer: createStepTimer(), checkAfterPublish: slowFails, rollBack, markRolledBack });
    expect(rolled.status).toBe("rolled back");
    expect(actions).toEqual(["roll back: shield widget-record: widget:today is no longer written", "marked rolled back"]);
  });

  it("rolls back when the slow checks cannot run, and says so when the roll back itself fails", async () => {
    const marks: string[] = [];
    async function slowThrows() {
      throw new Error("WebKit gone");
    }
    async function rollBackWorks() {
      return { rolledBack: true };
    }
    async function rollBackBroken() {
      throw new Error("Worker down");
    }
    async function markRolledBack(reason: string) {
      marks.push(reason);
    }
    const rolled = await afterPublish({ timer: createStepTimer(), checkAfterPublish: slowThrows, rollBack: rollBackWorks, markRolledBack });
    expect(rolled.status).toBe("rolled back");
    const stuck = await afterPublish({ timer: createStepTimer(), checkAfterPublish: slowThrows, rollBack: rollBackBroken, markRolledBack });
    expect(stuck).toMatchObject({ status: "roll back failed", error: "Worker down" });
    expect(marks).toEqual(["rolled back"]);
  });
});

// ---- the new version ----------------------------------------------------------------------------

describe("planVersion", () => {
  it("plans the page, manifest, tools.js and tests, with the hash deploy-sidekick.mjs would give", async () => {
    const { jobFolder } = makeJob(todo);
    const plan = await planVersion({ checkoutRoot: repoRoot, sidekickId: "todo", userId: USER_ID, jobFolder, deployedAt: NOW });
    const names = plan.files.map(function fileName(file: { name: string }) {
      return file.name;
    });
    expect(names).toEqual(["index.html", "manifest.json", "tools.js", "tests/TEST_CHANGES.md", "tests/todo-logic.test.ts", "tests/index.json"]);
    expect(plan.pointer.contentHash).toBe(bundleContentHash(todo.html, todo.manifestText, todo.toolsText));
    expect(plan.pointer.tools).toBe("tools.js");
    expect(plan.version).toMatch(/^20261113T170000000Z-[0-9a-f]{8}$/);
  });

  it("refuses a copy without tests", async () => {
    const { jobFolder } = makeJob(todo, false);
    await expect(planVersion({ checkoutRoot: repoRoot, sidekickId: "todo", userId: USER_ID, jobFolder, deployedAt: NOW })).rejects.toThrow("tests");
  });
});

// ---- the shield in two parts ----------------------------------------------------------------------

describe("shield parts", () => {
  it("shares the slow part's taps over several WebKit programs, every control exactly once, widget once", () => {
    const runs = pageRunsFor("slow", todoActions, 3);
    expect(runs.length).toBe(3);
    const tapped = runs.flatMap(function runActions(run: { actions: string[] }) {
      return run.actions;
    });
    expect(tapped).toEqual(todoActions);
    const widgetRuns = runs.filter(function hasWidget(run: { kinds: string[] }) {
      return run.kinds.includes("widget");
    });
    expect(widgetRuns.length).toBe(1);
    expect(pageRunsFor("fast", todoActions)).toEqual([{ actions: [], kinds: ["open"] }]);
  });

  it("the fast part opens only the first view; the slow part taps every control and checks the widget", async () => {
    const opener = makePageOpener();
    const fast = await runShield({ checkoutRoot: repoRoot, sidekickId: "todo", before: todo, after: todo, records, now: NOW, part: "fast", openPageImplementation: opener.openPageStandIn });
    expect(fast.checks.map(function checkId(check: { id: string }) {
      return check.id;
    })).toEqual(PART_CHECK_IDS.fast);
    for (const call of opener.calls) {
      expect(call.kinds).toEqual(["open"]);
    }
    expect(opener.calls.length).toBe(2);
    const slowOpener = makePageOpener();
    const slow = await runShield({ checkoutRoot: repoRoot, sidekickId: "todo", before: todo, after: todo, records, now: NOW, part: "slow", openPageImplementation: slowOpener.openPageStandIn });
    expect(slow.checks.map(function checkId(check: { id: string }) {
      return check.id;
    })).toEqual(PART_CHECK_IDS.slow);
    const tapped = slowOpener.calls.flatMap(function callActions(call: { actions: string[] }) {
      return call.actions;
    });
    expect(tapped.length).toBe(todoActions.length * 2);
    expect(fast.ok && slow.ok).toBe(true);
  });

  it("a fault after a tap passes the fast part and fails the slow part, in real WebKit", async () => {
    const broken = withPageScript(todo, BREAKS_ON_SEARCH_TAP);
    const fast = await runShield({ checkoutRoot: repoRoot, sidekickId: "todo", before: todo, after: broken, records, now: NOW, part: "fast" });
    expect(fast.ok).toBe(true);
    const slow = await runShield({ checkoutRoot: repoRoot, sidekickId: "todo", before: todo, after: broken, records, now: NOW, part: "slow" });
    expect(slow.ok).toBe(false);
    const pageViews = slow.checks.find(function isPageViews(check: { id: string }) {
      return check.id === "page-views";
    });
    expect(pageViews.problems.some(function namesSearch(problem: string) {
      return problem.includes('"go-search"') && problem.includes("search broke");
    })).toBe(true);
  }, WEBKIT_TIMEOUT_MS);
});

// ---- the checks around the publish -----------------------------------------------------------------

describe("checkBeforePublish and checkAfterPublish", () => {
  it("runs the shield's fast part and the copy's tests at the same time", async () => {
    const barrier = makeBarrier(3);
    const opener = makePageOpener({ onCall: barrier.arrive });
    async function testsAtTheSameTime() {
      await barrier.arrive();
      return { ok: true, output: "tests passed" };
    }
    const { jobFolder, beforeFolder } = makeJob(todo);
    const result = await checkBeforePublish({ checkoutRoot: repoRoot, sidekickId: "todo", jobFolder, beforeFolder, records, runTests: testsAtTheSameTime, openPageImplementation: opener.openPageStandIn, now: NOW });
    expect(result.ok).toBe(true);
    expect(result.shield.part).toBe("fast");
  });

  it("refuses at the gate without opening a page or running a test, and refuses failing tests", async () => {
    const opener = makePageOpener();
    const testRuns: string[] = [];
    async function recordTests() {
      testRuns.push("ran");
      return { ok: false, output: "1 failed" };
    }
    const gated = makeJob({ ...todo, html: todo.html.replace("</body>", "<script src=\"https://evil.example/x.js\"></script></body>") });
    const refused = await checkBeforePublish({ checkoutRoot: repoRoot, sidekickId: "todo", ...gated, records, runTests: recordTests, openPageImplementation: opener.openPageStandIn, now: NOW });
    expect(refused.ok).toBe(false);
    expect(refused.shield).toBeNull();
    expect(opener.calls.length + testRuns.length).toBe(0);
    const testsFail = await checkBeforePublish({ checkoutRoot: repoRoot, sidekickId: "todo", ...makeJob(todo), records, runTests: recordTests, openPageImplementation: opener.openPageStandIn, now: NOW });
    expect(testsFail.ok).toBe(false);
    expect(testsFail.problems).toContain("Sidekick tests failed");
  });

  it("checkAfterPublish fails a view that breaks after a tap", async () => {
    const broken = withPageScript(todo, BREAKS_ON_SEARCH_TAP);
    const opener = makePageOpener({ brokenAfterTap: "go-search", afterHtml: broken.html });
    const job = makeJob(broken);
    const result = await checkAfterPublish({ checkoutRoot: repoRoot, sidekickId: "todo", ...job, records, openPageImplementation: opener.openPageStandIn, now: NOW });
    expect(result.ok).toBe(false);
    expect(result.shield.part).toBe("slow");
  });
});

// ---- end to end through the Worker ---------------------------------------------------------------

describe("publish first through the Worker", () => {
  it("publishes a good repair: the person is on the new version once the fast checks pass, and stays there", async () => {
    const { env, token } = makeWorkerEnv();
    const { backend, job } = await claimedJob(env, token);
    const { jobFolder, beforeFolder } = makeJob(todo);
    const plan = await planVersion({ checkoutRoot: repoRoot, sidekickId: "todo", userId: USER_ID, jobFolder });
    const opener = makePageOpener();
    const timer = createStepTimer();
    const published = await publishFirst({
      timer,
      upload: function upload() {
        return uploadVersion({ backend, jobId: job.id, plan });
      },
      checkBeforePublish: function checks() {
        return checkBeforePublish({ checkoutRoot: repoRoot, sidekickId: "todo", jobFolder, beforeFolder, records, runTests: passingTests, openPageImplementation: opener.openPageStandIn });
      },
      flip: function flip() {
        return flipToVersion({ backend, jobId: job.id, plan });
      },
    });
    expect(published.status).toBe("published");
    expect(published.flipped).toEqual({ version: plan.version, previousVersion: OLD_VERSION });
    expect(await personVersion(env)).toBe(plan.version);
    const stepNames = timer.list().map(function stepName(step: { name: string }) {
      return step.name;
    });
    expect(stepNames).toEqual(["upload (alongside the checks)", "checks before publish", "pointer flip"]);
  });

  it("a slow check that fails after the publish puts the person back at once, and the repair is marked failed", async () => {
    const { env, token } = makeWorkerEnv();
    const { backend, job } = await claimedJob(env, token);
    const broken = withPageScript(todo, BREAKS_ON_SEARCH_TAP);
    const { jobFolder, beforeFolder } = makeJob(broken);
    const plan = await planVersion({ checkoutRoot: repoRoot, sidekickId: "todo", userId: USER_ID, jobFolder });
    const timer = createStepTimer();
    const shared = { checkoutRoot: repoRoot, sidekickId: "todo", jobFolder, beforeFolder, records };
    const published = await publishFirst({
      timer,
      upload: function upload() {
        return uploadVersion({ backend, jobId: job.id, plan });
      },
      checkBeforePublish: function checks() {
        return checkBeforePublish({ ...shared, runTests: passingTests });
      },
      flip: function flip() {
        return flipToVersion({ backend, jobId: job.id, plan });
      },
    });
    // The fast part cannot see a fault behind a tap: the person gets the update
    expect(published.status).toBe("published");
    expect(await personVersion(env)).toBe(plan.version);
    await backend.postStatus(job.id, "fix_ready", { summary: "Search is bigger." });
    await backend.postStatus(job.id, "deployed_live", { summary: "Search is bigger." });
    const after = await afterPublish({
      timer,
      checkAfterPublish: function slowChecks() {
        return checkAfterPublish(shared);
      },
      rollBack: function rollBack(reason: string) {
        return rollBackVersion({ backend, jobId: job.id, plan, reason });
      },
      markRolledBack: function markRolledBack(reason: string, detail: string) {
        return backend.postStatus(job.id, "failed", { reason, detail, rolledBack: true });
      },
    });
    expect(after.status).toBe("rolled back");
    expect(after.detail).toContain("go-search");
    expect(await personVersion(env)).toBe(OLD_VERSION);
    const rows = env.DB.query("SELECT status, fail_reason, result_kind FROM repair_reports WHERE id = ?", job.id);
    expect(rows[0]).toMatchObject({ status: "failed", fail_reason: "rolled back", result_kind: "couldnt_fix" });
    const founderEvents = env.DB.query("SELECT kind FROM repair_events WHERE report_id = ? AND audience = 'founder' AND kind = 'failed'", job.id);
    expect(founderEvents.length).toBe(1);
  }, WEBKIT_TIMEOUT_MS);
});

// ---- jobs without the 30 s poll ----------------------------------------------------------------------

describe("long poll", () => {
  it("the loop waits on the long poll instead of sleeping, and falls back to the poll when it fails", async () => {
    const sleeps: number[] = [];
    let claims = 0;
    let waits = 0;
    async function claimNothing() {
      claims += 1;
      return null;
    }
    async function sleepRecorded(milliseconds: number) {
      sleeps.push(milliseconds);
    }
    async function waitThenFail() {
      waits += 1;
      if (waits === 2) {
        throw new Error("old Worker");
      }
    }
    function stopAfterThree() {
      return claims >= 3;
    }
    async function noJob() {}
    await runLoop({ claimJob: claimNothing, runJob: noJob, pollIntervalMs: 30_000, sleep: sleepRecorded, shouldStop: stopAfterThree, waitForWork: waitThenFail });
    expect(waits).toBe(3);
    expect(sleeps).toEqual([30_000]);
  });

  it("answers as soon as any environment has a job, even while another still waits", async () => {
    const neverAnswers = { environment: "live", waitForJob: function hang() {
      return new Promise(function never() {});
    } };
    const hasJob = { environment: "staging", waitForJob: async function ready() {
      return true;
    } };
    const wait = waitFromEnvironments({ backends: [neverAnswers, hasJob], seconds: 25 });
    expect(await wait()).toBe(true);
  });

  it("says no job when every wait runs out, and throws when no environment can be asked", async () => {
    const errors: string[] = [];
    function recordError(error: Error) {
      errors.push(error.message);
    }
    const emptyLive = { environment: "live", waitForJob: async function notReady() {
      return false;
    } };
    const oldStaging = { environment: "staging", waitForJob: async function noRoute() {
      throw new Error("wait failed: 404");
    } };
    expect(await waitFromEnvironments({ backends: [emptyLive, oldStaging], seconds: 25, onError: recordError })()).toBe(false);
    expect(errors).toEqual(["staging: wait failed: 404"]);
    await expect(waitFromEnvironments({ backends: [oldStaging], seconds: 25 })()).rejects.toThrow("no environment");
  });

  it("the runner's client asks the Worker's long poll and gets ready once a report is queued", async () => {
    const { env, token } = makeWorkerEnv();
    const backend = backendFor(env);
    expect(await backend.waitForJob(0)).toBe(false);
    const form = new FormData();
    form.set("sidekickId", "todo");
    form.set("kind", "change");
    form.set("transcript", "bigger");
    form.set("bundleVersion", OLD_VERSION);
    await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form }, env);
    expect(await backend.waitForJob(5)).toBe(true);
  });
});
