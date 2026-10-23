import { createHash } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { MAX_VOICE_ERROR_LENGTH, VOICE_ERROR_FILE } from "../src/repairs";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Repair voice bug (2026-10-23): every repair report on staging had no words and nothing said
// why. The phone now sends `voiceError` (the recogniser's error domain and code, or "no words,
// N audio buffers"). No column for it (no migration): the server keeps it next to the report's
// files as voice-error.json and logs it. It never costs the report: a long one is cut, not refused.

const PNG_HEADER = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function makeEnv() {
  return { DB: makeMigratedD1(), BUNDLES: makeFakeR2() };
}

type TestEnv = ReturnType<typeof makeEnv>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addSignedInUser(env: TestEnv, userId: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'reminders', 'now')", userId);
  return token;
}

function makeForm(voiceError: string | null): FormData {
  const form = new FormData();
  form.set("sidekickId", "reminders");
  form.set("kind", "unknown");
  form.set("transcript", "make the tag bigger");
  form.set("strokes", JSON.stringify([[[10, 20, 0]]]));
  form.set("screenshot", new Blob([PNG_HEADER], { type: "image/png" }), "screenshot.png");
  form.set("drawing", new Blob([PNG_HEADER], { type: "image/png" }), "drawing.png");
  if (voiceError !== null) {
    form.set("voiceError", voiceError);
  }
  return form;
}

async function postReport(env: TestEnv, token: string, form: FormData): Promise<{ status: number; id: string }> {
  const response = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form }, env);
  const reply = (await response.json()) as { id: string };
  return { status: response.status, id: reply.id };
}

// The first argument of one console.log call, as text.
function firstArgumentText(call: unknown[]): string {
  return String(call[0]);
}

function isVoiceErrorLine(line: string): boolean {
  return line.includes("repair-voice-error");
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("repair report voiceError", () => {
  it("keeps the phone's voice error beside the report and logs it", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-1");
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => undefined);
    const voiceError = "kAFAssistantErrorDomain 1110; no words, 0 audio buffers";
    const posted = await postReport(env, token, makeForm(voiceError));
    expect(posted.status).toBe(201);

    const stored = await env.BUNDLES.get(`repairs/${posted.id}/${VOICE_ERROR_FILE}`);
    expect(stored).not.toBeNull();
    expect(await stored!.json()).toEqual({ voiceError });

    const loggedLines = logSpy.mock.calls.map(firstArgumentText);
    const voiceLines = loggedLines.filter(isVoiceErrorLine);
    expect(voiceLines.length).toBe(1);
    expect(JSON.parse(voiceLines[0])).toEqual({ event: "repair-voice-error", reportId: posted.id, voiceError });
  });

  it("writes no voice file when the phone sent none", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-1");
    const posted = await postReport(env, token, makeForm(null));
    expect(posted.status).toBe(201);
    expect(env.BUNDLES.keys()).not.toContain(`repairs/${posted.id}/${VOICE_ERROR_FILE}`);
    expect(env.BUNDLES.keys().length).toBe(3);
  });

  it("cuts a long voice error instead of refusing the report", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-1");
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    const posted = await postReport(env, token, makeForm("x".repeat(MAX_VOICE_ERROR_LENGTH + 50)));
    expect(posted.status).toBe(201);
    const stored = await env.BUNDLES.get(`repairs/${posted.id}/${VOICE_ERROR_FILE}`);
    const body = (await stored!.json()) as { voiceError: string };
    expect(body.voiceError.length).toBe(MAX_VOICE_ERROR_LENGTH);
  });
});
