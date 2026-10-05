import { Hono } from "hono";

type Bindings = {
  DB: D1Database;
  BUNDLES: R2Bucket;
};

const app = new Hono<{ Bindings: Bindings }>();

// Reports each binding separately so a phone can tell which one is down.
app.get("/health", async (c) => {
  const check = async (probe: () => Promise<unknown>) => {
    try {
      await probe();
      return "ok";
    } catch (err) {
      return err instanceof Error ? err.message : String(err);
    }
  };

  const [d1, r2] = await Promise.all([
    check(() => c.env.DB.prepare("SELECT 1").first()),
    check(() => c.env.BUNDLES.list({ limit: 1 })),
  ]);

  const ok = d1 === "ok" && r2 === "ok";
  return c.json({ ok, d1, r2, time: new Date().toISOString() }, ok ? 200 : 503);
});

export default app;
