// Faster repairs, tried on one Sidekick first (founder, 2026-11-02: repair b8dea1a6 on Reminder
// Test took about 6 minutes on the Mac mini; "make these changes for this runner only and then do
// it for all others if we see the actual results"). For a Sidekick in SPEED_TRIAL_SIDEKICKS:
//   - the agent's system prompt ends with a map of the page (every function and data-action with
//     its line) and a note on which tools to read with, so it stops searching a 5,000-line file
//     (b8dea1a6: 20 reads and 14 searches before the first edit; 2 refused cat/ls commands)
//   - the agent runs at a lower effort
//   - fetch-sidekick-copy.mjs and deploy-sidekick.mjs fetch and upload files several at a time
//     (b8dea1a6: fetch 29 s, deploy 39 s, one wrangler call after another)
// Every other Sidekick runs exactly as before.

export const SPEED_TRIAL_SIDEKICKS = new Set(["reminder-test"]);

export const SPEED_TRIAL_EFFORT = "medium";

export function isSpeedTrial(sidekickId) {
  return SPEED_TRIAL_SIDEKICKS.has(sidekickId);
}

// The agent's effort for this Sidekick, or null to leave the CLI's default.
export function effortFor(sidekickId) {
  return isSpeedTrial(sidekickId) ? SPEED_TRIAL_EFFORT : null;
}

// The extra flag the fetch and deploy scripts take to work on several files at once.
export function parallelArgsFor(sidekickId) {
  return isSpeedTrial(sidekickId) ? ["--parallel"] : [];
}

const FUNCTION_PATTERN = /^\s*(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(/;
const SECTION_PATTERN = /^\s*(?:\/\*|\/\/)\s*-{3,}\s*(.+?)\s*-{3,}/;
const ACTION_PATTERN = /data-action="([^"]+)"/g;

// One file's map: section headings, then "L<line> name" for each function, then each
// data-action with the first line it appears on. Lines are 1-based, as the Read tool shows them.
export function fileMapLines(fileText) {
  const lines = fileText.split("\n");
  const mapLines = [];
  const firstActionLine = new Map();
  for (let index = 0; index < lines.length; index += 1) {
    const lineNumber = index + 1;
    const line = lines[index];
    const section = line.match(SECTION_PATTERN);
    if (section) {
      mapLines.push(`L${lineNumber} == ${section[1]} ==`);
    }
    const declared = line.match(FUNCTION_PATTERN);
    if (declared) {
      mapLines.push(`L${lineNumber} ${declared[1]}()`);
    }
    for (const action of line.matchAll(ACTION_PATTERN)) {
      if (!firstActionLine.has(action[1])) {
        firstActionLine.set(action[1], lineNumber);
      }
    }
  }
  const actionEntries = [];
  for (const [actionName, lineNumber] of firstActionLine) {
    actionEntries.push(`${actionName} (L${lineNumber})`);
  }
  if (actionEntries.length > 0) {
    mapLines.push(`data-action: ${actionEntries.join(", ")}`);
  }
  return mapLines;
}

// The section appended to the system prompt for a trial Sidekick.
export function speedTrialPromptText({ html, toolsText }) {
  const parts = [
    "",
    "## Map of this copy (made by the runner when the job started)",
    "",
    "Use it to jump straight to the code: Read sidekick/index.html with an offset and limit around",
    "the line you need, instead of searching the whole file. Read, Grep and Glob are the way to look",
    "at files; Bash runs only the check tool and the intel tool (cat, ls, wc and other commands are",
    "refused). Line numbers move as you edit; Grep for a function name when they have.",
    "",
    "### sidekick/index.html",
    "```",
    ...fileMapLines(html),
    "```",
  ];
  if (toolsText) {
    parts.push("", "### sidekick/tools.js", "```", ...fileMapLines(toolsText), "```");
  }
  return parts.join("\n") + "\n";
}
