// A JSON body without an error message (a normal reply shape) adds nothing to the logged refusal:
// only the status is kept (2026-10-22, keeps "HTTP 400" for a refused request).
import { describe, expect, it } from "vitest";
import { openRouterErrorText } from "../src/voice-route";

describe("openRouterErrorText with a JSON body that is not an error", () => {
  it("keeps only the status", async () => {
    const response = new Response(JSON.stringify({ choices: [] }), { status: 400 });
    expect(await openRouterErrorText(response)).toBe("HTTP 400");
  });
});
