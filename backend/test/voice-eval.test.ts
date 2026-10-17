// The voice-reminders golden set (scripts/voice-golden.json) and the eval script
// (scripts/eval-voice.mjs), run against a mocked OpenRouter: the paid API is never called here
// (brief 2026-10-15: the founder runs the real eval). Spec: midas-intel
// docs/plans/2026-10-13-voice-reminders-v1.md, section 7, and the founder decisions of 2026-10-15
// (DeepSeek only; a failed check is "not done").
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  contextFor,
  formatReport,
  idealReplyFor,
  loadGolden,
  main,
  parseArgs,
  percentile,
  runEval,
  scoreCase,
  summarise,
} from "../scripts/eval-voice.mjs";
import { buildPrompt, buildReplySchema, replyShapeProblem, resolveReply } from "../src/voice.ts";

const golden = loadGolden();

type FetchCall = { url: string; init: { headers: Record<string, string>; body: string } };

// A fake OpenRouter: answers each request with `answerFor(body)` and records every call
function makeFakeOpenRouter(answerFor: (body: any) => { status?: number; content?: string; cost?: number; throws?: Error }) {
  const calls: FetchCall[] = [];
  async function fakeFetch(url: string, init: FetchCall["init"]) {
    calls.push({ url, init });
    const body = JSON.parse(init.body);
    const answer = answerFor(body);
    if (answer.throws) {
      throw answer.throws;
    }
    const status = answer.status ?? 200;
    const payload = {
      choices: [{ message: { content: answer.content } }],
      usage: { prompt_tokens: 800, completion_tokens: 80, cost: answer.cost },
    };
    return { ok: status >= 200 && status < 300, status, json: async () => payload };
  }
  return { fakeFetch, calls };
}

function sentenceOf(body: any): string {
  return JSON.parse(body.messages[1].content).sentence;
}

// The golden case a request is about: same sentence and the very same system prompt
function goldenCaseForRequest(body: any) {
  const system: string = body.messages[0].content;
  const sentence = sentenceOf(body);
  for (const goldenCase of golden.cases) {
    if (goldenCase.say !== sentence) {
      continue;
    }
    const expectedSystem = buildPrompt(contextFor(golden, goldenCase)).system;
    if (expectedSystem === system) {
      return goldenCase;
    }
  }
  throw new Error("the fake model was asked about a sentence that is not in the golden set");
}

// A model that always gives the ideal reply for the case it was asked about
function idealAnswer(body: any) {
  const goldenCase = goldenCaseForRequest(body);
  return { content: JSON.stringify(idealReplyFor(goldenCase)), cost: 0.0002 };
}

// A clock that moves 100 ms per reading, so every call takes exactly 100 ms
function makeSteppingClock() {
  let now = 0;
  function readClock() {
    now += 100;
    return now;
  }
  return readClock;
}

describe("golden set", () => {
  it("has exactly 300 sentences with unique ids", () => {
    expect(golden.cases.length).toBe(300);
    const ids = new Set<string>();
    for (const goldenCase of golden.cases) {
      ids.add(goldenCase.id);
    }
    expect(ids.size).toBe(300);
  });

  it("notes its sources and their licences in the header", () => {
    expect(golden.header.sources).toContain("MASSIVE");
    expect(golden.header.sources).toContain("CC BY 4.0");
    expect(golden.header.sources).toContain("TOPv2");
    expect(golden.header.sources).toContain("CC BY-SA 4.0");
  });

  it("gives every context a real now, a time zone and lists", () => {
    for (const context of Object.values<any>(golden.contexts)) {
      expect(Number.isNaN(Date.parse(context.now))).toBe(false);
      expect(typeof context.timeZone).toBe("string");
      expect(Array.isArray(context.lists)).toBe(true);
    }
  });

  it("covers every hand-written kind of case from section 7", () => {
    const sentences: string[] = [];
    const prefixes = new Map<string, number>();
    for (const goldenCase of golden.cases) {
      sentences.push(goldenCase.say);
      const kind = goldenCase.id.split("-")[1];
      prefixes.set(kind, (prefixes.get(kind) ?? 0) + 1);
    }
    const allText = sentences.join("\n");
    expect(prefixes.get("dst")).toBeGreaterThanOrEqual(15);
    expect(prefixes.get("fri")).toBeGreaterThanOrEqual(8);
    expect(prefixes.get("hr")).toBeGreaterThanOrEqual(30);
    expect(prefixes.get("rep")).toBeGreaterThanOrEqual(25);
    expect(prefixes.get("list")).toBeGreaterThanOrEqual(20);
    expect(prefixes.get("nr")).toBeGreaterThanOrEqual(10);
    expect((prefixes.get("me") ?? 0) + (prefixes.get("leap") ?? 0)).toBeGreaterThanOrEqual(10);
    expect(allText).toContain("7-Eleven");
    expect(allText).toContain("tonight");
    expect(allText).toContain("note");
  });

  it("has an ideal reply for every case that fits the strict schema's shape", () => {
    for (const goldenCase of golden.cases) {
      const reply = idealReplyFor(goldenCase);
      expect(replyShapeProblem(reply), goldenCase.id).toBe(null);
      const schema = buildReplySchema(golden.contexts[goldenCase.ctx].lists);
      expect(Object.keys(reply).sort(), goldenCase.id).toEqual(Object.keys(schema.schema.properties).sort());
      const allowedLists = (schema.schema.properties as any).listId.enum;
      expect(allowedLists, goldenCase.id).toContain(reply.listId);
    }
  });

  it("resolves every ideal reply to exactly the expected result (the labels and the rules agree)", () => {
    const disagreements: string[] = [];
    for (const goldenCase of golden.cases) {
      const outcome = resolveReply(idealReplyFor(goldenCase), contextFor(golden, goldenCase));
      const score = scoreCase(goldenCase.expect, outcome);
      const reasonWrong = goldenCase.expect.status === "not-done" && !score.reasonMatches;
      if (!score.pass || !score.notes || reasonWrong) {
        disagreements.push(goldenCase.id + " " + score.wrongFields.join(","));
      }
    }
    expect(disagreements).toEqual([]);
  });
});

describe("scoreCase", () => {
  const expected = { title: "Call mom", date: "2026-10-15", time: "18:00", repeat: { every: "week", weekdays: [1, 3] }, list: "list:work" };
  function doneWith(fields: Record<string, unknown>) {
    const reminder = { title: "call Mom.", notes: null, list: "list:work", date: "2026-10-15", time: "18:00", allDay: false, at: "x", repeat: { every: "week", weekdays: [3, 1] }, timeZone: "UTC" };
    return { status: "done", reminder: { ...reminder, ...fields } };
  }

  it("passes when date, time, repeat and list match and the title matches after normalising", () => {
    const score = scoreCase(expected, doneWith({}));
    expect(score).toMatchObject({ exact: true, title: true, pass: true, wrongFields: [] });
  });

  it("names each wrong field", () => {
    expect(scoreCase(expected, doneWith({ date: "2026-10-16" })).wrongFields).toEqual(["date"]);
    expect(scoreCase(expected, doneWith({ time: "06:00" })).wrongFields).toEqual(["time"]);
    expect(scoreCase(expected, doneWith({ repeat: { every: "week", interval: 2, weekdays: [1, 3] } })).wrongFields).toEqual(["repeat"]);
    expect(scoreCase(expected, doneWith({ list: null })).wrongFields).toEqual(["list"]);
    const wrongTitle = scoreCase(expected, doneWith({ title: "Call dad" }));
    expect(wrongTitle).toMatchObject({ exact: true, title: false, pass: false, wrongFields: ["title"] });
  });

  it("treats interval 1 and no interval as the same repeat", () => {
    const daily = { title: "Walk", date: "2026-10-15", time: "08:00", repeat: { every: "day" } };
    const score = scoreCase(daily, doneWith({ title: "Walk", time: "08:00", list: null, repeat: { every: "day", interval: 1, weekdays: [] } }));
    expect(score.pass).toBe(true);
  });

  it("fails a reminder that was expected not to be done, and passes a not-done with any reason", () => {
    const notDoneExpected = { status: "not-done", reason: "past" };
    expect(scoreCase(notDoneExpected, doneWith({})).pass).toBe(false);
    const otherReason = scoreCase(notDoneExpected, { status: "not-done", reason: "bad-date", transcript: "x" });
    expect(otherReason).toMatchObject({ pass: true, reasonMatches: false });
    const sameReason = scoreCase(notDoneExpected, { status: "not-done", reason: "past", transcript: "x" });
    expect(sameReason).toMatchObject({ pass: true, reasonMatches: true });
  });

  it("fails a not-done when a reminder was expected", () => {
    const score = scoreCase(expected, { status: "not-done", reason: "bad-reply", transcript: "x" });
    expect(score).toMatchObject({ pass: false, exact: false, wrongFields: ["status:bad-reply"] });
  });
});

describe("runEval with a mocked OpenRouter", () => {
  it("scores 100% when the model gives the ideal reply, and measures latency and cost", async () => {
    const { fakeFetch, calls } = makeFakeOpenRouter(idealAnswer);
    const run = await runEval({ golden, reasoning: "off", apiKey: "test-key", fetchImpl: fakeFetch, clock: makeSteppingClock(), concurrency: 1 });
    expect(calls.length).toBe(300);
    expect(run.summary.total).toBe(300);
    expect(run.summary.exactRate).toBe(1);
    expect(run.summary.passRate).toBe(1);
    expect(run.summary.notDoneReasonRate).toBe(1);
    expect(run.summary.errors).toBe(0);
    expect(run.summary.p50Ms).toBe(100);
    expect(run.summary.p95Ms).toBe(100);
    expect(run.summary.totalCost).toBeCloseTo(0.06, 10);
  });

  it("sends DeepSeek, strict JSON, temperature 0, no data collection, and the key as a bearer token", async () => {
    const { fakeFetch, calls } = makeFakeOpenRouter(idealAnswer);
    await runEval({ golden, reasoning: "low", apiKey: "test-key", fetchImpl: fakeFetch, cases: golden.cases.slice(0, 1) });
    const call = calls[0];
    const body = JSON.parse(call.init.body);
    expect(call.url).toBe("https://openrouter.ai/api/v1/chat/completions");
    expect(call.init.headers.authorization).toBe("Bearer test-key");
    expect(body.model).toBe("deepseek/deepseek-v4-flash");
    expect(body.temperature).toBe(0);
    expect(body.response_format.json_schema.strict).toBe(true);
    expect(body.provider).toEqual({ require_parameters: true, data_collection: "deny" });
    expect(body.reasoning).toEqual({ effort: "low" });
  });

  it("counts a wrong time, a non-JSON reply, an HTTP error and a timeout as failures", async () => {
    const chosen = [golden.cases[0], golden.cases[1], golden.cases[2], golden.cases[3]];
    function brokenAnswer(body: any) {
      const sentence = sentenceOf(body);
      if (sentence === chosen[0].say) {
        const reply = idealReplyFor(chosen[0]);
        return { content: JSON.stringify({ ...reply, minutesFromNow: reply.minutesFromNow + 5 }), cost: 0.0001 };
      }
      if (sentence === chosen[1].say) {
        return { content: "Sure, here you go", cost: 0.0001 };
      }
      if (sentence === chosen[2].say) {
        return { status: 500 };
      }
      const abort = new Error("aborted");
      abort.name = "AbortError";
      return { throws: abort };
    }
    const { fakeFetch } = makeFakeOpenRouter(brokenAnswer);
    const run = await runEval({ golden, reasoning: "off", apiKey: "k", fetchImpl: fakeFetch, clock: makeSteppingClock(), cases: chosen, concurrency: 2 });
    const [wrongTime, notJson, httpError, timeout] = run.results;
    expect(wrongTime.score.wrongFields).toEqual(["time"]);
    expect(notJson.outcome).toMatchObject({ status: "not-done", reason: "bad-reply" });
    expect(httpError.error).toBe("HTTP 500");
    expect(httpError.outcome).toMatchObject({ reason: "model-error" });
    expect(timeout.error).toBe("timeout");
    expect(run.summary.passRate).toBe(0);
    expect(run.summary.errors).toBe(2);
    expect(run.summary.wrongFieldCounts).toEqual({ time: 1, status: 3 });
  });
});

describe("summary, report and command line", () => {
  it("takes nearest-rank percentiles", () => {
    const latencies = [];
    for (let value = 1; value <= 20; value += 1) {
      latencies.push(value * 10);
    }
    expect(percentile(latencies, 0.5)).toBe(100);
    expect(percentile(latencies, 0.95)).toBe(190);
    expect(percentile([], 0.5)).toBe(null);
  });

  it("writes the measures into the report", () => {
    const results = [{ id: "A-1", say: "remind me at 6", score: { kind: "done", exact: false, title: true, notes: true, pass: false, reasonMatches: true, wrongFields: ["time"] }, outcome: { status: "done", reminder: { title: "X", date: "2026-10-14", time: "06:00", repeat: null, list: null } }, latencyMs: 900, cost: 0.0003, error: null }];
    const report = formatReport([{ model: "deepseek/deepseek-v4-flash", reasoning: "off", results, summary: summarise(results) }], "2026-10-15T00:00:00.000Z");
    expect(report).toContain("deepseek/deepseek-v4-flash, reasoning off");
    expect(report).toContain("| Exact (date, time, repeat, list) | 0.0% |");
    expect(report).toContain("| Latency p50 / p95 | 900 ms / 900 ms |");
    expect(report).toContain("| A-1 | remind me at 6 | time | X / 2026-10-14 06:00 |");
  });

  it("reads its options and refuses unknown ones", () => {
    expect(parseArgs(["--reasoning", "low", "--limit", "5", "--only", "A-"])).toMatchObject({ reasoning: "low", limit: 5, only: "A-" });
    expect(() => parseArgs(["--reasoning", "high"])).toThrow(/off, low or both/);
    expect(() => parseArgs(["--model", "x"])).toThrow(/unknown option/);
  });

  it("refuses to run without OPENROUTER_API_KEY", async () => {
    const { fakeFetch, calls } = makeFakeOpenRouter(idealAnswer);
    await expect(main([], {}, fakeFetch)).rejects.toThrow(/OPENROUTER_API_KEY/);
    expect(calls.length).toBe(0);
  });

  it("runs both reasoning modes on the chosen cases and writes the .md and .json report", async () => {
    const { fakeFetch, calls } = makeFakeOpenRouter(idealAnswer);
    const folder = mkdtempSync(join(tmpdir(), "voice-eval-"));
    const prefix = join(folder, "report");
    const finished = await main(["--only", "H-", "--out", prefix], { OPENROUTER_API_KEY: "k" }, fakeFetch);
    expect(finished.runs.length).toBe(2);
    expect(calls.length).toBe(2 * finished.runs[0].results.length);
    expect(existsSync(prefix + ".md")).toBe(true);
    const saved = JSON.parse(readFileSync(prefix + ".json", "utf8"));
    expect(saved.runs[0].reasoning).toBe("off");
    expect(saved.runs[1].reasoning).toBe("low");
    expect(saved.runs[0].summary.passRate).toBe(1);
  });
});
