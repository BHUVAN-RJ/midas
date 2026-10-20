// The store helper pasted into every Sidekick page (shell/sdk/midas-store.js). Each copy's tests
// require the page to contain the current helper unchanged (reminders-bundle.test.ts, "contains
// the shell's midas-store.js unchanged"), and the check runs those tests against the checkout's
// current SDK. A user copy made before an SDK change still holds the older helper and would fail
// its own tests on any repair. So the runner, and the user-copy upgrade planner, put the current
// helper in place of the old one. Every helper so far (d8c91ef, 7f402c5, 69c199d) starts with the
// same first line and ends with the "})();" that closes createMidasStore; the new helper is a
// superset of the old calls (set, get, query, delete), so the page's own code keeps working.
import { readFileSync } from "node:fs";

export const HELPER_FIRST_LINE = "// Midas local store for Sidekicks.";
const HELPER_STORE_LINE = "var store = (function createMidasStore() {";
const HELPER_END = "\n})();";

export function currentStoreHelper(helperPath = new URL("../../shell/sdk/midas-store.js", import.meta.url)) {
  return readFileSync(helperPath, "utf8").trim();
}

// The pasted helper in the page as { start, end } offsets, or null when the page has none (or
// one this code does not recognise).
export function findStoreHelper(html) {
  const start = html.indexOf(HELPER_FIRST_LINE);
  if (start === -1) {
    return null;
  }
  const storeLine = html.indexOf(HELPER_STORE_LINE, start);
  if (storeLine === -1) {
    return null;
  }
  const endMarker = html.indexOf(HELPER_END, storeLine);
  if (endMarker === -1) {
    return null;
  }
  return { start, end: endMarker + HELPER_END.length };
}

// Returns { html, status }: status "current" (already the current helper), "refreshed" (an
// older helper replaced) or "missing" (no helper found; the page is returned unchanged).
export function refreshStoreHelper(html, helperText) {
  const helper = helperText.trim();
  if (html.includes(helper)) {
    return { html, status: "current" };
  }
  const found = findStoreHelper(html);
  if (found === null) {
    return { html, status: "missing" };
  }
  const refreshed = html.slice(0, found.start) + helper + html.slice(found.end);
  return { html: refreshed, status: "refreshed" };
}
