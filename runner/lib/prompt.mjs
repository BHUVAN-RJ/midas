// Assembles the agent's system prompt for a job: the static template for the Sidekick category
// plus the current docs (read at run time so they stay in step with the repo) plus the report.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { REPO_ROOT } from "./config.mjs";
import { markdownSection } from "./intel.mjs";
import { CHECK_TOOL_PATH, INTEL_TOOL_PATH } from "./agent.mjs";

const TEMPLATES_FOLDER = join(REPO_ROOT, "runner", "agents");

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

// Returns the prompt text, or throws when the Sidekick has no repair agent yet.
export function buildSystemPrompt({ job, reportFiles, manifestText, checkoutRoot = REPO_ROOT, intelToolPath = INTEL_TOOL_PATH, checkToolPath = CHECK_TOOL_PATH }) {
  const templateName = templateNameForSidekick(job.sidekickId);
  if (templateName === null) {
    throw new Error(`no repair agent for Sidekick "${job.sidekickId}"`);
  }
  const templatePath = join(TEMPLATES_FOLDER, `${templateName}.md`);
  const template = readFileSync(templatePath, "utf8");

  const writingPath = join(checkoutRoot, "docs", "WRITING.md");
  const notificationsPath = join(checkoutRoot, "docs", "NOTIFICATIONS.md");
  const writingText = existsSync(writingPath) ? readFileSync(writingPath, "utf8") : "(docs/WRITING.md missing)";
  const notificationsText = existsSync(notificationsPath) ? readFileSync(notificationsPath, "utf8") : "";
  // Water's widgets are records its page writes, so its agent reads how they work.
  const widgetsPath = join(checkoutRoot, "docs", "WIDGETS.md");
  const widgetsText = existsSync(widgetsPath) ? readFileSync(widgetsPath, "utf8") : "(docs/WIDGETS.md missing)";
  // Every tile has a light and a dark variant; the agent writes both (founder, 2026-10-31).
  const iconsPath = join(checkoutRoot, "docs", "ICONS.md");
  const iconsText = existsSync(iconsPath) ? readFileSync(iconsPath, "utf8") : "(docs/ICONS.md missing)";

  const values = {
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
    TYPES: typesText(manifestText),
    TRANSCRIPT: job.transcript.trim(),
    WRITING: writingText,
    NOTIFICATIONS_SECTION_4: sectionOrNote(notificationsText, "4. Using it from a Sidekick"),
    NOTIFICATIONS_SECTION_7: sectionOrNote(notificationsText, "7. Limits"),
    WIDGETS: widgetsText,
    ICONS: iconsText,
  };
  return fillPlaceholders(template, values);
}
