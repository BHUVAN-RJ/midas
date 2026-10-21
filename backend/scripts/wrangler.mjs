// Runs the wrangler CLI for the scripts. Kept in one place so every remote call is easy to find.
// Always from backend/ (where wrangler is installed) and with npx --no-install: run from anywhere
// else, npx would ask on a hidden prompt to install wrangler and wait forever (the runner's
// read-back, first staging run, 2026-10-19). A missing wrangler now fails at once instead.
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

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
