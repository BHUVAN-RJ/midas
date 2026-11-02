import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  deletionRequest,
  exportFileNames,
  mentionsUserId,
  parseDeletionArgs,
  removeUserFromBackups,
  runDeletionCommand,
  splitSqlStatements,
  withoutUserRows,
} from "../scripts/delete-account.mjs";
import { ENVIRONMENTS } from "../scripts/environments.mjs";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import {
  claimAfterForgetting,
  claudeProjectFolderName,
  forgetDeletedAccounts,
  forgetJobs,
  isReportId,
  jobPaths,
} from "../../runner/lib/forget.mjs";

// The founder's tool (backend/scripts/delete-account.mjs) and the Mac mini clean-up
// (runner/lib/forget.mjs) for account deletion (founder, 2026-11-02;
// docs/briefs/account-deletion-2026-11-02.md): only the person's rows leave the backups, only
// the person's job folders leave the Mac mini.

const PERSON = "ab_c";
const JOB_A = "11111111-2222-4333-8444-555555555555";
const JOB_B = "66666666-7777-4888-9999-aaaaaaaaaaaa";
const SESSION_A = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
const SESSION_B = "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff";

function temporaryFolder(label: string): string {
  return mkdtempSync(join(tmpdir(), `midas-${label}-`));
}

const EXPORT = [
  "PRAGMA defer_foreign_keys=TRUE;",
  'CREATE TABLE IF NOT EXISTS "users" (id TEXT PRIMARY KEY, name TEXT NOT NULL);',
  // Schema is never dropped, even when it happens to hold the id
  "CREATE TABLE IF NOT EXISTS \"notes\" (who TEXT DEFAULT 'ab_c');",
  'INSERT INTO "users" ("id","name") VALUES(\'ab_c\',\'Priya\');',
  'INSERT INTO "users" ("id","name") VALUES(\'ab_cd\',\'Lena\');',
  'INSERT INTO "users" ("id","name") VALUES(\'abXc\',\'Sam; not ab_c\'\'s\');',
  'INSERT INTO "ops" ("seq","user_id","key","value") VALUES(7,\'u-founder\',\'req:ab_c:r1\',\'{"text":"a; b"}\');',
  'INSERT INTO "ops" ("seq","user_id","key","value") VALUES(8,\'u-founder\',\'req:ab_cd:r1\',\'{"text":"line one\nline two"}\');',
  'CREATE TRIGGER ops_are_never_updated BEFORE UPDATE ON ops',
  "BEGIN",
  "  SELECT RAISE(ABORT, 'ops are append only');",
  "END;",
  "",
].join("\n");

function isInsertPiece(piece: string): boolean {
  return piece.startsWith("INSERT");
}

describe("delete-account.mjs: arguments", () => {
  it("needs --env, takes --user with --yes or --check", () => {
    expect(parseDeletionArgs([]).error).toContain("usage");
    expect(parseDeletionArgs(["--env", "staging"])).toEqual({ environment: ENVIRONMENTS.staging, userId: null, mode: "list" });
    expect(parseDeletionArgs(["--env", "live", "--user", PERSON]).mode).toBe("preview");
    expect(parseDeletionArgs(["--env", "live", "--user", PERSON, "--yes"]).mode).toBe("carry-out");
    expect(parseDeletionArgs(["--env", "live", "--user", PERSON, "--check"]).mode).toBe("check");
    expect(parseDeletionArgs(["--env", "live", "--user", PERSON, "--yes", "--check"]).error).toBeDefined();
    expect(parseDeletionArgs(["--env", "live", "--user", "../x"]).error).toBeDefined();
    expect(parseDeletionArgs(["--env", "live", "--user"]).error).toBeDefined();
  });

  it("talks to the environment's Worker with the deletion token", () => {
    const request = deletionRequest(ENVIRONMENTS.live, "tok", "/ab_c/carry-out", "POST");
    expect(request.url).toBe("https://midas-api.midas-backend.workers.dev/account-deletions/ab_c/carry-out");
    expect(request.init).toEqual({ method: "POST", headers: { Authorization: "Deletion tok" } });
    const staging = deletionRequest(ENVIRONMENTS.staging, "tok", "");
    expect(staging.url).toBe("https://midas-api-staging.midas-backend.workers.dev/account-deletions");
  });
});

describe("delete-account.mjs: backups", () => {
  it("finds the id only as a whole value or as the user part of an inbox key", () => {
    expect(mentionsUserId("VALUES('ab_c','Priya')", PERSON)).toBe(true);
    expect(mentionsUserId("VALUES(1,'u-founder','req:ab_c:r1')", PERSON)).toBe(true);
    expect(mentionsUserId("VALUES(1,'u-founder','person:ab_c')", PERSON)).toBe(true);
    expect(mentionsUserId("VALUES(1,'u-founder','account-deleted:ab_c:7')", PERSON)).toBe(true);
    expect(mentionsUserId("VALUES('ab_cd','Lena')", PERSON)).toBe(false);
    expect(mentionsUserId("VALUES('xab_c','Lena')", PERSON)).toBe(false);
    expect(mentionsUserId("VALUES('abXc','Sam')", PERSON)).toBe(false);
    expect(mentionsUserId("VALUES(1,'u-founder','req:ab_cd:r1')", PERSON)).toBe(false);
    expect(mentionsUserId("VALUES('abXc','Sam; not ab_c''s')", PERSON)).toBe(false);
    expect(mentionsUserId("VALUES('abXc','note: ab_c')", PERSON)).toBe(false);
  });

  it("splits an export into statements without losing a byte, ; inside values included", () => {
    const pieces = splitSqlStatements(EXPORT);
    expect(pieces.join("")).toBe(EXPORT);
    const inserts = pieces.filter(isInsertPiece);
    expect(inserts.length).toBe(5);
  });

  it("drops only the rows that mention the person; schema, triggers and others' rows stay byte for byte", () => {
    const scrubbed = withoutUserRows(EXPORT, PERSON);
    expect(scrubbed.removed).toBe(2);
    expect(scrubbed.text).not.toContain("'Priya'");
    expect(scrubbed.text).not.toContain("req:ab_c:r1");
    expect(scrubbed.text).toContain("'Lena'");
    expect(scrubbed.text).toContain("'Sam; not ab_c''s'");
    expect(scrubbed.text).toContain("line one\nline two");
    expect(scrubbed.text).toContain("SELECT RAISE(ABORT, 'ops are append only');\nEND;");
    expect(scrubbed.text).toContain("DEFAULT 'ab_c');");
    const expected = EXPORT.replace("INSERT INTO \"users\" (\"id\",\"name\") VALUES('ab_c','Priya');\n", "").replace(
      'INSERT INTO "ops" ("seq","user_id","key","value") VALUES(7,\'u-founder\',\'req:ab_c:r1\',\'{"text":"a; b"}\');\n',
      "",
    );
    expect(scrubbed.text).toBe(expected);
    expect(withoutUserRows(EXPORT, "nobody-here").text).toBe(EXPORT);
  });

  it("names only the environment's own exports", () => {
    const names = ["live-midas-20261102T062210Z.sql", "staging-midas-staging-20261023T191423Z.sql", "live-midas-notes.txt", "other.sql"];
    expect(exportFileNames(names, ENVIRONMENTS.live)).toEqual(["live-midas-20261102T062210Z.sql"]);
    expect(exportFileNames(names, ENVIRONMENTS.staging)).toEqual(["staging-midas-staging-20261023T191423Z.sql"]);
  });

  it("rewrites the exports that mention them and uploads each over its R2 copy; removes their files folder only", () => {
    const backupDirectory = temporaryFolder("backups");
    const filesDirectory = join(backupDirectory, "files", "live");
    writeFileSync(join(backupDirectory, "live-midas-20261101T000000Z.sql"), EXPORT);
    writeFileSync(join(backupDirectory, "live-midas-20261102T000000Z.sql"), "INSERT INTO \"users\" VALUES('abXc','Sam');\n");
    writeFileSync(join(backupDirectory, "staging-midas-staging-20261101T000000Z.sql"), EXPORT);
    mkdirSync(join(filesDirectory, PERSON), { recursive: true });
    writeFileSync(join(filesDirectory, PERSON, "photo1"), "p");
    mkdirSync(join(filesDirectory, "ab_cd"), { recursive: true });
    writeFileSync(join(filesDirectory, "ab_cd", "photo1"), "p");
    const uploads: string[] = [];
    function recordUpload(environment: { name: string }, fileName: string) {
      uploads.push(`${environment.name}/${fileName}`);
    }
    const lines = removeUserFromBackups(ENVIRONMENTS.live, PERSON, { backupDirectory, filesDirectory, uploadExport: recordUpload });
    expect(uploads).toEqual(["live/live-midas-20261101T000000Z.sql"]);
    expect(readFileSync(join(backupDirectory, "live-midas-20261101T000000Z.sql"), "utf8")).toBe(withoutUserRows(EXPORT, PERSON).text);
    expect(readFileSync(join(backupDirectory, "staging-midas-staging-20261101T000000Z.sql"), "utf8")).toBe(EXPORT);
    expect(existsSync(join(filesDirectory, PERSON))).toBe(false);
    expect(existsSync(join(filesDirectory, "ab_cd", "photo1"))).toBe(true);
    expect(lines.length).toBe(2);
  });
});

describe("delete-account.mjs: the commands", () => {
  type Call = { url: string; init: RequestInit };

  function fakeWorker(status: number, reply: unknown) {
    const calls: Call[] = [];
    async function fetchReply(url: string, init: RequestInit) {
      calls.push({ url, init });
      return new Response(JSON.stringify(reply), { status });
    }
    return { calls, fetchReply };
  }

  it("refuses without the token", async () => {
    const result = await runDeletionCommand(["--env", "live"], { env: {} });
    expect(result.exitCode).toBe(2);
    expect(result.output).toBe("MIDAS_LIVE_DELETION_TOKEN is not set");
  });

  it("the list flags an alert that never arrived", async () => {
    const reply = {
      founderSet: true,
      founderDevices: 1,
      open: [{ userId: PERSON, userName: "Priya", ageDays: 6, dueDate: "Sat 7 Nov", alertDelivered: false, alertResult: "no devices", lastError: null }],
      done: [],
    };
    const worker = fakeWorker(200, reply);
    const result = await runDeletionCommand(["--env", "staging"], { env: { MIDAS_STAGING_DELETION_TOKEN: "t" }, fetch: worker.fetchReply });
    expect(result.exitCode).toBe(0);
    expect(result.output).toContain("OPEN Priya (ab_c): asked 6 days ago, delete by Sat 7 Nov; ALERT NOT DELIVERED (no devices)");
    expect(worker.calls[0].url).toBe("https://midas-api-staging.midas-backend.workers.dev/account-deletions");
  });

  it("--yes posts the carry-out, then cleans this Mac's backups; a stopped run cleans nothing", async () => {
    const cleaned: string[] = [];
    function recordClean(environment: { name: string }, userId: string) {
      cleaned.push(`${environment.name}:${userId}`);
      return ["live-midas-x.sql: 2 rows removed"];
    }
    const done = fakeWorker(200, { deleted: true, counts: { ops: 3, users: 1 }, allZero: true, alertResult: "sent 1 of 1" });
    const result = await runDeletionCommand(["--env", "live", "--user", PERSON, "--yes"], { env: { MIDAS_LIVE_DELETION_TOKEN: "t" }, fetch: done.fetchReply, removeFromBackups: recordClean });
    expect(done.calls[0].url).toBe("https://midas-api.midas-backend.workers.dev/account-deletions/ab_c/carry-out");
    expect(done.calls[0].init.method).toBe("POST");
    expect(result.exitCode).toBe(0);
    expect(result.output).toContain("Check: all zero.");
    expect(result.output).toContain("live-midas-x.sql: 2 rows removed");
    expect(cleaned).toEqual(["live:ab_c"]);

    const stopped = fakeWorker(500, { deleted: false, error: "R2 is down", remaining: { users: 1 } });
    const stoppedResult = await runDeletionCommand(["--env", "live", "--user", PERSON, "--yes"], { env: { MIDAS_LIVE_DELETION_TOKEN: "t" }, fetch: stopped.fetchReply, removeFromBackups: recordClean });
    expect(stoppedResult.exitCode).toBe(1);
    expect(stoppedResult.output).toContain("Not finished: R2 is down");
    expect(cleaned).toEqual(["live:ab_c"]);
  });

  it("without --yes it only reads", async () => {
    const preview = fakeWorker(200, { userId: PERSON, state: "open", counts: { ops: 3 }, total: 3, allZero: false, nonZero: ["ops"], runner: null });
    const result = await runDeletionCommand(["--env", "live", "--user", PERSON], { env: { MIDAS_LIVE_DELETION_TOKEN: "t" }, fetch: preview.fetchReply });
    expect(preview.calls[0].init.method).toBe("GET");
    expect(result.output).toContain("Left: ops");
  });
});

// A runner folder tree with two jobs, a look-alike folder and their Claude sessions.
function runnerTree() {
  const root = temporaryFolder("runner");
  const settings = { jobsRoot: join(root, "jobs"), logsRoot: join(root, "log"), claudeConfigDir: join(root, "claude") };
  for (const jobId of [JOB_A, JOB_B]) {
    mkdirSync(join(settings.jobsRoot, jobId, "report"), { recursive: true });
    writeFileSync(join(settings.jobsRoot, jobId, "report", "transcript.txt"), "words");
    mkdirSync(join(settings.logsRoot, jobId), { recursive: true });
  }
  mkdirSync(`${join(settings.jobsRoot, JOB_A)}.deploy`, { recursive: true });
  mkdirSync(`${join(settings.jobsRoot, JOB_A)}-other`, { recursive: true });
  const projectA = join(settings.claudeConfigDir, "projects", claudeProjectFolderName(join(settings.jobsRoot, JOB_A)));
  const projectB = join(settings.claudeConfigDir, "projects", claudeProjectFolderName(join(settings.jobsRoot, JOB_B)));
  mkdirSync(projectA, { recursive: true });
  mkdirSync(projectB, { recursive: true });
  writeFileSync(join(projectA, `${SESSION_A}.jsonl`), "{}");
  writeFileSync(join(projectB, `${SESSION_B}.jsonl`), "{}");
  for (const sessionId of [SESSION_A, SESSION_B]) {
    mkdirSync(join(settings.claudeConfigDir, "file-history", sessionId), { recursive: true });
    mkdirSync(join(settings.claudeConfigDir, "session-env", sessionId), { recursive: true });
  }
  return { settings, projectA, projectB };
}

describe("runner/lib/forget.mjs: the Mac mini clean-up", () => {
  it("names Claude's project folder the way Claude Code does", () => {
    expect(claudeProjectFolderName("/Users/x/Library/Application Support/midas-runner/jobs/ab-1")).toBe("-Users-x-Library-Application-Support-midas-runner-jobs-ab-1");
  });

  it("removes exactly one job's folders, log, Claude sessions; the other job and a look-alike folder stay", () => {
    const { settings, projectA, projectB } = runnerTree();
    expect(jobPaths(settings, JOB_A).length).toBe(6);
    const outcome = forgetJobs(settings, [JOB_A]);
    expect(outcome).toEqual({ removed: 6, skipped: [] });
    expect(existsSync(join(settings.jobsRoot, JOB_A))).toBe(false);
    expect(existsSync(`${join(settings.jobsRoot, JOB_A)}.deploy`)).toBe(false);
    expect(existsSync(join(settings.logsRoot, JOB_A))).toBe(false);
    expect(existsSync(projectA)).toBe(false);
    expect(existsSync(join(settings.claudeConfigDir, "file-history", SESSION_A))).toBe(false);
    expect(existsSync(join(settings.claudeConfigDir, "session-env", SESSION_A))).toBe(false);
    expect(existsSync(join(settings.jobsRoot, JOB_B, "report", "transcript.txt"))).toBe(true);
    expect(existsSync(join(settings.logsRoot, JOB_B))).toBe(true);
    expect(existsSync(projectB)).toBe(true);
    expect(existsSync(join(settings.claudeConfigDir, "file-history", SESSION_B))).toBe(true);
    expect(existsSync(`${join(settings.jobsRoot, JOB_A)}-other`)).toBe(true);
  });

  it("leaves anything that is not a report id alone", () => {
    const { settings } = runnerTree();
    const outcome = forgetJobs(settings, ["..", "", "jobs", `${JOB_B}/..`, "*"]);
    expect(outcome.removed).toBe(0);
    expect(outcome.skipped.length).toBe(5);
    expect(existsSync(settings.jobsRoot)).toBe(true);
    expect(existsSync(join(settings.jobsRoot, JOB_B))).toBe(true);
    expect(isReportId(JOB_A)).toBe(true);
    expect(isReportId("not-a-uuid")).toBe(false);
  });

  it("one pass: removes each deletion's jobs and reports it back", async () => {
    const { settings } = runnerTree();
    const confirmed: Array<[string, string]> = [];
    const backend = {
      environment: "staging",
      listForgets: async () => [{ userId: PERSON, reportIds: [JOB_A] }],
      confirmForget: async (userId: string, result: string) => {
        confirmed.push([userId, result]);
      },
    };
    const results = await forgetDeletedAccounts(backend, settings);
    expect(confirmed).toEqual([[PERSON, "removed 6 folders for 1 jobs"]]);
    expect(results).toEqual([{ userId: PERSON, result: "removed 6 folders for 1 jobs" }]);
    expect(existsSync(join(settings.jobsRoot, JOB_A))).toBe(false);
  });

  it("before a claim, at most once per interval; a failing environment does not stop the claim", async () => {
    const { settings } = runnerTree();
    let lists = 0;
    let claims = 0;
    const errors: string[] = [];
    let nowMs = 0;
    const failing = {
      environment: "live",
      listForgets: async () => {
        lists += 1;
        throw new Error("503");
      },
      confirmForget: async () => {},
    };
    const claim = claimAfterForgetting({
      claimJob: async () => {
        claims += 1;
        return null;
      },
      backends: [failing],
      settings,
      onError: (error: Error) => errors.push(error.message),
      intervalMs: 1000,
      now: () => nowMs,
    });
    await claim();
    nowMs = 500;
    await claim();
    nowMs = 1500;
    await claim();
    expect(claims).toBe(3);
    expect(lists).toBe(2);
    expect(errors).toEqual(["live: account deletion clean-up: 503", "live: account deletion clean-up: 503"]);
  });

  it("the runner's client asks the Worker with the runner token", async () => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    async function fakeFetch(url: string, init: RequestInit) {
      calls.push({ url, init });
      if (url.endsWith("/pending")) {
        return new Response(JSON.stringify({ deletions: [{ userId: PERSON, reportIds: [JOB_A] }] }), { status: 200 });
      }
      return new Response(JSON.stringify({ cleaned: true }), { status: 200 });
    }
    const client = createBackendClient({ baseUrl: "https://w", token: "rt", environment: "live", fetchImplementation: fakeFetch });
    expect(await client.listForgets()).toEqual([{ userId: PERSON, reportIds: [JOB_A] }]);
    await client.confirmForget(PERSON, "removed 6 folders for 1 jobs");
    expect(calls[0].url).toBe("https://w/account-deletions/runner/pending");
    expect((calls[0].init.headers as Record<string, string>).Authorization).toBe("Runner rt");
    expect(calls[1].url).toBe("https://w/account-deletions/runner/ab_c/cleaned");
    expect(JSON.parse(String(calls[1].init.body))).toEqual({ result: "removed 6 folders for 1 jobs" });
  });
});
