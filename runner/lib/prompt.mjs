// Assembles the agent's system prompt for a job: the static template for the Sidekick category
// plus the current docs (read at run time so they stay in step with the repo) plus the report.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { REPO_ROOT } from "./config.mjs";
import { markdownSection } from "./intel.mjs";
import { CHECK_TOOL_PATH, INTEL_TOOL_PATH } from "./agent.mjs";

const TEMPLATES_FOLDER = join(REPO_ROOT, "runner", "agents");

// Which template a Sidekick id uses. Reminders only for now; care-reminders is a Reminders
// variant and gets the same prompt.
export function templateNameForSidekick(sidekickId) {
  const remindersFamily = ["reminders", "care-reminders"];
  if (remindersFamily.includes(sidekickId)) {
    return "reminders";
  }
  return null;
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
export function buildSystemPrompt({ job, reportFiles, checkoutRoot = REPO_ROOT, intelToolPath = INTEL_TOOL_PATH, checkToolPath = CHECK_TOOL_PATH }) {
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
    TRANSCRIPT: job.transcript.trim(),
    WRITING: writingText,
    NOTIFICATIONS_SECTION_4: sectionOrNote(notificationsText, "4. Using it from a Sidekick"),
    NOTIFICATIONS_SECTION_7: sectionOrNote(notificationsText, "7. Limits"),
  };
  return fillPlaceholders(template, values);
}
