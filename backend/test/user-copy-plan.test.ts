// What each existing user copy needs to be on today's data rules (founder, 2026-10-19;
// docs/briefs/repair-data-2026-10-19.md item 5). The planner reads only; this is its pure part:
// a copy that follows the base needs at most --from-base; in a repaired copy only an older store
// helper is mechanical, and only after the schema and records checks pass; a repaired copy without
// types needs the schema pass first; a repaired copy that still writes retired shapes is listed for
// its repair to be carried over by hand.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { bundleContentHash } from "../scripts/bundle-tools.mjs";
import { currentStoreHelper } from "../scripts/store-helper.mjs";
import { planUserCopy, retiredWrites } from "../scripts/user-copy-plan.mjs";

const sidekickFolder = new URL("../../sidekicks/reminders/", import.meta.url);
const baseHtml = readFileSync(new URL("index.html", sidekickFolder), "utf8");
const baseManifestText = readFileSync(new URL("manifest.json", sidekickFolder), "utf8");
const baseManifest = JSON.parse(baseManifestText);
const helper = currentStoreHelper();
const baseHash = bundleContentHash(baseHtml, baseManifestText);

const OLD_HELPER = [
  "// Midas local store for Sidekicks. Paste this into the Sidekick bundle's inline script (its",
  "var store = (function createMidasStore() {",
  "  return { set: setRecord, get: getRecord, delete: deleteRecord, query: queryRecords };",
  "})();",
].join("\n");

const base = { pointer: { version: "base-2", contentHash: baseHash }, manifest: baseManifest };

function planFor(copy: { pointer: Record<string, unknown> | null; html?: string; manifestText?: string }, baseContentHashes: Record<string, string> = { "base-2": baseHash, "base-1": "hash-of-base-1" }) {
  return planUserCopy({
    sidekickId: "reminders",
    envName: "live",
    copy: { userId: "user-1", pointer: copy.pointer, html: copy.html ?? baseHtml, manifestText: copy.manifestText ?? baseManifestText },
    base,
    baseContentHashes,
    helperText: helper,
  });
}

describe("planUserCopy", () => {
  it("does nothing for a user without a copy", () => {
    const plan = planFor({ pointer: null });
    expect(plan.state).toBe("none");
    expect(plan.actions).toEqual([]);
  });

  it("does nothing for an untouched copy of the current base", () => {
    const plan = planFor({ pointer: { version: "base-2", baseVersion: "base-2", contentHash: baseHash } });
    expect(plan.state).toBe("follows base");
    expect(plan.actions).toEqual([]);
    expect(plan.gaps).toEqual([]);
  });

  it("moves an untouched copy of an older base with --from-base", () => {
    const plan = planFor({ pointer: { version: "base-1", baseVersion: "base-1", contentHash: "hash-of-base-1" } });
    expect(plan.state).toBe("follows base");
    expect(plan.actions).toEqual(["node scripts/deploy-sidekick.mjs reminders --env live --user user-1 --from-base"]);
  });

  it("never upgrades a repaired copy without types: it needs the schema pass first, and no deploy command is printed", () => {
    const oldPage = baseHtml.replace(helper, OLD_HELPER).replace("<title>Reminders</title>", "<title>My Reminders</title>");
    const manifestWithoutTypes = { ...baseManifest };
    delete manifestWithoutTypes.types;
    const plan = planFor({ pointer: { version: "u-1", baseVersion: "base-1", contentHash: "repaired" }, html: oldPage, manifestText: JSON.stringify(manifestWithoutTypes) });
    expect(plan.state).toBe("repaired");
    expect(plan.gaps).toEqual(["older store helper", "manifest has no types"]);
    expect(plan.upgraded).toBeNull();
    expect(plan.actions[0]).toMatch(/^needs the schema pass first/);
    expect(plan.actions).toEqual([plan.actions[0], "way back, losing the repair: node scripts/deploy-sidekick.mjs reminders --env live --user user-1 --from-base"]);
    // No printed command may publish this copy: no --dir deploy in any action.
    const deployActions = plan.actions.filter(function actionDeploysAFolder(action: string) {
      return action.includes("--dir");
    });
    expect(deployActions).toEqual([]);
  });

  it("lists a repaired copy that still writes task: records for its repair to be carried over, and writes nothing", () => {
    const oldPage = `${baseHtml}<script>store.set('task:' + id, item)</script>`;
    const plan = planFor({ pointer: { version: "u-1", baseVersion: "base-1", contentHash: "repaired" }, html: oldPage });
    expect(plan.state).toBe("repaired");
    expect(plan.gaps).toContain("writes task: records");
    expect(plan.upgraded).toBeNull();
    expect(plan.actions[0]).toMatch(/^needs its repair carried onto today's base by hand/);
    expect(plan.actions[1]).toBe("way back, losing the repair: node scripts/deploy-sidekick.mjs reminders --env live --user user-1 --from-base");
  });

  it("leaves a repaired copy that is already on today's rules alone", () => {
    const repairedPage = baseHtml.replace("<title>Reminders</title>", "<title>My Reminders</title>");
    const plan = planFor({ pointer: { version: "u-2", baseVersion: "base-2", contentHash: "repaired" }, html: repairedPage });
    expect(plan.state).toBe("repaired");
    expect(plan.gaps).toEqual([]);
    expect(plan.actions).toEqual([]);
  });
});

describe("retiredWrites", () => {
  it("sees writes of retired shapes, not reads", () => {
    expect(retiredWrites("store.query('task:'); store.get('settings:sidebar')")).toEqual([]);
    expect(retiredWrites("store.update(\"task:1\", p); store.set('settings:sidebar', s)")).toEqual(["writes task: records", "writes settings:sidebar"]);
    expect(retiredWrites(baseHtml)).toEqual([]);
  });
});
