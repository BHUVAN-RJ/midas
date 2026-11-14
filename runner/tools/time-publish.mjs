#!/usr/bin/env node
// Times a repair's publish, today's way and publish first (docs/briefs/repair-lanes.md W7), on
// past To-Do jobs from this Mac's runner logs, against a Worker you name (wrangler dev locally).
// The agent is not re-run: each job's repaired copy from its job folder is published again.
//
//   node runner/tools/time-publish.mjs --backend http://localhost:8796 --runner-token <t> \
//     --user-token <session token of the person> --persist-to <wrangler dev state folder> \
//     [--force-slow-failure] <job id prefix>...
//
// Per job: the person sends a report (POST /repairs), the runner's long poll wakes, claims it, and
// then the publish runs twice on the same files:
//   today          gate -> whole shield (every view) -> copy tests -> one `wrangler r2` process per
//                  object (--local here; against Cloudflare it is 1.5-3 s each, see the hand-back)
//   publish first  upload through the Worker alongside gate + shield fast part + copy tests ->
//                  pointer flip -> status -> shield slow part (roll back if it fails)
// --force-slow-failure adds a script that throws after a tap on "go-search" to the repaired page:
// the fast part passes, the person gets it, the slow part fails and the copy is rolled back.
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { createBackendClient } from "../lib/backend.mjs";
import { checkAfterPublish, checkBeforePublish, checkRepair } from "../lib/check.mjs";
import { REPO_ROOT } from "../lib/config.mjs";
import { afterPublish, createStepTimer, flipToVersion, planVersion, publishFirst, rollBackVersion, timingsTable, uploadVersion } from "../lib/publish-first.mjs";

const RUNNER_FOLDER = join(homedir(), "Library", "Application Support", "midas-runner");
const BREAKS_ON_SEARCH_TAP = "document.addEventListener('click', function (event) { if (event.target.closest('[data-action=\"go-search\"]')) { throw new Error('search broke'); } }, true);";

function optionValue(args, name) {
  const index = args.indexOf(`--${name}`);
  if (index === -1) {
    return null;
  }
  const value = args[index + 1];
  args.splice(index, 2);
  return value;
}

function flagSet(args, name) {
  const index = args.indexOf(`--${name}`);
  if (index === -1) {
    return false;
  }
  args.splice(index, 1);
  return true;
}

function seconds(milliseconds) {
  return `${(milliseconds / 1000).toFixed(2)} s`;
}

async function timedMs(run) {
  const startedAt = performance.now();
  const value = await run();
  return { value, ms: performance.now() - startedAt };
}

// The job's log and job folders, by id prefix
function pastJob(prefix) {
  const logRoot = join(RUNNER_FOLDER, "log");
  const fullId = readdirSync(logRoot).find(function startsWithPrefix(name) {
    return name.startsWith(prefix);
  });
  if (fullId === undefined) {
    throw new Error(`no runner log for ${prefix}`);
  }
  const job = JSON.parse(readFileSync(join(logRoot, fullId, "job.json"), "utf8"));
  return { id: fullId, job, beforeFolder: join(logRoot, fullId, "before"), jobFolder: join(RUNNER_FOLDER, "jobs", fullId) };
}

// A scratch copy of the job folder (sidekick/ and tests/), never the runner's own
function scratchJobFolder(sourceJobFolder, breakAfterTap) {
  const scratch = mkdtempSync(join(tmpdir(), "midas-time-publish-"));
  const jobFolder = join(scratch, "job");
  cpSync(join(sourceJobFolder, "sidekick"), join(jobFolder, "sidekick"), { recursive: true });
  cpSync(join(sourceJobFolder, "tests"), join(jobFolder, "tests"), { recursive: true });
  if (breakAfterTap) {
    const pagePath = join(jobFolder, "sidekick", "index.html");
    const html = readFileSync(pagePath, "utf8");
    // Inside the page's last inline script, not a new tag: a copy's own tests may count the tags
    const lastScriptEnd = html.lastIndexOf("</script>");
    const brokenHtml = `${html.slice(0, lastScriptEnd)}\n${BREAKS_ON_SEARCH_TAP}\n${html.slice(lastScriptEnd)}`;
    writeFileSync(pagePath, brokenHtml);
  }
  return jobFolder;
}

// The person's records, or, when the Worker has none for them, a dozen To-Dos made with the copy's
// own tools (as the shield's tests do), so the pages draw real rows
async function recordsFor({ backend, jobId, beforeFolder }) {
  const stored = await backend.listRecords(jobId);
  if (stored.length > 0) {
    return { records: stored, source: "the person's" };
  }
  const toolsCompare = await import(pathToFileURL(join(REPO_ROOT, "runner", "core-checks", "tools-compare.mjs")).href);
  const recordSchema = await import(pathToFileURL(join(REPO_ROOT, "shell", "sdk", "record-schema.js")).href);
  const nowIso = new Date().toISOString();
  const toolsText = readFileSync(join(beforeFolder, "tools.js"), "utf8");
  const types = JSON.parse(readFileSync(join(beforeFolder, "manifest.json"), "utf8")).types;
  const loaded = toolsCompare.loadDeterministicTools(toolsText, nowIso);
  let records = [];
  for (let index = 0; index < 12; index += 1) {
    const reply = loaded.tools.handlers.add({ title: `Item ${index}`, notes: null, list: null, someday: null, when: null }, records, nowIso);
    for (const op of reply.ops ?? []) {
      const others = records.filter(function isOtherKey(record) {
        return record.key !== op.key;
      });
      const stamped = recordSchema.default.stampType(types, op.key, op.value);
      records = [...others, { key: op.key, value: stamped }];
    }
  }
  return { records, source: "made with the copy's own add tool" };
}

async function sendReport({ backendUrl, userToken, transcript }) {
  const form = new FormData();
  form.set("sidekickId", "todo");
  form.set("kind", "change");
  form.set("transcript", transcript);
  const response = await fetch(`${backendUrl}/repairs`, { method: "POST", headers: { Authorization: `Bearer ${userToken}` }, body: form });
  if (response.status !== 201) {
    throw new Error(`report refused: ${response.status} ${await response.text()}`);
  }
  return response.json();
}

// Report sent -> the runner's long poll wakes -> claimed. The wait starts before the report.
async function pickUp({ backend, backendUrl, userToken, transcript }) {
  const waiting = backend.waitForJob(25);
  const sentAt = performance.now();
  await sendReport({ backendUrl, userToken, transcript });
  const ready = await waiting;
  const job = await backend.claimJob();
  return { ready, job, pickupMs: performance.now() - sentAt };
}

// Today's upload: one wrangler process per object, then the read-back, as deploy-sidekick.mjs and
// deploy.mjs do (2 pointer reads + 1 D1 query + every put + 1 read-back), here with --local
function uploadTheOldWay({ plan, persistTo, prefixKey }) {
  const backendFolder = join(REPO_ROOT, "backend");
  const scratch = mkdtempSync(join(tmpdir(), "midas-time-old-upload-"));
  const options = { cwd: backendFolder, stdio: "pipe" };
  function wrangler(args) {
    execFileSync("npx", ["wrangler", ...args, "--local", "--persist-to", persistTo], options);
  }
  function tryWrangler(args) {
    try {
      wrangler(args);
    } catch {
      // a missing object is a normal answer for the pointer reads
    }
  }
  tryWrangler(["r2", "object", "get", `midas-bundles/sidekicks/todo/current.json`, "--pipe"]);
  tryWrangler(["r2", "object", "get", `midas-bundles/${prefixKey}/current.json`, "--pipe"]);
  tryWrangler(["d1", "execute", "midas", "--command", "SELECT COALESCE(MAX(seq), 0) AS seq FROM ops"]);
  const objects = [...plan.files, { name: "version.json", body: "{}" }];
  let count = 0;
  for (const object of objects) {
    count += 1;
    const filePath = join(scratch, `object-${count}`);
    writeFileSync(filePath, object.body);
    wrangler(["r2", "object", "put", `midas-bundles/${prefixKey}/${plan.version}/${object.name}`, "--file", filePath]);
  }
  const pointerPath = join(scratch, "pointer");
  writeFileSync(pointerPath, JSON.stringify(plan.pointer));
  wrangler(["r2", "object", "put", `midas-bundles/${prefixKey}/current.json`, "--file", pointerPath]);
  tryWrangler(["r2", "object", "get", `midas-bundles/${prefixKey}/current.json`, "--pipe"]);
  return objects.length + 5;
}

async function runTodaysWay({ past, jobFolder, records, persistTo }) {
  const check = await timedMs(function checkAll() {
    return checkRepair({ checkoutRoot: REPO_ROOT, sidekickId: "todo", jobFolder, beforeFolder: past.beforeFolder, records });
  });
  const plan = await planVersion({ checkoutRoot: REPO_ROOT, sidekickId: "todo", userId: "timing-old-way", jobFolder });
  const upload = await timedMs(function uploadOld() {
    return uploadTheOldWay({ plan, persistTo, prefixKey: "sidekicks/todo/users/timing-old-way" });
  });
  return { checkMs: check.ms, checkOk: check.value.ok, uploadMs: upload.ms, wranglerCalls: upload.value, totalMs: check.ms + upload.ms };
}

async function runPublishFirst({ backend, job, past, jobFolder, records }) {
  const timer = createStepTimer();
  const plan = await planVersion({ checkoutRoot: REPO_ROOT, sidekickId: "todo", userId: job.userId, jobFolder });
  const shared = { checkoutRoot: REPO_ROOT, sidekickId: "todo", jobFolder, beforeFolder: past.beforeFolder, records };
  const published = await publishFirst({
    timer,
    upload: function upload() {
      return uploadVersion({ backend, jobId: job.id, plan });
    },
    checkBeforePublish: function checks() {
      return checkBeforePublish(shared);
    },
    flip: function flip() {
      return flipToVersion({ backend, jobId: job.id, plan });
    },
  });
  if (published.status !== "published") {
    return { timer, published, plan };
  }
  await timer.time("status: live (the person is told)", async function markLive() {
    await backend.postStatus(job.id, "fix_ready", { summary: "timing run" });
    await backend.postStatus(job.id, "deployed_live", { summary: "timing run" });
  });
  const personHasItAtMs = timer.list().at(-1).endMs;
  const after = await afterPublish({
    timer,
    checkAfterPublish: function slowChecks() {
      return checkAfterPublish(shared);
    },
    rollBack: function rollBack(reason) {
      return rollBackVersion({ backend, jobId: job.id, plan, reason });
    },
    markRolledBack: function markRolledBack(reason, detail) {
      return backend.postStatus(job.id, "failed", { reason, detail, rolledBack: true });
    },
  });
  return { timer, published, after, plan, personHasItAtMs };
}

async function main() {
  const args = process.argv.slice(2);
  const backendUrl = optionValue(args, "backend");
  const runnerToken = optionValue(args, "runner-token");
  const userToken = optionValue(args, "user-token");
  const persistTo = optionValue(args, "persist-to");
  const forceSlowFailure = flagSet(args, "force-slow-failure");
  if (!backendUrl || !runnerToken || !userToken || !persistTo || args.length === 0) {
    console.error("usage: node runner/tools/time-publish.mjs --backend <url> --runner-token <t> --user-token <t> --persist-to <dir> [--force-slow-failure] <job id prefix>...");
    process.exit(2);
  }
  const backend = createBackendClient({ baseUrl: backendUrl, token: runnerToken, environment: null });
  const rows = [];
  for (const prefix of args) {
    const past = pastJob(prefix);
    const jobFolder = scratchJobFolder(past.jobFolder, forceSlowFailure);
    const picked = await pickUp({ backend, backendUrl, userToken, transcript: past.job.transcript });
    const { records, source } = await recordsFor({ backend, jobId: picked.job.id, beforeFolder: past.beforeFolder });
    const today = forceSlowFailure ? null : await runTodaysWay({ past, jobFolder, records, persistTo });
    const first = await runPublishFirst({ backend, job: picked.job, past, jobFolder, records });
    console.log(`\n== ${prefix} "${past.job.transcript.slice(0, 60)}" (records: ${records.length}, ${source})`);
    console.log(`pickup (report sent -> long poll wakes -> claimed): ${seconds(picked.pickupMs)}`);
    if (today !== null) {
      console.log(`today: checks (gate, whole shield, copy tests) ${seconds(today.checkMs)} ${today.checkOk ? "pass" : "FAIL"}; upload ${today.wranglerCalls} wrangler --local calls ${seconds(today.uploadMs)}; checks + upload ${seconds(today.totalMs)}`);
    }
    console.log(`publish first: ${first.published.status}${first.after ? `, after publish: ${first.after.status}` : ""}`);
    console.log(timingsTable(first.timer.list()));
    if (first.published.status !== "published") {
      const problems = first.published.check?.problems ?? [first.published.detail];
      console.log(`not published: ${problems.join("; ")}`);
    }
    if (first.after?.status === "rolled back") {
      const served = await backend.downloadAsset(picked.job.id, "bundle.html");
      const servedText = served === null ? "" : served.toString("utf8");
      const stillBroken = servedText.includes("search broke");
      console.log(`rolled back: ${first.after.detail}`);
      console.log(`the person's copy now: ${stillBroken ? "STILL THE BROKEN VERSION" : "the version they had before"} (read back from the Worker)`);
    }
    rows.push({ prefix, pickupMs: picked.pickupMs, today, personHasItAtMs: first.personHasItAtMs ?? null, steps: first.timer.list(), after: first.after?.status ?? null });
  }
  const outPath = join(mkdtempSync(join(tmpdir(), "midas-time-publish-out-")), "timings.json");
  mkdirSync(join(outPath, ".."), { recursive: true });
  writeFileSync(outPath, JSON.stringify(rows, null, 2));
  console.log(`\ntimings: ${outPath}`);
}

await main();
