// What each existing user copy needs to be on today's data rules (CONCERNS 8, founder 2026-10-19).
// Pure: no I/O. plan-user-copies.mjs reads staging or live and prints this plan; it writes nothing
// remote. The founder runs (or approves) the printed commands.
//
// A copy is one user's own version of a Sidekick (sidekicks/<id>/users/<uid>/current.json). It is:
//   - "none": the user runs the base; nothing to do for the page.
//   - "follows base": its page and manifest are exactly a base version (never repaired). The next
//     base deploy moves it with the base; until then --from-base moves it now.
//   - "repaired": it differs from its base version. A base deploy leaves it alone. The only
//     mechanical upgrade is today's store helper in a page whose manifest declares its types, and
//     only when the runner's own checks pass on it (founder go, 2026-10-19): the schema rules
//     (add only, every literal write declared) and every record the user has fitting the copy's
//     types. A copy without types is never mechanical: giving it the base's types narrows what
//     the shell accepts from that page (keys built from variables), so it needs the schema pass
//     first. A page that writes a prefix its types do not declare needs its repair carried onto
//     today's base.
import { schemaRuleProblems, undeclaredWritePrefixes } from "../../runner/lib/schema-change.mjs";
import { checkUserRecords, recordFailureDetail } from "../../runner/lib/user-records.mjs";
import { bundleContentHash, sortUserCopies } from "./bundle-tools.mjs";
import { refreshStoreHelper } from "./store-helper.mjs";

// Prefixes the page writes that its types do not declare: the shell refuses those writes on the
// phone. A copy without types is reported as that instead.
export function undeclaredWrites(html, manifest) {
  const undeclared = undeclaredWritePrefixes(html, manifest?.types);
  return undeclared.map(function describeUndeclared(prefix) {
    return `writes ${prefix} records its types do not declare`;
  });
}

function hasTypes(manifest) {
  return manifest !== null && typeof manifest === "object" && typeof manifest.types === "object" && manifest.types !== null;
}

// copy: { userId, pointer, html, manifestText } (pointer null when the user has no copy).
// base: { pointer, manifest } for the base's current version. baseContentHashes: base version ->
// contentHash. records: the user's latest records of this Sidekick ([{ key, value }]), or null
// when they were not read; without them no deploy command is printed. Returns
// { userId, state, gaps, actions, upgraded } where upgraded is { html, manifestText, contentHash }
// for a mechanical upgrade that passed every check, else null. envName goes into the commands.
export function planUserCopy({ sidekickId, envName, copy, base, baseContentHashes, helperText, records = null }) {
  const userId = copy.userId;
  const result = { userId, state: "none", gaps: [], actions: [], upgraded: null };
  if (copy.pointer === null) {
    return result;
  }
  const sorted = sortUserCopies([{ userId, pointer: copy.pointer }], baseContentHashes);
  const followsBase = sorted.untouched.length === 1;
  const onCurrentBase = copy.pointer.version === base.pointer?.version;

  const manifest = JSON.parse(copy.manifestText);
  const helper = refreshStoreHelper(copy.html, helperText);
  if (helper.status === "refreshed") {
    result.gaps.push("older store helper");
  } else if (helper.status === "missing") {
    result.gaps.push("no store helper found");
  }
  if (!hasTypes(manifest)) {
    result.gaps.push("manifest has no types");
  }
  const undeclared = undeclaredWrites(copy.html, manifest);
  result.gaps.push(...undeclared);

  if (followsBase) {
    result.state = "follows base";
    if (!onCurrentBase) {
      result.actions.push(`node scripts/deploy-sidekick.mjs ${sidekickId} --env ${envName} --user ${userId} --from-base`);
    }
    return result;
  }

  result.state = "repaired";
  if (result.gaps.length === 0) {
    return result;
  }
  const wayBack = `way back, losing the repair: node scripts/deploy-sidekick.mjs ${sidekickId} --env ${envName} --user ${userId} --from-base`;
  if (undeclared.length > 0 || helper.status === "missing") {
    result.actions.push(`needs its repair carried onto today's base by hand (or a new repair): ${result.gaps.join(", ")}`);
    result.actions.push(wayBack);
    return result;
  }
  if (!hasTypes(manifest)) {
    result.actions.push("needs the schema pass first: the copy has no types, and the runner refuses to repair it until it has; write its types from the page and the user's records");
    if (records !== null) {
      const againstBase = checkUserRecords({ sidekickId, records, manifest: { ...manifest, types: base.manifest.types } });
      const baseFit = againstBase.failures.length === 0 ? `all ${againstBase.checked} fit` : recordFailureDetail(againstBase.failures);
      result.actions.push(`the user's records against the base's types, for that pass: ${baseFit}`);
    }
    result.actions.push(wayBack);
    return result;
  }
  // Only the store helper changes: the runner's checks on the upgraded copy, then the command.
  const ruleProblems = schemaRuleProblems({ manifestBefore: manifest, manifestAfter: manifest, htmlAfter: helper.html });
  if (ruleProblems.length > 0) {
    result.actions.push(`not published: ${ruleProblems.join("; ")}`);
    return result;
  }
  if (records === null) {
    result.actions.push("not published: the user's records were not read, so they are not checked against the copy's types");
    return result;
  }
  const recordsCheck = checkUserRecords({ sidekickId, records, manifest });
  if (recordsCheck.failures.length > 0) {
    result.actions.push(`not published: ${recordFailureDetail(recordsCheck.failures)}`);
    return result;
  }
  result.upgraded = { html: helper.html, manifestText: copy.manifestText, contentHash: bundleContentHash(helper.html, copy.manifestText) };
  result.actions.push(`checked: schema unchanged, every literal write declared, ${recordsCheck.checked} of the user's records fit`);
  result.actions.push(`node scripts/deploy-sidekick.mjs ${sidekickId} --env ${envName} --user ${userId} --dir <out>/${sidekickId}/${userId}`);
  return result;
}
