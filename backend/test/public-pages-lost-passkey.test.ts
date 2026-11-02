import { describe, expect, it } from "vitest";
import app from "../src/index";
import { SUPPORT_EMAIL, SUPPORT_PAGE } from "../src/public-pages";
import { makeFakeR2 } from "../test/helpers/fake-r2";
import { makeMigratedD1 } from "../test/helpers/migrated-d1";

// Account recovery W1 (founder, 2026-11-02; CONCERNS §5): a person who lost their passkey emails
// the founder with their Midas name. Shown only on /support, not in the app.

function makeEnv() {
  return { DB: makeMigratedD1(), BUNDLES: makeFakeR2() };
}

describe("/support lost passkey", () => {
  it("has a Lost passkey section asking for an email with the Midas name", () => {
    const lostPasskeySections = SUPPORT_PAGE.sections.filter(function isLostPasskey(section) {
      return section.heading === "Lost passkey";
    });
    expect(lostPasskeySections).toHaveLength(1);
    expect(lostPasskeySections[0].paragraphs).toEqual(["Email bhuvanrj73@gmail.com with your Midas name."]);
  });

  it("the served page shows the section with a mail link", async () => {
    const response = await app.request("/support", {}, makeEnv());
    const html = await response.text();
    expect(response.status).toBe(200);
    const expectedSection = `<h2>Lost passkey</h2>\n<p>Email <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a> with your Midas name.</p>`;
    expect(html).toContain(expectedSection);
  });
});
