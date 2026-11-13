// Sort-step benchmark (repair lanes W2, founder 2026-11-13): can a cheap model (or Jev) put each
// past repair request in the right lane, fast? Reads the runner's past jobs on this Mac, asks each
// model the same question, prints accuracy, latency and cost. This is the one script that calls
// OpenRouter for real; the unit tests mock it.
//
// The lane and guess wording comes from the Worker's own src/repair-sort-model.ts, so the benchmark
// and the Worker cannot drift apart (node 22.18+ loads the .ts file directly).
//
// Usage (the key comes from OPENROUTER_API_KEY or ~/.openrouter-key):
//   cd ~/Desktop/Midas/midas/backend && node scripts/sort-bench.mjs --worker   (the Worker's own sort: Jev, then Haiku below 0.7)
//   cd ~/Desktop/Midas/midas/backend && node scripts/sort-bench.mjs            (each model alone, words + drawing outline)
//   cd ~/Desktop/Midas/midas/backend && node scripts/sort-bench.mjs --images   (also sends screenshot + drawing, resized)
//   cd ~/Desktop/Midas/midas/backend && node scripts/sort-bench.mjs --models typesafe/jev-1.14,anthropic/claude-haiku-5.5
// Results are written to $TMPDIR/midas-sort-bench/, never into the repo.

import { readFileSync, readdirSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { homedir, tmpdir } from "node:os";
import { GUESSES, LANES, sortRequest } from "../src/repair-sort-model.ts";

const JOBS_FOLDER = join(homedir(), "Library/Application Support/midas-runner/jobs");
const OUT_FOLDER = join(tmpdir(), "midas-sort-bench");
// The key comes from the environment, or from ~/.openrouter-key (one line, nothing else).
function readApiKey() {
  if (process.env.OPENROUTER_API_KEY) {
    return process.env.OPENROUTER_API_KEY;
  }
  const keyPath = join(homedir(), ".openrouter-key");
  return existsSync(keyPath) ? readFileSync(keyPath, "utf8").trim() : "";
}
const API_KEY = readApiKey();

const DEFAULT_MODELS = [
  "typesafe/jev-1.14",
  "anthropic/claude-haiku-5.5",
  "deepseek/deepseek-v4.1-flash",
  "z-ai/glm-5.3-flash",
  "qwen/qwen3.8-flash",
  "google/gemini-3.1-flash-lite"
];

// LANES and GUESSES: imported from src/repair-sort-model.ts (the Worker's wording, the reference).
const WORKER_MODE = "worker";

// Expected lane per past job (from the 2026-11-08 review of all runner logs).
const EXPECTED = {
  "13edb182": "code", "9d619921": "code", "fdd6509a": "code", "06ed8ab8": "ask_back", "bdd63740": "look",
  "38580f9d": "jess_command", "4a66c712": "code", "e298466e": "setting", "3365bd8a": "shell_cant", "50ca5522": "setting",
  "9c699df4": "setting", "ef2c8a90": "setting", "6bcf16a1": "shell_cant", "e6a9c747": "setting", "bffa6356": "setting",
  "22c5571b": "setting", "35cadeae": "setting", "d84d2d44": "code", "ef0e08d6": "shell_cant", "a3cc0820": "shell_cant",
  "5700cf94": "code", "01ea4185": "code", "dbb53686": "look", "d889a96e": "ask_back", "3597797e": "ask_back",
  "ab418b9d": "ask_back", "e8ef504b": "ask_back", "e9e79fe6": "ask_back", "d0dc226f": "code", "40594f96": "code",
  "b8dea1a6": "code", "71787004": "code", "3bab525e": "ask_back", "0616a34f": "ask_back", "b6c666eb": "setting",
  "4c9ec881": "setting", "dbc32614": "setting", "14402759": "code", "fe62fea8": "setting", "27e3ee48": "setting",
  "42396937": "setting", "993103d2": "ask_back", "2da2e6b0": "setting", "adfd6130": "not_a_request",
  "9148ab8e": "not_a_request", "b6d9bc20": "not_a_request"
};

const SIDEKICK_NAMES = {
  reminders: "Reminders (lists of reminders with times)", "reminder-test": "Reminders (test copy)",
  "care-reminders": "Care reminders (medicine and care, repeats)", hydration: "Water (daily water goal, reminders)",
  todo: "To-Do (lists, Today, Upcoming)"
};

function readArgs() {
  const args = process.argv.slice(2);
  const withImages = args.includes("--images");
  const modelsIndex = args.indexOf("--models");
  let models = modelsIndex >= 0 ? args[modelsIndex + 1].split(",") : DEFAULT_MODELS;
  // --worker: the Worker's own sort (Jev, Haiku below 0.7, code on any failure), words only.
  if (args.includes("--worker")) {
    models = [WORKER_MODE];
  }
  return { withImages, models };
}

// Where the drawing is, in words: number of strokes and the box they cover on a 402 x 874 screen.
function describeStrokes(strokesPath) {
  if (!existsSync(strokesPath)) {
    return "no drawing";
  }
  const strokes = JSON.parse(readFileSync(strokesPath, "utf8"));
  const points = strokes.flat();
  if (points.length === 0) {
    return "no drawing (empty)";
  }
  const xs = points.map(function pickX(point) { return point[0]; });
  const ys = points.map(function pickY(point) { return point[1]; });
  const box = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)].map(Math.round);
  return strokes.length + " stroke(s) covering x " + box[0] + "–" + box[2] + ", y " + box[1] + "–" + box[3] + " on a 402×874 screen";
}

// Resizes a PNG to 402 px wide with macOS sips and returns it as a data URL.
function imageAsDataUrl(pngPath, scratchFolder) {
  const target = join(scratchFolder, Date.now() + "-" + Math.random().toString(36).slice(2) + ".png");
  // Some "screenshot.png" files are really JPEGs; convert everything to a real PNG.
  execFileSync("sips", ["-s", "format", "png", "--resampleWidth", "402", pngPath, "--out", target], { stdio: "ignore" });
  const base64 = readFileSync(target).toString("base64");
  return "data:image/png;base64," + base64;
}

function loadCases(withImages) {
  const scratchFolder = join(OUT_FOLDER, "img");
  mkdirSync(scratchFolder, { recursive: true });
  const folders = readdirSync(JOBS_FOLDER);
  const cases = [];
  for (const folder of folders) {
    const shortId = folder.slice(0, 8);
    const reportFolder = join(JOBS_FOLDER, folder, "report");
    if (folder.endsWith(".check") || !(shortId in EXPECTED) || !existsSync(reportFolder)) {
      continue;
    }
    const transcriptPath = join(reportFolder, "transcript.txt");
    const transcript = existsSync(transcriptPath) ? readFileSync(transcriptPath, "utf8").trim() : "";
    const reportJson = JSON.parse(readFileSync(join(reportFolder, "report.json"), "utf8"));
    const sidekickId = reportJson.sidekickId || folder;
    const testCase = {
      id: shortId, expected: EXPECTED[shortId], transcript: transcript,
      sidekick: SIDEKICK_NAMES[sidekickId] || sidekickId, drawing: describeStrokes(join(reportFolder, "strokes.json")), images: []
    };
    if (withImages) {
      for (const name of ["screenshot.png", "drawing.png"]) {
        const imagePath = join(reportFolder, name);
        if (existsSync(imagePath)) {
          testCase.images.push(imageAsDataUrl(imagePath, scratchFolder));
        }
      }
    }
    cases.push(testCase);
  }
  return cases;
}

function stateText(testCase) {
  return "A person is using the Midas app \"" + testCase.sidekick + "\". They opened repair mode, may have drawn on the screen, and said: \"" +
    testCase.transcript + "\". Drawing: " + testCase.drawing + ".";
}

// Jev: typed choice questions through the Decisions API.
async function askJev(model, testCase) {
  const textPart = { type: "text", text: stateText(testCase) };
  const imageParts = testCase.images.map(function toImagePart(url) { return { type: "image_url", image_url: { url: url } }; });
  const state = imageParts.length > 0 ? [textPart].concat(imageParts) : textPart.text;
  const body = {
    model: model, state: state,
    questions: {
      lane: { type: "choice", instructions: "What should happen with this repair request?", criteria: LANES },
      guess: { type: "choice", instructions: "If the person wants something changed but did not say into what, what most likely?", criteria: GUESSES }
    }
  };
  const response = await fetch("https://openrouter.ai/api/alpha/decisions", {
    method: "POST", headers: { Authorization: "Bearer " + API_KEY, "Content-Type": "application/json" }, body: JSON.stringify(body)
  });
  const json = await response.json();
  if (!response.ok) {
    throw new Error(JSON.stringify(json).slice(0, 300));
  }
  const guessProbabilities = json.answers.guess.probabilities;
  const topGuesses = Object.keys(guessProbabilities).sort(function byProbability(a, b) { return guessProbabilities[b] - guessProbabilities[a]; }).slice(0, 3);
  return { lane: json.answers.lane.choice, confidence: json.answers.lane.confidence, guesses: topGuesses, cost: json.usage?.cost ?? 0 };
}

// Generating models: same lanes, JSON answer through Chat Completions.
async function askChatModel(model, testCase) {
  const laneLines = Object.entries(LANES).map(function laneLine(entry) { return "- " + entry[0] + ": " + entry[1]; }).join("\n");
  const guessLines = Object.entries(GUESSES).map(function guessLine(entry) { return "- " + entry[0] + ": " + entry[1]; }).join("\n");
  const instructions = stateText(testCase) + "\n\nPick the lane:\n" + laneLines +
    "\n\nAlso pick up to 3 likely guesses for what they want, from:\n" + guessLines +
    "\n\nAnswer only JSON: {\"lane\": \"...\", \"guesses\": [\"...\"]}";
  const content = [{ type: "text", text: instructions }];
  for (const url of testCase.images) {
    content.push({ type: "image_url", image_url: { url: url } });
  }
  const body = {
    model: model, max_tokens: 2000, messages: [{ role: "user", content: content }],
    response_format: { type: "json_object" }, reasoning: { effort: "low", exclude: true }, usage: { include: true }
  };
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST", headers: { Authorization: "Bearer " + API_KEY, "Content-Type": "application/json" }, body: JSON.stringify(body)
  });
  const json = await response.json();
  if (!response.ok || !json.choices) {
    throw new Error(JSON.stringify(json).slice(0, 300));
  }
  // Some models put the answer only in their reasoning field; fall back to it.
  const message = json.choices[0].message;
  const text = message.content || message.reasoning || "";
  const jsonText = text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
  const parsed = JSON.parse(jsonText);
  return { lane: parsed.lane, confidence: null, guesses: parsed.guesses || [], cost: json.usage?.cost ?? 0 };
}

// The Worker's own sort step on one past request, through the same code the Worker runs.
async function askWorkerSort(testCase) {
  const input = { transcript: testCase.transcript, sidekickName: testCase.sidekick, sidekickDescription: null, drawing: testCase.drawing, answer: null };
  const result = await sortRequest(input, API_KEY, fetch);
  if (result.error !== null) {
    throw new Error(result.error);
  }
  return { lane: result.lane, confidence: result.confidence, guesses: result.guesses, cost: result.costUsd, model: result.model };
}

function askModel(model, testCase) {
  if (model === WORKER_MODE) {
    return askWorkerSort(testCase);
  }
  if (model.startsWith("typesafe/")) {
    return askJev(model, testCase);
  }
  return askChatModel(model, testCase);
}

async function runOne(model, testCase) {
  const startedAt = performance.now();
  try {
    const answer = await askModel(model, testCase);
    const seconds = (performance.now() - startedAt) / 1000;
    return { ...answer, model: model, decidedBy: answer.model ?? model, id: testCase.id, expected: testCase.expected, seconds: seconds, ok: answer.lane === testCase.expected };
  } catch (error) {
    const seconds = (performance.now() - startedAt) / 1000;
    return { model: model, id: testCase.id, expected: testCase.expected, lane: "ERROR", error: String(error.message), seconds: seconds, ok: false, cost: 0 };
  }
}

// Runs a model over every case, four at a time.
async function runModel(model, cases) {
  const results = [];
  const queue = cases.slice();
  async function worker() {
    while (queue.length > 0) {
      const testCase = queue.shift();
      const result = await runOne(model, testCase);
      results.push(result);
    }
  }
  await Promise.all([worker(), worker(), worker(), worker()]);
  return results;
}

function percentile(values, share) {
  const sorted = values.slice().sort(function ascending(a, b) { return a - b; });
  const index = Math.min(sorted.length - 1, Math.floor(share * sorted.length));
  return sorted[index];
}

function summarise(model, results) {
  const answered = results.filter(function notError(result) { return result.lane !== "ERROR"; });
  const correct = results.filter(function isCorrect(result) { return result.ok; }).length;
  const quickLanes = ["ask_back", "not_a_request", "shell_cant", "jess_command"];
  const quickCases = results.filter(function isQuick(result) { return quickLanes.includes(result.expected); });
  const quickCorrect = quickCases.filter(function isCorrect(result) { return result.ok; }).length;
  // Wrongly sent to a cheaper lane when it needed code: the costly mistake.
  const sentDown = results.filter(function wasSentDown(result) { return result.expected === "code" && result.lane !== "code" && result.lane !== "ERROR"; }).length;
  const seconds = answered.map(function pickSeconds(result) { return result.seconds; });
  const cost = results.reduce(function addCost(sum, result) { return sum + (result.cost || 0); }, 0);
  return {
    model: model, correct: correct + "/" + results.length, quickLanes: quickCorrect + "/" + quickCases.length, codeSentDown: sentDown,
    errors: results.length - answered.length, p50s: seconds.length ? percentile(seconds, 0.5).toFixed(2) : "-",
    p90s: seconds.length ? percentile(seconds, 0.9).toFixed(2) : "-", costUsd: cost.toFixed(5)
  };
}

async function main() {
  if (!API_KEY) {
    console.error("Set OPENROUTER_API_KEY first.");
    process.exit(1);
  }
  const { withImages, models } = readArgs();
  mkdirSync(OUT_FOLDER, { recursive: true });
  const cases = loadCases(withImages && !models.includes(WORKER_MODE));
  console.log(cases.length + " past requests, " + (withImages ? "with" : "without") + " pictures");
  const allResults = [];
  const summaries = [];
  for (const model of models) {
    const results = await runModel(model, cases);
    allResults.push(...results);
    const summary = summarise(model, results);
    summaries.push(summary);
    console.log(JSON.stringify(summary));
  }
  console.table(summaries);
  const outName = "results-" + (withImages ? "images" : "text") + ".json";
  writeFileSync(join(OUT_FOLDER, outName), JSON.stringify({ summaries: summaries, results: allResults }, null, 1));
  console.log("Details: " + join(OUT_FOLDER, outName));
}

main();
