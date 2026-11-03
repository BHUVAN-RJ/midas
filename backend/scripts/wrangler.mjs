// Runs the wrangler CLI for the scripts. Kept in one place so every remote call is easy to find.
// Always from backend/ (where wrangler is installed) and with npx --no-install: run from anywhere
// else, npx would ask on a hidden prompt to install wrangler and wait forever (the runner's
// read-back, first staging run, 2026-10-19). A missing wrangler now fails at once instead.
import { execFile, execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export const BACKEND_FOLDER = fileURLToPath(new URL("../", import.meta.url));

// What execFileSync runs for `wrangler <args>`: { command, args, cwd }.
export function wranglerInvocation(wranglerArgs) {
  return { command: "npx", args: ["--no-install", "wrangler", ...wranglerArgs], cwd: BACKEND_FOLDER };
}

export function runWrangler(wranglerArgs) {
  const invocation = wranglerInvocation(wranglerArgs);
  execFileSync(invocation.command, invocation.args, { cwd: invocation.cwd, stdio: "inherit" });
}

// Same, but returns what wrangler prints instead of showing it. The buffer is large enough for a
// whole ops table as JSON (Node's default is 1 MB). timeoutMs, when
// given, kills wrangler after that long (the runner's read-back must never wait unseen).
const CAPTURE_BUFFER_BYTES = 512 * 1024 * 1024;

export function captureWrangler(wranglerArgs, { timeoutMs } = {}) {
  const invocation = wranglerInvocation(wranglerArgs);
  const options = { cwd: invocation.cwd, encoding: "utf8", stdio: ["inherit", "pipe", "inherit"], maxBuffer: CAPTURE_BUFFER_BYTES };
  if (timeoutMs !== undefined) {
    options.timeout = timeoutMs;
  }
  return execFileSync(invocation.command, invocation.args, options);
}

// ---- Several at once (--parallel, runner speed trial 2026-11-02) ------------------------------

// Same as captureWrangler, but returns a promise, so several wrangler calls can run together.
// What wrangler prints on stderr is passed through once it finishes.
export async function captureWranglerAsync(wranglerArgs) {
  const invocation = wranglerInvocation(wranglerArgs);
  const options = { cwd: invocation.cwd, encoding: "utf8", maxBuffer: CAPTURE_BUFFER_BYTES };
  const result = await execFileAsync(invocation.command, invocation.args, options);
  if (result.stderr) {
    process.stderr.write(result.stderr);
  }
  return result.stdout;
}

// Same as runWrangler, as a promise; wrangler's output is printed when the call ends, so lines of
// calls running together are never interleaved.
export async function runWranglerAsync(wranglerArgs) {
  const output = await captureWranglerAsync(wranglerArgs);
  process.stdout.write(output);
}

export const PARALLEL_WRANGLER_CALLS = 6;

// Runs workItem on every item, at most `limit` at a time; resolves with the results in the items'
// order. The first failure rejects (calls already started still finish).
export async function runWithLimit(items, limit, workItem) {
  const results = new Array(items.length);
  let nextIndex = 0;
  async function workNextItems() {
    while (nextIndex < items.length) {
      const itemIndex = nextIndex;
      nextIndex += 1;
      results[itemIndex] = await workItem(items[itemIndex], itemIndex);
    }
  }
  const workerCount = Math.min(limit, items.length);
  const workers = [];
  for (let workerIndex = 0; workerIndex < workerCount; workerIndex += 1) {
    workers.push(workNextItems());
  }
  await Promise.all(workers);
  return results;
}
