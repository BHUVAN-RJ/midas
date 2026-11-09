// The privacy page's Camera section (founder, 2026-11-08): a receipt photo jess adds to Money is
// kept with that expense in the person's Midas files; any other photo is not kept.
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { makeMigratedD1 } from "./helpers/migrated-d1";

async function cameraSection(): Promise<string> {
  const response = await app.request("/privacy", {}, { DB: makeMigratedD1() });
  const page = await response.text();
  const start = page.indexOf("Camera");
  const end = page.indexOf("Edit", start);
  return page.slice(start, end);
}

describe("the privacy page, Camera", () => {
  it("says a receipt photo added to Money is kept with that expense", async () => {
    const section = await cameraSection();
    expect(section).toContain("When the photo is a receipt that jess adds to Money, it is kept with that expense");
  });

  it("still says any other photo is not kept", async () => {
    const section = await cameraSection();
    expect(section).toContain("Midas does not keep the photo.");
  });
});
