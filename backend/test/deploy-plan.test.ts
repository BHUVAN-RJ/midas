import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  USER_ID_PATTERN,
  bundleContentHash,
  checkBundleFiles,
  planDeploy,
  pointerKeyFor,
  sortUserCopies,
  storePrefix,
} from "../scripts/bundle-tools.mjs";

// What deploy-sidekick.mjs writes, planned without wrangler (repair, 2026-10-13): a user deploy
// touches only that user's store, a base deploy only the base; versions are never reused.

const HTML = "<!doctype html><title>Reminders</title><script>document.title='ok'</script>";
const MANIFEST = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [] };
const MANIFEST_TEXT = JSON.stringify(MANIFEST);
const AT = new Date("2026-10-13T10:00:00.000Z");

function keysOf(plan: { puts: Array<{ key: string }> }): string[] {
  return plan.puts.map(keyOf);
}

function keyOf(put: { key: string }): string {
  return put.key;
}

describe("planDeploy for one user's copy", () => {
  const plan = planDeploy({ sidekickId: "reminders", userId: "u-amogh", html: HTML, manifestText: MANIFEST_TEXT, deployedAt: AT, baseVersion: "b2" });

  it("writes the version's files first and the user's pointer last, all under the user's store", () => {
    const keys = keysOf(plan);
    expect(keys).toEqual([
      `sidekicks/reminders/users/u-amogh/${plan.version}/index.html`,
      `sidekicks/reminders/users/u-amogh/${plan.version}/manifest.json`,
      `sidekicks/reminders/users/u-amogh/${plan.version}/version.json`,
      "sidekicks/reminders/users/u-amogh/current.json",
    ]);
  });

  it("never writes the base pointer or any base version", () => {
    for (const key of keysOf(plan)) {
      expect(key.startsWith("sidekicks/reminders/users/u-amogh/")).toBe(true);
    }
    expect(keysOf(plan)).not.toContain("sidekicks/reminders/current.json");
  });

  it("records the base it builds on and the content hash, so a base deploy can tell it was repaired", () => {
    expect(plan.pointer).toEqual({
      version: plan.version,
      scriptHashes: plan.scriptHashes,
      contentHash: bundleContentHash(HTML, MANIFEST_TEXT),
      baseVersion: "b2",
    });
    const versionRecord = JSON.parse(plan.puts[2].body);
    expect(versionRecord.forUser).toBe("u-amogh");
    expect(versionRecord.baseVersion).toBe("b2");
    expect(versionRecord.deployedAt).toBe("2026-10-13T10:00:00.000Z");
  });

  it("refuses a user id that could leave the user's store", () => {
    function planWithBadId() {
      return planDeploy({ sidekickId: "reminders", userId: "../x", html: HTML, manifestText: MANIFEST_TEXT, deployedAt: AT });
    }
    expect(planWithBadId).toThrow(/bad user id/);
    expect(USER_ID_PATTERN.test("u/amogh")).toBe(false);
    expect(USER_ID_PATTERN.test("Zk9_-abc")).toBe(true);
    expect(pointerKeyFor("reminders", "u-amogh")).toBe("sidekicks/reminders/users/u-amogh/current.json");
    expect(pointerKeyFor("reminders")).toBe("sidekicks/reminders/current.json");
    expect(storePrefix("reminders")).toBe("sidekicks/reminders");
  });
});

describe("planDeploy for the base", () => {
  it("writes only under the base, never under users/", () => {
    const plan = planDeploy({ sidekickId: "reminders", html: HTML, manifestText: MANIFEST_TEXT, deployedAt: AT });
    for (const key of keysOf(plan)) {
      expect(key.startsWith(`sidekicks/reminders/`)).toBe(true);
      expect(key.includes("/users/")).toBe(false);
    }
    expect(keysOf(plan).at(-1)).toBe("sidekicks/reminders/current.json");
    expect(plan.pointer.baseVersion).toBeNull();
    expect(JSON.parse(plan.puts[2].body).forUser).toBeNull();
  });
});

describe("versions are immutable", () => {
  it("names a new version for every deploy, even of the same content", () => {
    const first = planDeploy({ sidekickId: "reminders", html: HTML, manifestText: MANIFEST_TEXT, deployedAt: AT });
    const later = new Date(AT.getTime() + 1);
    const second = planDeploy({ sidekickId: "reminders", html: HTML, manifestText: MANIFEST_TEXT, deployedAt: later });
    expect(second.version).not.toBe(first.version);
    const firstVersionKeys = keysOf(first).slice(0, 3);
    for (const key of keysOf(second).slice(0, 3)) {
      expect(firstVersionKeys).not.toContain(key);
    }
  });

  it("refuses to write into a version that already exists", () => {
    const first = planDeploy({ sidekickId: "reminders", html: HTML, manifestText: MANIFEST_TEXT, deployedAt: AT });
    function planAgain() {
      return planDeploy({ sidekickId: "reminders", html: HTML, manifestText: MANIFEST_TEXT, deployedAt: AT, existingVersions: [first.version] });
    }
    expect(planAgain).toThrow(/immutable/);
  });

  it("a copy of a base version keeps that version's name in the user's store", () => {
    const plan = planDeploy({ sidekickId: "reminders", userId: "u-priya", html: HTML, manifestText: MANIFEST_TEXT, deployedAt: AT, baseVersion: "b3", version: "b3" });
    expect(plan.version).toBe("b3");
    expect(keysOf(plan)[0]).toBe("sidekicks/reminders/users/u-priya/b3/index.html");
    expect(plan.pointer.baseVersion).toBe("b3");
  });
});

describe("a base deploy and the user copies", () => {
  const baseContentHashes = { b1: "hash-b1", b2: "hash-b2" };

  it("updates an untouched copy, leaves a repaired one and lists it", () => {
    const sorted = sortUserCopies(
      [
        { userId: "u-priya", pointer: { version: "b2", scriptHashes: [], contentHash: "hash-b2", baseVersion: "b2" } },
        { userId: "u-amogh", pointer: { version: "a9", scriptHashes: [], contentHash: "hash-a9", baseVersion: "b2" } },
        { userId: "u-old", pointer: { version: "b1", scriptHashes: [], contentHash: "hash-b1", baseVersion: "b1" } },
      ],
      baseContentHashes,
    );
    expect(sorted.untouched).toEqual([
      { userId: "u-priya", version: "b2", baseVersion: "b2" },
      { userId: "u-old", version: "b1", baseVersion: "b1" },
    ]);
    expect(sorted.left).toEqual([{ userId: "u-amogh", version: "a9", reason: "repaired on base b2" }]);
  });

  it("leaves a copy whose origin cannot be checked", () => {
    const sorted = sortUserCopies(
      [
        { userId: "u-nobase", pointer: { version: "x1", scriptHashes: [], contentHash: "hash-x1" } },
        { userId: "u-unknownbase", pointer: { version: "b7", scriptHashes: [], contentHash: "hash-b7", baseVersion: "b7" } },
      ],
      baseContentHashes,
    );
    expect(sorted.untouched).toEqual([]);
    expect(sorted.left).toHaveLength(2);
    expect(sorted.left[0].reason).toBe("origin unknown");
  });
});

describe("checkBundleFiles (--dir)", () => {
  it("accepts a bundle read from any directory and refuses one that fails the gate", () => {
    const directory = mkdtempSync(join(tmpdir(), "job-"));
    writeFileSync(join(directory, "index.html"), HTML);
    writeFileSync(join(directory, "manifest.json"), MANIFEST_TEXT);
    expect(checkBundleFiles(HTML, MANIFEST_TEXT, "reminders").problems).toEqual([]);
    expect(checkBundleFiles(`${HTML}<script src="x.js"></script>`, MANIFEST_TEXT, "reminders").problems[0]).toMatch(/deploy gate rejected/);
    expect(checkBundleFiles(HTML, MANIFEST_TEXT, "calendar").problems[0]).toMatch(/id must be "calendar"/);
    expect(checkBundleFiles(HTML, "{not json", "reminders").problems).toEqual(["manifest.json is not JSON"]);
  });
});
