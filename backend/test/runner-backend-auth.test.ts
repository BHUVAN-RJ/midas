import { describe, expect, it } from "vitest";
import app from "../src/index";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// The runner's own backend client against the real Worker app (2026-10-19). The runner and the
// intake were built by different agents and each was tested against its own fake; the first
// real claim on staging was refused (401) because the runner sent "Bearer <token>" and the Worker
// only accepts "Runner <token>". Here the client's requests go straight into the app, so the two
// sides must agree for these tests to pass.

const RUNNER_TOKEN = "runner-secret-for-tests";

function makeEnv() {
  return {
    DB: makeMigratedD1(),
    BUNDLES: makeFakeR2(),
    REPAIR_RUNNER_TOKEN: RUNNER_TOKEN,
  };
}

type TestEnv = ReturnType<typeof makeEnv>;

/** A fetch that hands every request to the Worker app instead of the network. */
function fetchIntoApp(env: TestEnv) {
  return async function fetchThroughWorker(url: string, init?: RequestInit): Promise<Response> {
    return app.request(url, init, env);
  };
}

function addQueuedReport(env: TestEnv, reportId: string) {
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES ('user-1', 'user-1', 'now')");
  env.DB.execute(
    "INSERT INTO repair_reports (id, user_id, sidekick_id, kind, transcript, status, created_at, updated_at) VALUES (?, 'user-1', 'reminders', 'bug', 'the line does not wrap', 'queued', 'now', 'now')",
    reportId,
  );
}

describe("runner client and Worker agree on the runner token", () => {
  it("claims a queued report with the runner token", async () => {
    const env = makeEnv();
    addQueuedReport(env, "report-1");
    const backend = createBackendClient({ baseUrl: "https://worker.test", token: RUNNER_TOKEN, fetchImplementation: fetchIntoApp(env) });

    const job = await backend.claimJob();

    expect(job?.id).toBe("report-1");
    expect(job?.sidekickId).toBe("reminders");
  });

  it("gets nothing, without an error, when no report waits", async () => {
    const env = makeEnv();
    const backend = createBackendClient({ baseUrl: "https://worker.test", token: RUNNER_TOKEN, fetchImplementation: fetchIntoApp(env) });

    await expect(backend.claimJob()).resolves.toBeNull();
  });

  it("is refused with a wrong token", async () => {
    const env = makeEnv();
    addQueuedReport(env, "report-1");
    const backend = createBackendClient({ baseUrl: "https://worker.test", token: "not-the-runner-token", fetchImplementation: fetchIntoApp(env) });

    await expect(backend.claimJob()).rejects.toThrow("claim failed: 401");
  });
});
