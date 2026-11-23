import MidasSettings from "../../shell/sdk/midas-settings.js";
import type { SettingEntry, SettingValue, SettingsCatalogue } from "../../shell/sdk/midas-settings.js";

// The setting lane's model call (repair lanes W5, founder D1 and "setting" lane, 2026-11-13).
// A request the sort put in lane `setting` is mapped to { key, value } changes by Claude Haiku 5.5
// through OpenRouter, reading the Sidekick's own catalogue (manifest.json "settings") and the
// person's current values. Every change is checked against the catalogue with the same engine
// the page runs (shell/sdk/midas-settings.js). No change, a change the catalogue does not offer,
// a timeout or an error: the request goes up to `code` (never down).

export const SETTING_MODEL = "anthropic/claude-haiku-5.5";
export const SETTING_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions";
// One request changes at most this many settings ("make the title blue and bigger" is two)
export const MAX_CHANGES = 3;

// Mutable so tests can shorten the wait; the Worker gives the call 6 s, as the sort does.
export const settingCallSettings = { timeoutMs: 6000 };

export type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

export type SettingRequest = {
  words: string;
  sidekickName: string;
  drawing: string;
  catalogue: SettingsCatalogue;
  record: Record<string, unknown> | null;
};

export type SettingChange = { key: string; label: string; value: SettingValue; previous: SettingValue | null };

export type SettingMapping =
  | { ok: true; changes: SettingChange[]; latencyMs: number; costUsd: number }
  | { ok: false; reason: string; latencyMs: number; costUsd: number };

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/* ---------- The prompt ---------- */

function valuesText(entry: SettingEntry): string {
  if (entry.type === "colour") {
    return "a colour #RRGGBB";
  }
  if (entry.type === "show") {
    return "true (shown) or false (hidden)";
  }
  const allowed = MidasSettings.allowedValues(entry) ?? [];
  return `one of ${allowed.map(String).join(", ")}`;
}

// One line per setting: key | what it is | allowed values | value now
export function catalogueLines(catalogue: SettingsCatalogue, record: Record<string, unknown> | null): string {
  const current = MidasSettings.valuesFrom(catalogue, record);
  const lines: string[] = [];
  for (const entry of catalogue.entries) {
    lines.push(`- ${entry.key} | ${entry.label} | ${valuesText(entry)} | now ${String(current[entry.key])}`);
  }
  return lines.join("\n");
}

// People never name the setting (founder, 2026-11-22: "Can you change the color to red" on
// Reminders came back empty and fell to the slow code lane). When the words do not say which part,
// the most visible setting of that kind is the one they mean; empty only when the app has no
// setting of that kind at all.
export const VAGUE_WORDS_RULE =
  "People rarely name the part. When their words do not say which part, pick the most visible setting of that kind, never nothing: " +
  "a colour with no part named is the main colour (the accent: buttons, links, ticks; with no accent, the most visible coloured part, such as the title or the main button); " +
  "bigger or smaller with no part named is the main text size (the size of the whole page or list when there is one, else the main text); " +
  "darker or lighter with no part named is the background colour (or a light or dark appearance setting); " +
  'words like "make it pop" or "brighter" mean a bolder, brighter main colour.';

export const EMPTY_ONLY_RULE = 'Answer {"changes": []} only when the app has no setting of that kind at all (no colour, no size, no show or hide that fits).';

export function buildSettingPrompt(request: SettingRequest): string {
  return (
    `A person using the "${request.sidekickName}" app asked to change how it looks.\n` +
    `Their words: "${request.words}"\n` +
    `They circled: ${request.drawing}\n\n` +
    `The app's settings (key | what it changes | allowed values | value now):\n${catalogueLines(request.catalogue, request.record)}\n\n` +
    "Pick the setting changes that do what they asked, at most 3. A colour is #RRGGBB: pick a clear, " +
    "pleasant shade of the colour they named; darker or lighter is relative to the value now. Bigger or " +
    "smaller is one size step from the value now. Remove, hide or get rid of is false; bring back or show is true. " +
    "Date formats: day-month 13 Nov, month-day Nov 13, day-month-year 13 Nov 2026, month-day-year Nov 13, 2026, " +
    "weekday-day-month Thu 13 Nov, weekday-month-day Thu, Nov 13, numeric-day-first 13/11/2026, numeric-month-first 11/13/2026, auto as built. " +
    `${VAGUE_WORDS_RULE} ${EMPTY_ONLY_RULE}\n\n` +
    'Answer only JSON: {"changes": [{"key": "...", "value": ...}]}'
  );
}

export function buildSettingRequest(request: SettingRequest): Record<string, unknown> {
  return {
    model: SETTING_MODEL,
    max_tokens: 1000,
    messages: [{ role: "user", content: buildSettingPrompt(request) }],
    response_format: { type: "json_object" },
    reasoning: { effort: "low", exclude: true },
    usage: { include: true },
  };
}

/* ---------- Reading the answer ---------- */

type RawChange = { key: unknown; value: unknown };

// The changes in Haiku's JSON text (some providers put it in the reasoning field only), or null
export function readSettingAnswer(json: Record<string, unknown> | null): RawChange[] | null {
  const choices = json?.choices as Array<{ message?: { content?: unknown; reasoning?: unknown } }> | undefined;
  const message = choices?.[0]?.message;
  const content = typeof message?.content === "string" && message.content.length > 0 ? message.content : message?.reasoning;
  if (typeof content !== "string") {
    return null;
  }
  const jsonText = content.slice(content.indexOf("{"), content.lastIndexOf("}") + 1);
  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonText);
  } catch {
    return null;
  }
  if (!isPlainObject(parsed) || !Array.isArray(parsed.changes)) {
    return null;
  }
  const changes: RawChange[] = [];
  for (const item of parsed.changes) {
    if (isPlainObject(item)) {
      changes.push({ key: item.key, value: item.value });
    }
  }
  return changes;
}

// Every change checked against the catalogue; one that does not fit fails them all (a half-done
// request is worse than the code lane doing all of it). previous: the stored value, or null when
// the person never set it (Undo then removes the key).
export function checkedChanges(catalogue: SettingsCatalogue, record: Record<string, unknown> | null, rawChanges: RawChange[]): { changes: SettingChange[] } | { problem: string } {
  if (rawChanges.length === 0) {
    return { problem: "no setting does it" };
  }
  if (rawChanges.length > MAX_CHANGES) {
    return { problem: `more than ${MAX_CHANGES} changes` };
  }
  const changes: SettingChange[] = [];
  const seenKeys: string[] = [];
  for (const raw of rawChanges) {
    const key = typeof raw.key === "string" ? raw.key : "";
    const entry = MidasSettings.entryFor(catalogue, key);
    if (entry === null) {
      return { problem: `not a setting: ${key.slice(0, 60)}` };
    }
    if (seenKeys.includes(key)) {
      return { problem: `${key} twice` };
    }
    seenKeys.push(key);
    const picked = MidasSettings.checkValue(entry, raw.value);
    if (picked.problem !== undefined) {
      return { problem: `${key}: ${picked.problem}` };
    }
    const stored = record !== null && Object.hasOwn(record, key) ? record[key] : undefined;
    const previous = stored === undefined ? null : (stored as SettingValue);
    changes.push({ key, label: entry.label, value: picked.value, previous });
  }
  const current = MidasSettings.valuesFrom(catalogue, record);
  const changesAnything = changes.some(function changesValue(change) {
    return current[change.key] !== change.value;
  });
  if (!changesAnything) {
    return { problem: "already set" };
  }
  return { changes };
}

/* ---------- The call ---------- */

function costOf(json: Record<string, unknown> | null): number {
  const usage = json?.usage as { cost?: unknown } | undefined;
  return typeof usage?.cost === "number" ? usage.cost : 0;
}

type CallOutcome = { json: Record<string, unknown> | null; error: string | null; ms: number };

// POSTs to OpenRouter with the time limit; never throws.
async function postSettingCall(fetchImpl: FetchLike, apiKey: string, body: Record<string, unknown>): Promise<CallOutcome> {
  const controller = new AbortController();
  function abortCall() {
    controller.abort();
  }
  const timer = setTimeout(abortCall, settingCallSettings.timeoutMs);
  const startedAt = Date.now();
  try {
    const response = await fetchImpl(SETTING_CHAT_URL, {
      method: "POST",
      headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json", "x-title": "Midas setting lane" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) {
      return { json: null, error: `HTTP ${response.status}`, ms: Date.now() - startedAt };
    }
    const json = (await response.json()) as Record<string, unknown>;
    return { json, error: null, ms: Date.now() - startedAt };
  } catch (error) {
    const timedOut = controller.signal.aborted;
    const reason = timedOut ? "timeout" : error instanceof Error ? error.message.slice(0, 120) : "network";
    return { json: null, error: reason, ms: Date.now() - startedAt };
  } finally {
    clearTimeout(timer);
  }
}

// Maps the words to checked changes; never throws.
export async function mapSetting(request: SettingRequest, apiKey: string | undefined, fetchImpl: FetchLike): Promise<SettingMapping> {
  if (apiKey === undefined || apiKey.length === 0) {
    return { ok: false, reason: "no OPENROUTER_API_KEY", latencyMs: 0, costUsd: 0 };
  }
  const call = await postSettingCall(fetchImpl, apiKey, buildSettingRequest(request));
  const costUsd = costOf(call.json);
  if (call.error !== null) {
    return { ok: false, reason: `haiku: ${call.error}`, latencyMs: call.ms, costUsd };
  }
  const rawChanges = readSettingAnswer(call.json);
  if (rawChanges === null) {
    return { ok: false, reason: "haiku: unreadable answer", latencyMs: call.ms, costUsd };
  }
  const checked = checkedChanges(request.catalogue, request.record, rawChanges);
  if ("problem" in checked) {
    return { ok: false, reason: checked.problem, latencyMs: call.ms, costUsd };
  }
  return { ok: true, changes: checked.changes, latencyMs: call.ms, costUsd };
}
