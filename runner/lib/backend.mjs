// The runner's view of the backend (docs/briefs/repair-contract.md, "Job pull for the Mac").
// All with the runner token, never a user session:
//   POST /repairs/jobs/claim            -> one report (200) or none (204)
//   GET  /repairs/<id>/assets/<name>    -> bytes (200) or missing (404)
//   POST /repairs/<id>/status           -> { status, ...extra }
//   GET  /repairs/<id>/records          -> { records: [{ key, value }] } (the reporter's own)
//   POST /repairs/<id>/jess-rerun       -> the routed re-run of a pending jess request (200) or
//                                          none (204) (jess grows the Sidekick, 2026-10-21)
//   POST /repairs/<id>/jess-rerun/ops   -> { status: "done", ops } | { status: "failed", reason }
// Asset names the runner asks for. "bundle.html", "bundle.manifest.json" and "bundle.tools.js"
// are the reporter's current copy of the Sidekick, served by the backend from the live bucket
// (tools.js only when the copy has the jess router's tools, else 404).
export const ASSET_NAMES = {
  screenshot: "screenshot.png",
  drawing: "drawing.png",
  strokes: "strokes.json",
  transcript: "transcript.txt",
  bundleHtml: "bundle.html",
  bundleManifest: "bundle.manifest.json",
  bundleTools: "bundle.tools.js",
};

// no_change (founder, 2026-10-23): the agent found nothing to change; the backend stores it as
// failed with result kind already_there, so the user sees "Already There", never "failed".
export const STATUSES = ["received", "queued", "running", "fix_ready", "deployed_live", "failed", "no_change"];

function pickFirstDefined(source, keys) {
  for (const key of keys) {
    if (source[key] !== undefined && source[key] !== null) {
      return source[key];
    }
  }
  return null;
}

// The claim reply as the runner uses it. Accepts the D1 row shape (snake_case) and a camelCase
// shape, and a reply that wraps the report under "report" or "job".
export function normalizeJob(reply) {
  if (reply === null || typeof reply !== "object") {
    return null;
  }
  const report = reply.report ?? reply.job ?? reply;
  const id = pickFirstDefined(report, ["id", "reportId", "report_id"]);
  const userId = pickFirstDefined(report, ["userId", "user_id"]);
  const sidekickId = pickFirstDefined(report, ["sidekickId", "sidekick_id"]);
  if (id === null || userId === null || sidekickId === null) {
    throw new Error(`claim reply lacks id, userId or sidekickId: ${JSON.stringify(reply).slice(0, 200)}`);
  }
  return {
    id: String(id),
    userId: String(userId),
    sidekickId: String(sidekickId),
    bundleVersion: pickFirstDefined(report, ["bundleVersion", "bundle_version"]),
    kind: pickFirstDefined(report, ["kind"]) ?? "unknown",
    transcript: pickFirstDefined(report, ["transcript"]) ?? "",
    device: pickFirstDefined(report, ["device"]),
    appVersion: pickFirstDefined(report, ["appVersion", "app_version"]),
    createdAt: pickFirstDefined(report, ["createdAt", "created_at"]),
    leaseExpiresAt: pickFirstDefined(reply, ["leaseExpiresAt", "lease_expires_at"]) ?? pickFirstDefined(report, ["leaseExpiresAt", "lease_expires_at"]),
  };
}

// environment: "live" or "staging", the Worker this client talks to (the runner serves both,
// founder 2026-10-21). Every job it claims carries it, so the job runs in that environment only.
export function createBackendClient({ baseUrl, token, environment = null, fetchImplementation = globalThis.fetch }) {
  // "Runner", not "Bearer": the Worker keeps the runner's token apart from user sessions
  // (backend/src/repairs.ts RUNNER_PREFIX)
  const authorizationHeader = { Authorization: `Runner ${token}` };

  async function claimJob() {
    const response = await fetchImplementation(`${baseUrl}/repairs/jobs/claim`, { method: "POST", headers: authorizationHeader });
    if (response.status === 204) {
      return null;
    }
    if (!response.ok) {
      throw new Error(`claim failed: ${response.status}`);
    }
    const reply = await response.json();
    if (reply === null || (typeof reply === "object" && Object.keys(reply).length === 0)) {
      return null;
    }
    const job = normalizeJob(reply);
    if (environment !== null) {
      job.environment = environment;
    }
    return job;
  }

  // The asset's bytes, or null when the backend has none (404).
  async function downloadAsset(reportId, assetName) {
    const assetUrl = `${baseUrl}/repairs/${encodeURIComponent(reportId)}/assets/${encodeURIComponent(assetName)}`;
    const response = await fetchImplementation(assetUrl, { headers: authorizationHeader });
    if (response.status === 404) {
      return null;
    }
    if (!response.ok) {
      throw new Error(`asset ${assetName} failed: ${response.status}`);
    }
    const bytes = await response.arrayBuffer();
    return Buffer.from(bytes);
  }

  async function postStatus(reportId, status, extra = {}) {
    if (!STATUSES.includes(status)) {
      throw new Error(`unknown status "${status}"`);
    }
    const statusUrl = `${baseUrl}/repairs/${encodeURIComponent(reportId)}/status`;
    const body = JSON.stringify({ status, ...extra });
    const headers = { ...authorizationHeader, "Content-Type": "application/json" };
    const response = await fetchImplementation(statusUrl, { method: "POST", headers, body });
    if (!response.ok) {
      throw new Error(`status ${status} failed: ${response.status}`);
    }
  }

  // The backend's own words for a refusal, e.g. " records too large (5000000 bytes, limit 4194304)".
  async function errorSuffix(response) {
    let body;
    try {
      body = await response.json();
    } catch {
      return "";
    }
    if (body === null || typeof body !== "object" || typeof body.error !== "string") {
      return "";
    }
    const sizeText = typeof body.bytes === "number" ? ` (${body.bytes} bytes, limit ${body.limit})` : "";
    return ` ${body.error}${sizeText}`;
  }

  // The reporter's latest records for the report's Sidekick (runner-only route, founder
  // 2026-10-19), as [{ key, value }]. Throws on anything but a well-formed 200: the runner never
  // publishes a schema it could not check against the user's records.
  async function listRecords(reportId) {
    const recordsUrl = `${baseUrl}/repairs/${encodeURIComponent(reportId)}/records`;
    const response = await fetchImplementation(recordsUrl, { headers: authorizationHeader });
    if (!response.ok) {
      throw new Error(`records failed: ${response.status}${await errorSuffix(response)}`);
    }
    const reply = await response.json();
    if (reply === null || typeof reply !== "object" || !Array.isArray(reply.records)) {
      throw new Error("records reply has no records list");
    }
    return reply.records;
  }

  async function postJson(path, body) {
    const headers = { ...authorizationHeader, "Content-Type": "application/json" };
    return fetchImplementation(`${baseUrl}${path}`, { method: "POST", headers, body: JSON.stringify(body) });
  }

  // The routed re-run of the pending jess request linked to the report, or null when none waits
  async function rerunJess(reportId, body) {
    const response = await postJson(`/repairs/${encodeURIComponent(reportId)}/jess-rerun`, body);
    if (response.status === 204) {
      return null;
    }
    if (!response.ok) {
      throw new Error(`jess re-run failed: ${response.status}${await errorSuffix(response)}`);
    }
    return response.json();
  }

  async function sendJessOps(reportId, body) {
    const response = await postJson(`/repairs/${encodeURIComponent(reportId)}/jess-rerun/ops`, body);
    if (!response.ok) {
      throw new Error(`jess re-run ops failed: ${response.status}${await errorSuffix(response)}`);
    }
    return response.json();
  }

  return { environment, claimJob, downloadAsset, postStatus, listRecords, rerunJess, sendJessOps };
}
