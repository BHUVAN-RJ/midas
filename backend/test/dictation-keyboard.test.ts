// The Midas dictation keyboard's records (TEST, staging only; founder 2026-11-14,
// docs/briefs/dictation-keyboard-test.md; branch agent/dictation-test, never merged). A keyboard
// insert is saved by the shell as a `dictation.run` with source "keyboard"
// (shell/Midas/DictationSidekick.swift, DictationTestRuns.keyboard): the manifest takes it exactly
// as the shell writes it and still refuses unknown sources; the page and tools.js know the source
// and label it "Keyboard"; their copied blocks stay identical (the deploy gate); and the shell's
// names match.
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { checkBundleFiles } from "../scripts/bundle-tools.mjs";
import { loadToolsScript } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/dictation/", import.meta.url);
const html = readFileSync(new URL("index.html", folder), "utf8");
const manifestText = readFileSync(new URL("manifest.json", folder), "utf8");
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const manifest = JSON.parse(manifestText);
const sidekickSource = readFileSync(new URL("../../shell/Midas/DictationSidekick.swift", import.meta.url), "utf8");
const sessionSource = readFileSync(new URL("../../shell/Midas/DictationKeyboardSession.swift", import.meta.url), "utf8");
const sharedSource = readFileSync(new URL("../../shell/DictationKeyboardShared/DictationKeyboardShared.swift", import.meta.url), "utf8");

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;
const NOW = "2026-11-14T22:00:00.000Z";

type Value = Record<string, unknown>;

// A keyboard run exactly as DictationRunRecord.value writes DictationTestRuns.keyboard's run
function keyboardRun(fields: Value = {}): Value {
  return {
    $type: "dictation.run", at: "2026-11-14T21:30:11.045Z", source: "keyboard", raw: "uh tell mom im on my way",
    cleaned: "Tell mom I'm on my way.", cleanupMs: 0, releaseToRawMs: 1002, totalMs: 1045, firstCall: false, modelStatus: "Available",
    device: "iPhone17,1", ios: "27.0", build: "33", path: "rule", matched: ["uh"], gateMs: 0.03, thermal: "fair", ...fields,
  };
}

function schemaProblem(key: string, value: Value) {
  const stamped = MidasRecordSchema.stampType(manifest.types, key, value);
  return MidasRecordSchema.checkRecord(manifest.types, key, stamped);
}

describe("dictation keyboard: the record", () => {
  it("takes a keyboard run as the shell writes it", () => {
    expect(schemaProblem("run:20261114T213011045Z-0001", keyboardRun())).toBeNull();
  });

  it("lists keyboard as the fourth source and still refuses unknown ones", () => {
    expect(manifest.types["run:"].schema.properties.source.enum).toEqual(["phrase", "spoken", "run-all", "keyboard"]);
    expect(schemaProblem("run:x", keyboardRun({ source: "typed" }))).not.toBeNull();
    expect(schemaProblem("run:x", keyboardRun({ totalMs: -1 }))).not.toBeNull();
  });
});

describe("dictation keyboard: the page and the tools", () => {
  it("still pass the deploy gate (the copied block matches the page)", () => {
    const checked = checkBundleFiles(html, manifestText, "dictation", toolsText);
    expect(checked.problems).toEqual([]);
  });

  it("show a keyboard run as Keyboard with its raw and total times", () => {
    const records = [{ key: "run:20261114T213011045Z-0001", value: keyboardRun() }];
    const outcome = JSON.parse(JSON.stringify(tools.handlers.runs({ limit: null }, records, NOW)));
    expect(outcome.result.text).toContain("Keyboard");
    expect(outcome.result.text).toContain("Tell mom I'm on my way.");
    expect(outcome.result.text).not.toContain("Phrase");
    expect(html).toContain("'keyboard': 'Keyboard'");
    expect(toolsText).toContain("'keyboard': 'Keyboard'");
  });
});

describe("dictation keyboard: the shell's names", () => {
  it("writes source keyboard with no model time", () => {
    expect(sidekickSource).toContain("case keyboard");
    expect(sidekickSource).toContain("source: .keyboard");
    expect(sidekickSource).toContain("cleanupMs: 0");
  });

  it("uses the brief's constants", () => {
    expect(sharedSource).toContain('static let startURL = URL(string: "midastest://dictation")!');
    expect(sharedSource).toContain("static let endOfSpeechSilence: Duration = .seconds(1)");
    expect(sharedSource).toContain("static let sessionIdleTimeout: TimeInterval = 5 * 60");
    expect(sessionSource).toContain("DictationTestRuns.keyboard(");
  });
});
