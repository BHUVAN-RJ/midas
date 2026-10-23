// The voice log keeps OpenRouter's reason for a refusal, not only the status (2026-10-22: staging
// showed only "HTTP 404", which did not say what OpenRouter objected to).
import { describe, expect, it } from "vitest";
import { openRouterErrorText } from "../src/voice-route";

describe("openRouterErrorText", () => {
  it("keeps the message from OpenRouter's JSON error", async () => {
    const response = new Response(JSON.stringify({ error: { message: "No endpoints found matching your data policy" } }), { status: 404 });
    expect(await openRouterErrorText(response)).toBe("HTTP 404: No endpoints found matching your data policy");
  });

  it("keeps a plain-text body and shortens a long one", async () => {
    const response = new Response("x".repeat(500), { status: 502 });
    const text = await openRouterErrorText(response);
    expect(text.startsWith("HTTP 502: x")).toBe(true);
    expect(text.length).toBe("HTTP 502: ".length + 300);
  });

  it("falls back to the status when the body is empty", async () => {
    expect(await openRouterErrorText(new Response("", { status: 404 }))).toBe("HTTP 404");
  });
});
