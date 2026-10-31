import { Hono } from "hono";
import type { Context, Next } from "hono";
import { requireSession } from "./auth";
import { FILE_ID_HEADER, FILE_ID_PATTERN, MAX_FILE_BYTES, fileKey, fileReference } from "./files";
import {
  MAKE_INBOX_PUSH_TITLE,
  MAKE_INBOX_SIDEKICK_ID,
  MAKE_SENDER_NAME,
  MAKE_SIDEKICK_ID,
  isNativeSidekick,
  makeFounderUserId,
} from "./make-sidekick";
import { sendMakeEventsAfterResponse } from "./push";
import type { PushBindings } from "./push";
import { nativeTypesFor, recordSchema } from "./record-types";
import { isRunnerToken } from "./repairs";
import type { CleanOp } from "./sync";

// Make (founder, 2026-10-24; docs/briefs/make-contract.md sections 3 and 5). A person asks for
// something in their "make" store; the founder answers from his "make-inbox" store. Both ride on
// /sync. This file holds:
//   makeOpProblem       the write rules for both stores, run in /sync/push after the schema check
//   makeCopyStatements  the copy step: a person's write lands in the founder's inbox under a key
//                       that starts with the person's id, the founder's write lands back in the
//                       person's store; same DB.batch as the pushed ops, so both or neither
//   /make routes        the founder's Built picker, and the server path that sends question cards
// Server-written ops never pass through /sync/push, so a copy is never copied again.

export type MakeBindings = PushBindings & {
  DB: D1Database;
  BUNDLES: R2Bucket;
  FILES?: R2Bucket;
  MAKE_FOUNDER_USER_ID?: string;
  REPAIR_RUNNER_TOKEN?: string;
};

type MakeVariables = {
  userId: string;
};

type MakeEnv = { Bindings: MakeBindings; Variables: MakeVariables };
type MakeContext = Context<MakeEnv>;

const MAKE_ITEM_ID_PATTERN = /^[A-Za-z0-9_-]{8,40}$/;
const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const FILE_REFERENCE_PATTERN = /^file:([A-Za-z0-9_-]{8,64})$/;
const PUSH_BODY_LIMIT = 120;
const MAX_OP_ID_LENGTH = 64;

type RecordKind = "req" | "message" | "card" | "answer" | "person";

// A key split into its parts. userId is set for inbox keys only; itemId is the message, card or
// answer's own id (absent for req: and person:).
type MakeKey = {
  kind: RecordKind;
  userId: string | null;
  reqId: string | null;
  itemId: string | null;
};

type StoredOp = { opId: string; value: Record<string, unknown> | null };

type OptionValue = { id?: unknown; label?: unknown; image?: unknown };

type CardValue = {
  question?: unknown;
  kind?: unknown;
  options?: unknown;
  allowsOwnWords?: unknown;
};

function boundStatement(db: D1Database, sql: string, ...params: unknown[]): D1PreparedStatement {
  const prepared = db.prepare(sql);
  return prepared.bind(...params);
}

function isRecordKind(text: string): text is RecordKind {
  return text === "req" || text === "message" || text === "card" || text === "answer" || text === "person";
}

/* ---------- Keys ---------- */

// The person's store: req:<r>, message:<r>:<m>, card:<r>:<c>, answer:<r>:<c>.
export function parsePersonKey(key: string): MakeKey | null {
  const parts = key.split(":");
  const kind = parts[0];
  if (!isRecordKind(kind) || kind === "person") {
    return null;
  }
  if (kind === "req") {
    const isRequestKey = parts.length === 2 && MAKE_ITEM_ID_PATTERN.test(parts[1]);
    return isRequestKey ? { kind, userId: null, reqId: parts[1], itemId: null } : null;
  }
  const isItemKey = parts.length === 3 && MAKE_ITEM_ID_PATTERN.test(parts[1]) && MAKE_ITEM_ID_PATTERN.test(parts[2]);
  return isItemKey ? { kind, userId: null, reqId: parts[1], itemId: parts[2] } : null;
}

// The founder's inbox: person:<u>, req:<u>:<r>, message:<u>:<r>:<m>, card:<u>:<r>:<c>,
// answer:<u>:<r>:<c>.
export function parseInboxKey(key: string): MakeKey | null {
  const parts = key.split(":");
  const kind = parts[0];
  if (!isRecordKind(kind) || parts.length < 2 || !USER_ID_PATTERN.test(parts[1])) {
    return null;
  }
  if (kind === "person") {
    return parts.length === 2 ? { kind, userId: parts[1], reqId: null, itemId: null } : null;
  }
  if (kind === "req") {
    const isRequestKey = parts.length === 3 && MAKE_ITEM_ID_PATTERN.test(parts[2]);
    return isRequestKey ? { kind, userId: parts[1], reqId: parts[2], itemId: null } : null;
  }
  const isItemKey = parts.length === 4 && MAKE_ITEM_ID_PATTERN.test(parts[2]) && MAKE_ITEM_ID_PATTERN.test(parts[3]);
  return isItemKey ? { kind, userId: parts[1], reqId: parts[2], itemId: parts[3] } : null;
}

// The key a record has in the person's store (no user id in it).
function personKeyOf(parsed: MakeKey): string {
  if (parsed.kind === "req") {
    return `req:${parsed.reqId}`;
  }
  return `${parsed.kind}:${parsed.reqId}:${parsed.itemId}`;
}

// The key the same record has in the founder's inbox.
function inboxKeyOf(personUserId: string, parsed: MakeKey): string {
  if (parsed.kind === "req") {
    return `req:${personUserId}:${parsed.reqId}`;
  }
  return `${parsed.kind}:${personUserId}:${parsed.reqId}:${parsed.itemId}`;
}

/* ---------- Reading stored ops ---------- */

function parseObject(text: string | null): Record<string, unknown> | null {
  if (text === null) {
    return null;
  }
  const parsed = JSON.parse(text) as unknown;
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return null;
  }
  return parsed as Record<string, unknown>;
}

// Every stored op of one key, oldest first.
async function storedOps(db: D1Database, userId: string, sidekickId: string, key: string): Promise<StoredOp[]> {
  const statement = boundStatement(db, "SELECT op_id, value FROM ops WHERE user_id = ? AND sidekick_id = ? AND key = ? ORDER BY seq", userId, sidekickId, key);
  const queryResult = await statement.all<{ op_id: string; value: string | null }>();
  const ops: StoredOp[] = [];
  for (const row of queryResult.results) {
    ops.push({ opId: row.op_id, value: parseObject(row.value) });
  }
  return ops;
}

async function latestStoredValue(db: D1Database, userId: string, sidekickId: string, key: string): Promise<Record<string, unknown> | null> {
  const ops = await storedOps(db, userId, sidekickId, key);
  if (ops.length === 0) {
    return null;
  }
  return ops[ops.length - 1].value;
}

function earlierOpsOfKey(earlierOps: CleanOp[], sidekickId: string, key: string): CleanOp[] {
  const matching: CleanOp[] = [];
  for (const earlierOp of earlierOps) {
    if (earlierOp.sidekickId === sidekickId && earlierOp.key === key) {
      matching.push(earlierOp);
    }
  }
  return matching;
}

// True when the key already has an op other than this one: stored, or earlier in the same push.
async function keyHasOtherOp(db: D1Database, userId: string, sidekickId: string, key: string, opId: string, earlierOps: CleanOp[]): Promise<boolean> {
  const stored = await storedOps(db, userId, sidekickId, key);
  for (const storedOp of stored) {
    if (storedOp.opId !== opId) {
      return true;
    }
  }
  const earlier = earlierOpsOfKey(earlierOps, sidekickId, key);
  for (const earlierOp of earlier) {
    if (earlierOp.opId !== opId) {
      return true;
    }
  }
  return false;
}

// True when the key has any op: stored, or earlier in the same push (a new request and its first
// message usually arrive in one push).
async function keyExists(db: D1Database, userId: string, sidekickId: string, key: string, earlierOps: CleanOp[]): Promise<boolean> {
  const earlier = earlierOpsOfKey(earlierOps, sidekickId, key);
  if (earlier.length > 0) {
    return true;
  }
  const stored = await storedOps(db, userId, sidekickId, key);
  return stored.length > 0;
}

function cardOptions(card: CardValue): OptionValue[] {
  if (!Array.isArray(card.options)) {
    return [];
  }
  return card.options as OptionValue[];
}

function isOptionOf(card: CardValue, optionId: unknown): boolean {
  const options = cardOptions(card);
  for (const option of options) {
    if (option.id === optionId) {
      return true;
    }
  }
  return false;
}

/* ---------- Write rules ---------- */

const NOT_ALLOWED = "not allowed";
const NO_DELETES = "Make records cannot be deleted";
const SERVER_ONLY = "written by Make only";

async function personOpProblem(db: D1Database, userId: string, op: CleanOp, value: Record<string, unknown> | null, earlierOps: CleanOp[]): Promise<string | null> {
  if (op.deleted === 1) {
    return NO_DELETES;
  }
  const parsed = parsePersonKey(op.key);
  if (parsed === null || value === null) {
    return "bad Make key";
  }
  if (parsed.kind === "card") {
    return SERVER_ONLY;
  }
  const requestKey = `req:${parsed.reqId}`;
  if (parsed.kind === "req") {
    if (await keyHasOtherOp(db, userId, MAKE_SIDEKICK_ID, op.key, op.opId, earlierOps)) {
      return "request already exists";
    }
    if (value.status !== "sent") {
      return "a new request has status sent";
    }
    const setsMakerFields = "sidekickId" in value || "plan" in value || "builtAt" in value;
    if (setsMakerFields) {
      return "sidekickId, plan and builtAt are set by Make only";
    }
    return null;
  }
  if (parsed.kind === "message") {
    if (value.from !== "person") {
      return "from must be person";
    }
    if (!(await keyExists(db, userId, MAKE_SIDEKICK_ID, requestKey, earlierOps))) {
      return "no such request";
    }
    return null;
  }
  // An answer: to a card the server sent, once, with one of its options or, when the card takes
  // them, the person's own words.
  const cardKey = `card:${parsed.reqId}:${parsed.itemId}`;
  const card = (await latestStoredValue(db, userId, MAKE_SIDEKICK_ID, cardKey)) as CardValue | null;
  if (card === null) {
    return "no such card";
  }
  if (value.cardId !== parsed.itemId) {
    return "cardId must match the key";
  }
  if (await keyHasOtherOp(db, userId, MAKE_SIDEKICK_ID, op.key, op.opId, earlierOps)) {
    return "card already answered";
  }
  if ("optionId" in value) {
    return isOptionOf(card, value.optionId) ? null : "optionId is not an option of this card";
  }
  return card.allowsOwnWords === true ? null : "this card takes a pick";
}

async function founderOpProblem(db: D1Database, env: MakeBindings, op: CleanOp, value: Record<string, unknown> | null, earlierOps: CleanOp[]): Promise<string | null> {
  if (op.deleted === 1) {
    return NO_DELETES;
  }
  const parsed = parseInboxKey(op.key);
  if (parsed === null || value === null || parsed.userId === null) {
    return "bad Make key";
  }
  if (parsed.kind === "card" || parsed.kind === "answer" || parsed.kind === "person") {
    return SERVER_ONLY;
  }
  if ("userId" in value && value.userId !== parsed.userId) {
    return "userId must match the key";
  }
  const requestKey = `req:${parsed.reqId}`;
  if (!(await keyExists(db, parsed.userId, MAKE_SIDEKICK_ID, requestKey, []))) {
    return "no such request";
  }
  if (parsed.kind === "message") {
    return value.from === "maker" ? null : "from must be maker";
  }
  if (value.status !== "built") {
    return null;
  }
  const sidekickId = value.sidekickId;
  if (typeof sidekickId !== "string" || typeof value.plan !== "string") {
    return "built needs sidekickId and plan";
  }
  if (isNativeSidekick(sidekickId)) {
    return "a request cannot be built into a built-in Sidekick";
  }
  const pointer = await env.BUNDLES.get(`sidekicks/${sidekickId}/current.json`);
  if (pointer === null) {
    return "no such Sidekick";
  }
  return null;
}

// Why a pushed op to make or make-inbox cannot be stored, or null. Runs after the schema check.
// earlierOps are the ops of the same push accepted before this one.
export async function makeOpProblem(db: D1Database, env: MakeBindings, userId: string, op: CleanOp, earlierOps: CleanOp[] = []): Promise<string | null> {
  const value = parseObject(op.value);
  if (op.sidekickId === MAKE_SIDEKICK_ID) {
    return personOpProblem(db, userId, op, value, earlierOps);
  }
  if (op.sidekickId !== MAKE_INBOX_SIDEKICK_ID) {
    return null;
  }
  const founderId = makeFounderUserId(env);
  if (founderId === null || userId !== founderId) {
    return NOT_ALLOWED;
  }
  return founderOpProblem(db, env, op, value, earlierOps);
}

/* ---------- The copy step ---------- */

export type FileCopy = { fromUserId: string; toUserId: string; fileId: string };

// The statements to add to the push's batch. eventIndexes points at the make_events inserts
// inside statements, so the caller can push only the events this batch inserted.
export type MakeCopyPlan = {
  statements: D1PreparedStatement[];
  eventIndexes: Array<{ index: number; eventId: string }>;
  fileCopies: FileCopy[];
};

function hexOfBytes(bytes: Uint8Array): string {
  let hex = "";
  for (const byte of bytes) {
    hex += byte.toString(16).padStart(2, "0");
  }
  return hex;
}

// A copy's op id is fixed by its source and target, so building it twice stores it once.
export async function copyOpId(sourceOpId: string, targetUserId: string): Promise<string> {
  const input = new TextEncoder().encode(`${sourceOpId}>${targetUserId}`);
  const digest = await crypto.subtle.digest("SHA-256", input);
  const hex = hexOfBytes(new Uint8Array(digest));
  return `mk${hex.slice(0, 40)}`;
}

export function personRecordOpId(userId: string): string {
  const opId = `mk-person-${userId}`;
  return opId.slice(0, MAX_OP_ID_LENGTH);
}

function copyOpStatement(db: D1Database, opId: string, targetUserId: string, sidekickId: string, key: string, value: unknown, clientTime: string | null, receivedAt: string): D1PreparedStatement {
  const valueText = JSON.stringify(value);
  return boundStatement(
    db,
    `INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, client_time, received_at)
     VALUES (?, ?, ?, ?, ?, 0, ?, ?) ON CONFLICT(op_id) DO NOTHING`,
    opId,
    targetUserId,
    sidekickId,
    key,
    valueText,
    clientTime,
    receivedAt,
  );
}

type MakeEvent = {
  id: string;
  audience: "person" | "founder";
  userId: string;
  aboutUserId: string;
  requestId: string;
  kind: "card" | "built" | "message" | "answer";
  title: string;
  body: string;
};

export function makeEventStatement(db: D1Database, event: MakeEvent, createdAt: string): D1PreparedStatement {
  return boundStatement(
    db,
    `INSERT INTO make_events (id, audience, user_id, about_user_id, request_id, kind, title, body, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING`,
    event.id,
    event.audience,
    event.userId,
    event.aboutUserId,
    event.requestId,
    event.kind,
    event.title,
    event.body,
    createdAt,
  );
}

// Push text is cut to 120 characters, counted as a person would (an emoji is one).
export function pushBodyText(text: string): string {
  const characters = Array.from(text);
  if (characters.length <= PUSH_BODY_LIMIT) {
    return text;
  }
  const kept = characters.slice(0, PUSH_BODY_LIMIT - 1);
  return `${kept.join("")}…`;
}

// Every file:<id> anywhere in a record.
export function fileIdsInValue(value: unknown): string[] {
  if (typeof value === "string") {
    const match = FILE_REFERENCE_PATTERN.exec(value);
    return match === null ? [] : [match[1]];
  }
  if (typeof value !== "object" || value === null) {
    return [];
  }
  const children = Array.isArray(value) ? value : Object.values(value);
  const fileIds: string[] = [];
  for (const child of children) {
    fileIds.push(...fileIdsInValue(child));
  }
  return fileIds;
}

function withoutUserId(value: Record<string, unknown>): Record<string, unknown> {
  const copy: Record<string, unknown> = {};
  for (const [fieldName, fieldValue] of Object.entries(value)) {
    if (fieldName !== "userId") {
      copy[fieldName] = fieldValue;
    }
  }
  return copy;
}

async function userName(db: D1Database, userId: string): Promise<string> {
  const statement = boundStatement(db, "SELECT name FROM users WHERE id = ?", userId);
  const row = await statement.first<{ name: string }>();
  return row?.name ?? userId;
}

// What the founder's push says a person answered: the option's label, else "Design <n>", else
// the person's own words.
function answerText(card: CardValue | null, answer: Record<string, unknown>): string {
  if (typeof answer.text === "string") {
    return answer.text;
  }
  const options = card === null ? [] : cardOptions(card);
  for (let index = 0; index < options.length; index += 1) {
    const option = options[index];
    if (option.id !== answer.optionId) {
      continue;
    }
    if (typeof option.label === "string") {
      return option.label;
    }
    return `Design ${index + 1}`;
  }
  return String(answer.optionId);
}

type PlanBuilder = {
  db: D1Database;
  founderId: string;
  receivedAt: string;
  plan: MakeCopyPlan;
  personRecordsAdded: Set<string>;
  namesByUserId: Map<string, string>;
};

function addEvent(builder: PlanBuilder, event: MakeEvent): void {
  const statement = makeEventStatement(builder.db, event, builder.receivedAt);
  builder.plan.eventIndexes.push({ index: builder.plan.statements.length, eventId: event.id });
  builder.plan.statements.push(statement);
}

function addFileCopies(builder: PlanBuilder, value: unknown, fromUserId: string, toUserId: string): void {
  const fileIds = fileIdsInValue(value);
  for (const fileId of fileIds) {
    builder.plan.fileCopies.push({ fromUserId, toUserId, fileId });
  }
}

async function cachedUserName(builder: PlanBuilder, userId: string): Promise<string> {
  const cached = builder.namesByUserId.get(userId);
  if (cached !== undefined) {
    return cached;
  }
  const name = await userName(builder.db, userId);
  builder.namesByUserId.set(userId, name);
  return name;
}

// A person's req:, message: or answer: goes to the founder's inbox; the first one also writes
// person:<userId> (a fixed op id, so only the first is stored).
async function addPersonToFounderCopy(builder: PlanBuilder, personUserId: string, op: CleanOp, value: Record<string, unknown>): Promise<void> {
  const parsed = parsePersonKey(op.key);
  if (parsed === null || parsed.kind === "card") {
    return;
  }
  const founderId = builder.founderId;
  const name = await cachedUserName(builder, personUserId);
  if (!builder.personRecordsAdded.has(personUserId)) {
    builder.personRecordsAdded.add(personUserId);
    const personValue = { $type: "make.person", userId: personUserId, name: name.slice(0, 64), firstAt: builder.receivedAt };
    const personStatement = copyOpStatement(builder.db, personRecordOpId(personUserId), founderId, MAKE_INBOX_SIDEKICK_ID, `person:${personUserId}`, personValue, null, builder.receivedAt);
    builder.plan.statements.push(personStatement);
  }
  const inboxValue = { ...value, userId: personUserId };
  const targetOpId = await copyOpId(op.opId, founderId);
  const copyStatement = copyOpStatement(builder.db, targetOpId, founderId, MAKE_INBOX_SIDEKICK_ID, inboxKeyOf(personUserId, parsed), inboxValue, op.clientTime, builder.receivedAt);
  builder.plan.statements.push(copyStatement);
  addFileCopies(builder, value, personUserId, founderId);

  const requestId = parsed.reqId ?? "";
  if (parsed.kind === "message") {
    const body = pushBodyText(`${name}: ${String(value.text)}`);
    const event: MakeEvent = { id: `msg:${op.opId}`, audience: "founder", userId: founderId, aboutUserId: personUserId, requestId, kind: "message", title: MAKE_INBOX_PUSH_TITLE, body };
    addEvent(builder, event);
  }
  if (parsed.kind === "answer") {
    const cardKey = `card:${parsed.reqId}:${parsed.itemId}`;
    const card = (await latestStoredValue(builder.db, personUserId, MAKE_SIDEKICK_ID, cardKey)) as CardValue | null;
    const body = pushBodyText(`${name}: ${answerText(card, value)}`);
    const event: MakeEvent = { id: `ans:${op.opId}`, audience: "founder", userId: founderId, aboutUserId: personUserId, requestId, kind: "answer", title: MAKE_INBOX_PUSH_TITLE, body };
    addEvent(builder, event);
  }
}

// The founder's req:<u>:<r> or message:<u>:<r>:<m> goes back to person <u>'s store. Built also
// assigns the Sidekick to the person and pushes to them.
async function addFounderToPersonCopy(builder: PlanBuilder, op: CleanOp, value: Record<string, unknown>): Promise<void> {
  const parsed = parseInboxKey(op.key);
  if (parsed === null || parsed.userId === null || (parsed.kind !== "req" && parsed.kind !== "message")) {
    return;
  }
  const personUserId = parsed.userId;
  const personValue = withoutUserId(value);
  const targetOpId = await copyOpId(op.opId, personUserId);
  const copyStatement = copyOpStatement(builder.db, targetOpId, personUserId, MAKE_SIDEKICK_ID, personKeyOf(parsed), personValue, op.clientTime, builder.receivedAt);
  builder.plan.statements.push(copyStatement);
  addFileCopies(builder, value, builder.founderId, personUserId);

  const isBuilt = parsed.kind === "req" && value.status === "built" && typeof value.sidekickId === "string";
  if (!isBuilt) {
    return;
  }
  // Built again after the person deleted it: theirs again, at the end of the grid like a new one
  // (settings-delete, 2026-10-31); one never deleted keeps its place
  const assign = boundStatement(builder.db, "INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, ?) ON CONFLICT(user_id, sidekick_id) DO UPDATE SET removed_at = NULL, assigned_at = excluded.assigned_at WHERE assignments.removed_at IS NOT NULL", personUserId, value.sidekickId, builder.receivedAt);
  builder.plan.statements.push(assign);
  const requestId = parsed.reqId ?? "";
  const body = pushBodyText(`${String(value.title)}: Built`);
  const event: MakeEvent = { id: `built:${personUserId}:${requestId}`, audience: "person", userId: personUserId, aboutUserId: personUserId, requestId, kind: "built", title: MAKE_SENDER_NAME, body };
  addEvent(builder, event);
}

// The statements that copy this push's accepted Make ops to the other side. Built for every
// accepted op, also ones stored by an earlier push: copy ids are fixed, so nothing is stored
// twice and an earlier push that failed half way is completed. Nothing is copied while
// MAKE_FOUNDER_USER_ID is unset.
export async function makeCopyStatements(db: D1Database, env: MakeBindings, userId: string, ops: CleanOp[], receivedAt: string): Promise<MakeCopyPlan> {
  const plan: MakeCopyPlan = { statements: [], eventIndexes: [], fileCopies: [] };
  const founderId = makeFounderUserId(env);
  if (founderId === null) {
    return plan;
  }
  // A founder id that names no user (a typo in wrangler.jsonc) would fail every push on the
  // ops foreign key; the person's writes are stored and nothing is copied instead.
  if (!(await userExists(db, founderId))) {
    console.error("MAKE_FOUNDER_USER_ID names no user; Make copies skipped");
    return plan;
  }
  const builder: PlanBuilder = { db, founderId, receivedAt, plan, personRecordsAdded: new Set(), namesByUserId: new Map() };
  for (const op of ops) {
    const value = parseObject(op.value);
    if (op.deleted === 1 || value === null) {
      continue;
    }
    if (op.sidekickId === MAKE_SIDEKICK_ID) {
      await addPersonToFounderCopy(builder, userId, op, value);
    }
    const isFounderWrite = op.sidekickId === MAKE_INBOX_SIDEKICK_ID && userId === founderId;
    if (isFounderWrite) {
      await addFounderToPersonCopy(builder, op, value);
    }
  }
  return plan;
}

// The ids of the events the batch inserted now (an event stored before inserts nothing).
export function insertedEventIds(plan: MakeCopyPlan, batchResults: D1Result[], offset: number): string[] {
  const eventIds: string[] = [];
  for (const eventIndex of plan.eventIndexes) {
    const result = batchResults[offset + eventIndex.index];
    const changes = result?.meta?.changes ?? 0;
    if (changes > 0) {
      eventIds.push(eventIndex.eventId);
    }
  }
  return eventIds;
}

/* ---------- Files ---------- */

// Copies one file from one user's folder to another's, keeping its type. Never overwrites: a file
// already at the target is left as it is. Returns false when the source does not exist.
export async function copyFileIfMissing(files: R2Bucket, fromUserId: string, toUserId: string, fileId: string): Promise<boolean> {
  const targetKey = fileKey(toUserId, fileId);
  const existing = await files.head(targetKey);
  if (existing !== null) {
    return true;
  }
  const source = await files.get(fileKey(fromUserId, fileId));
  if (source === null) {
    return false;
  }
  const bytes = await source.arrayBuffer();
  await files.put(targetKey, bytes, {
    httpMetadata: source.httpMetadata,
    customMetadata: { userId: toUserId, copiedFrom: fromUserId, uploadedAt: new Date().toISOString() },
  });
  return true;
}

export async function copyMakeFiles(files: R2Bucket | undefined, fileCopies: FileCopy[]): Promise<void> {
  if (files === undefined) {
    return;
  }
  for (const fileCopy of fileCopies) {
    await copyFileIfMissing(files, fileCopy.fromUserId, fileCopy.toUserId, fileCopy.fileId);
  }
}

/* ---------- Routes ---------- */

async function readJsonBody(c: MakeContext): Promise<Record<string, unknown>> {
  try {
    const body = await c.req.json();
    if (typeof body === "object" && body !== null && !Array.isArray(body)) {
      return body as Record<string, unknown>;
    }
    return {};
  } catch {
    return {};
  }
}

const NOT_FOUND = { error: "not found" };
const NOT_SET_UP = { error: "Make is not set up on this server" };

// The founder's session only. Anyone else signed in gets a 404, as if the route did not exist.
async function requireFounder(c: MakeContext, next: Next) {
  const founderId = makeFounderUserId(c.env);
  let isFounder = false;
  async function markFounder() {
    isFounder = founderId !== null && c.get("userId") === founderId;
  }
  const sessionRefusal = await requireSession(c as unknown as Parameters<typeof requireSession>[0], markFounder);
  if (sessionRefusal) {
    return sessionRefusal;
  }
  if (!isFounder) {
    return c.json(NOT_FOUND, 404);
  }
  await next();
}

// The repair runner's token (Claude skills on the Mac mini) or the founder's session.
async function requireRunnerOrFounder(c: MakeContext, next: Next) {
  if (makeFounderUserId(c.env) === null) {
    return c.json(NOT_SET_UP, 503);
  }
  if (await isRunnerToken(c as unknown as Parameters<typeof isRunnerToken>[0])) {
    await next();
    return;
  }
  return requireFounder(c, next);
}

type PickerSidekick = { id: string; name: string; version: string };

// Sidekick ids under sidekicks/: from R2's delimited prefixes, else from every key listed.
async function baseSidekickIds(bucket: R2Bucket): Promise<string[]> {
  const sidekickIds = new Set<string>();
  let cursor: string | undefined = undefined;
  for (;;) {
    const listOptions: R2ListOptions = { prefix: "sidekicks/", delimiter: "/", cursor };
    const listing: R2Objects = await bucket.list(listOptions);
    const delimitedPrefixes = listing.delimitedPrefixes ?? [];
    for (const prefix of delimitedPrefixes) {
      const prefixParts = prefix.split("/");
      sidekickIds.add(prefixParts[1]);
    }
    for (const object of listing.objects) {
      const keyParts = object.key.split("/");
      if (keyParts.length >= 3) {
        sidekickIds.add(keyParts[1]);
      }
    }
    if (!listing.truncated) {
      break;
    }
    cursor = (listing as { cursor?: string }).cursor;
  }
  const sortedIds = Array.from(sidekickIds);
  sortedIds.sort();
  return sortedIds;
}

async function pickerEntry(bucket: R2Bucket, sidekickId: string): Promise<PickerSidekick | null> {
  const pointerObject = await bucket.get(`sidekicks/${sidekickId}/current.json`);
  if (pointerObject === null) {
    return null;
  }
  const pointer = (await pointerObject.json()) as { version?: unknown };
  if (typeof pointer.version !== "string") {
    return null;
  }
  const manifestObject = await bucket.get(`sidekicks/${sidekickId}/${pointer.version}/manifest.json`);
  const manifest = manifestObject === null ? null : ((await manifestObject.json()) as { name?: unknown });
  const name = typeof manifest?.name === "string" ? manifest.name : sidekickId;
  return { id: sidekickId, name, version: pointer.version };
}

// GET /make/sidekicks -> {sidekicks:[{id, name, version}]}: every base Sidekick, for the Built
// picker. Built-in Sidekicks are left out (a request cannot become one).
async function handlePickerSidekicks(c: MakeContext) {
  const sidekickIds = await baseSidekickIds(c.env.BUNDLES);
  const sidekicks: PickerSidekick[] = [];
  for (const sidekickId of sidekickIds) {
    if (isNativeSidekick(sidekickId)) {
      continue;
    }
    const entry = await pickerEntry(c.env.BUNDLES, sidekickId);
    if (entry !== null) {
      sidekicks.push(entry);
    }
  }
  return c.json({ sidekicks });
}

async function userExists(db: D1Database, userId: string): Promise<boolean> {
  const statement = boundStatement(db, "SELECT 1 AS found FROM users WHERE id = ?", userId);
  const row = await statement.first();
  return row !== null;
}

function newMakeId(): string {
  const uuid = crypto.randomUUID();
  return uuid.replaceAll("-", "");
}

// POST /make/files?userId=<u>, the bytes as the body: a picture for a question card. Stored in the
// founder's folder and copied to the person's, so both can open it. {id, ref}: 201 stored now,
// 200 when the id was stored before.
async function handleMakeFile(c: MakeContext) {
  const files = c.env.FILES;
  const founderId = makeFounderUserId(c.env);
  if (files === undefined || founderId === null) {
    return c.json(NOT_SET_UP, 503);
  }
  const personUserId = c.req.query("userId") ?? "";
  if (!USER_ID_PATTERN.test(personUserId) || !(await userExists(c.env.DB, personUserId))) {
    return c.json({ error: "no such person" }, 404);
  }
  const declaredLength = Number(c.req.header("Content-Length") ?? "0");
  if (declaredLength > MAX_FILE_BYTES) {
    return c.json({ error: `file is over ${MAX_FILE_BYTES} bytes` }, 413);
  }
  const requestedId = c.req.header(FILE_ID_HEADER);
  if (requestedId !== undefined && !FILE_ID_PATTERN.test(requestedId)) {
    return c.json({ error: `${FILE_ID_HEADER} must be 8 to 64 letters, digits, - or _` }, 400);
  }
  const fileId = requestedId ?? newMakeId();
  const founderKey = fileKey(founderId, fileId);
  const existing = await files.head(founderKey);
  let status: 200 | 201 = 200;
  if (existing === null) {
    const bytes = await c.req.arrayBuffer();
    if (bytes.byteLength === 0) {
      return c.json({ error: "file is empty" }, 400);
    }
    if (bytes.byteLength > MAX_FILE_BYTES) {
      return c.json({ error: `file is over ${MAX_FILE_BYTES} bytes` }, 413);
    }
    const contentType = c.req.header("Content-Type") ?? "application/octet-stream";
    await files.put(founderKey, bytes, {
      httpMetadata: { contentType },
      customMetadata: { userId: founderId, uploadedAt: new Date().toISOString() },
    });
    status = 201;
  }
  await copyFileIfMissing(files, founderId, personUserId, fileId);
  return c.json({ id: fileId, ref: fileReference(fileId) }, status);
}

type CardInput = {
  personUserId: string;
  requestId: string;
  cardId: string;
  value: Record<string, unknown>;
};

function cleanCardInput(body: Record<string, unknown>, sentAt: string): CardInput | { error: string } {
  const personUserId = body.userId;
  if (typeof personUserId !== "string" || !USER_ID_PATTERN.test(personUserId)) {
    return { error: "bad userId" };
  }
  const requestId = body.requestId;
  if (typeof requestId !== "string" || !MAKE_ITEM_ID_PATTERN.test(requestId)) {
    return { error: "bad requestId" };
  }
  const givenCardId = body.cardId;
  if (givenCardId !== undefined && (typeof givenCardId !== "string" || !MAKE_ITEM_ID_PATTERN.test(givenCardId))) {
    return { error: "bad cardId" };
  }
  const cardId = typeof givenCardId === "string" ? givenCardId : newMakeId();
  const value = {
    $type: "make.card",
    question: body.question,
    kind: body.kind,
    options: body.options,
    allowsOwnWords: body.allowsOwnWords,
    sentAt,
  };
  const cardKey = `card:${requestId}:${cardId}`;
  const makeTypes = nativeTypesFor(MAKE_SIDEKICK_ID);
  const problem = recordSchema.checkRecord(makeTypes, cardKey, value);
  if (problem !== null) {
    return { error: problem };
  }
  return { personUserId, requestId, cardId, value };
}

// Every picture of the card is in the person's folder (copied from the founder's when needed).
async function missingCardFile(files: R2Bucket | undefined, founderId: string, personUserId: string, value: Record<string, unknown>): Promise<string | null> {
  const fileIds = fileIdsInValue(value.options);
  if (fileIds.length === 0) {
    return null;
  }
  if (files === undefined) {
    return "files are not set up on this server";
  }
  for (const fileId of fileIds) {
    const present = await copyFileIfMissing(files, founderId, personUserId, fileId);
    if (!present) {
      return `no such file: ${fileId}`;
    }
  }
  return null;
}

function cardPushBody(value: Record<string, unknown>): string {
  if (value.kind === "design") {
    const optionCount = Array.isArray(value.options) ? value.options.length : 0;
    return `${optionCount} designs`;
  }
  return pushBodyText(String(value.question));
}

// POST /make/cards {userId, requestId, cardId?, question, kind, options, allowsOwnWords} ->
// {cardId}. Writes the card to the person (op mkcard-<cardId>-p) and to the founder's inbox (op
// mkcard-<cardId>-f) in one batch, then pushes to the person. The same cardId again changes
// nothing.
async function handleMakeCard(c: MakeContext) {
  const founderId = makeFounderUserId(c.env);
  if (founderId === null) {
    return c.json(NOT_SET_UP, 503);
  }
  const body = await readJsonBody(c);
  const sentAt = new Date().toISOString();
  const input = cleanCardInput(body, sentAt);
  if ("error" in input) {
    return c.json({ error: input.error }, 400);
  }
  const requestKey = `req:${input.requestId}`;
  const request = await latestStoredValue(c.env.DB, input.personUserId, MAKE_SIDEKICK_ID, requestKey);
  if (request === null) {
    return c.json({ error: "no such request" }, 404);
  }
  const fileProblem = await missingCardFile(c.env.FILES, founderId, input.personUserId, input.value);
  if (fileProblem !== null) {
    return c.json({ error: fileProblem }, 400);
  }

  const personKey = `card:${input.requestId}:${input.cardId}`;
  const inboxKey = `card:${input.personUserId}:${input.requestId}:${input.cardId}`;
  const inboxValue = { ...input.value, userId: input.personUserId };
  const personStatement = copyOpStatement(c.env.DB, `mkcard-${input.cardId}-p`, input.personUserId, MAKE_SIDEKICK_ID, personKey, input.value, null, sentAt);
  const inboxStatement = copyOpStatement(c.env.DB, `mkcard-${input.cardId}-f`, founderId, MAKE_INBOX_SIDEKICK_ID, inboxKey, inboxValue, null, sentAt);
  const event: MakeEvent = {
    id: `card:${input.cardId}`,
    audience: "person",
    userId: input.personUserId,
    aboutUserId: input.personUserId,
    requestId: input.requestId,
    kind: "card",
    title: MAKE_SENDER_NAME,
    body: cardPushBody(input.value),
  };
  const eventStatement = makeEventStatement(c.env.DB, event, sentAt);
  const batchResults = await c.env.DB.batch([personStatement, inboxStatement, eventStatement]);
  const eventChanges = batchResults[2]?.meta?.changes ?? 0;
  if (eventChanges > 0) {
    await sendMakeEventsAfterResponse(c, [event.id]);
  }
  return c.json({ cardId: input.cardId });
}

export const makeRoutes = new Hono<MakeEnv>();
makeRoutes.get("/sidekicks", requireFounder, handlePickerSidekicks);
makeRoutes.post("/files", requireRunnerOrFounder, handleMakeFile);
makeRoutes.post("/cards", requireRunnerOrFounder, handleMakeCard);
