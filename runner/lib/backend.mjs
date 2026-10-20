// The runner's view of the backend (docs/briefs/repair-contract.md, "Job pull for the Mac").
// Three calls, all with the runner token, never a user session:
//   POST /repairs/jobs/claim            -> one report (200) or none (204)
//   GET  /repairs/<id>/assets/<name>    -> bytes (200) or missing (404)
//   POST /repairs/<id>/status           -> { status, ...extra }
// Asset names the runner asks for. "bundle.html" and "bundle.manifest.json" are the reporter's
// current copy of the Sidekick, served by the backend from the live bucket.
export const ASSET_NAMES = {
  screenshot: "screenshot.png",
  drawing: "drawing.png",
  strokes: "strokes.json",
  transcript: "transcript.txt",
  bundleHtml: "bundle.html",
  bundleManifest: "bundle.manifest.json",
};

export const STATUSES = ["received", "queued", "running", "fix_ready", "deployed_live", "failed"];

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

export function createBackendClient({ baseUrl, token, fetchImplementation = globalThis.fetch }) {
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
    return normalizeJob(reply);
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

  return { claimJob, downloadAsset, postStatus };
}
