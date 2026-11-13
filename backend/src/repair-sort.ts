import type { Context } from "hono";
import { askedText } from "./edit-failed";
import { makeFounderUserId } from "./make-sidekick";
import { pushFetchFromEnv, runAfterResponse, sendToUserDevices } from "./push";
import type { PushBindings } from "./push";
import { FALLBACK_LANE, describeStrokes, isGuessId, sortRequest } from "./repair-sort-model";
import type { GuessId, Lane, SortInput, SortResult } from "./repair-sort-model";

// Repair lanes, the sort step (founder, 2026-11-13; docs/briefs/repair-lanes.md W2). A repair
// report is sorted before any runner can claim it: sort_status 'sorting', then the lane decides
// what happens (migration 0015 says why the status column itself cannot hold 'sorting').
//
//   code, setting, look  -> status queued: the runner does it (setting and look until W5/W6 build
//                           those lanes: up a lane, never down)
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

// Lanes the runner works on today.
const RUNNER_LANES = new Set<Lane>(["code", "setting", "look"]);
// After an answer the card is never shown again, and an answer is never chat: both go up to code.
const LANES_NOT_AFTER_ANSWER = new Set<Lane>(["ask_back", "not_a_request"]);
const MAX_OPTIONS = 3;

// What each guess looks like on the card. icon is an SF Symbol name the shell draws.
export const CARD_OPTIONS: Record<GuessId, { label: string; icon: string }> = {
  other_icon: { label: "Other icon", icon: "photo" },
  smaller: { label: "Smaller", icon: "arrow.down.right.and.arrow.up.left" },
  bigger: { label: "Bigger", icon: "arrow.up.left.and.arrow.down.right" },
  other_colour: { label: "Other colour", icon: "paintpalette" },
  remove: { label: "Remove", icon: "eye.slash" },
  move: { label: "Move it", icon: "arrow.up.and.down.and.arrow.left.and.right" },
  other_words: { label: "Other words", icon: "textformat" },
  other_layout: { label: "Other layout", icon: "square.grid.2x2" },
};
// The mockup's three (repair-ask-back-2026-11-08.html, "A · Cards"): used to fill a short card.
const DEFAULT_GUESSES: GuessId[] = ["other_icon", "smaller", "remove"];

export type CardOption = { id: GuessId; label: string; icon: string };
export type Question = { text: string; options: CardOption[] };
export type SortReply = { lane: Lane; question?: Question; message?: string };

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

// 3 options (the card shows 2-3): the sort's guesses first, then the mockup's defaults fill a
// short card, so a card never has fewer than 2.
export function questionFor(guesses: GuessId[]): Question {
  const chosen: GuessId[] = [];
  for (const guessId of guesses.concat(DEFAULT_GUESSES)) {
    if (!chosen.includes(guessId) && chosen.length < MAX_OPTIONS) {
      chosen.push(guessId);
    }
  }
  const options: CardOption[] = [];
  for (const guessId of chosen) {
    const look = CARD_OPTIONS[guessId];
    options.push({ id: guessId, label: look.label, icon: look.icon });
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
type SidekickWords = { name: string; description: string | null; fromManifest: boolean };

// The person's current copy's manifest (their own pointer, else the shared page), as the repair
// agent sees it. Missing or unreadable: the Sidekick's id stands in for its name.
async function sidekickWords(bucket: R2Bucket, sidekickId: string, userId: string): Promise<SidekickWords> {
  const fallback = { name: sidekickId, description: null, fromManifest: false };
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
      const manifest = (await manifestObject.json()) as { name?: unknown; agent?: { description?: unknown } };
      const name = typeof manifest.name === "string" && manifest.name.length > 0 ? manifest.name : sidekickId;
      const description = typeof manifest.agent?.description === "string" ? manifest.agent.description : null;
      return { name, description, fromManifest: true };
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
};

// The lane decides the row's status and what the phone hears. After an answer, ask_back and
// not_a_request are read as code (up a lane, never down).
export function placementFor(result: SortResult, sidekickName: string | null, afterAnswer: boolean): Placement {
  const lane: Lane = afterAnswer && LANES_NOT_AFTER_ANSWER.has(result.lane) ? FALLBACK_LANE : result.lane;
  const status = RUNNER_LANES.has(lane) ? "queued" : "received";
  if (lane === "ask_back") {
    return { lane, status, sortStatus: "asking", question: questionFor(result.guesses), message: null };
  }
  if (lane === "not_a_request") {
    return { lane, status, sortStatus: "sorted", question: null, message: NOT_A_REQUEST_TEXT };
  }
  if (lane === "shell_cant") {
    return { lane, status, sortStatus: "sorted", question: null, message: shellCantMessage(sidekickName) };
  }
  return { lane, status, sortStatus: "sorted", question: null, message: null };
}

export function replyFor(placement: Placement): SortReply {
  const reply: SortReply = { lane: placement.lane };
  if (placement.question !== null) {
    reply.question = placement.question;
  }
  if (placement.message !== null) {
    reply.message = placement.message;
  }
  return reply;
}

// The stored reply, for a retry of a report the phone already sent.
type StoredReply = { lane: string | null; question?: Question; message?: string };

export function replyFromStored(row: { lane: string | null; sort_question: string | null; sort_message: string | null; sort_status: string | null }): StoredReply {
  const reply: StoredReply = { lane: row.lane };
  if (row.sort_status === "asking" && row.sort_question !== null) {
    reply.question = JSON.parse(row.sort_question) as Question;
  }
  if (row.sort_message !== null) {
    reply.message = row.sort_message;
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

function founderEventStatement(db: D1Database, reportId: string, createdAt: string): D1PreparedStatement {
  return boundStatement(
    db,
    "INSERT INTO repair_events (id, report_id, audience, kind, created_at) VALUES (?, ?, 'founder', 'request_received', ?)",
    crypto.randomUUID(),
    reportId,
    createdAt,
  );
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
  };
  const result = await sortRequest(input, env.OPENROUTER_API_KEY, workerFetch);
  const shownName = words.fromManifest ? words.name : null;
  const placement = placementFor(result, shownName, answer !== null);
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
    }),
  );
  if (placement.lane === "shell_cant") {
    await runAfterResponse(c, alertFounderShellCant(env, report, words.name));
  }
  return replyFor(placement);
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
  if (!isGuessId(answer.optionId) || questionJson === null) {
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
