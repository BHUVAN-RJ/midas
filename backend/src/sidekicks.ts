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

// Written by scripts/deploy-sidekick.mjs as sidekicks/<id>/current.json. It names the version
// the shell gets; every version stays stored under sidekicks/<id>/<version>/.
type BundlePointer = {
  version: string;
  scriptHashes: string[];
};

// manifest.json next to each version's index.html (checked at deploy by validateManifest).
type SidekickManifest = {
  id: string;
  name: string;
  icon: { symbol: string; background: string };
  reads: string[];
};

export const SIDEKICK_ID_PATTERN = /^[a-z0-9-]{1,40}$/;

function pointerKey(sidekickId: string): string {
  return `sidekicks/${sidekickId}/current.json`;
}

function versionFileKey(sidekickId: string, version: string, fileName: string): string {
  return `sidekicks/${sidekickId}/${version}/${fileName}`;
}

async function readPointer(bucket: R2Bucket, sidekickId: string): Promise<BundlePointer | null> {
  const pointerObject = await bucket.get(pointerKey(sidekickId));
  if (pointerObject === null) {
    return null;
  }
  return (await pointerObject.json()) as BundlePointer;
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

// The current version's manifest plus that version, or null when nothing usable is deployed.
async function currentListing(bucket: R2Bucket, sidekickId: string) {
  const pointer = await readPointer(bucket, sidekickId);
  if (pointer === null) {
    return null;
  }
  const manifestObject = await bucket.get(versionFileKey(sidekickId, pointer.version, "manifest.json"));
  if (manifestObject === null) {
    return null;
  }
  const manifest = (await manifestObject.json()) as SidekickManifest;
  return { ...manifest, id: sidekickId, version: pointer.version };
}

// The signed-in user's Sidekicks, in the order they were assigned. The shell builds its folder
// from this. An assigned Sidekick with no deployed version (or an old version deployed before
// manifests existed) is left out rather than failing the whole list.
async function handleListSidekicks(c: SidekickContext) {
  const sidekickIds = await assignedSidekickIds(c.env.DB, c.get("userId"));
  const listings = [];
  for (const sidekickId of sidekickIds) {
    const listing = await currentListing(c.env.BUNDLES, sidekickId);
    if (listing !== null) {
      listings.push(listing);
    }
  }
  return c.json({ sidekicks: listings });
}

// Serves the current version of a Sidekick's bundle to the shell. The shell builds the CSP
// from X-Midas-Script-Hashes, so only the scripts that were deployed can run. A Sidekick that
// is not assigned to the user answers exactly like one that does not exist.
async function handleSidekickBundle(c: SidekickContext) {
  const sidekickId = c.req.param("id") ?? "";
  if (!SIDEKICK_ID_PATTERN.test(sidekickId)) {
    return c.json({ error: "bad sidekick id" }, 400);
  }
  if (!(await isAssigned(c.env.DB, c.get("userId"), sidekickId))) {
    return c.json({ error: "no such sidekick" }, 404);
  }

  const pointer = await readPointer(c.env.BUNDLES, sidekickId);
  if (pointer === null) {
    return c.json({ error: "no such sidekick" }, 404);
  }

  const htmlObject = await c.env.BUNDLES.get(versionFileKey(sidekickId, pointer.version, "index.html"));
  if (htmlObject === null) {
    return c.json({ error: "bundle version missing" }, 500);
  }

  return new Response(htmlObject.body, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Midas-Bundle-Version": pointer.version,
      "X-Midas-Script-Hashes": pointer.scriptHashes.join(" "),
    },
  });
}

export const sidekickRoutes = new Hono<SidekickEnv>();
sidekickRoutes.use("*", requireSession);
sidekickRoutes.get("/", handleListSidekicks);
sidekickRoutes.get("/:id/bundle", handleSidekickBundle);
