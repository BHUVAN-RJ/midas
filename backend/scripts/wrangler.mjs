// Runs the wrangler CLI for the scripts. Kept in one place so every remote call is easy to find.
import { execFileSync } from "node:child_process";

export function runWrangler(wranglerArgs) {
  const commandArgs = ["wrangler", ...wranglerArgs];
  execFileSync("npx", commandArgs, { stdio: "inherit" });
}

// Same, but returns what wrangler prints instead of showing it.
export function captureWrangler(wranglerArgs) {
  const commandArgs = ["wrangler", ...wranglerArgs];
  return execFileSync("npx", commandArgs, { encoding: "utf8", stdio: ["inherit", "pipe", "inherit"] });
}
