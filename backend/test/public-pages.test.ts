import { describe, expect, it } from "vitest";
import app from "../src/index";
import { PRIVACY_PAGE, SUPPORT_EMAIL, SUPPORT_PAGE, escapeHtml, renderPage } from "../src/public-pages";
import { makeFakeR2 } from "../test/helpers/fake-r2";
import { makeMigratedD1 } from "../test/helpers/migrated-d1";

// The privacy policy and support pages App Store Connect links to (build 22, founder 2026-10-31):
// served by the Worker at /privacy and /support, no sign-in, contact bhuvanrj73@gmail.com.

function makeEnv() {
  return { DB: makeMigratedD1(), BUNDLES: makeFakeR2() };
}

async function fetchPage(path: string) {
  const response = await app.request(path, {}, makeEnv());
  const html = await response.text();
  return { response, html };
}

function pageText(page: typeof PRIVACY_PAGE): string {
  const parts: string[] = [page.title];
  for (const section of page.sections) {
    parts.push(section.heading, ...(section.paragraphs ?? []), ...(section.bullets ?? []));
  }
  return parts.join("\n");
}

describe("public pages", () => {
  it("/privacy is an HTML page with no sign-in, the contact and the 7-day deletion", async () => {
    const { response, html } = await fetchPage("/privacy");
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toContain("text/html");
    expect(html).toContain("<title>Midas Privacy Policy</title>");
    expect(html).toContain(`<a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>`);
    expect(SUPPORT_EMAIL).toBe("bhuvanrj73@gmail.com");
    expect(html).toContain("Effective 2026-10-31");
    expect(html).toContain("deleted within 7 days");
    expect(html).toContain("Audio never leaves your iPhone.");
  });

  it("/support names the email and how to edit and delete", async () => {
    const { response, html } = await fetchPage("/support");
    expect(response.status).toBe(200);
    expect(html).toContain("<title>Midas Support</title>");
    expect(html).toContain(`mailto:${SUPPORT_EMAIL}`);
    expect(html).toContain("Edit a Sidekick");
    expect(html).toContain("Delete your account");
  });

  it("the pages load nothing from anywhere else and run no script", async () => {
    for (const path of ["/privacy", "/support"]) {
      const { response, html } = await fetchPage(path);
      expect(html).not.toMatch(/<script/i);
      expect(html).not.toMatch(/src=|<link/i);
      expect(response.headers.get("Content-Security-Policy")).toContain("default-src 'none'");
    }
  });

  it("no placeholder or Repair wording reaches a public page", () => {
    for (const page of [PRIVACY_PAGE, SUPPORT_PAGE]) {
      const text = pageText(page);
      expect(text).not.toMatch(/FOUNDER FILLS|TODO|TBD|\[|lorem/i);
      expect(text).not.toMatch(/\brepair/i);
      expect(text).not.toMatch(/\bbeta\b/i);
    }
  });

  it("page text is escaped", () => {
    expect(escapeHtml(`<a href="x">&'`)).toBe("&lt;a href=&quot;x&quot;&gt;&amp;&#39;");
    const html = renderPage({ title: "<b>", sections: [{ heading: "h", paragraphs: ["<script>"] }] });
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });

  it("other paths are not answered by the pages", async () => {
    const { response } = await fetchPage("/privacy/extra");
    expect(response.status).toBe(404);
  });
});
