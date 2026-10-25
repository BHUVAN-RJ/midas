// Usage, from backend/:
//   node scripts/make-card.mjs --env staging --user <userId> --request <reqId> \
//     --question "Which one?" --option "Big buttons" --option "Small buttons" [--own-words]
//   node scripts/make-card.mjs --env staging --user <userId> --request <reqId> \
//     --question "Which look?" --kind design --image a.png --image b.png [--label "A" --label "B"]
// Sends one question card to a person's Make request (founder, 2026-10-24;
// docs/briefs/make-contract.md section 5): pictures first through POST /make/files, then
// POST /make/cards. The person's phone gets the card in its thread and a push.
// Uses the runner token: MIDAS_STAGING_RUNNER_TOKEN or MIDAS_LIVE_RUNNER_TOKEN (the same values as
// the Mac mini runner's ~/.midas-runner/env). --card-id makes a retry land on the same card.
import { readFileSync } from "node:fs";
import { basename, extname } from "node:path";
import { pathToFileURL } from "node:url";
import { environmentFromArgs } from "./environments.mjs";

export const BACKEND_URLS = {
  staging: "https://midas-api-staging.midas-backend.workers.dev",
  live: "https://midas-api.midas-backend.workers.dev",
};

export const TOKEN_VARIABLES = {
  staging: "MIDAS_STAGING_RUNNER_TOKEN",
  live: "MIDAS_LIVE_RUNNER_TOKEN",
};

const IMAGE_TYPES = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp", ".heic": "image/heic" };
const REPEATED_FLAGS = new Set(["--option", "--image", "--label"]);
const VALUE_FLAGS = new Set(["--env", "--user", "--request", "--question", "--kind", "--card-id"]);

// Ids Make accepts: 8 to 40 letters, digits, - or _.
export function newMakeId() {
  const uuid = crypto.randomUUID();
  return uuid.replaceAll("-", "");
}

// The flags as one object; repeated flags as lists. Throws on an unknown flag.
export function parseMakeCardArgs(argv) {
  const parsed = { options: [], images: [], labels: [], ownWords: false };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (flag === "--own-words") {
      parsed.ownWords = true;
      continue;
    }
    const isKnown = REPEATED_FLAGS.has(flag) || VALUE_FLAGS.has(flag);
    if (!isKnown || index + 1 >= argv.length) {
      throw new Error(`unknown or incomplete flag: ${flag}`);
    }
    const flagValue = argv[index + 1];
    index += 1;
    if (flag === "--option") {
      parsed.options.push(flagValue);
    } else if (flag === "--image") {
      parsed.images.push(flagValue);
    } else if (flag === "--label") {
      parsed.labels.push(flagValue);
    } else {
      const fieldName = flag.slice(2).replace("-id", "Id");
      parsed[fieldName] = flagValue;
    }
  }
  return parsed;
}

// The body for POST /make/cards. imageRefs are the "file:<id>" refs of the uploaded pictures, in
// the order of --image.
export function cardBody(parsed, cardId, imageRefs, makeOptionId = newMakeId) {
  const kind = parsed.kind ?? (imageRefs.length > 0 ? "design" : "choice");
  const options = [];
  if (kind === "design") {
    for (let index = 0; index < imageRefs.length; index += 1) {
      const option = { id: makeOptionId(), image: imageRefs[index] };
      if (parsed.labels[index] !== undefined) {
        option.label = parsed.labels[index];
      }
      options.push(option);
    }
  } else {
    for (const label of parsed.options) {
      options.push({ id: makeOptionId(), label });
    }
  }
  return {
    userId: parsed.user,
    requestId: parsed.request,
    cardId,
    question: parsed.question,
    kind,
    options,
    allowsOwnWords: parsed.ownWords,
  };
}

async function replyOrThrow(response, what) {
  const replyText = await response.text();
  if (!response.ok) {
    throw new Error(`${what} failed: ${response.status} ${replyText}`);
  }
  return JSON.parse(replyText);
}

async function uploadImage(backendUrl, token, userId, imagePath) {
  const bytes = readFileSync(imagePath);
  const extension = extname(imagePath).toLowerCase();
  const contentType = IMAGE_TYPES[extension] ?? "application/octet-stream";
  const fileId = newMakeId();
  const url = `${backendUrl}/make/files?userId=${encodeURIComponent(userId)}`;
  const requestInit = {
    method: "POST",
    headers: { Authorization: `Runner ${token}`, "Content-Type": contentType, "X-Midas-File-Id": fileId },
    body: bytes,
  };
  const response = await fetch(url, requestInit);
  const reply = await replyOrThrow(response, `upload ${basename(imagePath)}`);
  return reply.ref;
}

async function main() {
  const commandArgs = process.argv.slice(2);
  const environment = environmentFromArgs(commandArgs);
  if (environment === null) {
    console.error("usage: node scripts/make-card.mjs --env staging|live --user <userId> --request <reqId> --question <text> (--option <label>... | --image <path>...) [--own-words]");
    process.exit(1);
  }
  const parsed = parseMakeCardArgs(commandArgs);
  const tokenVariable = TOKEN_VARIABLES[environment.name];
  const token = process.env[tokenVariable];
  if (!token) {
    console.error(`${tokenVariable} is not set`);
    process.exit(1);
  }
  const backendUrl = BACKEND_URLS[environment.name];
  const imageRefs = [];
  for (const imagePath of parsed.images) {
    const ref = await uploadImage(backendUrl, token, parsed.user, imagePath);
    imageRefs.push(ref);
  }
  const cardId = parsed.cardId ?? newMakeId();
  const body = cardBody(parsed, cardId, imageRefs);
  const requestInit = {
    method: "POST",
    headers: { Authorization: `Runner ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
  const response = await fetch(`${backendUrl}/make/cards`, requestInit);
  const reply = await replyOrThrow(response, "card");
  console.log(`card ${reply.cardId} sent on ${environment.name}`);
}

const isRunDirectly = process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isRunDirectly) {
  await main();
}
