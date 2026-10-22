import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { buildJessRequest, parseSidekick } from "../src/jess";
import type { JessContext, JessSidekick } from "../src/jess";
import { buildOpenRouterRequest } from "../src/voice";

// With provider.require_parameters true, one parameter a provider does not list in its
// supported_parameters drops that provider; one no provider lists gives OpenRouter
// "HTTP 404: No endpoints found" (bug 2026-10-22: parallel_tool_calls on deepseek-v4-flash).
// The top-level keys allowed: OpenRouter's own routing fields plus the parameters every
// deepseek/deepseek-v4-flash provider lists (GET /api/v1/models/deepseek/deepseek-v4-flash/endpoints).
const ROUTING_KEYS = ["model", "messages", "provider", "usage"];
const PARAMETERS_EVERY_PROVIDER_LISTS = ["tools", "tool_choice", "temperature", "max_tokens", "reasoning", "response_format"];
const ALLOWED_KEYS = new Set([...ROUTING_KEYS, ...PARAMETERS_EVERY_PROVIDER_LISTS]);

const NOW = "2026-10-20T17:00:00.000Z";
const ZONE = "America/Los_Angeles";
const REPO_ROOT = join(__dirname, "..", "..");

function agentOf(sidekickId: string) {
  return JSON.parse(readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8")).agent;
}

function jessContext(grow: boolean): JessContext {
  const sent = { id: "reminders", name: "Reminders", version: "v5", agent: agentOf("reminders"), context: { lists: ["Groceries"], items: [] } };
  const parsed = parseSidekick(sent);
  if (parsed === null) {
    throw new Error("reminders did not parse");
  }
  const sidekicks: JessSidekick[] = [parsed];
  return { transcript: "add milk", now: NOW, timeZone: ZONE, locale: "en-US", sidekicks, grow };
}

function keysOutsideAllowed(request: object): string[] {
  const outside: string[] = [];
  for (const key of Object.keys(request)) {
    if (!ALLOWED_KEYS.has(key)) {
      outside.push(key);
    }
  }
  return outside;
}

describe("OpenRouter requests send only parameters every provider supports", () => {
  for (const reasoning of ["off", "low"] as const) {
    it(`jess request, reasoning ${reasoning}, with and without grow`, () => {
      expect(keysOutsideAllowed(buildJessRequest(jessContext(false), { reasoning }))).toEqual([]);
      expect(keysOutsideAllowed(buildJessRequest(jessContext(true), { reasoning }))).toEqual([]);
    });

    it(`voice reminder request, reasoning ${reasoning}`, () => {
      const context = { transcript: "add milk", now: NOW, timeZone: ZONE, locale: "en-US", lists: [{ id: "l1", name: "Groceries" }] };
      expect(keysOutsideAllowed(buildOpenRouterRequest(context, { reasoning }))).toEqual([]);
    });
  }

  it("keeps require_parameters on, so the allowlist above is what decides routing", () => {
    expect(buildJessRequest(jessContext(false), { reasoning: "off" }).provider.require_parameters).toBe(true);
  });
});
