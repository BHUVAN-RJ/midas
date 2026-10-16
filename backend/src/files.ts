import { Hono } from "hono";
import type { Context } from "hono";
import { requireSession } from "./auth";

// Files (unified data plan, section 7; founder 2026-10-15): screenshots, images and other things
// larger than a record. The file lives in the FILES bucket under <userId>/<fileId>; a record holds
// the reference "file:<fileId>" (schema: ^file:[A-Za-z0-9_-]{1,64}$). A file is read only by its
// owner. Nothing here is ever deleted or overwritten: a second upload under the same id answers
// with what is stored. Limit 20 MB per file, checked on the bytes, not only on Content-Length.
//
// Buckets: midas-files-staging (staging), midas-files (live, created by the founder); bound as
// FILES in wrangler.jsonc (the lead). Without the binding the routes answer 503, so a Worker
// deployed before the binding still runs.

type FilesBindings = {
  DB: D1Database;
  FILES?: R2Bucket;
  RP_ID?: string;
};

type FilesVariables = {
  userId: string;
};

type FilesEnv = { Bindings: FilesBindings; Variables: FilesVariables };
type FilesContext = Context<FilesEnv>;

export const MAX_FILE_BYTES = 20 * 1024 * 1024;
// The shell chooses the id (X-Midas-File-Id), so a retry of the same upload lands on the same key.
export const FILE_ID_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;
export const FILE_ID_HEADER = "X-Midas-File-Id";
const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const DEFAULT_CONTENT_TYPE = "application/octet-stream";
// Only plain media types; a parameter such as charset is kept, anything odd is replaced.
const CONTENT_TYPE_PATTERN = /^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+(;\s*[a-z0-9-]+=[A-Za-z0-9._-]+)?$/i;

export function fileKey(userId: string, fileId: string): string {
  if (!USER_ID_PATTERN.test(userId) || !FILE_ID_PATTERN.test(fileId)) {
    throw new Error("bad file key");
  }
  return `${userId}/${fileId}`;
}

export function fileReference(fileId: string): string {
  return `file:${fileId}`;
}

function cleanContentType(header: string | undefined): string {
  if (header === undefined || !CONTENT_TYPE_PATTERN.test(header.trim())) {
    return DEFAULT_CONTENT_TYPE;
  }
  return header.trim();
}

function newFileId(): string {
  return crypto.randomUUID().replaceAll("-", "");
}

function fileAnswer(fileId: string, size: number, contentType: string) {
  return { id: fileId, ref: fileReference(fileId), size, contentType };
}

// POST /files, the bytes as the body, Content-Type the file's type, X-Midas-File-Id optional.
// Answers {id, ref, size, contentType}: 201 when stored now, 200 when the id was stored before.
async function handleUpload(c: FilesContext) {
  const bucket = c.env.FILES;
  if (bucket === undefined) {
    return c.json({ error: "files are not set up on this server" }, 503);
  }
  const declaredLength = Number(c.req.header("Content-Length") ?? "0");
  if (declaredLength > MAX_FILE_BYTES) {
    return c.json({ error: `file is over ${MAX_FILE_BYTES} bytes` }, 413);
  }
  const requestedId = c.req.header(FILE_ID_HEADER);
  if (requestedId !== undefined && !FILE_ID_PATTERN.test(requestedId)) {
    return c.json({ error: `${FILE_ID_HEADER} must be 8 to 64 letters, digits, - or _` }, 400);
  }
  const userId = c.get("userId");
  const fileId = requestedId ?? newFileId();
  const key = fileKey(userId, fileId);

  // A retry of an upload the server already has: the stored file wins, nothing is overwritten.
  const existing = await bucket.get(key);
  if (existing !== null) {
    return c.json(fileAnswer(fileId, existing.size, existing.httpMetadata?.contentType ?? DEFAULT_CONTENT_TYPE), 200);
  }

  const bytes = await c.req.arrayBuffer();
  if (bytes.byteLength === 0) {
    return c.json({ error: "file is empty" }, 400);
  }
  if (bytes.byteLength > MAX_FILE_BYTES) {
    return c.json({ error: `file is over ${MAX_FILE_BYTES} bytes` }, 413);
  }
  const contentType = cleanContentType(c.req.header("Content-Type"));
  await bucket.put(key, bytes, {
    httpMetadata: { contentType },
    customMetadata: { userId, uploadedAt: new Date().toISOString() },
  });
  return c.json(fileAnswer(fileId, bytes.byteLength, contentType), 201);
}

// GET /files/:id, the owner's file as stored. Another user's file, or an unknown id, is 404.
async function handleDownload(c: FilesContext) {
  const bucket = c.env.FILES;
  if (bucket === undefined) {
    return c.json({ error: "files are not set up on this server" }, 503);
  }
  const fileId = c.req.param("id") ?? "";
  if (!FILE_ID_PATTERN.test(fileId)) {
    return c.json({ error: "no such file" }, 404);
  }
  const object = await bucket.get(fileKey(c.get("userId"), fileId));
  if (object === null) {
    return c.json({ error: "no such file" }, 404);
  }
  const contentType = object.httpMetadata?.contentType ?? DEFAULT_CONTENT_TYPE;
  return new Response(object.body, {
    headers: {
      "Content-Type": contentType,
      "Content-Length": String(object.size),
      "Cache-Control": "private, no-store",
    },
  });
}

export const filesRoutes = new Hono<FilesEnv>();
filesRoutes.use("*", requireSession);
filesRoutes.post("/", handleUpload);
filesRoutes.get("/:id", handleDownload);
