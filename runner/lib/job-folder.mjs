// The job folder is the only thing the repair agent sees. It holds exactly:
//   sidekick/index.html, sidekick/manifest.json   the reporter's current copy
//   report/...                                     the report (text, strokes, images)
//   outcome.json                                   written by the agent at the end
// Nothing else: no .git, no CLAUDE.md, no node_modules, nothing from the repo.
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { execFileSync } from "node:child_process";

export const SIDEKICK_FILES = ["index.html", "manifest.json"];
export const OUTCOME_FILE = "outcome.json";

// What may exist in a job folder, as relative paths with "/" separators.
const ALLOWED_PATTERNS = [
  /^sidekick\/(index\.html|manifest\.json)$/,
  /^report\/[^/]+$/,
  /^outcome\.json$/,
];

export function isAllowedJobFile(relativePath) {
  return ALLOWED_PATTERNS.some((pattern) => pattern.test(relativePath));
}

// Every file under a folder, relative, "/"-separated, sorted. Directories themselves are not listed.
export function listFilesRecursively(rootPath) {
  const found = [];
  function walk(currentPath) {
    const entries = readdirSync(currentPath, { withFileTypes: true });
    for (const entry of entries) {
      const entryPath = join(currentPath, entry.name);
      if (entry.isDirectory()) {
        walk(entryPath);
      } else {
        const relativePath = relative(rootPath, entryPath).split(sep).join("/");
        found.push(relativePath);
      }
    }
  }
  walk(rootPath);
  found.sort();
  return found;
}

// Files in the job folder that do not belong there.
export function foreignFiles(jobFolder) {
  const allFiles = listFilesRecursively(jobFolder);
  return allFiles.filter((relativePath) => !isAllowedJobFile(relativePath));
}

// Writes the job folder from the claim reply and the downloaded assets. `assets` maps the
// report file name (screenshot.png, drawing.png, strokes.json) to a Buffer or null; the bundle
// files come in `bundle` as { html, manifestText }.
export function buildJobFolder({ jobsRoot, job, bundle, assets }) {
  const jobFolder = join(jobsRoot, job.id);
  if (existsSync(jobFolder)) {
    throw new Error(`job folder already exists: ${jobFolder}`);
  }
  const sidekickFolder = join(jobFolder, "sidekick");
  const reportFolder = join(jobFolder, "report");
  mkdirSync(sidekickFolder, { recursive: true });
  mkdirSync(reportFolder, { recursive: true });

  writeFileSync(join(sidekickFolder, "index.html"), bundle.html);
  writeFileSync(join(sidekickFolder, "manifest.json"), bundle.manifestText);

  const reportRecord = {
    id: job.id,
    sidekickId: job.sidekickId,
    kind: job.kind,
    bundleVersion: job.bundleVersion,
    device: job.device,
    appVersion: job.appVersion,
    createdAt: job.createdAt,
    files: [],
  };
  writeFileSync(join(reportFolder, "transcript.txt"), job.transcript);
  reportRecord.files.push("transcript.txt");
  for (const [fileName, bytes] of Object.entries(assets)) {
    if (bytes === null || bytes === undefined) {
      continue;
    }
    writeFileSync(join(reportFolder, fileName), bytes);
    reportRecord.files.push(fileName);
  }
  writeFileSync(join(reportFolder, "report.json"), JSON.stringify(reportRecord, null, 2));
  return jobFolder;
}

// The Sidekick files as text, keyed by file name, for diffs and restores.
export function readSidekickFiles(jobFolder) {
  const files = {};
  for (const fileName of SIDEKICK_FILES) {
    files[fileName] = readFileSync(join(jobFolder, "sidekick", fileName), "utf8");
  }
  return files;
}

// A unified diff between two snapshots of the Sidekick files, via git (no index needed).
// Empty string when nothing changed.
export function diffSidekickFiles(beforeFolder, afterFolder) {
  try {
    execFileSync("git", ["diff", "--no-index", "--", beforeFolder, afterFolder], { encoding: "utf8" });
    return "";
  } catch (error) {
    // git exits 1 when the folders differ; anything else is a real failure.
    if (error.status === 1 && typeof error.stdout === "string") {
      return error.stdout;
    }
    throw error;
  }
}

// Saves the Sidekick files of a job folder into a sibling folder outside it, for the diff.
export function snapshotSidekickFiles(jobFolder, snapshotFolder) {
  mkdirSync(snapshotFolder, { recursive: true });
  for (const fileName of SIDEKICK_FILES) {
    const bytes = readFileSync(join(jobFolder, "sidekick", fileName));
    writeFileSync(join(snapshotFolder, fileName), bytes);
  }
}

export function sidekickFolderSize(jobFolder) {
  let total = 0;
  for (const fileName of SIDEKICK_FILES) {
    total += statSync(join(jobFolder, "sidekick", fileName)).size;
  }
  return total;
}
