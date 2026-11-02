import { describe, expect, it } from "vitest";
import { PRIVACY_PAGE, renderPage } from "../src/public-pages";

// Privacy page wording decided by the founder on 2026-11-02 (docs/PRODUCT.md, build 22 privacy
// page): Edits by Anthropic's Claude on a Midas server, the voice log goes with the account,
// Cloudflare server logs named, and what account deletion removes (agent/account-deletion).
describe("privacy page wording, 2026-11-02", () => {
  const html = renderPage(PRIVACY_PAGE);

  it("says Edits run on a Midas server, not Midas's own computer", () => {
    expect(html).toContain("Anthropic&#39;s Claude coding assistant on a Midas server");
    expect(html).not.toContain("own computer");
    expect(html).not.toContain("Claude Code");
  });

  it("says the voice log is deleted with the account", () => {
    expect(html).toContain("The log is kept while your account exists and is deleted with it.");
  });

  it("names Cloudflare's server logs and their IP addresses", () => {
    expect(html).toContain("server logs may include your IP address");
  });

  it("lists what account deletion removes and the backup window", () => {
    expect(html).toContain("your Make conversations and your push tokens");
    expect(html).toContain("Database backups can keep a copy for up to 7 more days");
  });
});
