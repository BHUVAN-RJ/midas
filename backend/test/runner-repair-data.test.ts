// The repair runner on the unified data rules (founder, 2026-10-19; docs/briefs/repair-data-2026-10-19.md;
// CONCERNS 8; unified data plan section 6): the copy's schema may only grow (founder, 2026-10-15:
// add only), every literal record write is declared, every record the reporter has must pass the
// new schema (older shapes upgraded in memory first), each Sidekick gets its own prompt on the
// current shapes, and a copy's older store helper is replaced so its own tests pass on today's SDK.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { buildSystemPrompt, templateNameForSidekick, typesText } from "../../runner/lib/prompt.mjs";
import { SCHEMA_REFUSAL_REASON, breakingChangeVerdict, literalWritePrefixes, schemaChangeProblems, undeclaredWritePrefixes } from "../../runner/lib/schema-change.mjs";
import { checkUserRecords, recordFailureDetail } from "../../runner/lib/user-records.mjs";
import { currentStoreHelper, findStoreHelper, refreshStoreHelper } from "../scripts/store-helper.mjs";

const repoRoot = new URL("../../", import.meta.url);

function readRepoText(relativePath: string): string {
  return readFileSync(new URL(relativePath, repoRoot), "utf8");
}

function manifestOf(sidekickId: string) {
  return JSON.parse(readRepoText(`sidekicks/${sidekickId}/manifest.json`));
}

// A deep copy, so each case edits its own.
function typesOf(sidekickId: string) {
  return JSON.parse(JSON.stringify(manifestOf(sidekickId).types));
}

describe("schema changes a repair may make (add only)", () => {
  it("finds nothing when the types are unchanged, for both Sidekicks", () => {
    expect(schemaChangeProblems(typesOf("reminders"), typesOf("reminders"))).toEqual([]);
    expect(schemaChangeProblems(typesOf("care-reminders"), typesOf("care-reminders"))).toEqual([]);
  });

  it("allows a new optional field, a new type, a wider limit, a grown enum and a dropped required", () => {
    const before = typesOf("reminders");
    const after = typesOf("reminders");
    after["reminder:"].schema.properties.priority = { type: "string", enum: ["low", "high"] };
    after["tag:"] = { $type: "reminders.tag", schema: { type: "object", required: ["name"], properties: { $type: { type: "string" }, name: { type: "string", maxLength: 80 } } } };
    after["reminder:"].schema.properties.notes.maxLength = 40000;
    after["reminder:"].schema.$defs.repeat.properties.every.enum.push("hour");
    after["list:"].schema.required = [];
    after["reminder:"].schema.properties.title.description = "What the reminder says";
    expect(schemaChangeProblems(before, after)).toEqual([]);
  });

  it("refuses a removed or renamed field", () => {
    const after = typesOf("reminders");
    after["reminder:"].schema.properties.memo = after["reminder:"].schema.properties.notes;
    delete after["reminder:"].schema.properties.notes;
    const problems = schemaChangeProblems(typesOf("reminders"), after);
    expect(problems).toEqual(["reminders.item.notes was removed (a rename is a remove; add a new field instead)"]);
  });

  it("refuses a changed type, format or pattern", () => {
    const after = typesOf("reminders");
    after["reminder:"].schema.properties.done = { type: "string" };
    after["list:"].schema.properties.createdAt = { type: "string", format: "date" };
    after["reminder:"].schema.properties.image.pattern = "^file:[a-z]{1,8}$";
    const problems = schemaChangeProblems(typesOf("reminders"), after);
    expect(problems).toContain("reminders.item.done changed its type");
    expect(problems).toContain("reminders.list.createdAt changed its format");
    expect(problems).toContain("reminders.item.image changed its pattern");
    expect(problems).toHaveLength(3);
  });

  it("refuses a new required field, even one added in the same change", () => {
    const after = typesOf("reminders");
    after["reminder:"].schema.properties.priority = { type: "string" };
    after["reminder:"].schema.required = ["title", "priority"];
    expect(schemaChangeProblems(typesOf("reminders"), after)).toEqual(["reminders.item.priority became required (new fields must be optional)"]);
  });

  it("refuses a tightened limit, a new limit, a shrunk enum, uniqueItems and closed objects", () => {
    const after = typesOf("care-reminders");
    after["reminder:"].schema.properties.title.maxLength = 100;
    after["list:"].schema.properties.color.minLength = 3;
    after["reminder:"].schema.properties.everyHours.enum = [2, 3];
    after["list:"].schema.properties.alerts.uniqueItems = true;
    after["list:"].schema.additionalProperties = false;
    const problems = schemaChangeProblems(typesOf("care-reminders"), after);
    expect(problems).toContain("care.item.title maxLength went from 1000 to 100");
    expect(problems).toContain("care.list.color gained minLength 3");
    expect(problems).toContain("care.item.everyHours no longer allows 4");
    expect(problems).toContain("care.list.alerts now requires unique items");
    expect(problems).toContain("care.list.additionalProperties was added, so values that passed before may not");
    expect(problems).toHaveLength(5);
  });

  it("refuses a removed type, a changed $type and a changed shared definition", () => {
    const after = typesOf("reminders");
    delete after["history:"];
    after["list:"].$type = "reminders.folder";
    after["reminder:"].schema.$defs.instant.format = "date";
    const problems = schemaChangeProblems(typesOf("reminders"), after);
    expect(problems).toContain('types["history:"] was removed');
    expect(problems).toContain('types["list:"].$type changed from "reminders.list" to "reminders.folder"');
    expect(problems).toContain("reminders.item.$defs.instant changed its format");
  });

  it("treats a manifest that loses its whole types block as removing every type", () => {
    const problems = schemaChangeProblems(typesOf("reminders"), undefined);
    expect(problems).toHaveLength(Object.keys(typesOf("reminders")).length);
  });

  it("decides in one place: no problems publishes, any problem is refused with every problem named", () => {
    expect(breakingChangeVerdict({ problems: [] })).toBeNull();
    const refusal = breakingChangeVerdict({ problems: ["a was removed", "b changed its type"] });
    expect(refusal).toEqual({ reason: SCHEMA_REFUSAL_REASON, detail: "a was removed; b changed its type" });
    expect(SCHEMA_REFUSAL_REASON).toBe("schema not backward compatible");
  });
});

describe("every record type the page writes is declared", () => {
  it("both base pages declare every prefix they write with a literal key", () => {
    for (const sidekickId of ["reminders", "care-reminders"]) {
      const html = readRepoText(`sidekicks/${sidekickId}/index.html`);
      expect(literalWritePrefixes(html).length).toBeGreaterThan(0);
      expect(undeclaredWritePrefixes(html, manifestOf(sidekickId).types)).toEqual([]);
    }
  });

  it("names a new prefix written without a type; reads of retired prefixes and shell prefixes are fine", () => {
    const html = "store.set('tag:' + id, value); store.update(`note:${id}`, patch); store.query('task:'); store.set('request:x', v); store.set('reminder:' + id, v)";
    expect(undeclaredWritePrefixes(html, manifestOf("reminders").types)).toEqual(["note:", "tag:"]);
  });
});

describe("the reporter's records against the new schema", () => {
  const remindersManifest = manifestOf("reminders");

  it("passes today's records and skips shell-owned ones", () => {
    const records = [
      { key: "reminder:1", value: { $type: "reminders.item", title: "Call mom", at: "2026-10-20T09:00:00.000Z" } },
      { key: "list:home", value: { $type: "reminders.list", name: "Home" } },
      { key: "widget:main", value: { anything: true } },
    ];
    const result = checkUserRecords({ sidekickId: "reminders", records, manifest: remindersManifest });
    expect(result.failures).toEqual([]);
    expect(result.checked).toBe(2);
  });

  it("upgrades older shapes in memory first (task:, body, epoch ms, no $type) and then they pass", () => {
    const records = [
      { key: "task:7", value: { title: "Undated", body: "old notes", createdAt: 1760000000000 } },
      { key: "reminder:8", value: { title: "Dated", at: 1760000000000 } },
      { key: "settings:sidebar", value: { order: ["home"] } },
    ];
    const result = checkUserRecords({ sidekickId: "reminders", records, manifest: remindersManifest });
    expect(result.failures).toEqual([]);
    expect(result.upgraded).toBeGreaterThan(0);
  });

  it("fails a record that does not fit, naming its key, and a record of a prefix the copy no longer declares", () => {
    const records = [
      { key: "reminder:1", value: { $type: "reminders.item", title: "" } },
      { key: "mood:1", value: { $type: "reminders.mood", level: 3 } },
    ];
    const result = checkUserRecords({ sidekickId: "reminders", records, manifest: remindersManifest });
    const failedKeys = result.failures.map(function keyOfFailure(failure: { key: string }) {
      return failure.key;
    });
    expect(failedKeys.sort()).toEqual(["mood:1", "reminder:1"]);
    const detail = recordFailureDetail(result.failures);
    expect(detail).toMatch(/^2 of the user's records do not fit the new schema: /);
    expect(detail).toContain("reminder:1: ");
  });

  it("names at most three records in the detail and counts the rest", () => {
    const failures = [1, 2, 3, 4, 5].map(function makeFailure(number: number) {
      return { key: `reminder:${number}`, problem: "bad" };
    });
    const detail = recordFailureDetail(failures);
    expect(detail).toContain("reminder:3: bad");
    expect(detail).not.toContain("reminder:4");
    expect(detail).toMatch(/and 2 more$/);
  });

  it("checks care-reminders records with the care rules (folded alert records upgrade, a missing at fails)", () => {
    const careManifest = manifestOf("care-reminders");
    const good = checkUserRecords({
      sidekickId: "care-reminders",
      records: [{ key: "reminder:a", value: { $type: "care.item", title: "Dentist", at: "2026-10-21T15:00:00.000Z", list: "appointments" } }],
      manifest: careManifest,
    });
    expect(good.failures).toEqual([]);
    const bad = checkUserRecords({
      sidekickId: "care-reminders",
      records: [{ key: "reminder:b", value: { $type: "care.item", title: "No time" } }],
      manifest: careManifest,
    });
    expect(bad.failures.length).toBe(1);
    expect(bad.failures[0].key).toBe("reminder:b");
  });
});

describe("one prompt per Sidekick, on today's shapes", () => {
  const job = { id: "rep-9", sidekickId: "reminders", kind: "feature", transcript: "let me add a photo", createdAt: "2026-10-19T10:00:00.000Z" };

  function promptFor(sidekickId: string): string {
    const manifestText = readRepoText(`sidekicks/${sidekickId}/manifest.json`);
    return buildSystemPrompt({ job: { ...job, sidekickId }, reportFiles: ["transcript.txt"], manifestText });
  }

  it("picks care-reminders' own template", () => {
    expect(templateNameForSidekick("care-reminders")).toBe("care-reminders");
    expect(promptFor("care-reminders")).toContain("You repair one user's copy of the care-reminders Sidekick");
    expect(promptFor("reminders")).toContain("You repair one user's copy of the Reminders Sidekick");
  });

  it("says files are supported, names store.update, and says the runner publishes live", () => {
    for (const sidekickId of ["reminders", "care-reminders"]) {
      const prompt = promptFor(sidekickId);
      expect(prompt).toContain("store.putFile");
      expect(prompt).toContain("store.fileUrl");
      expect(prompt).toContain("store.update");
      expect(prompt).toContain("20 MB");
      expect(prompt).toContain("publishes");
      expect(prompt).not.toMatch(/there is no file store/);
      expect(prompt).not.toMatch(/the founder reads your summary and the diff and deploys/);
      expect(prompt).not.toMatch(/\{\{[A-Z_0-9]+\}\}/);
    }
  });

  it("no longer describes task: or body as current shapes, and says to declare new fields in manifest.json", () => {
    const prompt = promptFor("reminders");
    expect(prompt).not.toContain("`task:<id>`: an item without a date");
    expect(prompt).not.toContain("optional `body`");
    expect(prompt).not.toContain("`settings:sidebar`: the user's list order");
    expect(prompt).not.toContain("task:");
    expect(prompt).toContain("Every item, dated or not, is a `reminder:` record");
    expect(prompt).toContain("`settings:self`");
    expect(prompt).toContain("**Add only.**");
    expect(prompt).toContain("manifest.json");
  });

  it("shows the copy's own types, not the base's", () => {
    const copyManifest = manifestOf("reminders");
    copyManifest.types["reminder:"].schema.properties.priorityOnlyInThisCopy = { type: "string" };
    const prompt = buildSystemPrompt({ job, reportFiles: ["transcript.txt"], manifestText: JSON.stringify(copyManifest) });
    expect(prompt).toContain("priorityOnlyInThisCopy");
    expect(typesText(JSON.stringify({ id: "reminders" }))).toBe("(this copy's manifest.json has no types block)");
  });
});

describe("a copy's older store helper is replaced with today's", () => {
  const helper = currentStoreHelper();
  // The first store helper (d8c91ef, 2026-10-09), as old copies hold it: set, get, delete, query.
  const oldHelper = [
    "// Midas local store for Sidekicks. Paste this into the Sidekick bundle's inline script (its",
    "// hash goes into the deploy like any other script).",
    "var store = (function createMidasStore() {",
    "  var storeURL = window.location.origin + '/_midas/store';",
    "  async function setRecord(key, value) {}",
    "  return { set: setRecord, get: getRecord, delete: deleteRecord, query: queryRecords };",
    "})();",
  ].join("\n");
  const page = `<html><script>\n${oldHelper}\n\nasync function start() { await store.set('reminder:1', {}); }\n})();\n</script></html>`;

  it("finds the old helper and replaces exactly it, keeping the page's own code", () => {
    expect(findStoreHelper(page)).not.toBeNull();
    const refreshed = refreshStoreHelper(page, helper);
    expect(refreshed.status).toBe("refreshed");
    expect(refreshed.html).toContain(helper);
    expect(refreshed.html).not.toContain("return { set: setRecord, get: getRecord, delete: deleteRecord, query: queryRecords };");
    expect(refreshed.html).toContain("async function start() { await store.set('reminder:1', {}); }");
    expect(refreshed.html.startsWith("<html><script>\n// Midas local store")).toBe(true);
  });

  it("leaves a page with today's helper alone, and a page without a helper unchanged", () => {
    const basePage = readRepoText("sidekicks/reminders/index.html");
    expect(refreshStoreHelper(basePage, helper)).toEqual({ html: basePage, status: "current" });
    const noHelper = "<html><script>var x = 1;</script></html>";
    expect(refreshStoreHelper(noHelper, helper)).toEqual({ html: noHelper, status: "missing" });
  });
});
