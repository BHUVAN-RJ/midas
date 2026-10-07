import { Hono } from "hono";
import type { Context, Next } from "hono";

type Bindings = {
  DB: D1Database;
  BUNDLES: R2Bucket;
};

type AppContext = Context<{ Bindings: Bindings }>;

// Written by scripts/deploy-sidekick.mjs next to each version's index.html.
type BundlePointer = {
  version: string;
  scriptHashes: string[];
};

// Sidekick pages are served by the shell under this scheme, so their fetch Origin is
// "sidekick://<id>". Only those origins get CORS; a browser page elsewhere gets none.
const SIDEKICK_ORIGIN_PATTERN = /^sidekick:\/\/[a-z0-9-]{1,40}$/;
const SIDEKICK_ID_PATTERN = /^[a-z0-9-]{1,40}$/;

const app = new Hono<{ Bindings: Bindings }>();

async function sidekickCors(c: AppContext, next: Next) {
  const requestOrigin = c.req.header("Origin") ?? "";
  const isSidekickOrigin = SIDEKICK_ORIGIN_PATTERN.test(requestOrigin);

  if (c.req.method === "OPTIONS") {
    if (!isSidekickOrigin) {
      return c.body(null, 403);
    }
    c.header("Access-Control-Allow-Origin", requestOrigin);
    c.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    c.header("Access-Control-Allow-Headers", "Authorization, Content-Type");
    c.header("Access-Control-Max-Age", "600");
    c.header("Vary", "Origin");
    return c.body(null, 204);
  }

  await next();
  if (isSidekickOrigin) {
    c.res.headers.set("Access-Control-Allow-Origin", requestOrigin);
    c.res.headers.append("Vary", "Origin");
  }
}

async function probeBinding(probe: () => Promise<unknown>): Promise<string> {
  try {
    await probe();
    return "ok";
  } catch (err) {
    return err instanceof Error ? err.message : String(err);
  }
}

// Reports each binding separately so a phone can tell which one is down.
async function handleHealth(c: AppContext) {
  const probeD1 = () => c.env.DB.prepare("SELECT 1").first();
  const probeR2 = () => c.env.BUNDLES.list({ limit: 1 });
  const [d1, r2] = await Promise.all([probeBinding(probeD1), probeBinding(probeR2)]);

  const ok = d1 === "ok" && r2 === "ok";
  return c.json({ ok, d1, r2, time: new Date().toISOString() }, ok ? 200 : 503);
}

// Serves the current version of a Sidekick's bundle to the shell. The shell builds the CSP
// from X-Midas-Script-Hashes, so only the scripts that were deployed can run.
// TODO(D3/D5): require a valid shell token; until then this route is open, and bundles hold
// code only, never user data.
async function handleSidekickBundle(c: AppContext) {
  const sidekickId = c.req.param("id") ?? "";
  if (!SIDEKICK_ID_PATTERN.test(sidekickId)) {
    return c.json({ error: "bad sidekick id" }, 400);
  }

  const pointerObject = await c.env.BUNDLES.get(`sidekicks/${sidekickId}/current.json`);
  if (pointerObject === null) {
    return c.json({ error: "no such sidekick" }, 404);
  }
  const pointer = (await pointerObject.json()) as BundlePointer;

  const htmlObject = await c.env.BUNDLES.get(`sidekicks/${sidekickId}/${pointer.version}/index.html`);
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

app.use("*", sidekickCors);
app.get("/health", handleHealth);
app.get("/sidekicks/:id/bundle", handleSidekickBundle);

export default app;
