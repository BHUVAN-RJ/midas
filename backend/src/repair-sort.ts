import type { Context } from "hono";
import { askedText } from "./edit-failed";
import { makeFounderUserId } from "./make-sidekick";
import { pushFetchFromEnv, runAfterResponse, sendToUserDevices } from "./push";
import type { PushBindings } from "./push";
import { FALLBACK_LANE, describeStrokes, sortRequest } from "./repair-sort-model";
import { CHANGED_TEXT, runSettingLane, settingReply, storedChanges } from "./repair-setting";
import type { SettingOutcome, SettingReply } from "./repair-setting";
import type { CardChoice, GuessId, Lane, SortInput, SortResult } from "./repair-sort-model";

// Repair lanes, the sort step (founder, 2026-11-13; docs/briefs/repair-lanes.md W2). A repair
// report is sorted before any runner can claim it: sort_status 'sorting', then the lane decides
// what happens (migration 0015 says why the status column itself cannot hold 'sorting').
//
//   code, look           -> status queued: the runner does it (look until W6 builds that lane:
//                           up a lane, never down)
//   setting              -> done here (repair-setting.ts, W5): Haiku maps the words to settings,
//                           settings:self is written, no job; anything it cannot map goes up to code
//   ask_back             -> the card goes back to the phone; POST /repairs/:id/answer sorts again
//   not_a_request        -> the pill says NOT_A_REQUEST_TEXT; no job
//   shell_cant           -> the phone says it can't yet; the founder gets a push; no job
//   jess_command         -> no job (what runs it is the lead's open question; see the hand-back)
//
// The phone's reply (contract with W3):
//   POST /repairs  ->  { id, status, lane, question?, message? }
//   POST /repairs/:id/answer { optionId } | { text }  ->  { lane, message? }

export const ASK_BACK_TEXT = "What should it be?";
export const NOT_A_REQUEST_TEXT = "Say or draw what to change.";
// A card left unanswered this long is dropped and logged (founder, 2026-11-13).
export const ANSWER_WINDOW_MS = 2 * 60 * 1000;
export const MAX_ANSWER_LENGTH = 1000;
export const SHELL_CANT_PUSH_TITLE = "Can't do yet";
const MAX_PUSH_ASKED_LENGTH = 180;

// Lanes the runner works on today. `setting` is done in the Worker; one it cannot do becomes code.
const RUNNER_LANES = new Set<Lane>(["code", "look"]);
// After an answer the card is never shown again, and an answer is never chat: both go up to code.
const LANES_NOT_AFTER_ANSWER = new Set<Lane>(["ask_back", "not_a_request"]);
const MAX_OPTIONS = 3;

// The card's picture for each kind of guess. icon is an SF Symbol name the shell draws.
export const CARD_ICONS: Record<GuessId, string> = {
  other_icon: "photo",
  smaller: "arrow.down.right.and.arrow.up.left",
  bigger: "arrow.up.left.and.arrow.down.right",
  other_colour: "paintpalette",
  remove: "eye.slash",
  move: "arrow.up.and.down.and.arrow.left.and.right",
  other_words: "textformat",
  other_layout: "square.grid.2x2",
};
// The fixed options when Haiku wrote too few: concrete changes only, never categories like "Other
// layout" (founder, 2026-11-22, after job d82c7640). Their ids stay the guess ids.
export const FALLBACK_OPTIONS: Partial<Record<GuessId, string>> = {
  smaller: "Smaller",
  bigger: "Bigger",
  remove: "Remove",
  move: "Move to the Top",
};
const DEFAULT_FALLBACKS: GuessId[] = ["smaller", "bigger", "remove"];

// id: a guess id for a fixed option, "option-1".."option-3" for one Haiku wrote. Phones send the
// id back and show the label as it is (shell/Midas/RepairSort.swift), so free labels need no app build.
export type CardOption = { id: string; label: string; icon: string };
export type Question = { text: string; options: CardOption[] };
export type SortReply = { lane: Lane; question?: Question; message?: string; setting?: SettingReply };

type SortBindings = PushBindings & {
  DB: D1Database;
  BUNDLES: R2Bucket;
  OPENROUTER_API_KEY?: string;
  MAKE_FOUNDER_USER_ID?: string;
};

type SortContext = Context<{ Bindings: SortBindings }>;

// The report fields the sort reads.
export type SortableReport = {
  id: string;
  user_id: string;
  sidekick_id: string;
  transcript: string;
  typed_text: string | null;
};

type SortRow = SortableReport & {
  status: string;
  strokes_key: string | null;
  lane: string | null;
  sort_status: string | null;
  sort_question: string | null;
  sort_message: string | null;
  sort_asked_at: string | null;
};

function boundStatement(db: D1Database, sql: string, ...params: unknown[]): D1PreparedStatement {
  const prepared = db.prepare(sql);
  return prepared.bind(...params);
}

function workerFetch(url: string, init: RequestInit): Promise<Response> {
  return fetch(url, init);
}

/* ---------- The card ---------- */

function labelTaken(options: CardOption[], label: string): boolean {
  const wanted = label.toLowerCase();
  for (const option of options) {
    if (option.label.toLowerCase() === wanted) {
      return true;
    }
  }
  return false;
}

// 2-3 options: Haiku's concrete ones first (founder, 2026-11-22); a card with fewer than 2 is
// filled from the fixed concrete ones, the sort's own guesses among them first.
export function questionFor(guesses: GuessId[], written: CardChoice[] = []): Question {
  const options: CardOption[] = [];
  for (const choice of written) {
    if (options.length < MAX_OPTIONS && !labelTaken(options, choice.label)) {
      options.push({ id: `option-${options.length + 1}`, label: choice.label, icon: CARD_ICONS[choice.kind] });
    }
  }
  if (options.length >= 2) {
    return { text: ASK_BACK_TEXT, options };
  }
  for (const guessId of guesses.concat(DEFAULT_FALLBACKS)) {
    const label = FALLBACK_OPTIONS[guessId];
    if (label === undefined || options.length >= MAX_OPTIONS || labelTaken(options, label)) {
      continue;
    }
    options.push({ id: guessId, label, icon: CARD_ICONS[guessId] });
  }
  return { text: ASK_BACK_TEXT, options };
}

// Named when the manifest gave a name; never the raw Sidekick id.
export function shellCantMessage(sidekickName: string | null): string {
  if (sidekickName === null) {
    return "Can't do that yet. Sent to Midas.";
  }
  return `${sidekickName} can't do that yet. Sent to Midas.`;
}

/* ---------- The Sidekick's name and description ---------- */

// fromManifest: false when no manifest was found and the id stands in for the name.
// settingLabels: the catalogue's labels (manifest "settings"), for the card's options.
type SidekickWords = { name: string; description: string | null; fromManifest: boolean; settingLabels: string[] };

// The labels of the manifest's settings catalogue; empty when there is none or it is malformed.
function catalogueLabels(settings: unknown): string[] {
  const entries = (settings as { entries?: unknown } | undefined)?.entries;
  if (!Array.isArray(entries)) {
    return [];
  }
  const labels: string[] = [];
  for (const entry of entries) {
    const label = (entry as { label?: unknown } | null)?.label;
    if (typeof label === "string" && label.length > 0) {
      labels.push(label);
    }
  }
  return labels;
}

// The person's current copy's manifest (their own pointer, else the shared page), as the repair
// agent sees it. Missing or unreadable: the Sidekick's id stands in for its name.
async function sidekickWords(bucket: R2Bucket, sidekickId: string, userId: string): Promise<SidekickWords> {
  const fallback = { name: sidekickId, description: null, fromManifest: false, settingLabels: [] };
  const prefixes = [`sidekicks/${sidekickId}/users/${userId}`, `sidekicks/${sidekickId}`];
  try {
    for (const prefix of prefixes) {
      const pointerObject = await bucket.get(`${prefix}/current.json`);
      if (pointerObject === null) {
        continue;
      }
      const pointer = (await pointerObject.json()) as { version?: unknown };
      const manifestObject = await bucket.get(`${prefix}/${String(pointer.version)}/manifest.json`);
      if (manifestObject === null) {
        return fallback;
      }
      const manifest = (await manifestObject.json()) as { name?: unknown; agent?: { description?: unknown }; settings?: unknown };
      const name = typeof manifest.name === "string" && manifest.name.length > 0 ? manifest.name : sidekickId;
      const description = typeof manifest.agent?.description === "string" ? manifest.agent.description : null;
      return { name, description, fromManifest: true, settingLabels: catalogueLabels(manifest.settings) };
    }
  } catch {
    return fallback;
  }
  return fallback;
}

async function strokesText(bucket: R2Bucket, strokesKey: string | null): Promise<string | null> {
  if (strokesKey === null) {
    return null;
  }
  const object = await bucket.get(strokesKey);
  if (object === null) {
    return null;
  }
  return object.text();
}

/* ---------- Where a sorted report goes ---------- */

type Placement = {
  lane: Lane;
  status: "queued" | "received";
  sortStatus: "asking" | "sorted";
  question: Question | null;
  message: string | null;
  setting: SettingReply | null;
};

// The lane decides the row's status and what the phone hears. After an answer, ask_back and
// not_a_request are read as code (up a lane, never down).
export function placementFor(result: SortResult, sidekickName: string | null, afterAnswer: boolean): Placement {
  const lane: Lane = afterAnswer && LANES_NOT_AFTER_ANSWER.has(result.lane) ? FALLBACK_LANE : result.lane;
  const status = RUNNER_LANES.has(lane) ? "queued" : "received";
  if (lane === "ask_back") {
    return { lane, status, sortStatus: "asking", question: questionFor(result.guesses, result.options), message: null, setting: null };
  }
  if (lane === "not_a_request") {
    return { lane, status, sortStatus: "sorted", question: null, message: NOT_A_REQUEST_TEXT, setting: null };
  }
  if (lane === "shell_cant") {
    return { lane, status, sortStatus: "sorted", question: null, message: shellCantMessage(sidekickName), setting: null };
  }
  return { lane, status, sortStatus: "sorted", question: null, message: null, setting: null };
}

// The setting lane's result: done (no job, the phone hears the changes) or up to code
export function placementAfterSetting(placement: Placement, outcome: SettingOutcome): Placement {
  if (outcome.applied) {
    return { lane: "setting", status: "received", sortStatus: "sorted", question: null, message: CHANGED_TEXT, setting: settingReply(outcome.changes, false) };
  }
  return { lane: FALLBACK_LANE, status: "queued", sortStatus: "sorted", question: null, message: null, setting: null };
}

export function replyFor(placement: Placement): SortReply {
  const reply: SortReply = { lane: placement.lane };
  if (placement.question !== null) {
    reply.question = placement.question;
  }
  if (placement.message !== null) {
    reply.message = placement.message;
  }
  if (placement.setting !== null) {
    reply.setting = placement.setting;
  }
  return reply;
}

// The stored reply, for a retry of a report the phone already sent.
type StoredReply = { lane: string | null; question?: Question; message?: string; setting?: SettingReply };

type StoredSortFields = { lane: string | null; sort_question: string | null; sort_message: string | null; sort_status: string | null; setting_changes?: string | null };

export function replyFromStored(row: StoredSortFields): StoredReply {
  const reply: StoredReply = { lane: row.lane };
  if (row.sort_status === "asking" && row.sort_question !== null) {
    reply.question = JSON.parse(row.sort_question) as Question;
  }
  if (row.sort_message !== null) {
    reply.message = row.sort_message;
  }
  const changes = row.lane === "setting" ? storedChanges(row.setting_changes ?? null) : null;
  if (changes !== null) {
    reply.setting = settingReply(changes, false);
  }
  return reply;
}

/* ---------- The founder's push for shell_cant ---------- */

function cut(text: string, limit: number): string {
  const characters = Array.from(text);
  if (characters.length <= limit) {
    return text;
  }
  return `${characters.slice(0, limit - 1).join("")}…`;
}

function shellCantPayload(report: SortableReport, sidekickName: string): Record<string, unknown> {
  const asked = cut(askedText(report).replace(/\s+/g, " "), MAX_PUSH_ASKED_LENGTH);
  return {
    aps: { alert: { title: SHELL_CANT_PUSH_TITLE, body: `${sidekickName}: ${asked}` }, sound: "default" },
    founderAlert: { kind: "repair-shell-cant", reportId: report.id, userId: report.user_id, sidekickId: report.sidekick_id },
  };
}

// Pushes the founder and stores what came of it on the report. Logged, never thrown.
async function alertFounderShellCant(env: SortBindings, report: SortableReport, sidekickName: string): Promise<void> {
  const founderId = makeFounderUserId(env);
  let outcome = "no founder set";
  try {
    if (founderId !== null) {
      outcome = await sendToUserDevices(env.DB, env, founderId, shellCantPayload(report, sidekickName), pushFetchFromEnv(env), Date.now());
    }
  } catch (error) {
    outcome = error instanceof Error ? error.message : String(error);
    console.error(`repair shell_cant alert for ${report.id} failed: ${outcome}`);
  }
  try {
    const storeOutcome = boundStatement(env.DB, "UPDATE repair_reports SET sort_alert = ? WHERE id = ?", outcome, report.id);
    await storeOutcome.run();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`repair shell_cant alert result for ${report.id} not stored: ${message}`);
  }
}

/* ---------- Sorting and placing ---------- */

// One request_received per report: a sort that finishes after the report was already placed (a
// late sort after the lane route put a stuck one in code) adds no second event.
function founderEventStatement(db: D1Database, reportId: string, createdAt: string): D1PreparedStatement {
  return boundStatement(
    db,
    `INSERT INTO repair_events (id, report_id, audience, kind, created_at)
     SELECT ?, ?, 'founder', 'request_received', ?
     WHERE NOT EXISTS (SELECT 1 FROM repair_events WHERE report_id = ? AND audience = 'founder' AND kind = 'request_received')`,
    crypto.randomUUID(),
    reportId,
    createdAt,
    reportId,
  );
}

// The setting lane writes settings:self, so it runs only while the report is still being sorted.
async function isStillSorting(db: D1Database, reportId: string): Promise<boolean> {
  const statement = boundStatement(db, "SELECT sort_status FROM repair_reports WHERE id = ?", reportId);
  const row = await statement.first<{ sort_status: string | null }>();
  return row !== null && row.sort_status === "sorting";
}

// What the setting lane did, on the report row (migration 0016)
function settingColumnsStatement(db: D1Database, reportId: string, outcome: SettingOutcome): D1PreparedStatement {
  const changesJson = outcome.applied ? JSON.stringify(outcome.changes) : null;
  const version = outcome.applied ? outcome.version : null;
  const problem = outcome.applied ? null : outcome.reason.slice(0, 300);
  return boundStatement(
    db,
    "UPDATE repair_reports SET setting_changes = ?, setting_version = ?, setting_problem = ?, setting_latency_ms = ?, setting_cost_usd = ? WHERE id = ?",
    changesJson,
    version,
    problem,
    outcome.latencyMs,
    outcome.costUsd,
    reportId,
  );
}

function settingLogFields(outcome: SettingOutcome): Record<string, unknown> {
  if (outcome.applied) {
    return { applied: true, keys: outcome.changes.map(changeKey), latencyMs: outcome.latencyMs, costUsd: outcome.costUsd };
  }
  return { applied: false, reason: outcome.reason, latencyMs: outcome.latencyMs, costUsd: outcome.costUsd };
}

function changeKey(change: { key: string }): string {
  return change.key;
}

// Sorts one report that is in sort_status 'sorting' and writes where it goes. Latency and cost add
// up over both sorts of an answered request. A runner lane also gets the founder's request event
// in the same batch, as before the sort existed.
export async function sortAndPlace(c: Context, report: SortableReport, strokesJson: string | null, answer: string | null): Promise<SortReply> {
  const env = c.env as SortBindings;
  const words = await sidekickWords(env.BUNDLES, report.sidekick_id, report.user_id);
  const input: SortInput = {
    transcript: askedText(report),
    sidekickName: words.name,
    sidekickDescription: words.description,
    drawing: describeStrokes(strokesJson),
    answer,
    settingLabels: words.settingLabels,
  };
  const result = await sortRequest(input, env.OPENROUTER_API_KEY, workerFetch);
  const shownName = words.fromManifest ? words.name : null;
  let placement = placementFor(result, shownName, answer !== null);
  // The setting lane runs here, before the row is written, so the row says what happened
  let settingOutcome: SettingOutcome | null = null;
  if (placement.lane === "setting" && !(await isStillSorting(env.DB, report.id))) {
    // Placed while this sort ran (the lane route put a stuck sort in code): change nothing
    placement = placementAfterSetting(placement, { applied: false, reason: "placed while sorting", latencyMs: 0, costUsd: 0 });
  }
  if (placement.lane === "setting") {
    const settingWords = answer === null ? input.transcript : `${input.transcript}\nAsked "What should it be?", they answered: "${answer}"`;
    const laneInput = { reportId: report.id, userId: report.user_id, sidekickId: report.sidekick_id, sidekickName: words.name, words: settingWords, drawing: input.drawing };
    settingOutcome = await runSettingLane(env, laneInput);
    placement = placementAfterSetting(placement, settingOutcome);
  }
  const placedAt = new Date().toISOString();
  const askedAt = placement.sortStatus === "asking" ? placedAt : null;
  const questionJson = placement.question === null ? null : JSON.stringify(placement.question);

  const updateRow = boundStatement(
    env.DB,
    `UPDATE repair_reports SET status = ?, sort_status = ?, lane = ?, sort_confidence = ?, sort_model = ?,
       sort_latency_ms = COALESCE(sort_latency_ms, 0) + ?, sort_cost_usd = COALESCE(sort_cost_usd, 0) + ?, sort_error = ?,
       sort_question = ?, sort_asked_at = ?, sort_message = ?, updated_at = ?
     WHERE id = ? AND sort_status = 'sorting'`,
    placement.status,
    placement.sortStatus,
    placement.lane,
    result.confidence,
    result.model,
    result.latencyMs,
    result.costUsd,
    result.error,
    questionJson,
    askedAt,
    placement.message,
    placedAt,
    report.id,
  );
  const statements = [updateRow];
  if (settingOutcome !== null) {
    statements.push(settingColumnsStatement(env.DB, report.id, settingOutcome));
  }
  if (placement.status === "queued") {
    statements.push(founderEventStatement(env.DB, report.id, placedAt));
  }
  await env.DB.batch(statements);

  console.log(
    JSON.stringify({
      event: "repair-sort",
      reportId: report.id,
      lane: placement.lane,
      modelLane: result.lane,
      confidence: result.confidence,
      model: result.model,
      latencyMs: result.latencyMs,
      costUsd: result.costUsd,
      error: result.error,
      answered: answer !== null,
      setting: settingOutcome === null ? undefined : settingLogFields(settingOutcome),
    }),
  );
  if (placement.lane === "shell_cant") {
    await runAfterResponse(c, alertFounderShellCant(env, report, words.name));
  }
  return replyFor(placement);
}

/* ---------- Sorting after the reply (founder, 2026-11-22) ---------- */

// Send closes repair mode at once: the Worker answers the upload first and sorts after the reply
// (waitUntil). The phone follows the lane with GET /repairs/lanes/:clientReportId.

// A sort still running this long after the report was stored did not finish (the Worker was cut
// off): the lane route puts it in code, up a lane, never down.
export const STUCK_SORT_MS = 60 * 1000;
const STUCK_SORT_ERROR = "sort did not finish";

// Puts a report still in sort_status 'sorting' in the code lane, with the founder's request
// event, as a sort that failed would have. Nothing happens when another sort placed it first.
async function placeInCode(db: D1Database, reportId: string, reason: string): Promise<boolean> {
  const placedAt = new Date().toISOString();
  const placeRow = boundStatement(
    db,
    "UPDATE repair_reports SET status = 'queued', sort_status = 'sorted', lane = 'code', sort_error = ?, updated_at = ? WHERE id = ? AND sort_status = 'sorting' RETURNING id",
    reason.slice(0, 300),
    placedAt,
    reportId,
  );
  const placed = await placeRow.all();
  if (placed.results.length === 0) {
    return false;
  }
  await founderEventStatement(db, reportId, placedAt).run();
  return true;
}

// sortAndPlace for a new report, never throwing: an error goes up to code, so the report is never
// left sorting.
export async function sortSafely(c: Context, report: SortableReport, strokesJson: string | null): Promise<SortReply> {
  try {
    return await sortAndPlace(c, report, strokesJson, null);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`repair sort for ${report.id} failed: ${message}`);
    const env = c.env as SortBindings;
    try {
      await placeInCode(env.DB, report.id, `sort failed: ${message}`);
    } catch (placeError) {
      const placeMessage = placeError instanceof Error ? placeError.message : String(placeError);
      console.error(`repair sort for ${report.id} not placed in code: ${placeMessage}`);
    }
    return { lane: FALLBACK_LANE };
  }
}

type LaneRow = StoredSortFields & {
  id: string;
  user_id: string;
  status: string;
  updated_at: string;
};

const CLIENT_REPORT_ID_PATTERN = /^[A-Za-z0-9-]{1,80}$/;

export function isStuckSort(row: { sort_status: string | null; updated_at: string }, nowMs: number): boolean {
  if (row.sort_status !== "sorting") {
    return false;
  }
  const updatedMs = Date.parse(row.updated_at);
  return Number.isFinite(updatedMs) && nowMs - updatedMs >= STUCK_SORT_MS;
}

async function readLaneRow(db: D1Database, userId: string, clientReportId: string): Promise<LaneRow | null> {
  const statement = boundStatement(db, "SELECT * FROM repair_reports WHERE user_id = ? AND client_report_id = ?", userId, clientReportId);
  return statement.first<LaneRow>();
}

// GET /repairs/lanes/:clientReportId -> where the phone's report went, found by the phone's own id:
//   { id, status, sortStatus, lane, question?, message?, setting? }
// sortStatus 'sorting': not yet (lane null); 'asking': the card waits (question); 'dropped': the
// card was not answered in 2 minutes; 'sorted': the lane is final. 404 when the caller has no such
// report (not uploaded yet, or someone else's).
export async function handleGetLane(c: Context) {
  const sortContext = c as unknown as SortContext;
  const db = sortContext.env.DB;
  const userId = c.get("userId") as string;
  const clientReportId = c.req.param("clientReportId") ?? "";
  if (!CLIENT_REPORT_ID_PATTERN.test(clientReportId)) {
    return c.json({ error: "bad report id" }, 400);
  }
  const nowMs = Date.now();
  await dropStaleQuestions(db, nowMs);
  let row = await readLaneRow(db, userId, clientReportId);
  if (row === null) {
    return c.json({ error: "no such report" }, 404);
  }
  if (isStuckSort(row, nowMs)) {
    await placeInCode(db, row.id, STUCK_SORT_ERROR);
    row = await readLaneRow(db, userId, clientReportId);
    if (row === null) {
      return c.json({ error: "no such report" }, 404);
    }
  }
  return c.json({ id: row.id, status: row.status, sortStatus: row.sort_status, ...replyFromStored(row) });
}

/* ---------- Dropping unanswered cards ---------- */

function answerCutoffIso(nowMs: number): string {
  return new Date(nowMs - ANSWER_WINDOW_MS).toISOString();
}

// Every card unanswered for 2 minutes becomes dropped, and each is logged. Run when the runner
// polls for a job and when an answer arrives, so no timer is needed.
export async function dropStaleQuestions(db: D1Database, nowMs: number): Promise<string[]> {
  const dropStatement = boundStatement(
    db,
    "UPDATE repair_reports SET sort_status = 'dropped', updated_at = ? WHERE sort_status = 'asking' AND sort_asked_at < ? RETURNING id, user_id, sidekick_id",
    new Date(nowMs).toISOString(),
    answerCutoffIso(nowMs),
  );
  const dropped = await dropStatement.all<{ id: string; user_id: string; sidekick_id: string }>();
  const droppedIds: string[] = [];
  for (const row of dropped.results) {
    console.log(JSON.stringify({ event: "repair-question-dropped", reportId: row.id, userId: row.user_id, sidekickId: row.sidekick_id }));
    droppedIds.push(row.id);
  }
  return droppedIds;
}

/* ---------- POST /repairs/:id/answer ---------- */

type AnswerBody = { kind: "option"; optionId: string } | { kind: "text"; text: string };

function readAnswerBody(body: unknown): AnswerBody | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }
  const fields = body as { optionId?: unknown; text?: unknown };
  if (typeof fields.optionId === "string" && fields.optionId.length > 0) {
    return { kind: "option", optionId: fields.optionId };
  }
  if (typeof fields.text === "string") {
    const trimmed = fields.text.trim();
    if (trimmed.length > 0 && trimmed.length <= MAX_ANSWER_LENGTH) {
      return { kind: "text", text: trimmed };
    }
  }
  return null;
}

// The words the answer adds to the request: the tapped option's label, or what they said.
function answerWords(answer: AnswerBody, questionJson: string | null): string | null {
  if (answer.kind === "text") {
    return answer.text;
  }
  if (questionJson === null) {
    return null;
  }
  const question = JSON.parse(questionJson) as Question;
  for (const option of question.options) {
    if (option.id === answer.optionId) {
      return option.label;
    }
  }
  return null;
}

const REPORT_ID_PATTERN = /^[0-9a-f-]{36}$/;

async function readSortRow(db: D1Database, reportId: string): Promise<SortRow | null> {
  const statement = boundStatement(db, "SELECT * FROM repair_reports WHERE id = ?", reportId);
  return statement.first<SortRow>();
}

// The answer joins the same request, which is sorted again. Only the reporter may answer; a card
// already answered is 409, one dropped is 410.
export async function handleAnswer(c: Context) {
  const sortContext = c as unknown as SortContext;
  const db = sortContext.env.DB;
  const reportId = c.req.param("id") ?? "";
  if (!REPORT_ID_PATTERN.test(reportId)) {
    return c.json({ error: "bad report id" }, 400);
  }
  let rawBody: unknown = null;
  try {
    rawBody = await c.req.json();
  } catch {
    rawBody = null;
  }
  const answer = readAnswerBody(rawBody);
  if (answer === null) {
    return c.json({ error: "optionId or text expected" }, 400);
  }
  const nowMs = Date.now();
  await dropStaleQuestions(db, nowMs);
  const row = await readSortRow(db, reportId);
  if (row === null || row.user_id !== c.get("userId")) {
    return c.json({ error: "no such report" }, 404);
  }
  if (row.sort_status === "dropped") {
    return c.json({ error: "question dropped" }, 410);
  }
  if (row.sort_status !== "asking") {
    return c.json({ error: "no question waiting" }, 409);
  }
  const words = answerWords(answer, row.sort_question);
  if (words === null) {
    return c.json({ error: "no such option" }, 400);
  }
  // One statement takes the card, so two answers never sort the same request twice.
  const takeCard = boundStatement(
    db,
    "UPDATE repair_reports SET sort_status = 'sorting', sort_answer = ?, updated_at = ? WHERE id = ? AND sort_status = 'asking' AND sort_asked_at >= ? RETURNING id",
    words,
    new Date(nowMs).toISOString(),
    reportId,
    answerCutoffIso(nowMs),
  );
  const taken = await takeCard.all();
  if (taken.results.length === 0) {
    return c.json({ error: "no question waiting" }, 409);
  }
  const strokesJson = await strokesText(sortContext.env.BUNDLES, row.strokes_key);
  const reply = await sortAndPlace(c, row, strokesJson, words);
  return c.json(reply);
}
