// Records fit (docs/briefs/repair-lanes.md W1): every record the person already has passes the
// repaired copy's schema. This reuses the runner's own records check (runner/lib/user-records.mjs,
// the validator the phone and the server run, loaded from the checkout under test) rather than a
// second copy of it, so the shield and the publish step can never disagree.
import { join } from "node:path";
import { pathToFileURL } from "node:url";

async function loadRecordsCheck(checkoutRoot) {
  const modulePath = join(checkoutRoot, "runner", "lib", "user-records.mjs");
  return import(pathToFileURL(modulePath).href);
}

// Returns { problems, notes }.
export async function checkRecordsFit({ checkoutRoot, records, manifestAfter }) {
  const recordsCheck = await loadRecordsCheck(checkoutRoot);
  const modules = await recordsCheck.loadDataModules(checkoutRoot);
  const result = recordsCheck.checkUserRecords({ records, manifest: manifestAfter, modules });
  if (result.failures.length > 0) {
    return { problems: [recordsCheck.recordFailureDetail(result.failures)], notes: [] };
  }
  return { problems: [], notes: [`${result.checked} of the person's records fit`] };
}
