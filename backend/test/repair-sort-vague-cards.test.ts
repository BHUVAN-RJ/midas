import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { CARD_ICONS, FALLBACK_OPTIONS, questionFor } from "../src/repair-sort";
import {
  CARD_OPTIONS_RULE,
  CHAT_URL,
  DECISIONS_URL,
  VAGUE_WORDS_RULE,
  buildHaikuRequest,
  buildJevRequest,
  isConcreteLabel,
  readHaikuOptions,
  sortRequest,
} from "../src/repair-sort-model";
import type { SortInput } from "../src/repair-sort-model";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Vague words ask back, and the card's options are concrete (founder, 2026-11-22; PRODUCT.md D4,
// 2026-11-13). Seen on staging, job d82c7640: To-Do, a row circled, "Make this different"; the
// card offered "Other layout", the person picked it, the repair agent could not act on it. Now:
// Haiku gets a tie-break rule for vague change words and writes 2-3 concrete options; categories
// are dropped; the fixed fallbacks are concrete; any option id the card showed can be answered.
// No network: OpenRouter is a stand-in.

type GoldenCase = { id: string; group: string; transcript: string; expected: string };
const GOLDEN = JSON.parse(readFileSync(new URL("../scripts/sort-golden.json", import.meta.url), "utf8")) as { cases: GoldenCase[] };

const INPUT: SortInput = {
  transcript: "Make this different",
  sidekickName: "To-Do",
  sidekickDescription: "A to-do list.",
  drawing: "1 stroke(s) covering x 105–362, y 136–178 on a 402×874 screen",
  answer: null,
  settingLabels: ["Accent colour (buttons, ticks, Today)", "Spacing between to-dos"],
};

function haikuPrompt(input: SortInput): string {
  const request = buildHaikuRequest(input);
  const messages = request.messages as Array<{ content: string }>;
  return messages[0].content;
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "content-type": "application/json" } });
}

function haikuPayload(content: string) {
  return { choices: [{ message: { content } }], usage: { cost: 0.0001 } };
}

function jevPayload(lane: string, confidence: number, guesses: Record<string, number> = {}) {
  return { answers: { lane: { choice: lane, confidence }, guess: { probabilities: guesses } }, usage: { cost: 0.00003 } };
}

describe("the tie-break rule for vague words", () => {
  it("Haiku's prompt carries the rule after the lanes, naming the vague words", () => {
    const prompt = haikuPrompt(INPUT);
    expect(prompt).toContain(VAGUE_WORDS_RULE);
    expect(prompt.indexOf(VAGUE_WORDS_RULE)).toBeGreaterThan(prompt.indexOf("- code:"));
    for (const words of ["make this different", "change this", "fix this", "make it better", "I don't like this", "do something with this"]) {
      expect(VAGUE_WORDS_RULE).toContain(`"${words}"`);
    }
    expect(VAGUE_WORDS_RULE).toContain("are ask_back");
    expect(VAGUE_WORDS_RULE).toContain("are code, not ask_back");
  });

  it("every vague golden case's words are named in the rule", () => {
    const vague = GOLDEN.cases.filter(function isVague(goldenCase) { return goldenCase.group === "vague"; });
    expect(vague.length).toBeGreaterThanOrEqual(8);
    const ruleLower = VAGUE_WORDS_RULE.toLowerCase();
    for (const goldenCase of vague) {
      expect(goldenCase.expected).toBe("ask_back");
      expect(ruleLower).toContain(`"${goldenCase.transcript.toLowerCase()}"`);
    }
    const concrete = GOLDEN.cases.filter(function isConcrete(goldenCase) { return goldenCase.group === "concrete"; });
    expect(concrete.length).toBeGreaterThanOrEqual(8);
    for (const goldenCase of concrete) {
      expect(goldenCase.expected).not.toBe("ask_back");
    }
  });

  it("Haiku is asked for concrete card options and gets the Sidekick's catalogue labels", () => {
    const prompt = haikuPrompt(INPUT);
    expect(prompt).toContain(CARD_OPTIONS_RULE);
    expect(prompt).toContain('"options": [{"label": "...", "kind": "..."}]');
    expect(prompt).toContain("Accent colour (buttons, ticks, Today); Spacing between to-dos");
  });

  it("Jev's request stays as benchmarked: no rule, no catalogue", () => {
    const state = String(buildJevRequest(INPUT).state);
    expect(state).not.toContain("Tie-break");
    expect(state).not.toContain("Spacing between to-dos");
  });
});

describe("concrete labels", () => {
  it("categories are refused", () => {
    for (const label of ["Other layout", "Other Layout", "A different icon or picture", "Other words", "Other colour", "Different Icon", "Change It", "Title Colour", "Something Else", ""]) {
      expect(isConcreteLabel(label)).toBe(false);
    }
  });

  it("concrete changes pass; too long for the card does not", () => {
    for (const label of ["Checkbox at the Start", "Smaller Rows", "Date Beside the Title", "Red Title", "Smaller", "Remove"]) {
      expect(isConcreteLabel(label)).toBe(true);
    }
    expect(isConcreteLabel("Show the Date and the Time Beside Every Title")).toBe(false);
  });

  it("Haiku's options: categories dropped, repeats dropped, 3 at most, unknown kind drawn as layout", () => {
    const content = JSON.stringify({
      lane: "ask_back",
      options: [
        { label: "Other Layout", kind: "other_layout" },
        { label: "Checkbox at the Start", kind: "other_icon" },
        { label: "checkbox at the start", kind: "other_icon" },
        { label: "Smaller Rows", kind: "smaller" },
        { label: "Date Beside the Title", kind: "made_up" },
        { label: "Red Title", kind: "other_colour" },
      ],
    });
    expect(readHaikuOptions(haikuPayload(content))).toEqual([
      { label: "Checkbox at the Start", kind: "other_icon" },
      { label: "Smaller Rows", kind: "smaller" },
      { label: "Date Beside the Title", kind: "other_layout" },
    ]);
    expect(readHaikuOptions(haikuPayload('{"lane": "code"}'))).toEqual([]);
    expect(readHaikuOptions(null)).toEqual([]);
  });
});

describe("the card", () => {
  it("Haiku's options come first, with their own ids and pictures", () => {
    const question = questionFor(["other_icon"], [
      { label: "Checkbox at the Start", kind: "other_icon" },
      { label: "Smaller Rows", kind: "smaller" },
    ]);
    expect(question.options).toEqual([
      { id: "option-1", label: "Checkbox at the Start", icon: CARD_ICONS.other_icon },
      { id: "option-2", label: "Smaller Rows", icon: CARD_ICONS.smaller },
    ]);
  });

  it("too few written: filled from concrete fallbacks only, never a category", () => {
    const question = questionFor(["other_icon", "other_layout", "other_words", "move"], []);
    const labels = question.options.map(function labelOf(option) { return option.label; });
    expect(labels).toEqual(["Move to the Top", "Smaller", "Bigger"]);
    for (const label of labels) {
      expect(isConcreteLabel(label)).toBe(true);
    }
    for (const label of Object.values(FALLBACK_OPTIONS)) {
      expect(isConcreteLabel(String(label))).toBe(true);
    }
    const oneWritten = questionFor([], [{ label: "Red Title", kind: "other_colour" }]);
    expect(oneWritten.options.map(function idOf(option) { return option.id; })).toEqual(["option-1", "smaller", "bigger"]);
  });
});

describe("the sort writes the card's options", () => {
  it("Jev sure of ask_back: Jev's lane stands and Haiku writes the options", async () => {
    const calls: string[] = [];
    function fakeFetch(url: string): Promise<Response> {
      calls.push(url);
      if (url === DECISIONS_URL) {
        return Promise.resolve(jsonResponse(jevPayload("ask_back", 0.9, { other_layout: 0.6 })));
      }
      const content = JSON.stringify({ lane: "code", guesses: [], options: [{ label: "Smaller Rows", kind: "smaller" }, { label: "Red Title", kind: "other_colour" }] });
      return Promise.resolve(jsonResponse(haikuPayload(content)));
    }
    const result = await sortRequest(INPUT, "key", fakeFetch);
    expect(calls).toEqual([DECISIONS_URL, CHAT_URL]);
    expect(result.lane).toBe("ask_back");
    expect(result.options).toEqual([{ label: "Smaller Rows", kind: "smaller" }, { label: "Red Title", kind: "other_colour" }]);
    expect(result.error).toBeNull();
    expect(result.costUsd).toBeCloseTo(0.00013);
  });

  it("Jev sure of ask_back and Haiku fails: still ask_back, no options, no error", async () => {
    function fakeFetch(url: string): Promise<Response> {
      if (url === DECISIONS_URL) {
        return Promise.resolve(jsonResponse(jevPayload("ask_back", 0.9)));
      }
      return Promise.resolve(jsonResponse({ error: "down" }, 500));
    }
    const result = await sortRequest(INPUT, "key", fakeFetch);
    expect(result.lane).toBe("ask_back");
    expect(result.options).toEqual([]);
    expect(result.error).toBeNull();
  });

  it("the second sort (answered) and other sure lanes do not call Haiku", async () => {
    const calls: string[] = [];
    function fakeFetch(url: string): Promise<Response> {
      calls.push(url);
      return Promise.resolve(jsonResponse(jevPayload("ask_back", 0.9)));
    }
    await sortRequest({ ...INPUT, answer: "Smaller Rows" }, "key", fakeFetch);
    expect(calls).toEqual([DECISIONS_URL]);
  });
});

/* ---------- End to end: the route shows Haiku's options and takes their ids ---------- */

const STROKES = JSON.stringify([[[105, 136, 0], [362, 178, 50]]]);

function makeEnv() {
  const bundles = makeFakeR2({
    "sidekicks/todo/current.json": JSON.stringify({ version: "v1", scriptHashes: [] }),
    "sidekicks/todo/v1/manifest.json": JSON.stringify({
      id: "todo",
      name: "To-Do",
      agent: { description: "A to-do list." },
      settings: { entries: [{ key: "density", label: "Spacing between to-dos", type: "choice", values: ["compact", "roomy"], default: "roomy" }] },
    }),
  });
  return { DB: makeMigratedD1(), BUNDLES: bundles, REPAIR_RUNNER_TOKEN: "runner-secret", OPENROUTER_API_KEY: "test-key" };
}

type TestEnv = ReturnType<typeof makeEnv>;

function addSignedInUser(env: TestEnv, userId: string): string {
  const token = `token-${userId}`;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", tokenHash, userId, Date.now() + 3600000);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'todo', 'now')", userId);
  return token;
}

type ModelCall = { url: string; body: Record<string, unknown> };
let fetchSpy: ReturnType<typeof vi.spyOn>;
let modelCalls: ModelCall[];
let jevAnswers: Array<Record<string, unknown>>;
let haikuAnswers: string[];

function plannedFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const url = String(input);
  modelCalls.push({ url, body: JSON.parse(String(init?.body)) as Record<string, unknown> });
  if (url === DECISIONS_URL) {
    const next = jevAnswers.shift();
    return Promise.resolve(next === undefined ? jsonResponse({}, 500) : jsonResponse(next));
  }
  if (url === CHAT_URL) {
    return Promise.resolve(jsonResponse(haikuPayload(haikuAnswers.shift() ?? "")));
  }
  return Promise.reject(new Error(`unexpected fetch ${url}`));
}

beforeEach(function spyOnFetch() {
  modelCalls = [];
  jevAnswers = [];
  haikuAnswers = [];
  fetchSpy = vi.spyOn(globalThis, "fetch");
  fetchSpy.mockImplementation(plannedFetch);
});

afterEach(function restoreFetch() {
  fetchSpy.mockRestore();
});

describe("POST /repairs and /answer with Haiku's options", () => {
  it("the card shows Haiku's concrete labels, and their id answers with the label", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    jevAnswers.push(jevPayload("ask_back", 0.9, { other_layout: 0.7 }));
    haikuAnswers.push(JSON.stringify({ lane: "ask_back", options: [{ label: "Other Layout", kind: "other_layout" }, { label: "Checkbox at the Start", kind: "other_icon" }, { label: "Smaller Rows", kind: "smaller" }] }));

    const form = new FormData();
    form.set("sidekickId", "todo");
    form.set("kind", "change");
    form.set("transcript", "Make this different");
    form.set("strokes", STROKES);
    const posted = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form }, env);
    const reply = (await posted.json()) as { id: string; lane: string; question?: { options: Array<{ id: string; label: string }> } };

    expect(reply.lane).toBe("ask_back");
    const labels = (reply.question?.options ?? []).map(function labelOf(option) { return option.label; });
    expect(labels).toEqual(["Checkbox at the Start", "Smaller Rows"]);
    const haikuCall = modelCalls.find(function isHaiku(call) { return call.url === CHAT_URL; });
    const prompt = (haikuCall?.body.messages as Array<{ content: string }>)[0].content;
    expect(prompt).toContain("Spacing between to-dos");

    const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
    // An id the card did not show is refused, and the card stays open
    const unknown = await app.request(`/repairs/${reply.id}/answer`, { method: "POST", headers, body: JSON.stringify({ optionId: "option-9" }) }, env);
    expect(unknown.status).toBe(400);

    jevAnswers.push(jevPayload("code", 0.9));
    const answered = await app.request(`/repairs/${reply.id}/answer`, { method: "POST", headers, body: JSON.stringify({ optionId: "option-1" }) }, env);
    expect(answered.status).toBe(200);
    const rows = env.DB.query("SELECT sort_answer FROM repair_reports WHERE id = ?", reply.id);
    expect(rows[0].sort_answer).toBe("Checkbox at the Start");
    const lastJev = modelCalls.filter(function isJev(call) { return call.url === DECISIONS_URL; }).pop();
    expect(String(lastJev?.body.state)).toContain('they answered: "Checkbox at the Start"');

  });
});
