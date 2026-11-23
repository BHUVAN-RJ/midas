// Shared fixtures for the shield's tests (docs/briefs/repair-lanes.md W1): real Sidekick copies from
// sidekicks/, and records made by the Sidekick's own tools, stamped as the shell stores them.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { loadDeterministicTools } from "../../runner/core-checks/tools-compare.mjs";

export const repoRoot = fileURLToPath(new URL("../../", import.meta.url));
export const NOW = new Date("2026-11-13T17:00:00.000Z");
export const NOW_ISO = NOW.toISOString();

export type Copy = { html: string; manifestText: string; toolsText: string | null };
export type StoredRecord = { key: string; value: Record<string, unknown> };
type Op = { op: string; key: string; value?: Record<string, unknown> };

export function sidekickCopy(sidekickId: string): Copy {
  const folder = new URL(`sidekicks/${sidekickId}/`, new URL("../../", import.meta.url));
  return {
    html: readFileSync(new URL("index.html", folder), "utf8"),
    manifestText: readFileSync(new URL("manifest.json", folder), "utf8"),
    toolsText: readFileSync(new URL("tools.js", folder), "utf8"),
  };
}

// The same copy with its manifest changed by changeManifest
export function withManifest(copy: Copy, changeManifest: (manifest: Record<string, any>) => void): Copy {
  const manifest = JSON.parse(copy.manifestText);
  changeManifest(manifest);
  return { ...copy, manifestText: JSON.stringify(manifest) };
}

// The same copy with a line of code run after tools.js (it can replace or delete handlers)
export function withToolsAppended(copy: Copy, appendedCode: string): Copy {
  return { ...copy, toolsText: `${copy.toolsText}\n${appendedCode}\n` };
}

// The same copy with a script added at the end of the page's body
export function withPageScript(copy: Copy, scriptText: string): Copy {
  const html = copy.html.replace("</body>", `<script>${scriptText}</script>\n</body>`);
  return { ...copy, html };
}

function applyOps(records: StoredRecord[], ops: Op[], types: Record<string, unknown>) {
  let current = records;
  for (const op of ops) {
    const others = current.filter(function isOtherKey(record) {
      return record.key !== op.key;
    });
    if (op.op === "delete") {
      current = others;
      continue;
    }
    const stamped = MidasRecordSchema.stampType(types, op.key, op.value);
    current = [...others, { key: op.key, value: stamped }];
  }
  return current;
}

// Records made by calling the copy's own tools in order, as a person's store would hold them
export function recordsFromTools(copy: Copy, sidekickId: string, calls: Array<{ verb: string; input: unknown }>) {
  const loaded = loadDeterministicTools(copy.toolsText, NOW_ISO);
  if (loaded.problem) {
    throw new Error(loaded.problem);
  }
  const types = JSON.parse(copy.manifestText).types;
  let records: StoredRecord[] = [];
  for (const call of calls) {
    const reply = loaded.tools.handlers[call.verb](call.input, records, NOW_ISO);
    if (!Array.isArray(reply.ops)) {
      throw new Error(`${sidekickId}.${call.verb} refused: ${JSON.stringify(reply)}`);
    }
    records = applyOps(records, reply.ops, types);
  }
  return records;
}

// "today", as the handler gets it once Midas has worked out the date
const TODAY_WHEN = {
  whenKind: "absolute",
  minutesFromNow: null,
  daysFromNow: null,
  date: NOW_ISO.slice(0, 10),
  yearMissing: false,
  weekday: null,
  weekdayNext: false,
  time: null,
  ampmStated: false,
  partOfDay: null,
  repeat: null,
  whenText: "today",
};

function todoAdd(title: string, when: unknown) {
  return { verb: "add", input: { title, notes: null, list: null, someday: null, when } };
}

// Two to-dos, one of them ticked. "Buy milk" is for today; To-Do carries it over, so it stays on
// the Today view on any later day the tests run.
export function todoRecords() {
  const copy = sidekickCopy("todo");
  const calls = [todoAdd("Buy milk", TODAY_WHEN), todoAdd("Call dad", null), { verb: "complete", input: { item: "Call dad" } }];
  return recordsFromTools(copy, "todo", calls);
}
