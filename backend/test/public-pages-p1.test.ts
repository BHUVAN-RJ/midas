import { describe, expect, it } from "vitest";
import app from "../src/index";
import { PRIVACY_PAGE, SUPPORT_EMAIL, SUPPORT_PAGE, escapeHtml, renderPage } from "../src/public-pages";
import { makeFakeR2 } from "../test/helpers/fake-r2";
import { makeMigratedD1 } from "../test/helpers/migrated-d1";

// The P1 "Plain" look for /privacy and /support (founder, 2026-11-01; mockup
// docs/mockups/public-pages-2026-10-31.html): DESIGN.md colours light and dark, the written Midas
// wordmark drawn inline, short bullet labels in semibold, a Privacy / Support footer. Words unchanged.

function makeEnv() {
  return { DB: makeMigratedD1(), BUNDLES: makeFakeR2() };
}

async function fetchHtml(path: string): Promise<string> {
  const response = await app.request(path, {}, makeEnv());
  return response.text();
}

function styleOf(html: string): string {
  const match = html.match(/<style>([\s\S]*?)<\/style>/);
  return match === null ? "" : match[1];
}

function darkBlockOf(style: string): string {
  const start = style.indexOf("@media (prefers-color-scheme:dark)");
  if (start < 0) {
    return "";
  }
  const end = style.indexOf("}}", start);
  return style.slice(start, end + 2);
}

// The page with the markup P1 adds around words taken out: label bold tags and the mail link.
function wordsOf(html: string): string {
  const mailLink = `<a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>`;
  const withoutBold = html.replace(/<\/?b>/g, "");
  return withoutBold.split(mailLink).join(SUPPORT_EMAIL);
}

function everyLineOf(page: typeof PRIVACY_PAGE): string[] {
  const lines: string[] = [page.title];
  for (const section of page.sections) {
    lines.push(section.heading, ...(section.paragraphs ?? []), ...(section.bullets ?? []));
  }
  return lines;
}

describe("public pages, P1 look", () => {
  it("uses the DESIGN.md colours in light and switches to the dark ones with the device", async () => {
    const style = styleOf(await fetchHtml("/privacy"));
    expect(style).toContain("--paper:#FFFFFF");
    expect(style).toContain("--ink:#111111");
    const dark = darkBlockOf(style);
    expect(dark).toContain("--paper:#111111");
    expect(dark).toContain("--ink:#FFFFFF");
    expect(dark).toContain("--ink-2:#A3A3A3");
    expect(style).toContain("background:var(--paper)");
    expect(style).toContain("color:var(--ink)");
  });

  it("loads no URL, font file or image from anywhere: the wordmark is an inline path", async () => {
    for (const path of ["/privacy", "/support"]) {
      const html = await fetchHtml(path);
      expect(html).not.toMatch(/https?:\/\//i);
      expect(html).not.toMatch(/url\(|@import|@font-face|<img/i);
      expect(html).toMatch(/<header class="top"><svg class="mark" viewBox="[^"]+" role="img" aria-label="Midas"><path d="M[^"]{2000,}"\/><\/svg><\/header>/);
    }
  });

  it("sets a short label before a colon in semibold, and leaves other bullets plain", async () => {
    const html = await fetchHtml("/privacy");
    expect(html).toContain("<li><b>Account:</b> the name you type when you start");
    expect(html).toContain("<li><b>Apple Reminders:</b> if you tap Import");
    expect(html).toContain("<li><b>Device details:</b> iPhone model");
    expect(html).toContain("<li>Your voice is turned into text on your iPhone.");
    expect(styleOf(html)).toContain(".doc li b{font-weight:600}");
    const long = renderPage({ title: "t", sections: [{ heading: "h", bullets: ["This lead is far too long for a label: rest"] }] });
    expect(long).toContain("<li>This lead is far too long for a label: rest</li>");
  });

  it("keeps every word of both pages, headings in the order of the source", async () => {
    for (const [path, page] of [["/privacy", PRIVACY_PAGE], ["/support", SUPPORT_PAGE]] as const) {
      const words = wordsOf(await fetchHtml(path));
      for (const line of everyLineOf(page)) {
        expect(words, line).toContain(escapeHtml(line));
      }
      let from = 0;
      for (const section of page.sections) {
        const at = words.indexOf(`<h2>${escapeHtml(section.heading)}</h2>`, from);
        expect(at, section.heading).toBeGreaterThanOrEqual(from);
        from = at;
      }
    }
  });

  it("puts each section in its own block, one per source section", async () => {
    for (const [path, page] of [["/privacy", PRIVACY_PAGE], ["/support", SUPPORT_PAGE]] as const) {
      const html = await fetchHtml(path);
      const blocks = html.match(/<section>/g) ?? [];
      expect(blocks.length).toBe(page.sections.length);
      expect(html).toContain('<main class="doc">');
    }
  });

  it("ends with a Privacy / Support footer that marks the page you are on", async () => {
    const privacy = await fetchHtml("/privacy");
    expect(privacy).toContain('<footer class="foot"><a href="/privacy" aria-current="page">Privacy</a><a href="/support">Support</a><span class="copy-note">© 2026 Midas</span></footer>');
    const support = await fetchHtml("/support");
    expect(support).toContain('<a href="/privacy">Privacy</a><a href="/support" aria-current="page">Support</a>');
  });
});
