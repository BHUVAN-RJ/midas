// The jess router's golden set and eval (jess router, founder 2026-10-21, phase 6), with the model
// mocked: the founder runs it live once (scripts/eval-jess.mjs). Every golden case's ideal tool
// call passes the real checks and scores as expected, every tool of both Sidekicks is covered,
// and the scoring, retries, summary and report are right.
import { describe, expect, it } from "vitest";
import { CANNOT_ACT_TOOL, JESS_MODEL, REPAIR_TOOL, outcomeFromToolCall } from "../src/jess";
import { contextFor, formatReport, idealCallFor, loadGolden, main, parseArgs, runEval, scoreCase, summarise } from "../scripts/eval-jess.mjs";

type GoldenCase = { id: string; ctx: string; say: string; call: { tool: string; args: Record<string, unknown> }; expect: Record<string, unknown> };
type Golden = { contexts: Record<string, { sidekicks: Array<{ id: string }> }>; cases: GoldenCase[] };

const golden = loadGolden() as Golden;

function caseBySentence(sentence: string): GoldenCase {
  for (const goldenCase of golden.cases) {
    if (goldenCase.say === sentence) {
      return goldenCase;
    }
  }
  throw new Error("no case says " + sentence);
}

function toolCallReply(name: string, argumentsText: string) {
  const payload = {
    choices: [{ message: { role: "assistant", content: null, tool_calls: [{ id: "c1", type: "function", function: { name, arguments: argumentsText } }] } }],
    usage: { prompt_tokens: 3000, completion_tokens: 60, cost: 0.0003 },
  };
  return new Response(JSON.stringify(payload), { status: 200, headers: { "content-type": "application/json" } });
}

function sentenceOf(init: RequestInit): string {
  const body = JSON.parse(String(init.body));
  const userMessage = body.messages[body.messages.length - 1];
  return JSON.parse(userMessage.content).sentence;
}

// A model that answers every sentence with its golden case's ideal call
async function idealModel(_url: string, init: RequestInit) {
  const goldenCase = caseBySentence(sentenceOf(init));
  const call = idealCallFor(goldenCase, contextFor(golden, goldenCase));
  return toolCallReply(call.name, call.argumentsText);
}

function stepClock() {
  let now = 0;
  function tick() {
    now += 250;
    return now;
  }
  return tick;
}

describe("the golden set", () => {
  it("has about 150 sentences with unique ids, in known contexts", () => {
    expect(golden.cases.length).toBeGreaterThanOrEqual(150);
    const ids = new Set<string>();
    for (const goldenCase of golden.cases) {
      expect(ids.has(goldenCase.id)).toBe(false);
      ids.add(goldenCase.id);
      expect(Object.keys(golden.contexts)).toContain(goldenCase.ctx);
    }
  });

  it("covers every tool of both Sidekicks, repairs of both and every cannot-act reason", () => {
    const called = new Set<string>();
    const repaired = new Set<unknown>();
    const reasons = new Set<unknown>();
    for (const goldenCase of golden.cases) {
      called.add(goldenCase.call.tool);
      if (goldenCase.call.tool === REPAIR_TOOL) {
        repaired.add(goldenCase.call.args.sidekick);
      }
      if (goldenCase.call.tool === CANNOT_ACT_TOOL) {
        reasons.add(goldenCase.call.args.reason);
      }
    }
    const context = contextFor(golden, golden.cases[0]);
    for (const sidekick of context.sidekicks) {
      for (const tool of sidekick.agent.tools) {
        expect(called.has(tool.name), tool.name).toBe(true);
      }
    }
    expect([...repaired].sort()).toEqual(["care-reminders", "reminders"]);
    expect([...reasons].sort()).toEqual(["no-tool-fits", "not-a-request", "not-confident", "question", "two-match"]);
  });

  it("scores every ideal call as expected through the real checks and date resolver", () => {
    const misses: string[] = [];
    for (const goldenCase of golden.cases) {
      const context = contextFor(golden, goldenCase);
      const outcome = outcomeFromToolCall(idealCallFor(goldenCase, context), context);
      const score = scoreCase(goldenCase.expect, outcome);
      if (!score.pass || !score.title || !score.reasonMatches) {
        misses.push(goldenCase.id + " " + JSON.stringify(score.wrongFields));
      }
    }
    expect(misses).toEqual([]);
  });
});

describe("scoring one case", () => {
  const add = caseBySentence("remind me to call the bank tomorrow at 9am");
  const context = contextFor(golden, add);

  function outcomeWith(argumentsValue: Record<string, unknown>, tool = "reminders__add") {
    const ideal = JSON.parse(idealCallFor(add, context).argumentsText);
    return outcomeFromToolCall({ name: tool, argumentsText: JSON.stringify({ ...ideal, ...argumentsValue }) }, context);
  }

  it("fails a wrong time, list or tool, and counts a different title apart", () => {
    const ideal = JSON.parse(idealCallFor(add, context).argumentsText);
    const wrongTime = scoreCase(add.expect, outcomeWith({ when: { ...ideal.when, time: "10:00" } }));
    expect(wrongTime).toMatchObject({ pass: false, wrongFields: ["when"] });
    const wrongList = scoreCase(add.expect, outcomeWith({ list: "Work" }));
    expect(wrongList).toMatchObject({ pass: false, wrongFields: ["list"] });
    const otherTitle = scoreCase(add.expect, outcomeWith({ title: "Phone the bank" }));
    expect(otherTitle).toMatchObject({ pass: true, title: false, wrongFields: ["title"] });
    const sameTitle = scoreCase(add.expect, outcomeWith({ title: "call the bank." }));
    expect(sameTitle).toMatchObject({ pass: true, title: true });
    const wrongTool = scoreCase(add.expect, { status: "done", sidekickId: "care-reminders", tool: "care-reminders.add", input: {} });
    expect(wrongTool).toMatchObject({ pass: false, wrongFields: ["tool:care-reminders.add"] });
  });

  it("passes not-done whatever the reason and reports the reason; a repair must name the right Sidekick", () => {
    const notDone = { status: "not-done", reason: "question" };
    expect(scoreCase(notDone, { status: "not-done", reason: "no-tool-fits", transcript: "x" })).toMatchObject({ pass: true, reasonMatches: false });
    expect(scoreCase(notDone, { status: "done", sidekickId: "reminders", tool: "reminders.add", input: {} })).toMatchObject({ pass: false });
    const repair = { status: "repair", sidekick: "reminders", kind: "bug" };
    expect(scoreCase(repair, { status: "repair", sidekickId: "reminders", kind: "change", request: "x" })).toMatchObject({ pass: true, reasonMatches: false });
    expect(scoreCase(repair, { status: "repair", sidekickId: "care-reminders", kind: "bug", request: "x" })).toMatchObject({ pass: false });
    expect(scoreCase(add.expect, { status: "not-done", reason: "past", transcript: "x" })).toMatchObject({ pass: false, wrongFields: ["status:not-done:past"] });
  });
});

describe("a run with the model mocked", () => {
  it("scores the ideal model at 100% and sends the route's own request", async () => {
    const seen: Array<{ url: string; init: RequestInit }> = [];
    async function recordingModel(url: string, init: RequestInit) {
      seen.push({ url, init });
      return idealModel(url, init);
    }
    const run = await runEval({ golden, reasoning: "off", apiKey: "sk-or-test", fetchImpl: recordingModel, clock: stepClock(), concurrency: 3 });
    expect(run.model).toBe(JESS_MODEL);
    expect(run.summary).toMatchObject({ total: golden.cases.length, passRate: 1, doneRate: 1, repairRate: 1, notDoneRate: 1, notDoneReasonRate: 1, titleRate: 1, wrongActions: 0, errors: 0, retried: 0 });
    expect(run.summary.totalCost).toBeCloseTo(0.0003 * golden.cases.length, 8);
    expect(seen).toHaveLength(golden.cases.length);
    const body = JSON.parse(String(seen[0].init.body));
    expect(seen[0].url).toBe("https://openrouter.ai/api/v1/chat/completions");
    expect(body.model).toBe(JESS_MODEL);
    expect(body.tool_choice).toBe("required");
    expect((seen[0].init.headers as Record<string, string>).authorization).toBe("Bearer sk-or-test");
  });

  it("counts a model that always acts on Call Mom as a wrong action everywhere else", async () => {
    async function deletingModel() {
      return toolCallReply("reminders__delete", JSON.stringify({ item: "Call Mom" }));
    }
    const homeCases: GoldenCase[] = [];
    for (const goldenCase of golden.cases) {
      if (goldenCase.ctx !== "care") {
        homeCases.push(goldenCase);
      }
    }
    const run = await runEval({ golden, reasoning: "off", apiKey: "k", fetchImpl: deletingModel, clock: stepClock(), cases: homeCases });
    const deletesCallMom = caseBySentence("delete call mom");
    expect(run.summary.passRate).toBeCloseTo(1 / homeCases.length, 8);
    expect(run.summary.wrongActions).toBe(homeCases.length - 1);
    expect(run.results.find((result: { id: string }) => result.id === deletesCallMom.id).score.pass).toBe(true);
    expect(formatReport([run], "2026-10-21T00:00:00Z")).toContain("| ra-01 | add bread to my grocery list | tool:reminders.delete |");
  });

  it("tries a busy model once more, then counts it as a model error", async () => {
    let calls = 0;
    async function busyModel() {
      calls += 1;
      return new Response("busy", { status: 503 });
    }
    const one = [caseBySentence("add bread to my grocery list")];
    const run = await runEval({ golden, reasoning: "off", apiKey: "k", fetchImpl: busyModel, clock: stepClock(), cases: one });
    expect(calls).toBe(2);
    expect(run.results[0]).toMatchObject({ attempts: 2, error: "HTTP 503", outcome: { status: "not-done", reason: "model-error" } });
    expect(run.summary).toMatchObject({ errors: 1, retried: 1, passRate: 0, wrongActions: 0 });
  });

  it("summarises an empty run without dividing by zero", () => {
    expect(summarise([])).toMatchObject({ total: 0, passRate: 0, p50Ms: null, costPerSentence: 0 });
  });
});

describe("the command line", () => {
  it("defaults to reasoning off, as the route, and refuses bad options", () => {
    expect(parseArgs([])).toMatchObject({ reasoning: "off", concurrency: 4, limit: null, only: null, timeoutMs: 60000 });
    expect(parseArgs(["--reasoning", "both", "--only", "rx-", "--limit", "5", "--timeout", "30"])).toMatchObject({ reasoning: "both", only: "rx-", limit: 5, timeoutMs: 30000 });
    expect(() => parseArgs(["--reasoning", "high"])).toThrow("--reasoning is off, low or both");
    expect(() => parseArgs(["--fast"])).toThrow("unknown option --fast");
  });

  it("needs the OpenRouter key and calls nothing without it", async () => {
    let calls = 0;
    async function anyModel() {
      calls += 1;
      return new Response("{}");
    }
    await expect(main([], {}, anyModel)).rejects.toThrow("OPENROUTER_API_KEY is not set");
    expect(calls).toBe(0);
  });
});
