// jess grows the Sidekick, the re-run (founder 2026-10-21: in the backend, not on the phone).
// Right after a repair is published to the reporter's copy and marked deployed_live, the runner
// re-runs the pending jess request linked to it, if any:
//   1. the new tools.js context() of the reporter's records -> POST /repairs/<id>/jess-rerun, which
//      claims the request once and routes its original words with its original time;
//   2. a "done" names a tool: the runner runs that handler of the published tools.js here, in
//      node:vm (as the phone runs it in JavaScriptCore: pure, no network, no store), with the
//      reporter's records and the time now;
//   3. its ops (or its refusal) -> POST /repairs/<id>/jess-rerun/ops, which checks each against the
//      published version's schema and appends them to the reporter's op log. The phone pulls them.
// Kept self-contained (no import from backend/): the runner folder is also run on its own.
import vm from "node:vm";

const TOOLS_GLOBAL = "MidasSidekickTools";
const RUN_TIMEOUT_MS = 2000;

// tools.js in a fresh context with nothing but a silent console. Returns the tools object or
// throws with why.
export function loadTools(toolsText) {
  const sandbox = { console: { log() {}, warn() {}, error() {} } };
  vm.createContext(sandbox);
  vm.runInContext(`${toolsText}\n;globalThis.__tools = typeof ${TOOLS_GLOBAL} === "undefined" ? null : ${TOOLS_GLOBAL};`, sandbox, { timeout: RUN_TIMEOUT_MS });
  const tools = sandbox.__tools;
  if (tools === null || typeof tools !== "object" || typeof tools.context !== "function" || typeof tools.handlers !== "object" || tools.handlers === null) {
    throw new Error(`tools.js sets no ${TOOLS_GLOBAL} with context and handlers`);
  }
  return tools;
}

// Values cross into and out of the sandbox as JSON, as on the phone
function throughJson(value) {
  return JSON.parse(JSON.stringify(value));
}

// "reminders.add" -> "add", only for the Sidekick named
export function verbOf(tool, sidekickId) {
  const prefix = sidekickId + ".";
  if (typeof tool !== "string" || !tool.startsWith(prefix) || tool.length === prefix.length) {
    return null;
  }
  return tool.slice(prefix.length);
}

// What the ops route gets for a handler's reply
export function opsBody({ pendingId, version, reply }) {
  const text = reply && reply.result && typeof reply.result.text === "string" ? reply.result.text : "";
  if (typeof reply.refused === "string") {
    return { pendingId, version, refused: reply.refused, text };
  }
  if (!Array.isArray(reply.ops)) {
    return { pendingId, version, failed: "handler gave neither ops nor refused", text };
  }
  return { pendingId, version, ops: reply.ops, text };
}

// deps: { backend, job, toolsText, records, now?: () => Date }
// Returns { status: "none" } (nothing linked or the flag off), { status: "not-done", reason }, or
// what the ops route answered ({ status: "done", ops } | { status: "failed", reason }). Throws
// only when the backend cannot be reached; the repair itself stays deployed either way.
export async function rerunPendingRequest({ backend, job, toolsText, records, now = () => new Date() }) {
  if (typeof toolsText !== "string") {
    return { status: "none" };
  }
  let tools;
  let context = null;
  try {
    tools = loadTools(toolsText);
    context = throughJson(tools.context(throughJson(records), now().toISOString()));
  } catch {
    tools = null;
  }
  const routed = await backend.rerunJess(job.id, { context });
  if (routed === null) {
    return { status: "none" };
  }
  if (routed.status !== "done") {
    return { status: "not-done", reason: routed.reason };
  }
  const base = { pendingId: routed.pendingId, version: routed.version };
  const verb = verbOf(routed.tool, job.sidekickId);
  if (tools === null || verb === null || typeof tools.handlers[verb] !== "function") {
    return backend.sendJessOps(job.id, { ...base, failed: tools === null ? "tools.js did not load" : `no handler for ${routed.tool}`, text: "" });
  }
  let reply;
  try {
    reply = throughJson(tools.handlers[verb](throughJson(routed.input), throughJson(records), now().toISOString()));
  } catch (error) {
    return backend.sendJessOps(job.id, { ...base, failed: `handler threw: ${error && error.message ? error.message : String(error)}`.slice(0, 200), text: "" });
  }
  return backend.sendJessOps(job.id, opsBody({ ...base, reply }));
}
