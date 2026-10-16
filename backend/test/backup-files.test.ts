import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { FILE_ROWS_SQL, backupFiles, fileIdsInValue, fileReferences } from "../scripts/backup-files.mjs";
import { ENVIRONMENTS } from "../scripts/environments.mjs";

// The database backup also copies every user file the records refer to (unified data plan,
// section 7: "backup-db.mjs gains an R2 files copy"). Nothing is deleted anywhere.

describe("file references in records", () => {
  it("finds every file:<id> string, however deep, and nothing else", () => {
    const value = { image: "file:abc123", notes: "see file:not-a-ref inside text", items: [{ attachment: "file:x_Y-9" }, "file:zzz"], nested: { deep: { ref: "file:abc123" } }, number: 5 };
    expect(fileIdsInValue(value)).toEqual(["abc123", "x_Y-9", "zzz", "abc123"]);
    expect(fileIdsInValue("file:solo")).toEqual(["solo"]);
    expect(fileIdsInValue({ bad: "file:has space", worse: "file:" })).toEqual([]);
  });

  it("lists each user's referenced files once, in a stable order, skipping rows it cannot read", () => {
    const rows = [
      { user_id: "u-rj", value: JSON.stringify({ image: "file:b" }) },
      { user_id: "u-rj", value: JSON.stringify({ image: "file:a", again: "file:b" }) },
      { user_id: "u-amogh", value: JSON.stringify(["file:a"]) },
      { user_id: "u-rj", value: "not json" },
      { user_id: "../bad", value: JSON.stringify({ image: "file:c" }) },
      { user_id: "u-rj", value: null },
    ];
    expect(fileReferences(rows)).toEqual([
      { userId: "u-amogh", fileId: "a" },
      { userId: "u-rj", fileId: "a" },
      { userId: "u-rj", fileId: "b" },
    ]);
  });

  it("reads live records only and never deletes", () => {
    expect(FILE_ROWS_SQL).toContain("deleted = 0");
    expect(FILE_ROWS_SQL.toUpperCase()).not.toContain("DELETE FROM");
  });
});

describe("backupFiles", () => {
  let directory: string;

  afterEach(() => {
    rmSync(directory, { recursive: true, force: true });
  });

  it("fetches each referenced file once into files/<env>/<user>/<id> and skips what is already there", () => {
    directory = mkdtempSync(join(tmpdir(), "files-backup-"));
    const rows = [
      { user_id: "u-rj", value: JSON.stringify({ image: "file:shot1" }) },
      { user_id: "u-rj", value: JSON.stringify({ image: "file:shot2" }) },
      { user_id: "u-amogh", value: JSON.stringify({ image: "file:shot1" }) },
    ];
    const captured: string[][] = [];
    const ran: string[][] = [];
    function capture(args: string[]) {
      captured.push(args);
      return JSON.stringify([{ results: rows }]);
    }
    function run(args: string[]) {
      ran.push(args);
      // wrangler writes the object to --file; stand in for it.
      const filePath = args[args.indexOf("--file") + 1];
      writeFileSync(filePath, "bytes");
    }
    mkdirSync(join(directory, "u-rj"), { recursive: true });
    writeFileSync(join(directory, "u-rj", "shot1"), "already here");

    const fetched = backupFiles(ENVIRONMENTS.staging, { capture, run, directory });

    expect(captured).toHaveLength(1);
    expect(captured[0].slice(0, 3)).toEqual(["d1", "execute", "midas-staging"]);
    expect(captured[0]).toContain(FILE_ROWS_SQL);
    expect(captured[0]).toContain("--env");
    expect(fetched).toEqual([{ userId: "u-amogh", fileId: "shot1" }, { userId: "u-rj", fileId: "shot2" }]);
    expect(ran.map((args) => args[3])).toEqual(["midas-files-staging/u-amogh/shot1", "midas-files-staging/u-rj/shot2"]);
    for (const args of ran) {
      expect(args.slice(0, 3)).toEqual(["r2", "object", "get"]);
      expect(args).toContain("--remote");
      expect(args).not.toContain("delete");
    }
    expect(readFileSync(join(directory, "u-rj", "shot1"), "utf8")).toBe("already here");
    expect(existsSync(join(directory, "u-amogh", "shot1"))).toBe(true);
    expect(ENVIRONMENTS.live.filesBucket).toBe("midas-files");
  });
});
