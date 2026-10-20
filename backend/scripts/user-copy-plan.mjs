// What each existing user copy needs to be on today's data rules (CONCERNS 8, founder 2026-10-19).
// Pure: no I/O. plan-user-copies.mjs reads staging or live and prints this plan; it writes nothing
// remote. The founder runs (or approves) the printed commands.
//
// A copy is one user's own version of a Sidekick (sidekicks/<id>/users/<uid>/current.json). It is:
//   - "none": the user runs the base; nothing to do for the page.
//   - "follows base": its page and manifest are exactly a base version (never repaired). The next
//     base deploy moves it with the base; until then --from-base moves it now.
//   - "repaired": it differs from its base version. A base deploy leaves it alone. It is upgraded
//     mechanically when the only gaps are mechanical (an older store helper, a manifest without
//     types); a page that still writes retired shapes needs its repair carried onto today's base.
import { bundleContentHash, sortUserCopies } from "./bundle-tools.mjs";
import { refreshStoreHelper } from "./store-helper.mjs";

// Literal writes of shapes the rework retired (unified data plan, section 4).
const RETIRED_WRITE_PATTERNS = [
  { pattern: /store\.(?:set|update)\(\s*['"`]task:/, what: "writes task: records" },
  { pattern: /store\.(?:set|update)\(\s*['"`]settings:sidebar['"`]/, what: "writes settings:sidebar" },
];

export function retiredWrites(html) {
  const found = [];
  for (const retired of RETIRED_WRITE_PATTERNS) {
    if (retired.pattern.test(html)) {
      found.push(retired.what);
    }
  }
  return found;
}

function hasTypes(manifest) {
  return manifest !== null && typeof manifest === "object" && typeof manifest.types === "object" && manifest.types !== null;
}

// copy: { userId, pointer, html, manifestText } (pointer null when the user has no copy).
// base: { pointer, manifest } for the base's current version. baseContentHashes: base version ->
// contentHash. Returns { userId, state, gaps, actions, upgraded } where upgraded is
// { html, manifestText } for a mechanical upgrade, else null. envName goes into the commands.
export function planUserCopy({ sidekickId, envName, copy, base, baseContentHashes, helperText }) {
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
  const retired = retiredWrites(copy.html);
  result.gaps.push(...retired);

  if (followsBase) {
    result.state = "follows base";
    if (!onCurrentBase) {
      result.actions.push(`node scripts/deploy-sidekick.mjs ${sidekickId} --env ${envName} --user ${userId} --from-base`);
    }
    return result;
  }

  result.state = "repaired";
  const mechanical = retired.length === 0 && helper.status !== "missing";
  if (result.gaps.length === 0) {
    return result;
  }
  if (!mechanical) {
    result.actions.push(`needs its repair carried onto today's base by hand (or a new repair): ${result.gaps.join(", ")}`);
    result.actions.push(`way back, losing the repair: node scripts/deploy-sidekick.mjs ${sidekickId} --env ${envName} --user ${userId} --from-base`);
    return result;
  }
  // Mechanical: today's helper in the page; the base's types in a manifest that has none (the
  // copy's own fields stay valid: no base type forbids extra fields).
  const upgradedManifest = hasTypes(manifest) ? manifest : { ...manifest, types: base.manifest.types };
  const upgradedManifestText = hasTypes(manifest) ? copy.manifestText : `${JSON.stringify(upgradedManifest, null, 2)}\n`;
  result.upgraded = { html: helper.html, manifestText: upgradedManifestText, contentHash: bundleContentHash(helper.html, upgradedManifestText) };
  result.actions.push(`node scripts/deploy-sidekick.mjs ${sidekickId} --env ${envName} --user ${userId} --dir <out>/${sidekickId}/${userId}`);
  return result;
}
