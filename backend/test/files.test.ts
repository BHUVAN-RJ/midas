import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { FILE_ID_HEADER, MAX_FILE_BYTES } from "../src/files";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Files (unified data plan, section 7; founder 2026-10-15): POST /files stores a user's file in
// the FILES bucket under <userId>/<fileId>, size checked on the bytes; GET /files/<id> is owner
// only; the record holds "file:<id>". Nothing is deleted.

function makeEnv(withFiles = true) {
  const env: Record<string, unknown> = { DB: makeMigratedD1(), BUNDLES: makeFakeR2() };
  if (withFiles) {
    env.FILES = makeFakeR2();
  }
  return env as { DB: ReturnType<typeof makeMigratedD1>; BUNDLES: ReturnType<typeof makeFakeR2>; FILES?: ReturnType<typeof makeFakeR2> };
}

type TestEnv = ReturnType<typeof makeEnv>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addSignedInUser(env: TestEnv, userId: string, name: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, name);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  return token;
}

type FileAnswer = { id: string; ref: string; size: number; contentType: string };

async function upload(env: TestEnv, token: string | null, bytes: Uint8Array, contentType: string, fileId?: string) {
  const headers: Record<string, string> = { "Content-Type": contentType };
  if (token !== null) {
    headers.Authorization = `Bearer ${token}`;
  }
  if (fileId !== undefined) {
    headers[FILE_ID_HEADER] = fileId;
  }
  return app.request("/files", { method: "POST", headers, body: bytes }, env);
}

async function download(env: TestEnv, token: string | null, fileId: string) {
  const headers: Record<string, string> = token === null ? {} : { Authorization: `Bearer ${token}` };
  return app.request(`/files/${fileId}`, { headers }, env);
}

const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);

describe("POST /files", () => {
  it("stores the bytes under the owner with their type and answers the reference", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-rj", "R J");
    const response = await upload(env, token, png, "image/png");
    expect(response.status).toBe(201);
    const answer = (await response.json()) as FileAnswer;
    expect(answer.ref).toBe(`file:${answer.id}`);
    expect(answer.size).toBe(png.length);
    expect(answer.contentType).toBe("image/png");
    expect(answer.ref).toMatch(/^file:[A-Za-z0-9_-]{1,64}$/);
    expect(env.FILES!.keys()).toEqual([`u-rj/${answer.id}`]);
  });

  it("uses the id the phone chose and answers 200 with what is stored when the same id comes again", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-rj", "R J");
    const first = await upload(env, token, png, "image/png", "shot-0001-abcdef");
    expect(first.status).toBe(201);
    expect((await first.json()).id).toBe("shot-0001-abcdef");
    const again = await upload(env, token, new Uint8Array([9, 9, 9]), "image/jpeg", "shot-0001-abcdef");
    expect(again.status).toBe(200);
    const answer = (await again.json()) as FileAnswer;
    expect(answer).toEqual({ id: "shot-0001-abcdef", ref: "file:shot-0001-abcdef", size: png.length, contentType: "image/png" });
    expect(env.FILES!.keys()).toEqual(["u-rj/shot-0001-abcdef"]);
    const bad = await upload(env, token, png, "image/png", "../escape");
    expect(bad.status).toBe(400);
  });

  it("refuses an empty file, a file over 20 MB by its bytes, an odd content type is replaced", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-rj", "R J");
    expect((await upload(env, token, new Uint8Array(0), "image/png")).status).toBe(400);
    const tooBig = new Uint8Array(MAX_FILE_BYTES + 1);
    const refused = await upload(env, token, tooBig, "image/png");
    expect(refused.status).toBe(413);
    expect(env.FILES!.keys()).toEqual([]);
    const odd = await upload(env, token, png, "not a type");
    expect(((await odd.json()) as FileAnswer).contentType).toBe("application/octet-stream");
  });

  it("needs a session, and answers 503 on a server without the files bucket", async () => {
    const env = makeEnv();
    expect((await upload(env, null, png, "image/png")).status).toBe(401);
    const bare = makeEnv(false);
    const token = addSignedInUser(bare, "u-rj", "R J");
    const response = await upload(bare, token, png, "image/png");
    expect(response.status).toBe(503);
    expect((await download(bare, token, "shot-0001-abcdef")).status).toBe(503);
  });
});

describe("GET /files/:id", () => {
  it("gives the owner the bytes and type back; another user and an unknown id get 404", async () => {
    const env = makeEnv();
    const ownerToken = addSignedInUser(env, "u-rj", "R J");
    const otherToken = addSignedInUser(env, "u-amogh", "Amogh");
    const uploaded = (await (await upload(env, ownerToken, png, "image/png")).json()) as FileAnswer;

    const response = await download(env, ownerToken, uploaded.id);
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("image/png");
    expect(response.headers.get("Cache-Control")).toBe("private, no-store");
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(png);

    expect((await download(env, otherToken, uploaded.id)).status).toBe(404);
    expect((await download(env, ownerToken, "neverstored00")).status).toBe(404);
    expect((await download(env, ownerToken, "..")).status).toBe(404);
    expect((await download(env, null, uploaded.id)).status).toBe(401);
  });
});
