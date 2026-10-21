import { Hono } from "hono";
import type { Context } from "hono";
import { requireSession } from "./auth";

type SidekickBindings = {
  DB: D1Database;
  BUNDLES: R2Bucket;
  RP_ID?: string;
};

type SidekickVariables = {
  userId: string;
};

type SidekickEnv = { Bindings: SidekickBindings; Variables: SidekickVariables };
type SidekickContext = Context<SidekickEnv>;

// Written by scripts/deploy-sidekick.mjs as sidekicks/<id>/current.json (the base) or as
// sidekicks/<id>/users/<user_id>/current.json (one user's copy, repair 2026-10-13). It names the
// version the shell gets; every version stays stored next to its pointer under <version>/.
// contentHash and baseVersion let a base deploy tell an untouched copy from a repaired one.
// tools is "tools.js" when the version has the jess router's tools beside its page (2026-10-21).
type BundlePointer = {
  version: string;
  scriptHashes: string[];
  contentHash?: string;
  baseVersion?: string | null;
  tools?: string;
};

// Where a user's bundle came from: their own copy, or the base when they have no copy yet.
type ResolvedBundle = {
  pointer: BundlePointer;
  prefix: string;
  scope: "user" | "base";
};

// manifest.json next to each version's index.html (checked at deploy by validateManifest).
type SidekickManifest = {
  id: string;
  name: string;
  icon: { symbol: string; background: string };
  reads: string[];
};

export const SIDEKICK_ID_PATTERN = /^[a-z0-9-]{1,40}$/;
// User ids are base64url (auth.ts randomId); nothing here can leave the users/ prefix.
const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

function basePrefix(sidekickId: string): string {
  return `sidekicks/${sidekickId}`;
}

function userPrefix(sidekickId: string, userId: string): string {
  if (!USER_ID_PATTERN.test(userId)) {
    throw new Error("bad user id");
  }
  return `sidekicks/${sidekickId}/users/${userId}`;
}

function pointerKey(prefix: string): string {
  return `${prefix}/current.json`;
}

function versionFileKey(prefix: string, version: string, fileName: string): string {
  return `${prefix}/${version}/${fileName}`;
}

async function readPointer(bucket: R2Bucket, prefix: string): Promise<BundlePointer | null> {
  const pointerObject = await bucket.get(pointerKey(prefix));
  if (pointerObject === null) {
    return null;
  }
  return (await pointerObject.json()) as BundlePointer;
}

// The user's own pointer wins; without one, the base. Null when the Sidekick has no base either.
async function resolveBundle(bucket: R2Bucket, sidekickId: string, userId: string): Promise<ResolvedBundle | null> {
  const ownPrefix = userPrefix(sidekickId, userId);
  const ownPointer = await readPointer(bucket, ownPrefix);
  if (ownPointer !== null) {
    return { pointer: ownPointer, prefix: ownPrefix, scope: "user" };
  }
  const base = basePrefix(sidekickId);
  const basePointer = await readPointer(bucket, base);
  if (basePointer === null) {
    return null;
  }
  return { pointer: basePointer, prefix: base, scope: "base" };
}

const COPIED_FILES = ["index.html", "manifest.json"];
const TOOLS_FILE = "tools.js";

// A version's tests live under <version>/tests/<name>, listed in <version>/tests/index.json
// (founder, 2026-10-13: tests move every copy forward). Never served: no route reads them.
const TESTS_INDEX_PATH = "tests/index.json";
const TEST_FILE_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,120}$/;

type TestsIndex = { files: string[] };

async function copyObject(bucket: R2Bucket, sourceKey: string, targetKey: string): Promise<boolean> {
  const sourceObject = await bucket.get(sourceKey);
  if (sourceObject === null) {
    return false;
  }
  await bucket.put(targetKey, sourceObject.body);
  return true;
}

// Copies the base version's tests into the user's version. A base deployed before tests were
// stored has no index; the copy then has no tests either, and the record says so.
async function copyBaseTests(bucket: R2Bucket, base: string, ownPrefix: string, version: string): Promise<string[] | null> {
  const indexObject = await bucket.get(versionFileKey(base, version, TESTS_INDEX_PATH));
  if (indexObject === null) {
    return null;
  }
  const index = (await indexObject.json()) as TestsIndex;
  for (const fileName of index.files) {
    if (!TEST_FILE_NAME_PATTERN.test(fileName)) {
      throw new Error(`base ${version} lists a bad test file name: ${fileName}`);
    }
    const copied = await copyObject(bucket, versionFileKey(base, version, `tests/${fileName}`), versionFileKey(ownPrefix, version, `tests/${fileName}`));
    if (!copied) {
      throw new Error(`base ${version} is missing test file ${fileName}`);
    }
  }
  await bucket.put(versionFileKey(ownPrefix, version, TESTS_INDEX_PATH), JSON.stringify(index));
  return index.files;
}

// A user's first load copies the base's current version into their own store, so from then on
// their copy is theirs: a repair moves only their pointer, and a base change reaches them only
// when the founder's base deploy updates untouched copies. Files first, then tests, pointer
// last. A failed copy is logged and retried on the next load; the page is served from the base
// regardless.
async function copyBaseToUser(bucket: R2Bucket, sidekickId: string, userId: string, basePointer: BundlePointer): Promise<void> {
  const base = basePrefix(sidekickId);
  const ownPrefix = userPrefix(sidekickId, userId);
  const version = basePointer.version;
  for (const fileName of COPIED_FILES) {
    const copied = await copyObject(bucket, versionFileKey(base, version, fileName), versionFileKey(ownPrefix, version, fileName));
    if (!copied) {
      throw new Error(`base ${sidekickId} ${version} has no ${fileName}`);
    }
  }
  const hasTools = basePointer.tools === TOOLS_FILE;
  if (hasTools) {
    const copied = await copyObject(bucket, versionFileKey(base, version, TOOLS_FILE), versionFileKey(ownPrefix, version, TOOLS_FILE));
    if (!copied) {
      throw new Error(`base ${sidekickId} ${version} has no ${TOOLS_FILE}`);
    }
  }
  const testFiles = await copyBaseTests(bucket, base, ownPrefix, version);
  const versionRecord = {
    version,
    scriptHashes: basePointer.scriptHashes,
    contentHash: basePointer.contentHash ?? null,
    baseVersion: version,
    forUser: userId,
    copiedAt: new Date().toISOString(),
    testFiles,
    ...(hasTools ? { tools: TOOLS_FILE } : {}),
  };
  await bucket.put(versionFileKey(ownPrefix, version, "version.json"), JSON.stringify(versionRecord));
  const ownPointer: BundlePointer = {
    version,
    scriptHashes: basePointer.scriptHashes,
    contentHash: basePointer.contentHash,
    baseVersion: version,
  };
  if (hasTools) {
    ownPointer.tools = TOOLS_FILE;
  }
  await bucket.put(pointerKey(ownPrefix), JSON.stringify(ownPointer));
}

async function copyBaseToUserOrLog(bucket: R2Bucket, sidekickId: string, userId: string, basePointer: BundlePointer): Promise<void> {
  try {
    await copyBaseToUser(bucket, sidekickId, userId, basePointer);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`could not copy base ${sidekickId} to user ${userId}: ${message}`);
  }
}

async function isAssigned(db: D1Database, userId: string, sidekickId: string): Promise<boolean> {
  const prepared = db.prepare("SELECT 1 AS assigned FROM assignments WHERE user_id = ? AND sidekick_id = ?");
  const assignmentStatement = prepared.bind(userId, sidekickId);
  const assignment = await assignmentStatement.first();
  return assignment !== null;
}

async function assignedSidekickIds(db: D1Database, userId: string): Promise<string[]> {
  const prepared = db.prepare("SELECT sidekick_id FROM assignments WHERE user_id = ? ORDER BY assigned_at, sidekick_id");
  const assignmentsStatement = prepared.bind(userId);
  const queryResult = await assignmentsStatement.all<{ sidekick_id: string }>();
  const sidekickIds: string[] = [];
  for (const row of queryResult.results) {
    sidekickIds.push(row.sidekick_id);
  }
  return sidekickIds;
}

// The manifest of the version this user gets plus that version, or null when nothing usable is
// deployed. Listing does not copy the base; the first bundle load does.
async function currentListing(bucket: R2Bucket, sidekickId: string, userId: string) {
  const resolved = await resolveBundle(bucket, sidekickId, userId);
  if (resolved === null) {
    return null;
  }
  const manifestObject = await bucket.get(versionFileKey(resolved.prefix, resolved.pointer.version, "manifest.json"));
  if (manifestObject === null) {
    return null;
  }
  const manifest = (await manifestObject.json()) as SidekickManifest;
  return { ...manifest, id: sidekickId, version: resolved.pointer.version };
}

// The signed-in user's Sidekicks, in the order they were assigned. The shell builds its folder
// from this. An assigned Sidekick with no deployed version (or an old version deployed before
// manifests existed) is left out rather than failing the whole list.
async function handleListSidekicks(c: SidekickContext) {
  const sidekickIds = await assignedSidekickIds(c.env.DB, c.get("userId"));
  const listings = [];
  for (const sidekickId of sidekickIds) {
    const listing = await currentListing(c.env.BUNDLES, sidekickId, c.get("userId"));
    if (listing !== null) {
      listings.push(listing);
    }
  }
  return c.json({ sidekicks: listings });
}

// Serves the user's current version of a Sidekick's bundle to the shell: their own copy, or the
// base on their first load (which also creates their copy). The shell builds the CSP from
// X-Midas-Script-Hashes, so only the scripts that were deployed can run. A Sidekick that is not
// assigned to the user answers exactly like one that does not exist, even if a copy exists.
// X-Midas-Bundle-Scope says where the page came from; the shell ignores it.
async function handleSidekickBundle(c: SidekickContext) {
  const sidekickId = c.req.param("id") ?? "";
  if (!SIDEKICK_ID_PATTERN.test(sidekickId)) {
    return c.json({ error: "bad sidekick id" }, 400);
  }
  const userId = c.get("userId");
  if (!(await isAssigned(c.env.DB, userId, sidekickId))) {
    return c.json({ error: "no such sidekick" }, 404);
  }

  const resolved = await resolveBundle(c.env.BUNDLES, sidekickId, userId);
  if (resolved === null) {
    return c.json({ error: "no such sidekick" }, 404);
  }
  const pointer = resolved.pointer;

  const htmlObject = await c.env.BUNDLES.get(versionFileKey(resolved.prefix, pointer.version, "index.html"));
  if (htmlObject === null) {
    return c.json({ error: "bundle version missing" }, 500);
  }

  if (resolved.scope === "base") {
    await copyBaseToUserOrLog(c.env.BUNDLES, sidekickId, userId, pointer);
  }

  return new Response(htmlObject.body, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Midas-Bundle-Version": pointer.version,
      "X-Midas-Script-Hashes": pointer.scriptHashes.join(" "),
      "X-Midas-Bundle-Scope": resolved.scope,
    },
  });
}

// Serves the tools.js of the version this user gets (jess router, founder 2026-10-21). The shell
// runs it in JavaScriptCore, never in the page, and keeps it keyed by X-Midas-Bundle-Version so
// it always matches the agent block of the same version. With ?version=, a different current
// version answers 409 so the shell refetches the listing first. A version without tools is 404.
async function handleSidekickTools(c: SidekickContext) {
  const sidekickId = c.req.param("id") ?? "";
  if (!SIDEKICK_ID_PATTERN.test(sidekickId)) {
    return c.json({ error: "bad sidekick id" }, 400);
  }
  const userId = c.get("userId");
  if (!(await isAssigned(c.env.DB, userId, sidekickId))) {
    return c.json({ error: "no such sidekick" }, 404);
  }
  const resolved = await resolveBundle(c.env.BUNDLES, sidekickId, userId);
  if (resolved === null) {
    return c.json({ error: "no such sidekick" }, 404);
  }
  const pointer = resolved.pointer;
  const wantedVersion = c.req.query("version");
  if (wantedVersion !== undefined && wantedVersion !== pointer.version) {
    return c.json({ error: "version changed", version: pointer.version }, 409);
  }
  if (pointer.tools !== TOOLS_FILE) {
    return c.json({ error: "no tools" }, 404);
  }
  const toolsObject = await c.env.BUNDLES.get(versionFileKey(resolved.prefix, pointer.version, TOOLS_FILE));
  if (toolsObject === null) {
    return c.json({ error: "tools missing" }, 500);
  }
  return new Response(toolsObject.body, {
    headers: {
      "Content-Type": "text/javascript; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Midas-Bundle-Version": pointer.version,
      "X-Midas-Bundle-Scope": resolved.scope,
    },
  });
}

export const sidekickRoutes = new Hono<SidekickEnv>();
sidekickRoutes.use("*", requireSession);
sidekickRoutes.get("/", handleListSidekicks);
sidekickRoutes.get("/:id/bundle", handleSidekickBundle);
sidekickRoutes.get("/:id/tools.js", handleSidekickTools);
