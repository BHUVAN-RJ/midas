import { Hono } from "hono";
import type { Context, Next } from "hono";
import { authRoutes, handleAppleAppSiteAssociation, requireSession } from "./auth";
import { filesRoutes } from "./files";
import { jessRerunRoutes } from "./jess-rerun";
import { jessRoutes } from "./jess-route";
import { makeRoutes } from "./make";
import { publicPageRoutes } from "./public-pages";
import { pushRoutes } from "./push";
import { repairBlockedRoutes } from "./repair-blocked";
import { repairRoutes } from "./repairs";
import { sidekickRoutes } from "./sidekicks";
import { syncRoutes } from "./sync";
import { voiceRoutes } from "./voice-route";

type Bindings = {
  DB: D1Database;
  BUNDLES: R2Bucket;
  // User files (unified data, 2026-10-15): midas-files-staging / midas-files. Optional until the
  // binding is added to wrangler.jsonc; the file routes answer 503 without it.
  FILES?: R2Bucket;
  // Passkey domain; set on the staging Worker, absent on live (see RELYING_PARTY_ID).
  RP_ID?: string;
  // Shared secret for the repair runner on the Mac mini (wrangler secret put REPAIR_RUNNER_TOKEN).
  REPAIR_RUNNER_TOKEN?: string;
  // OpenRouter key for voice reminders (wrangler secret put OPENROUTER_API_KEY), staging first.
  OPENROUTER_API_KEY?: string;
  // Make (2026-10-24): the founder's user id on this environment (a var in wrangler.jsonc), and
  // the APNs key for pushes (wrangler secret put APNS_KEY_P8 / APNS_KEY_ID / APNS_TEAM_ID).
  MAKE_FOUNDER_USER_ID?: string;
  APNS_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
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
// App Store Connect's privacy policy and support URLs (build 22, 2026-10-31): no sign-in
app.route("/", publicPageRoutes);
app.route("/sidekicks", sidekickRoutes);
app.route("/sync", syncRoutes);
app.route("/files", filesRoutes);
// Repair asked for on a built-in Sidekick (Make, 2026-10-24), before the repair routes
app.route("/repairs", repairBlockedRoutes);
// The jess re-run's runner-only routes (jess grows the Sidekick), beside the repair routes
app.route("/repairs", jessRerunRoutes);
app.route("/repairs", repairRoutes);
// One sign-in check for every /voice request, the jess router's included (founder, 2026-10-21:
// one session lookup per request); neither route group checks it again
app.use("/voice/*", requireSession);
app.route("/voice/jess", jessRoutes);
app.route("/voice", voiceRoutes);
app.get("/.well-known/apple-app-site-association", handleAppleAppSiteAssociation);
app.route("/auth", authRoutes);
app.route("/push", pushRoutes);
app.route("/make", makeRoutes);

export default app;
