// Opens a Sidekick page in WebKit with the person's own records (docs/briefs/repair-lanes.md W1,
// "Page opens"). The engine is macOS WKWebView driven by webkit-page.swift, compiled once per
// version of that file with the Xcode toolchain every runner Mac already has: the same WebKit
// engine as the iPhone shell, headless, no new dependency and no simulator lease (a simulator
// would serialise every repair behind the two pool phones, scripts/sim.sh).
//
// One run opens the page several times, each from a fresh copy of the records:
//   open     the records as they are; the page's first view must draw without errors
//   widget   the records without widget:* ones, so the page writes its widget records again
//   view:<a> the records as they are, then a tap on the page control data-action="<a>"
import { execFile, execFileSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const HARNESS_SOURCE = join(HERE, "webkit-page.swift");
const PRELUDE_SOURCE = join(HERE, "page-prelude.js");
// iPhone 17 Pro's points, the founder's phone class (memory: iPhone 16 Pro, same width)
const VIEWPORT = { width: 402, height: 874 };
const STEP_TIMEOUT_MS = 8000;
const SETTLE_MS = 300;
const MAX_SETTLE_MS = 3000;
const WIDGET_PREFIX = "widget:";

export const STEP_OPEN = "open";
export const STEP_WIDGET = "widget";
export const VIEW_STEP_PREFIX = "view:";

// The validator and shell types the shell itself loads, from the checkout under test
function sdkSources(checkoutRoot) {
  const recordSchemaPath = join(checkoutRoot, "shell", "sdk", "record-schema.js");
  const shellTypesPath = join(checkoutRoot, "shell", "sdk", "shell-types.js");
  return {
    recordSchema: readFileSync(recordSchemaPath, "utf8"),
    shellTypes: readFileSync(shellTypesPath, "utf8"),
  };
}

// The prelude for one step: the SDK files and the prelude in one function scope, so none of
// their names lands on the page's window.
export function buildPrelude({ checkoutRoot, config }) {
  const sources = sdkSources(checkoutRoot);
  const preludeText = readFileSync(PRELUDE_SOURCE, "utf8");
  const configText = JSON.stringify(config);
  return [
    "(function shieldWrapper() {",
    sources.recordSchema,
    sources.shellTypes,
    preludeText,
    `shieldPrelude(${configText}, MidasRecordSchema, MidasShellTypes);`,
    "})();",
  ].join("\n");
}

function withoutWidgetRecords(records) {
  return records.filter(function isNotWidgetRecord(record) {
    return !record.key.startsWith(WIDGET_PREFIX);
  });
}

// The steps of one run, in order: [{ name, records, action }]
export function plannedSteps({ records, actions }) {
  const steps = [
    { name: STEP_OPEN, records, action: null },
    { name: STEP_WIDGET, records: withoutWidgetRecords(records), action: null },
  ];
  for (const action of actions) {
    steps.push({ name: `${VIEW_STEP_PREFIX}${action}`, records, action });
  }
  return steps;
}

// The compiled harness, built once per source version into a shared temp folder. Written under a
// unique name and renamed into place, so two runs compiling at once never see half a file.
export function compiledHarness() {
  const sourceText = readFileSync(HARNESS_SOURCE);
  const hasher = createHash("sha256");
  hasher.update(sourceText);
  const fullHash = hasher.digest("hex");
  const sourceHash = fullHash.slice(0, 16);
  const cacheFolder = join(tmpdir(), "midas-shield", sourceHash);
  const binaryPath = join(cacheFolder, "webkit-page");
  if (existsSync(binaryPath)) {
    return binaryPath;
  }
  mkdirSync(cacheFolder, { recursive: true });
  const partialPath = `${binaryPath}.${process.pid}.${randomBytes(4).toString("hex")}`;
  execFileSync("xcrun", ["swiftc", "-O", "-o", partialPath, HARNESS_SOURCE], { stdio: "pipe" });
  renameSync(partialPath, binaryPath);
  return binaryPath;
}

// Runs the harness binary over a plan file. Resolves with its parsed JSON array; rejects with
// why when it could not run. Injectable in openPage for tests of the checks themselves.
export function runHarness({ planPath, stepCount }) {
  const binaryPath = compiledHarness();
  // Every step can take its full timeout, plus WebKit's own start
  const timeoutMs = stepCount * STEP_TIMEOUT_MS + 20000;
  return new Promise(function runHarnessProcess(resolve, reject) {
    const options = { encoding: "utf8", timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 };
    execFile(binaryPath, [planPath], options, function finishHarness(error, stdout, stderr) {
      if (error !== null) {
        reject(new Error(`WebKit page opener failed: ${error.message} ${stderr}`.trim()));
        return;
      }
      try {
        resolve(JSON.parse(stdout));
      } catch {
        reject(new Error(`WebKit page opener printed no JSON: ${stdout.slice(0, 200)}`));
      }
    });
  });
}

function stepResult(step, harnessEntry) {
  if (harnessEntry === undefined) {
    return { name: step.name, action: step.action, problem: "the step never ran" };
  }
  if (harnessEntry.timedOut === true) {
    return { name: step.name, action: step.action, problem: `the page did not finish opening in ${STEP_TIMEOUT_MS / 1000} s` };
  }
  if (typeof harnessEntry.loadError === "string") {
    return { name: step.name, action: step.action, problem: `the page did not load: ${harnessEntry.loadError}` };
  }
  return { name: step.name, action: step.action, report: harnessEntry.report };
}

// Opens one copy of a page. html: the page; manifest: its manifest (for types); records: the
// person's records [{ key, value }]; actions: the page controls to tap, one step each.
// Resolves with [{ name, action, report } | { name, action, problem }], one per step.
export async function openPage({ checkoutRoot, sidekickId, html, manifest, records, actions = [], runHarnessImplementation = runHarness }) {
  const workFolder = mkdtempSync(join(tmpdir(), "midas-shield-page-"));
  try {
    const htmlPath = join(workFolder, "index.html");
    writeFileSync(htmlPath, html);
    const steps = plannedSteps({ records, actions });
    const planSteps = steps.map(function planStep(step) {
      const nonce = randomBytes(16).toString("hex");
      const config = {
        nonce,
        sidekickId,
        records: step.records,
        types: manifest?.types ?? null,
        action: step.action,
        settleMs: SETTLE_MS,
        maxSettleMs: MAX_SETTLE_MS,
      };
      return { nonce, prelude: buildPrelude({ checkoutRoot, config }) };
    });
    const plan = {
      htmlPath,
      baseUrl: `https://${sidekickId}.sidekick.invalid/`,
      steps: planSteps,
      stepTimeoutMs: STEP_TIMEOUT_MS,
      width: VIEWPORT.width,
      height: VIEWPORT.height,
    };
    const planPath = join(workFolder, "plan.json");
    writeFileSync(planPath, JSON.stringify(plan));
    const harnessEntries = await runHarnessImplementation({ planPath, stepCount: steps.length });
    return steps.map(function resultForStep(step, index) {
      const entry = harnessEntries.find(function entryForIndex(candidate) {
        return candidate.step === index;
      });
      return stepResult(step, entry);
    });
  } finally {
    rmSync(workFolder, { recursive: true, force: true });
  }
}
