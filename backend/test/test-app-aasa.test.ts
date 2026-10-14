import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { APPLE_APP_ID, TEST_APPLE_APP_ID } from "../src/auth";
import { makeSqliteD1 } from "./helpers/sqlite-d1";

// "Midas Test" (founder, 2026-10-14): a second app on the same phone, on staging only. Staging's
// apple-app-site-association lists it so its passkeys work; live never does.

type AssociationReply = { webcredentials: { apps: string[] } };

async function associatedApps(vars: Record<string, string>): Promise<string[]> {
  const env = { DB: makeSqliteD1(), BUNDLES: {}, ...vars };
  const response = await app.request("/.well-known/apple-app-site-association", {}, env);
  const body = (await response.json()) as AssociationReply;
  return body.webcredentials.apps;
}

function wranglerConfigText(): string {
  const configURL = new URL("../wrangler.jsonc", import.meta.url);
  return readFileSync(configURL, "utf8");
}

describe("Midas Test app in apple-app-site-association", () => {
  it("is listed next to Midas when the Worker serves the test app (staging)", async () => {
    const apps = await associatedApps({ SERVE_TEST_APP: "true" });
    expect(apps).toEqual([APPLE_APP_ID, TEST_APPLE_APP_ID]);
    expect(TEST_APPLE_APP_ID).toBe("ZQ2JPFYL98.com.bhuvanrj.midas.test");
  });

  it("is not listed without the setting (live)", async () => {
    const apps = await associatedApps({});
    expect(apps).toEqual([APPLE_APP_ID]);
  });

  it("is switched on for staging only in wrangler.jsonc", () => {
    const configText = wranglerConfigText();
    const stagingStart = configText.indexOf('"staging"');
    expect(stagingStart).toBeGreaterThan(0);
    const liveSection = configText.slice(0, stagingStart);
    const stagingSection = configText.slice(stagingStart);
    expect(liveSection).not.toContain("SERVE_TEST_APP");
    expect(stagingSection).toContain('"SERVE_TEST_APP": "true"');
  });
});
