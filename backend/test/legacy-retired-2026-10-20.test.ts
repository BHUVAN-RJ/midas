// Second old-format sweep (docs/PRODUCT.md "Old formats retired (founder, 2026-10-20)": live
// converted, migration retired). Live and staging hold only the unified data format, so no code
// may read or write the old shapes any more: the one-time converter and migration left the codebase for docs/legacy/code/ (not
// imported, not run, not tested), the runner checks the reporter's records exactly as stored,
// and the copies planner flags any write a copy's types do not declare. Each check fails if the
// retired code or its in-memory upgrade comes back. Guard tests that hunt for the retired scripts'
// names may contain them as text; no file may import, require or join a path to them.
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";
import { buildSummary } from "../../runner/lib/summary.mjs";
import { checkUserRecords, loadDataModules, recordFailureDetail } from "../../runner/lib/user-records.mjs";
import { bundleContentHash } from "../scripts/bundle-tools.mjs";
import { currentStoreHelper } from "../scripts/store-helper.mjs";
import { planUserCopy, undeclaredWrites } from "../scripts/user-copy-plan.mjs";

const REPO_ROOT = new URL("../../", import.meta.url).pathname;
const THIS_FILE = "backend/test/legacy-retired-2026-10-20.test.ts";
// Guard tests that hunt for the retired scripts' names may contain them as text, never use them.
const NAME_HUNTING_GUARD_TESTS = [THIS_FILE, "backend/test/legacy-sweep-2-docs.test.ts"];
const RETIRED_SCRIPTS = ["record-upgrades.mjs", "migrate-records.mjs"];
const RETIRED_FOLDER = "docs/legacy/code";
const CODE_EXTENSIONS = [".ts", ".mjs", ".js", ".sql", ".sh", ".json", ".html"];
// Everything that runs or is tested: none of it may load or name the retired scripts.
const RUNNING_CODE_PATHS = ["backend/src", "backend/scripts", "backend/migrations", "backend/test", "runner/lib", "runner/bin", "runner/tools", "runner/install.sh", "scripts", "shell/sdk", "sidekicks"];
// Agent A's code (backend, runner, scripts): no upgrade-on-read wording either.
const SWEPT_CODE_PATHS = ["backend/src", "backend/scripts", "backend/migrations", "runner/lib", "runner/bin", "runner/tools", "runner/install.sh", "scripts"];
const UPGRADE_WORDING = [/upgrade[- ]on[- ]read/i, /upgraded in memory/i, /in memory first/i, /old-shape/i, /older (value )?shapes?/i];

function readRepoText(relativePath: string): string {
  return readFileSync(join(REPO_ROOT, relativePath), "utf8");
}

function hasCodeExtension(filePath: string): boolean {
  return CODE_EXTENSIONS.some(function endsWithExtension(extension) {
    return filePath.endsWith(extension);
  });
}

// Every code file under a path, repo-relative; node_modules left out.
function collectFiles(absolutePath: string, found: string[]) {
  const stats = statSync(absolutePath, { throwIfNoEntry: false });
  if (stats === undefined) {
    return;
  }
  if (stats.isFile()) {
    if (hasCodeExtension(absolutePath)) {
      found.push(relative(REPO_ROOT, absolutePath));
    }
    return;
  }
  for (const entryName of readdirSync(absolutePath)) {
    if (entryName === "node_modules") {
      continue;
    }
    collectFiles(join(absolutePath, entryName), found);
  }
}

function filesUnder(paths: string[]): string[] {
  const found: string[] = [];
  for (const scannedPath of paths) {
    collectFiles(join(REPO_ROOT, scannedPath), found);
  }
  return found;
}

function upgradeWordingIn(text: string): string[] {
  const hits: string[] = [];
  for (const pattern of UPGRADE_WORDING) {
    if (pattern.test(text)) {
      hits.push(String(pattern));
    }
  }
  return hits;
}

function escapedForRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// The retired scripts a text actually loads or copies: a static import or export from, a dynamic
// import, a require, or a path built with join(..., "<name>.mjs") (how a copy or import reaches it).
function retiredScriptUses(text: string): string[] {
  const used: string[] = [];
  for (const scriptName of RETIRED_SCRIPTS) {
    const name = escapedForRegExp(scriptName.replace(".mjs", ""));
    const usePatterns = [
      new RegExp(`from\\s*["'\`][^"'\`]*${name}`),
      new RegExp(`import\\(\\s*[^)]*${name}`),
      new RegExp(`require\\(\\s*[^)]*${name}`),
      new RegExp(`join\\([^)]*["'\`]${name}\\.mjs["'\`]`),
    ];
    const isUsed = usePatterns.some(function patternMatches(pattern) {
      return pattern.test(text);
    });
    if (isUsed) {
      used.push(scriptName);
    }
  }
  return used;
}

const remindersManifest = JSON.parse(readRepoText("sidekicks/reminders/manifest.json"));

describe("the converter and the migration are out of the codebase", () => {
  it("are no longer in backend/scripts and are kept, marked retired, in docs/legacy/code", () => {
    for (const scriptName of RETIRED_SCRIPTS) {
      expect(existsSync(join(REPO_ROOT, "backend", "scripts", scriptName)), scriptName).toBe(false);
      const header = readRepoText(`${RETIRED_FOLDER}/${scriptName}`).slice(0, 600);
      expect(header, scriptName).toContain("RETIRED 2026-10-20, KEPT FOR HISTORY ONLY: not imported, not run, not tested");
      expect(header, scriptName).toContain("docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md");
    }
  });

  it("are named by no code or test that runs, and used by none (the scan sees the runner, the planner and the tests)", () => {
    const files = filesUnder(RUNNING_CODE_PATHS);
    expect(files).toContain("runner/lib/user-records.mjs");
    expect(files).toContain("backend/scripts/user-copy-plan.mjs");
    expect(files).toContain("backend/test/helpers/runner-fixture.ts");
    expect(files).toContain(THIS_FILE);
    expect(files).toContain("backend/test/legacy-sweep-2-docs.test.ts");
    const hits: string[] = [];
    for (const filePath of files) {
      const text = readRepoText(filePath);
      // A name-hunting guard test may hold the names as markers; it still may not use the scripts.
      if (NAME_HUNTING_GUARD_TESTS.includes(filePath)) {
        for (const scriptName of retiredScriptUses(text)) {
          hits.push(`${filePath}: uses ${scriptName}`);
        }
        continue;
      }
      for (const scriptName of RETIRED_SCRIPTS) {
        const baseName = scriptName.replace(".mjs", "");
        if (text.includes(baseName)) {
          hits.push(`${filePath}: ${baseName}`);
        }
      }
    }
    expect(hits).toEqual([]);
  });

  it("the use check sees an import, a dynamic import, a require and a join of either script, and not a hunted marker (the scan can fail)", () => {
    // Samples are built from RETIRED_SCRIPTS so this file never holds a literal use.
    const [upgradesName, migrationName] = RETIRED_SCRIPTS;
    expect(retiredScriptUses(`import { planMigration } from "../scripts/${migrationName}";`)).toEqual([migrationName]);
    expect(retiredScriptUses(`const upgrades = await import("../../backend/scripts/${upgradesName}");`)).toEqual([upgradesName]);
    expect(retiredScriptUses(`const migration = require("./${migrationName}");`)).toEqual([migrationName]);
    expect(retiredScriptUses(`cpSync(join(REPO_ROOT, "backend", "scripts", "${upgradesName}"), target);`)).toEqual([upgradesName]);
    expect(retiredScriptUses(`{ pattern: /${migrationName.replace(".", "\\.")}/, oldText: "\`node scripts/${migrationName} --env live --dry-run\`" }`)).toEqual([]);
  });

  it("leave no upgrade-on-read wording in the backend, runner or scripts code (the scan can fail)", () => {
    expect(upgradeWordingIn("// Upgrade on read: a record not yet converted")).toHaveLength(1);
    expect(upgradeWordingIn("records are upgraded in memory before the check")).toHaveLength(1);
    expect(upgradeWordingIn("(2 old-shape changes applied in memory only)")).toHaveLength(1);
    const hits: string[] = [];
    for (const filePath of filesUnder(SWEPT_CODE_PATHS)) {
      for (const hit of upgradeWordingIn(readRepoText(filePath))) {
        hits.push(`${filePath}: ${hit}`);
      }
    }
    expect(hits).toEqual([]);
  });
});

describe("the runner checks the reporter's records exactly as stored", () => {
  it("passes a current record and reports only how many it checked", () => {
    const records = [{ key: "reminder:1", value: { $type: "reminders.item", title: "Call mom", at: "2026-10-20T09:00:00.000Z" } }];
    const result = checkUserRecords({ sidekickId: "reminders", records, manifest: remindersManifest });
    expect(result).toEqual({ checked: 1, failures: [] });
  });

  it("changes nothing before the check: a record without its $type fails under its own key", () => {
    const records = [{ key: "reminder:8", value: { title: "Dated", at: "2026-10-20T09:00:00.000Z" } }];
    const result = checkUserRecords({ sidekickId: "reminders", records, manifest: remindersManifest });
    expect(result).toEqual({ checked: 1, failures: [{ key: "reminder:8", problem: 'reminders.item.$type must be "reminders.item"' }] });
    expect(recordFailureDetail(result.failures)).toBe('1 of the user\'s records do not fit the new schema: reminder:8: reminders.item.$type must be "reminders.item"');
  });

  it("loads only the validator from the checkout, and refuses a checkout without one", async () => {
    const checkout = mkdtempSync(join(tmpdir(), "midas-retired-check-"));
    mkdirSync(join(checkout, "shell", "sdk"), { recursive: true });
    cpSync(join(REPO_ROOT, "shell", "sdk", "record-schema.js"), join(checkout, "shell", "sdk", "record-schema.js"));
    const modules = await loadDataModules(checkout);
    expect(Object.keys(modules)).toEqual(["MidasRecordSchema"]);
    expect(typeof modules.MidasRecordSchema.checkRecord).toBe("function");
    const emptyCheckout = mkdtempSync(join(tmpdir(), "midas-retired-empty-"));
    await expect(loadDataModules(emptyCheckout)).rejects.toThrow(`the checkout ${emptyCheckout} has no ${join("shell", "sdk", "record-schema.js")}`);
  });

  it("says in the summary how many records were checked and nothing more", () => {
    const summary = buildSummary({
      job: { id: "rep-1", sidekickId: "reminders", userId: "user-1", kind: "bug", transcript: "t" },
      jobFolder: "/job",
      outcome: { result: "no_change", summary: "Nothing to change." },
      diff: "",
      checkOutput: "",
      logFolder: "/log",
      recordsCheck: { checked: 2, failures: [] },
    });
    const lines = summary.split("\n");
    expect(lines).toContain("- User's records: 2 checked against the new schema, all fit");
  });
});

describe("the copies planner flags writes a copy's types do not declare", () => {
  const baseHtml = readRepoText("sidekicks/reminders/index.html");
  const baseManifestText = readRepoText("sidekicks/reminders/manifest.json");
  const baseHash = bundleContentHash(baseHtml, baseManifestText);
  const base = { pointer: { version: "base-2", contentHash: baseHash }, manifest: remindersManifest };

  it("sees literal writes of an undeclared prefix, not reads, and none in today's base", () => {
    expect(undeclaredWrites("store.query('tag:'); store.get('tag:1')", remindersManifest)).toEqual([]);
    expect(undeclaredWrites("store.set('tag:' + id, v); store.update(`note:${id}`, p)", remindersManifest)).toEqual(["writes note: records its types do not declare", "writes tag: records its types do not declare"]);
    expect(undeclaredWrites(baseHtml, remindersManifest)).toEqual([]);
  });

  it("lists a repaired copy that writes one for its repair to be carried over, and publishes nothing", () => {
    const repairedPage = `${baseHtml}<script>store.set('tag:' + id, item)</script>`;
    const plan = planUserCopy({
      sidekickId: "reminders",
      envName: "live",
      copy: { userId: "user-1", pointer: { version: "u-1", baseVersion: "base-1", contentHash: "repaired" }, html: repairedPage, manifestText: baseManifestText },
      base,
      baseContentHashes: { "base-2": baseHash, "base-1": "hash-of-base-1" },
      helperText: currentStoreHelper(),
    });
    expect(plan.state).toBe("repaired");
    expect(plan.gaps).toEqual(["writes tag: records its types do not declare"]);
    expect(plan.upgraded).toBeNull();
    expect(plan.actions[0]).toMatch(/^needs its repair carried onto today's base by hand/);
    expect(plan.actions[1]).toBe("way back, losing the repair: node scripts/deploy-sidekick.mjs reminders --env live --user user-1 --from-base");
  });
});
