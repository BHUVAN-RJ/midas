import { Hono } from "hono";
import type { Context, Next } from "hono";
import { authRoutes, handleAppleAppSiteAssociation } from "./auth";
import { sidekickRoutes } from "./sidekicks";

type Bindings = {
  DB: D1Database;
  BUNDLES: R2Bucket;
  // Passkey domain; set on the staging Worker, absent on live (see RELYING_PARTY_ID).
  RP_ID?: string;
};

type AppContext = Context<{ Bindings: Bindings }>;

// Sidekick pages are served by the shell under this scheme, so their fetch Origin is
// "sidekick://<id>". Only those origins get CORS; a browser page elsewhere gets none.
const SIDEKICK_ORIGIN_PATTERN = /^sidekick:\/\/[a-z0-9-]{1,40}$/;

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

app.use("*", sidekickCors);
app.get("/health", handleHealth);
app.route("/sidekicks", sidekickRoutes);
app.get("/.well-known/apple-app-site-association", handleAppleAppSiteAssociation);
app.route("/auth", authRoutes);

export default app;
