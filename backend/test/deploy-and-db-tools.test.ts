import { describe, expect, it } from "vitest";
import { bundleContentHash, liveDeployRefusal, validateManifest } from "../scripts/bundle-tools.mjs";
import { assignmentSql, backupFileName, checkAssignArgs, findUserSql, rowsFromWranglerJson, sqlLiteral } from "../scripts/db-tools.mjs";
import { ENVIRONMENTS, environmentFromArgs, positionalArgs } from "../scripts/environments.mjs";
import { makeMigratedD1 } from "./helpers/migrated-d1";

const REMINDERS_MANIFEST = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [] };

describe("validateManifest", () => {
  it("accepts the reminders manifest as the reminders agent wrote it", () => {
    expect(validateManifest(REMINDERS_MANIFEST, "reminders")).toEqual([]);
    expect(validateManifest({ ...REMINDERS_MANIFEST, id: "calendar", reads: ["reminder", "birthday"] }, "calendar")).toEqual([]);
  });

  it("rejects a manifest for another Sidekick, or with a missing or malformed field", () => {
    expect(validateManifest(REMINDERS_MANIFEST, "calendar")).toEqual(['id must be "calendar"']);
    expect(validateManifest({ ...REMINDERS_MANIFEST, name: " " }, "reminders")).toHaveLength(1);
    expect(validateManifest({ ...REMINDERS_MANIFEST, icon: { symbol: "checklist", background: "orange" } }, "reminders")).toHaveLength(1);
    expect(validateManifest({ ...REMINDERS_MANIFEST, icon: undefined }, "reminders")).toHaveLength(1);
    expect(validateManifest({ ...REMINDERS_MANIFEST, reads: "reminder" }, "reminders")).toHaveLength(1);
    expect(validateManifest({ ...REMINDERS_MANIFEST, reads: ["Reminder:"] }, "reminders")).toHaveLength(1);
    expect(validateManifest([], "reminders")).toEqual(["manifest must be a JSON object"]);
  });
});

describe("staging before live", () => {
  const html = "<p>reminders</p>";
  const manifestText = JSON.stringify(REMINDERS_MANIFEST);
  const contentHash = bundleContentHash(html, manifestText);

  it("hashes the page and the manifest, not the deploy time", () => {
    expect(bundleContentHash(html, manifestText)).toBe(contentHash);
    expect(bundleContentHash("<p>changed</p>", manifestText)).not.toBe(contentHash);
    expect(bundleContentHash(html, manifestText.replace("Reminders", "Todo"))).not.toBe(contentHash);
    // Moving text from the page into the manifest is a different deploy.
    expect(bundleContentHash("ab", "c")).not.toBe(bundleContentHash("a", "bc"));
  });

  it("lets live take exactly what staging runs", () => {
    expect(liveDeployRefusal({ version: "v1", scriptHashes: [], contentHash }, contentHash)).toBeNull();
  });

  it("refuses live when staging never had it, runs something else, or predates content hashes", () => {
    expect(liveDeployRefusal(null, contentHash)).toMatch(/deploy to staging first/);
    expect(liveDeployRefusal({ version: "v1", scriptHashes: [], contentHash: "other" }, contentHash)).toMatch(/different version/);
    expect(liveDeployRefusal({ version: "v1", scriptHashes: [] }, contentHash)).toMatch(/different version/);
  });
});

describe("environments", () => {
  it("requires an explicit, known --env and never defaults to live", () => {
    expect(environmentFromArgs(["reminders"])).toBeNull();
    expect(environmentFromArgs(["reminders", "--env"])).toBeNull();
    expect(environmentFromArgs(["reminders", "--env", "production"])).toBeNull();
    expect(environmentFromArgs(["reminders", "--env", "toString"])).toBeNull();
    expect(environmentFromArgs(["reminders", "--env", "live"])).toBe(ENVIRONMENTS.live);
    expect(environmentFromArgs(["--env", "staging", "reminders"])).toBe(ENVIRONMENTS.staging);
  });

  it("keeps staging on its own database and bucket", () => {
    expect(ENVIRONMENTS.staging.database).not.toBe(ENVIRONMENTS.live.database);
    expect(ENVIRONMENTS.staging.bucket).not.toBe(ENVIRONMENTS.live.bucket);
    expect(ENVIRONMENTS.staging.wranglerEnvArgs).toEqual(["--env", "staging"]);
  });

  it("strips the --env flag from positional arguments", () => {
    expect(positionalArgs(["Priya", "--env", "staging", "reminders"])).toEqual(["Priya", "reminders"]);
  });
});

describe("assign SQL", () => {
  it("quotes values so a name cannot break out of the string", () => {
    expect(sqlLiteral("O'Brien")).toBe("'O''Brien'");
    function quoteControlCharacter() {
      return sqlLiteral("a\nb");
    }
    expect(quoteControlCharacter).toThrow();
  });

  it("checks the name and Sidekick id like the routes do", () => {
    expect(checkAssignArgs("Priya", "reminders")).toEqual([]);
    expect(checkAssignArgs("   ", "reminders")).toHaveLength(1);
    expect(checkAssignArgs("Priya", "../x")).toHaveLength(1);
    expect(checkAssignArgs(undefined, undefined)).toHaveLength(2);
  });

  it("finds a user by name in any case and assigns by inserting only, once", () => {
    const db = makeMigratedD1();
    db.execute("INSERT INTO users (id, name, created_at) VALUES ('u1', 'O''Brien', 'now')");
    const found = db.query(findUserSql("  o'brien "));
    expect(found).toEqual([{ id: "u1", name: "O'Brien" }]);

    const assignedAt = new Date("2026-10-11T09:00:00.000Z");
    const insertSql = assignmentSql("u1", "reminders", assignedAt);
    expect(insertSql).toMatch(/^INSERT OR IGNORE INTO assignments /);
    db.execute(insertSql);
    db.execute(assignmentSql("u1", "reminders", new Date("2026-10-12T09:00:00.000Z")));
    expect(db.query("SELECT user_id, sidekick_id, assigned_at FROM assignments")).toEqual([
      { user_id: "u1", sidekick_id: "reminders", assigned_at: "2026-10-11T09:00:00.000Z" },
    ]);
  });

  it("reads rows from wrangler's --json output", () => {
    const output = JSON.stringify([{ results: [{ id: "u1", name: "Priya" }], success: true, meta: {} }]);
    expect(rowsFromWranglerJson(output)).toEqual([{ id: "u1", name: "Priya" }]);
    expect(rowsFromWranglerJson(JSON.stringify([{ results: [], success: true }]))).toEqual([]);
  });
});

describe("backupFileName", () => {
  it("names the environment and database and sorts by time", () => {
    const takenAt = new Date("2026-10-11T09:05:07.123Z");
    expect(backupFileName(ENVIRONMENTS.live, takenAt)).toBe("live-midas-20261011T090507Z.sql");
    expect(backupFileName(ENVIRONMENTS.staging, takenAt)).toBe("staging-midas-staging-20261011T090507Z.sql");
  });
});
