// Assembles the agent's system prompt for a job: the static template for the Sidekick category
// plus the current docs (read at run time so they stay in step with the repo) plus the report.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { REPO_ROOT } from "./config.mjs";
import { markdownSection } from "./intel.mjs";
import { CHECK_TOOL_PATH, INTEL_TOOL_PATH } from "./agent.mjs";
import { personNotesForPrompt, readPersonNotes } from "./person-notes.mjs";

const TEMPLATES_FOLDER = join(REPO_ROOT, "runner", "agents");
// One repair agent for every Sidekick (founder, 2026-11-13, D5): runner/agents/repair.md, filled
// with the copy's manifest, the primitive it was built from and the person's notes.
export const SHARED_TEMPLATE_NAME = "repair";
// Which agent a Sidekick with its own file gets. "per-sidekick" (the default until the one agent is
// live) keeps runner/agents/<id>.md; "shared" sends every Sidekick to the one agent. A Sidekick
// with no file of its own always gets the one agent. The per-Sidekick files and this switch are
// removed in one change once the one agent is live (docs/briefs/repair-lanes.md, W4).
export const REPAIR_AGENT_ENV = "MIDAS_REPAIR_AGENT";
export const REPAIR_AGENT_MODES = ["per-sidekick", "shared"];

// Which template a Sidekick id uses: one per Sidekick with a repair agent (founder, 2026-10-15:
// care-reminders gets its own prompt; its records and fields differ from Reminders').
export const TEMPLATE_BY_SIDEKICK = {
  reminders: "reminders",
  "care-reminders": "care-reminders",
  // Founder, 2026-10-25: every personal Sidekick has repair; Water (hydration) included.
  hydration: "hydration",
  // Founder, 2026-10-31: the To-Do Sidekick (docs/briefs/todo-sidekick.md, step 5).
  todo: "todo",
  // Founder, 2026-11-02: Reminder Test, the demo copy of Reminders (its own type and tool names).
  "reminder-test": "reminder-test",
  // Founder, 2026-11-08: Money (expenses in USD, receipts from the page or from jess's camera).
  money: "money",
};

export function templateNameForSidekick(sidekickId) {
  if (!Object.hasOwn(TEMPLATE_BY_SIDEKICK, sidekickId)) {
    return null;
  }
  return TEMPLATE_BY_SIDEKICK[sidekickId];
}

// The copy's own record types, pretty-printed for the prompt: the agent edits them, so it must
// see what this user's copy declares now, not the base's.
export function typesText(manifestText) {
  if (typeof manifestText !== "string") {
    return "(manifest.json not available)";
  }
  let manifest;
  try {
    manifest = JSON.parse(manifestText);
  } catch {
    return "(manifest.json is not JSON)";
  }
  if (manifest === null || typeof manifest !== "object" || manifest.types === undefined) {
    return "(this copy's manifest.json has no types block)";
  }
  return JSON.stringify(manifest.types, null, 2);
}

function fillPlaceholders(template, values) {
  let filled = template;
  for (const [name, value] of Object.entries(values)) {
    filled = filled.split(`{{${name}}}`).join(value);
  }
  return filled;
}

function sectionOrNote(docText, headingQuery) {
  const sectionText = markdownSection(docText, headingQuery);
  if (sectionText === null) {
    return `(section "${headingQuery}" not found)`;
  }
  return sectionText;
}

// One sentence telling the agent whether this report has a drawing. A feature request is often
// voice only (contract, settled 2026-10-13), so the agent must not wait for a drawing.
export function drawingNote(reportFiles) {
  const hasDrawing = reportFiles.includes("drawing.png");
  const hasScreenshot = reportFiles.includes("screenshot.png");
  if (hasDrawing) {
    return "This report has a drawing: read report/drawing.png before deciding.";
  }
  if (hasScreenshot) {
    return "This report has no drawing, only words and a screenshot: decide from the transcript.";
  }
  return "This report has no drawing and no screenshot: decide from the transcript alone.";
}

function readDocOrNote(path, missingNote) {
  if (!existsSync(path)) {
    return missingNote;
  }
  return readFileSync(path, "utf8");
}

// The repo docs every repair prompt embeds, read from the checkout at run time.
function sharedDocValues(checkoutRoot) {
  const docsFolder = join(checkoutRoot, "docs");
  const notificationsText = readDocOrNote(join(docsFolder, "NOTIFICATIONS.md"), "");
  return {
    WRITING: readDocOrNote(join(docsFolder, "WRITING.md"), "(docs/WRITING.md missing)"),
    NOTIFICATIONS_SECTION_4: sectionOrNote(notificationsText, "4. Using it from a Sidekick"),
    NOTIFICATIONS_SECTION_7: sectionOrNote(notificationsText, "7. Limits"),
    // Widgets are records a page writes, so the agent reads how they work.
    WIDGETS: readDocOrNote(join(docsFolder, "WIDGETS.md"), "(docs/WIDGETS.md missing)"),
    // Every tile has a light and a dark variant; the agent writes both (founder, 2026-10-31).
    ICONS: readDocOrNote(join(docsFolder, "ICONS.md"), "(docs/ICONS.md missing)"),
  };
}

// The ask-back card's question (repair lanes W2/W3, D4 = A); the claimed job carries only the
// answer, so the question is the card's own words unless the job names another.
export const SORT_QUESTION_TEXT = "What should it be?";

// The person's answer to the ask-back card, as one line for the agent, or null when there was no
// card or no answer. job.sort = { status, lane, confidence, model, answer } from the claim (W2).
export function sortAnswerLine(job) {
  const sort = job.sort ?? null;
  if (sort === null || typeof sort !== "object" || typeof sort.answer !== "string") {
    return null;
  }
  const answer = sort.answer.replace(/\s+/g, " ").trim();
  if (answer.length === 0) {
    return null;
  }
  const question = typeof sort.question === "string" && sort.question.trim().length > 0 ? sort.question.trim() : SORT_QUESTION_TEXT;
  return `Asked "${question}", they answered: "${answer}"`;
}

// The transcript the agent reads: the person's words, then their answer to the card when there is
// one, so the two are read together (founder, 2026-11-13: the answer joins the same request).
export function transcriptWithAnswer(job) {
  const words = job.transcript.trim();
  const answerLine = sortAnswerLine(job);
  if (answerLine === null) {
    return words;
  }
  return `${words}\n\n${answerLine}`;
}

// The report fields every repair prompt shows.
function reportValues({ job, reportFiles, intelToolPath, checkToolPath }) {
  return {
    INTEL_TOOL: intelToolPath,
    CHECK_TOOL: checkToolPath,
    DRAWING_NOTE: drawingNote(reportFiles),
    KIND: job.kind ?? "unknown",
    REPORT_ID: job.id ?? "unknown",
    REPORTED_AT: job.createdAt ?? "unknown",
    DEVICE: job.device ?? "unknown",
    APP_VERSION: job.appVersion ?? "unknown",
    BUNDLE_VERSION: job.bundleVersion ?? "unknown",
    REPORT_FILES: reportFiles.join(", "),
    TRANSCRIPT: transcriptWithAnswer(job),
  };
}

// The variable for one environment, in config.mjs's MIDAS_<ENV>_... form:
// MIDAS_STAGING_REPAIR_AGENT, MIDAS_LIVE_REPAIR_AGENT.
export function repairAgentVariableFor(environmentName) {
  return `MIDAS_${environmentName.toUpperCase()}_REPAIR_AGENT`;
}

// The mode from the runner's environment variables. One runner serves live and staging, so a job's
// own environment is asked first (staging can run the one agent while live keeps the per-Sidekick
// files: testing, then staging, then live), then MIDAS_REPAIR_AGENT for both. Anything unknown
// falls back to the default.
export function repairAgentMode(environment = process.env, environmentName = null) {
  const variableNames = [];
  if (typeof environmentName === "string" && environmentName.length > 0) {
    variableNames.push(repairAgentVariableFor(environmentName));
  }
  variableNames.push(REPAIR_AGENT_ENV);
  for (const variableName of variableNames) {
    const configured = environment[variableName];
    if (REPAIR_AGENT_MODES.includes(configured)) {
      return configured;
    }
  }
  return REPAIR_AGENT_MODES[0];
}

// True when this Sidekick's repair goes to the one shared agent.
export function usesSharedAgent(sidekickId, mode) {
  if (mode === "shared") {
    return true;
  }
  return templateNameForSidekick(sidekickId) === null;
}

// The copy's manifest as an object. Throws when there is none: the one agent learns what the
// Sidekick is from it.
export function parseCopyManifest(manifestText, sidekickId) {
  if (typeof manifestText !== "string") {
    throw new Error(`no repair agent for Sidekick "${sidekickId}": the copy has no manifest.json`);
  }
  let manifest;
  try {
    manifest = JSON.parse(manifestText);
  } catch {
    throw new Error(`no repair agent for Sidekick "${sidekickId}": the copy's manifest.json is not JSON`);
  }
  if (manifest === null || typeof manifest !== "object" || Array.isArray(manifest)) {
    throw new Error(`no repair agent for Sidekick "${sidekickId}": the copy's manifest.json is not an object`);
  }
  return manifest;
}

function bulletLine(item) {
  return `- ${String(item)}`;
}

function bulletList(items, emptyText) {
  if (!Array.isArray(items) || items.length === 0) {
    return emptyText;
  }
  const lines = items.map(bulletLine);
  return lines.join("\n");
}

function inBackticks(text) {
  return `\`${text}\``;
}

// One voice tool as a line: its name, what it does, the page controls it stands for, and the
// photo field when jess fills one from a photo.
function toolLine(tool) {
  const meta = tool._meta ?? {};
  const pageActions = Array.isArray(meta["midas/page-actions"]) ? meta["midas/page-actions"] : [];
  const quotedActions = pageActions.map(inBackticks);
  const actionsText = quotedActions.length > 0 ? ` Page controls: ${quotedActions.join(", ")}.` : "";
  const photoText = typeof meta["midas/photo"] === "string" ? ` Photo field: \`${meta["midas/photo"]}\`.` : "";
  const description = tool.description ?? "(no description)";
  return `- \`${tool.name}\`: ${description}${actionsText}${photoText}`;
}

// "This Sidekick": everything the manifest says about what the Sidekick is, for the agent.
export function sidekickAboutText(manifest, sidekickId) {
  const agentBlock = manifest.agent ?? {};
  const tools = Array.isArray(agentBlock.tools) ? agentBlock.tools : [];
  const toolLines = tools.map(toolLine);
  const toolsText = toolLines.length > 0 ? toolLines.join("\n") : "- (this copy has no tools yet)";
  const reads = Array.isArray(manifest.reads) ? manifest.reads : [];
  const readsText = reads.length > 0 ? JSON.stringify(reads) : "nothing (it reads no other Sidekick's records)";
  const parts = [
    `- Name shown to the person: ${manifest.name ?? sidekickId}`,
    `- Id: \`${sidekickId}\``,
    `- What it is: ${agentBlock.description ?? "(the manifest has no agent.description)"}`,
    `- Reads from other Sidekicks: ${readsText}`,
    "",
    "Not for (another Sidekick or nothing does these):",
    "",
    bulletList(agentBlock.notFor, "- (none listed)"),
    "",
    "How its actions behave (the rules jess follows; the page behaves the same way):",
    "",
    bulletList(agentBlock.rules, "- (none listed)"),
    "",
    "Its voice tools now (section \"Voice tools\"), one per action on the page:",
    "",
    toolsText,
  ];
  return parts.join("\n");
}

// "Settings": the manifest's settings catalogue (repair lanes W5) when the copy has one.
export function settingsText(manifest) {
  if (manifest.settings !== undefined) {
    const catalogueJson = JSON.stringify(manifest.settings, null, 2);
    return `\`\`\`json\n${catalogueJson}\n\`\`\``;
  }
  const types = manifest.types ?? {};
  if (Object.hasOwn(types, "settings:")) {
    return "This copy declares no `settings` block yet; its settings are the fields of the `settings:` type above and the page code that reads `settings:self`.";
  }
  return "This copy declares no `settings` block and no `settings:` type yet. A first setting adds the `settings:` type (stored as `settings:self`) and the page's handling of it.";
}

// A primitive folder name: lowercase words joined by "-". The copy's manifest is the person's
// (their repairs edit it), so its value is never used as a path unless it fits this.
const PRIMITIVE_ID_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// The primitive this Sidekick was built from: the manifest's "primitive" when it names one, else a
// primitive folder with the Sidekick's own id (To-Do is built from docs/primitives/todo). Null when
// there is none.
export function primitiveIdFor({ manifest, sidekickId, checkoutRoot }) {
  const candidates = [];
  if (typeof manifest.primitive === "string") {
    candidates.push(manifest.primitive);
  }
  candidates.push(sidekickId);
  for (const candidate of candidates) {
    if (!PRIMITIVE_ID_PATTERN.test(candidate)) {
      continue;
    }
    const readmePath = join(checkoutRoot, "docs", "primitives", candidate, "README.md");
    if (existsSync(readmePath)) {
      return candidate;
    }
  }
  return null;
}

// A block file's opening: its intro, the rules every pattern follows and the table of patterns
// (ID, name, core or on request, default), up to the first "---". The patterns' full text is long
// (about 25 KB a block) and stays out of the prompt.
export function blockOpening(blockText) {
  const separatorIndex = blockText.indexOf("\n---\n");
  if (separatorIndex === -1) {
    return blockText.trim();
  }
  const opening = blockText.slice(0, separatorIndex);
  return opening.trim();
}

// Lowers every markdown heading by two levels so a primitive doc sits under "## The primitive".
function nestHeadings(markdownText) {
  return markdownText.replace(/^(#{1,4}) /gm, "$1## ");
}

function isMarkdownFile(fileName) {
  return fileName.endsWith(".md");
}

const PRIMITIVE_DOC_FILES = ["README.md", "records.md", "recipe.md", "checklist.md"];

// "The primitive": its README, records, recipe and checklist whole, and every block's opening.
export function primitiveText({ manifest, sidekickId, checkoutRoot }) {
  const primitiveId = primitiveIdFor({ manifest, sidekickId, checkoutRoot });
  if (primitiveId === null) {
    return "This Sidekick was not built from a primitive in `docs/primitives/`. What its records and controls mean comes from its manifest (above) and its page code.";
  }
  const primitiveFolder = join(checkoutRoot, "docs", "primitives", primitiveId);
  const parts = [`Built from the \`${primitiveId}\` primitive (\`docs/primitives/${primitiveId}/\`). Where the built page and these docs differ, the page and its manifest win.`];
  for (const fileName of PRIMITIVE_DOC_FILES) {
    const docPath = join(primitiveFolder, fileName);
    if (existsSync(docPath)) {
      const docText = readFileSync(docPath, "utf8");
      parts.push(`### ${fileName}\n\n${nestHeadings(docText.trim())}`);
    }
  }
  const blocksFolder = join(primitiveFolder, "blocks");
  if (existsSync(blocksFolder)) {
    const blockFiles = readdirSync(blocksFolder).filter(isMarkdownFile);
    blockFiles.sort();
    for (const blockFile of blockFiles) {
      const blockText = readFileSync(join(blocksFolder, blockFile), "utf8");
      parts.push(`### blocks/${blockFile} (opening)\n\n${nestHeadings(blockOpening(blockText))}`);
    }
  }
  return parts.join("\n\n");
}

// Fills every {{NAME}} in one pass, so text that comes in through a value (the transcript, the
// notes, a doc) is never filled again. An unknown name is left as it is.
export function fillTemplateOnce(template, values) {
  function valueFor(placeholder, name) {
    if (Object.hasOwn(values, name)) {
      return values[name];
    }
    return placeholder;
  }
  return template.replace(/\{\{([A-Z_0-9]+)\}\}/g, valueFor);
}

// The one agent's prompt (founder, 2026-11-13, D5). personNotesText is the copy's
// tests/PERSON_NOTES.md text; without it, the notes are read from jobFolder when one is given.
export function buildSharedRepairPrompt({ job, reportFiles, manifestText, checkoutRoot = REPO_ROOT, intelToolPath = INTEL_TOOL_PATH, checkToolPath = CHECK_TOOL_PATH, jobFolder = null, personNotesText = null }) {
  const sidekickId = job.sidekickId;
  const manifest = parseCopyManifest(manifestText, sidekickId);
  const template = readFileSync(join(TEMPLATES_FOLDER, `${SHARED_TEMPLATE_NAME}.md`), "utf8");
  let notesText = personNotesText;
  if (notesText === null && jobFolder !== null) {
    notesText = readPersonNotes(jobFolder);
  }
  const values = {
    ...reportValues({ job, reportFiles, intelToolPath, checkToolPath }),
    ...sharedDocValues(checkoutRoot),
    SIDEKICK_ID: sidekickId,
    SIDEKICK_NAME: typeof manifest.name === "string" ? manifest.name : sidekickId,
    SIDEKICK_ABOUT: sidekickAboutText(manifest, sidekickId),
    PERSON_NOTES: personNotesForPrompt(notesText ?? ""),
    TYPES: typesText(manifestText),
    SETTINGS: settingsText(manifest),
    PRIMITIVE: primitiveText({ manifest, sidekickId, checkoutRoot }),
  };
  return fillTemplateOnce(template, values);
}

// The per-Sidekick prompt (runner/agents/<id>.md), kept until the one agent is live.
function buildPerSidekickPrompt({ job, reportFiles, manifestText, checkoutRoot, intelToolPath, checkToolPath }) {
  const templateName = templateNameForSidekick(job.sidekickId);
  const template = readFileSync(join(TEMPLATES_FOLDER, `${templateName}.md`), "utf8");
  const values = {
    ...reportValues({ job, reportFiles, intelToolPath, checkToolPath }),
    ...sharedDocValues(checkoutRoot),
    TYPES: typesText(manifestText),
  };
  return fillPlaceholders(template, values);
}

// Returns the prompt text. A Sidekick with its own file gets it unless the mode is "shared";
// every other Sidekick gets the one agent, which throws only when the copy has no usable manifest.
// Without agentMode, the mode comes from the variables for the job's environment (job.environment,
// set by the backend client that claimed it).
export function buildSystemPrompt({ job, reportFiles, manifestText, checkoutRoot = REPO_ROOT, intelToolPath = INTEL_TOOL_PATH, checkToolPath = CHECK_TOOL_PATH, jobFolder = null, personNotesText = null, agentMode = null }) {
  const mode = agentMode ?? repairAgentMode(process.env, job.environment ?? null);
  if (usesSharedAgent(job.sidekickId, mode)) {
    return buildSharedRepairPrompt({ job, reportFiles, manifestText, checkoutRoot, intelToolPath, checkToolPath, jobFolder, personNotesText });
  }
  return buildPerSidekickPrompt({ job, reportFiles, manifestText, checkoutRoot, intelToolPath, checkToolPath });
}
