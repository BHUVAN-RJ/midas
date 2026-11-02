import { describe, expect, it } from "vitest";
import { runDeletionCommand } from "../scripts/delete-account.mjs";

// Account deletion (founder, 2026-11-02; docs/briefs/account-deletion-2026-11-02.md): the founder
// runs --yes on each Mac that keeps ~/midas-backups. After the first Mac carried it out, the server
// answers "already deleted"; the second Mac still removes the person from its own backups.

type Call = { url: string; init: RequestInit };

function fakeWorker(status: number, reply: unknown) {
  const calls: Call[] = [];
  async function fetchReply(url: string, init: RequestInit) {
    calls.push({ url, init });
    return new Response(JSON.stringify(reply), { status });
  }
  return { calls, fetchReply };
}

describe("delete-account.mjs --yes on a second Mac", () => {
  it("already deleted on the server: this Mac's backups are still cleaned", async () => {
    const cleaned: string[] = [];
    function recordClean(environment: { name: string }, userId: string) {
      cleaned.push(`${environment.name}:${userId}`);
      return ["live-midas-old.sql: 4 rows removed"];
    }
    const worker = fakeWorker(409, { error: "already deleted", carriedOutAt: "2026-11-03T10:00:00.000Z" });
    const result = await runDeletionCommand(["--env", "live", "--user", "ab_c", "--yes"], { env: { MIDAS_LIVE_DELETION_TOKEN: "t" }, fetch: worker.fetchReply, removeFromBackups: recordClean });
    expect(result.exitCode).toBe(0);
    expect(cleaned).toEqual(["live:ab_c"]);
    expect(result.output).toContain("Already deleted on the server (2026-11-03T10:00:00.000Z).");
    expect(result.output).toContain("live-midas-old.sql: 4 rows removed");
  });

  it("any other refusal cleans nothing", async () => {
    const cleaned: string[] = [];
    function recordClean(environment: { name: string }, userId: string) {
      cleaned.push(`${environment.name}:${userId}`);
      return [];
    }
    const founderRefused = fakeWorker(409, { error: "the founder's account is not deleted here" });
    const founderResult = await runDeletionCommand(["--env", "live", "--user", "u-founder", "--yes"], { env: { MIDAS_LIVE_DELETION_TOKEN: "t" }, fetch: founderRefused.fetchReply, removeFromBackups: recordClean });
    expect(founderResult.exitCode).toBe(1);
    const notAsked = fakeWorker(404, { error: "no deletion request for this user" });
    const notAskedResult = await runDeletionCommand(["--env", "live", "--user", "abXc", "--yes"], { env: { MIDAS_LIVE_DELETION_TOKEN: "t" }, fetch: notAsked.fetchReply, removeFromBackups: recordClean });
    expect(notAskedResult.exitCode).toBe(1);
    expect(notAskedResult.output).toContain("404");
    expect(cleaned).toEqual([]);
  });
});
