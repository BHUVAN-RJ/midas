import { afterEach, describe, expect, it } from "vitest";
import {
  CHAT_URL,
  DECISIONS_URL,
  GUESSES,
  HAIKU_MODEL,
  JEV_MODEL,
  LANES,
  buildHaikuRequest,
  buildJevRequest,
  describeStrokes,
  readHaikuAnswer,
  readJevAnswer,
  sortCallSettings,
  sortRequest,
} from "../src/repair-sort-model";
import type { SortInput } from "../src/repair-sort-model";

// Repair lanes W2, the sort step (founder, 2026-11-13; docs/briefs/repair-lanes.md). Jev 1.14
// sorts; below 0.7 confidence Haiku 5.5 decides; any timeout or error goes to code. OpenRouter is
// never called here: every fetch is a stand-in.

// The lane and guess wording of the 2026-11-13 benchmark (sort-bench.mjs, 45/46 right), copied
// here on purpose: the Worker's wording must stay the benchmarked wording.
const BENCHMARK_LANES = {
  ask_back: "The person wants something changed, but the words and drawing do not say what it should become. Ask one question.",
  not_a_request: "Chat, a greeting, an apology, an insult or an accidental recording. Nothing to change.",
  shell_cant:
    "Needs something the page cannot do: a notification type (Time Sensitive, custom sound), phone sensors (gyroscope, camera), reminders more often than every 2 hours, Siri, Watch, Lock Screen.",
  jess_command: "Asks to do something with their data (add a reminder, log water, tick a to-do), not to change the app.",
  setting: "A look or visibility change of something already there: colour, size, show or hide, a date format, on or off.",
  look: "A small layout tweak no simple setting covers: spacing, padding, shape, position.",
  code: "A new feature, a new option, changed behaviour, or a bug to fix.",
};
const BENCHMARK_GUESSES = {
  other_icon: "A different icon or picture",
  smaller: "Make it smaller",
  bigger: "Make it bigger",
  other_colour: "A different colour",
  remove: "Remove or hide it",
  move: "Move it somewhere else",
  other_words: "Different words",
  other_layout: "A different shape or layout",
};

const INPUT: SortInput = {
  transcript: "I hate this can you change this",
  sidekickName: "Water",
  sidekickDescription: "daily water goal, reminders",
  drawing: "1 stroke(s) covering x 150–250, y 300–400 on a 402×874 screen",
  answer: null,
};

type Call = { url: string; body: Record<string, unknown> };
type Responder = (url: string, body: Record<string, unknown>, signal: AbortSignal | null) => Promise<Response>;

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "content-type": "application/json" } });
}

function jevPayload(lane: string, confidence: number, guessProbabilities: Record<string, number> = {}, cost = 0.00003) {
  return {
    answers: { lane: { choice: lane, confidence }, guess: { choice: "other_icon", probabilities: guessProbabilities } },
    usage: { cost },
  };
}

function haikuPayload(content: string, cost = 0.0001) {
  return { choices: [{ message: { content } }], usage: { cost } };
}

// A fetch stand-in that records each call and answers with the responder.
function fakeFetch(responder: Responder) {
  const calls: Call[] = [];
  async function fetchStandIn(url: string, init: RequestInit): Promise<Response> {
    const body = JSON.parse(String(init.body)) as Record<string, unknown>;
    calls.push({ url, body });
    return responder(url, body, init.signal ?? null);
  }
  return { fetchStandIn, calls };
}

function urlsOf(calls: Call[]): string[] {
  const urls: string[] = [];
  for (const call of calls) {
    urls.push(call.url);
  }
  return urls;
}

// Never answers; rejects when the caller aborts, the way fetch does.
function hangUntilAborted(signal: AbortSignal | null): Promise<Response> {
  return new Promise(function waitForAbort(_resolve, reject) {
    function rejectOnAbort() {
      const abortError = new Error("The operation was aborted");
      abortError.name = "AbortError";
      reject(abortError);
    }
    signal?.addEventListener("abort", rejectOnAbort);
  });
}

const DEFAULT_TIMEOUT_MS = sortCallSettings.timeoutMs;

afterEach(function restoreTimeout() {
  sortCallSettings.timeoutMs = DEFAULT_TIMEOUT_MS;
});

describe("the wording the models read", () => {
  it("lanes and guesses are the benchmarked wording, word for word", () => {
    expect(LANES).toEqual(BENCHMARK_LANES);
    expect(GUESSES).toEqual(BENCHMARK_GUESSES);
  });

  it("each call waits 6 seconds at most", () => {
    expect(DEFAULT_TIMEOUT_MS).toBe(6000);
  });

  it("Jev gets the words, the Sidekick's name and description and the drawing outline, and two choice questions", () => {
    const request = buildJevRequest(INPUT);
    expect(request.model).toBe("typesafe/jev-1.14");
    const state = String(request.state);
    expect(state).toContain('said: "I hate this can you change this"');
    expect(state).toContain('"Water (daily water goal, reminders)"');
    expect(state).toContain("1 stroke(s) covering x 150–250, y 300–400");
    const questions = request.questions as Record<string, { type: string; criteria: unknown }>;
    expect(Object.keys(questions).sort()).toEqual(["guess", "lane"]);
    expect(questions.lane.type).toBe("choice");
    expect(questions.lane.criteria).toEqual(BENCHMARK_LANES);
    expect(questions.guess.criteria).toEqual(BENCHMARK_GUESSES);
  });

  it("the second sort adds the answer to the same request", () => {
    const request = buildJevRequest({ ...INPUT, answer: "Other icon" });
    expect(String(request.state)).toContain('they answered: "Other icon"');
    expect(String(buildJevRequest(INPUT).state)).not.toContain("answered");
  });

  it("Haiku gets the same lanes and is asked for JSON", () => {
    const request = buildHaikuRequest(INPUT);
    expect(request.model).toBe("anthropic/claude-haiku-5.5");
    const messages = request.messages as Array<{ content: string }>;
    for (const wording of Object.values(BENCHMARK_LANES)) {
      expect(messages[0].content).toContain(wording);
    }
    expect(request.response_format).toEqual({ type: "json_object" });
  });
});

describe("the drawing outline", () => {
  it("counts strokes and gives the box they cover", () => {
    const strokes = JSON.stringify([[[10.4, 20, 0], [30, 40, 50]], [[100, 100.6, 900]]]);
    expect(describeStrokes(strokes)).toBe("2 stroke(s) covering x 10–100, y 20–101 on a 402×874 screen");
  });

  it("says when there is no drawing", () => {
    expect(describeStrokes(null)).toBe("no drawing");
    expect(describeStrokes("[]")).toBe("no drawing (empty)");
    expect(describeStrokes("not json")).toBe("no drawing");
  });
});

describe("reading the answers", () => {
  it("Jev: lane, confidence and guesses by probability", () => {
    const answer = readJevAnswer(jevPayload("ask_back", 0.91, { remove: 0.2, smaller: 0.5, other_icon: 0.3, made_up: 0.9 }));
    expect(answer).toEqual({ lane: "ask_back", confidence: 0.91, guesses: ["smaller", "other_icon", "remove"] });
  });

  it("Jev: a lane that is not one of the seven is no answer", () => {
    expect(readJevAnswer(jevPayload("delete_everything", 0.99))).toBeNull();
  });

  it("Haiku: JSON in the text, unknown guesses dropped", () => {
    const answer = readHaikuAnswer(haikuPayload('Sure. {"lane": "setting", "guesses": ["other_colour", "nonsense", "bigger"]}'));
    expect(answer).toEqual({ lane: "setting", guesses: ["other_colour", "bigger"] });
  });

  it("Haiku: a lane that is not one of the seven is no answer", () => {
    expect(readHaikuAnswer(haikuPayload('{"lane": "magic"}'))).toBeNull();
    expect(readHaikuAnswer(haikuPayload("no json here"))).toBeNull();
  });
});

describe("sortRequest", () => {
  it("Jev at 0.7 or above decides alone: lane, confidence, model, latency and cost", async () => {
    function answerConfidently(): Promise<Response> {
      return Promise.resolve(jsonResponse(jevPayload("setting", 0.7, { other_colour: 0.8, bigger: 0.1 })));
    }
    const { fetchStandIn, calls } = fakeFetch(answerConfidently);
    const result = await sortRequest(INPUT, "key", fetchStandIn);
    expect(calls.length).toBe(1);
    expect(calls[0].url).toBe(DECISIONS_URL);
    expect(result.lane).toBe("setting");
    expect(result.confidence).toBe(0.7);
    expect(result.model).toBe(JEV_MODEL);
    expect(result.guesses).toEqual(["other_colour", "bigger"]);
    expect(result.costUsd).toBeCloseTo(0.00003);
    expect(result.latencyMs).toBeGreaterThanOrEqual(0);
    expect(result.error).toBeNull();
  });

  it("Jev below 0.7: Haiku decides with the same lanes, and its guesses come first", async () => {
    function answerByModel(url: string): Promise<Response> {
      if (url === DECISIONS_URL) {
        return Promise.resolve(jsonResponse(jevPayload("look", 0.69, { smaller: 0.6, remove: 0.3 })));
      }
      return Promise.resolve(jsonResponse(haikuPayload('{"lane": "ask_back", "guesses": ["other_icon"]}')));
    }
    const { fetchStandIn, calls } = fakeFetch(answerByModel);
    const result = await sortRequest(INPUT, "key", fetchStandIn);
    const calledUrls = urlsOf(calls);
    expect(calledUrls).toEqual([DECISIONS_URL, CHAT_URL]);
    expect(calls[1].body.model).toBe(HAIKU_MODEL);
    expect(result.lane).toBe("ask_back");
    expect(result.confidence).toBe(0.69);
    expect(result.model).toBe(`${JEV_MODEL}+${HAIKU_MODEL}`);
    expect(result.guesses).toEqual(["other_icon", "smaller", "remove"]);
    expect(result.costUsd).toBeCloseTo(0.00013);
  });

  it("a Jev timeout goes to code, within the time limit", async () => {
    sortCallSettings.timeoutMs = 40;
    function hang(_url: string, _body: Record<string, unknown>, signal: AbortSignal | null): Promise<Response> {
      return hangUntilAborted(signal);
    }
    const { fetchStandIn, calls } = fakeFetch(hang);
    const startedAt = Date.now();
    const result = await sortRequest(INPUT, "key", fetchStandIn);
    expect(Date.now() - startedAt).toBeLessThan(2000);
    expect(calls.length).toBe(1);
    expect(result.lane).toBe("code");
    expect(result.error).toBe("jev: timeout");
  });

  it("a Jev error goes to code", async () => {
    function fail(): Promise<Response> {
      return Promise.resolve(jsonResponse({ error: { message: "busy" } }, 503));
    }
    const { fetchStandIn } = fakeFetch(fail);
    const result = await sortRequest(INPUT, "key", fetchStandIn);
    expect(result.lane).toBe("code");
    expect(result.error).toBe("jev: HTTP 503");
  });

  it("a Haiku timeout after an unsure Jev goes to code, not to Jev's cheaper lane", async () => {
    sortCallSettings.timeoutMs = 40;
    function unsureThenHang(url: string, _body: Record<string, unknown>, signal: AbortSignal | null): Promise<Response> {
      if (url === DECISIONS_URL) {
        return Promise.resolve(jsonResponse(jevPayload("not_a_request", 0.4)));
      }
      return hangUntilAborted(signal);
    }
    const { fetchStandIn } = fakeFetch(unsureThenHang);
    const result = await sortRequest(INPUT, "key", fetchStandIn);
    expect(result.lane).toBe("code");
    expect(result.error).toBe("haiku: timeout");
  });

  it("an unreadable Haiku answer goes to code", async () => {
    function unsureThenNonsense(url: string): Promise<Response> {
      if (url === DECISIONS_URL) {
        return Promise.resolve(jsonResponse(jevPayload("setting", 0.5)));
      }
      return Promise.resolve(jsonResponse(haikuPayload('{"lane": "somewhere"}')));
    }
    const { fetchStandIn } = fakeFetch(unsureThenNonsense);
    const result = await sortRequest(INPUT, "key", fetchStandIn);
    expect(result.lane).toBe("code");
    expect(result.error).toBe("haiku: unreadable answer");
  });

  it("no key: code, and nothing is called", async () => {
    function neverCalled(): Promise<Response> {
      throw new Error("must not be called");
    }
    const { fetchStandIn, calls } = fakeFetch(neverCalled);
    const result = await sortRequest(INPUT, undefined, fetchStandIn);
    expect(calls.length).toBe(0);
    expect(result.lane).toBe("code");
    expect(result.model).toBe("none");
  });
});
