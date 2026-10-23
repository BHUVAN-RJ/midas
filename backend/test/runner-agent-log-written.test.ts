// runAgent resolved before its log stream had written everything, so check-sandbox.mjs read a
// cut-off log (2026-10-22, all suites: a refused Read showed as "the call went through" because
// its result line was not on disk yet). A log stream that takes 300 ms per write shows it every
// time: without the fix runAgent resolves while both lines are still being written.
import { Writable } from "node:stream";
import { realpathSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { runAgent } from "../../runner/lib/agent.mjs";
import { makeScratch } from "./helpers/runner-fixture";

// A log stream that takes 300 ms per chunk and records what it has finished writing.
function slowLogStream(written: string[]): Writable {
  return new Writable({
    write(chunk, _encoding, done) {
      setTimeout(function finishSlowWrite() {
        written.push(chunk.toString());
        done();
      }, 300);
    },
  });
}

describe("runAgent resolves only after the log is written", () => {
  it("every line the agent printed is written when runAgent resolves", async () => {
    const { scratch } = makeScratch();
    const written: string[] = [];
    const run = await runAgent({
      command: "/bin/sh",
      args: ["-c", "echo line1; echo line2"],
      jobFolder: realpathSync(scratch),
      logPath: "unused",
      environment: { PATH: "/usr/bin:/bin" },
      timeoutMs: 60_000,
      openLogStream: function openSlowLog() {
        return slowLogStream(written);
      },
    });
    expect(run.exitCode).toBe(0);
    expect(written.join("")).toBe("line1\nline2\n");
  }, 60_000);
});
