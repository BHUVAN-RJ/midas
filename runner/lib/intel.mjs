// The repair agent's read-only intel: a fixed catalog of documents, read whole or by section.
// Nothing outside the catalog can be read through it.
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { REPO_ROOT } from "./config.mjs";

export const INTEL_REPO_ROOT = process.env.MIDAS_INTEL_ROOT || join(homedir(), "code", "midas-intel");

// name -> { path, about }. Names are what the agent types.
export function intelCatalog({ repoRoot = REPO_ROOT, intelRoot = INTEL_REPO_ROOT } = {}) {
  return {
    writing: { path: join(repoRoot, "docs", "WRITING.md"), about: "Rules for every word on screen" },
    notifications: { path: join(repoRoot, "docs", "NOTIFICATIONS.md"), about: "The notification engine: reminder: records, repeats, limits" },
    "reminders-analysis": { path: join(intelRoot, "docs", "research", "reminders", "ANALYSIS.md"), about: "What users love and leave in 20 reminder apps" },
    "reminders-brief": { path: join(intelRoot, "docs", "research", "reminders", "BRIEF.md"), about: "The research brief for the Reminders Sidekick" },
    "reminders-group-a": { path: join(intelRoot, "docs", "research", "reminders", "group-a.md"), about: "Apple Reminders, Todoist, Things 3, TickTick, Due" },
    "reminders-group-b": { path: join(intelRoot, "docs", "research", "reminders", "group-b.md"), about: "Microsoft To Do, Google Tasks, Any.do, OmniFocus, RTM" },
    "reminders-group-c": { path: join(intelRoot, "docs", "research", "reminders", "group-c.md"), about: "Structured, Tiimo, GoodTask, 2Do, Galarm" },
    "reminders-group-d": { path: join(intelRoot, "docs", "research", "reminders", "group-d.md"), about: "Sorted3, NotePlan, Amazing Marvin, Akiflow, Habitica, Sunsama" },
    "primitives-brief": { path: join(intelRoot, "docs", "research", "primitives-BRIEF.md"), about: "What a Sidekick can and cannot do in the shell" },
    "ios-notifications": { path: join(intelRoot, "docs", "research", "ios-notifications-reference.md"), about: "Every way iOS can reach a user outside the app, and what Midas supports" },
    "design-process": { path: join(intelRoot, "docs", "process", "sidekick-design-process.md"), about: "How the Reminders Sidekick was designed" },
  };
}

export function markdownHeadings(text) {
  const headings = [];
  const lines = text.split("\n");
  for (const line of lines) {
    const headingMatch = /^(#{1,6})\s+(.*)$/.exec(line);
    if (headingMatch !== null) {
      headings.push({ level: headingMatch[1].length, title: headingMatch[2].trim() });
    }
  }
  return headings;
}

// The section under a heading (matched case-insensitively, by containing the given text), up to
// the next heading of the same or higher level. Null when no heading matches.
export function markdownSection(text, headingQuery) {
  const lines = text.split("\n");
  const wanted = headingQuery.trim().toLowerCase();
  let startIndex = -1;
  let startLevel = 0;
  for (let index = 0; index < lines.length; index += 1) {
    const headingMatch = /^(#{1,6})\s+(.*)$/.exec(lines[index]);
    if (headingMatch !== null && headingMatch[2].trim().toLowerCase().includes(wanted)) {
      startIndex = index;
      startLevel = headingMatch[1].length;
      break;
    }
  }
  if (startIndex === -1) {
    return null;
  }
  let endIndex = lines.length;
  for (let index = startIndex + 1; index < lines.length; index += 1) {
    const headingMatch = /^(#{1,6})\s+/.exec(lines[index]);
    if (headingMatch !== null && headingMatch[1].length <= startLevel) {
      endIndex = index;
      break;
    }
  }
  return lines.slice(startIndex, endIndex).join("\n");
}

// Returns { text } or { problem }. Only names from the catalog; a path is never accepted.
export function readIntel({ name, section = null, catalog = intelCatalog() }) {
  if (!Object.hasOwn(catalog, name)) {
    return { problem: `unknown document "${name}"; run: intel list` };
  }
  const entry = catalog[name];
  if (!existsSync(entry.path)) {
    return { problem: `"${name}" is not on this machine` };
  }
  const text = readFileSync(entry.path, "utf8");
  if (section === null) {
    return { text };
  }
  const sectionText = markdownSection(text, section);
  if (sectionText === null) {
    const headings = markdownHeadings(text);
    const headingList = headings.map(function formatHeading(heading) {
      return `${"#".repeat(heading.level)} ${heading.title}`;
    });
    return { problem: `no heading matching "${section}" in ${name}. Headings:\n${headingList.join("\n")}` };
  }
  return { text: sectionText };
}

// The listing shown by `intel list`.
export function describeCatalog(catalog = intelCatalog()) {
  const lines = [];
  for (const [name, entry] of Object.entries(catalog)) {
    const available = existsSync(entry.path);
    const marker = available ? "" : "  (not on this machine)";
    lines.push(`${name}: ${entry.about}${marker}`);
    if (available) {
      const headings = markdownHeadings(readFileSync(entry.path, "utf8"));
      const topHeadings = headings.filter(function keepTopLevels(heading) {
        return heading.level <= 2;
      });
      for (const heading of topHeadings) {
        lines.push(`    ${heading.title}`);
      }
    }
  }
  return lines.join("\n");
}
