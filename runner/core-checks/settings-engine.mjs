// The settings engine is core in every Sidekick (founder D1, 2026-11-13): the Make It Yours panel
// may be hidden, the engine may not be removed. Repair 42396937 deleted todo.set_setting along
// with Make It Yours; this check is what stops that.
//
// The engine is four parts, all needed:
//   tool     manifest agent block has "<id>.set_setting"
//   handler  tools.js has handlers.set_setting
//   type     manifest types declares "settings:" (where settings:self lives)
//   page     index.html reads and writes "settings:self"
//
// Today only To-Do has all four; W5 adds the engine to Reminders, Care and Water. Until then the
// rule is "never lose it": a copy that had the engine must keep it. When everyEngine is true (set
// after W5 lands, shield.mjs SETTINGS_ENGINE_IN_EVERY_SIDEKICK), a copy without it fails too.

const SETTINGS_TYPE_PREFIX = "settings:";
const SETTINGS_KEY = "settings:self";
const SETTINGS_VERB = "set_setting";

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasSettingsTool(manifest, sidekickId) {
  const tools = manifest?.agent?.tools;
  if (!Array.isArray(tools)) {
    return false;
  }
  const toolName = `${sidekickId}.${SETTINGS_VERB}`;
  return tools.some(function isSettingsTool(tool) {
    return isPlainObject(tool) && tool.name === toolName;
  });
}

// copy: { manifest, html, loadedTools: { tools } | { problem } }. Returns the missing part names.
export function missingEngineParts({ sidekickId, copy }) {
  const missing = [];
  if (!hasSettingsTool(copy.manifest, sidekickId)) {
    missing.push(`tool ${sidekickId}.${SETTINGS_VERB}`);
  }
  const handlers = copy.loadedTools?.tools?.handlers;
  if (!isPlainObject(handlers) || typeof handlers[SETTINGS_VERB] !== "function") {
    missing.push(`tools.js handler ${SETTINGS_VERB}`);
  }
  const types = copy.manifest?.types;
  if (!isPlainObject(types) || !isPlainObject(types[SETTINGS_TYPE_PREFIX])) {
    missing.push(`record type "${SETTINGS_TYPE_PREFIX}"`);
  }
  if (typeof copy.html !== "string" || !copy.html.includes(SETTINGS_KEY)) {
    missing.push(`${SETTINGS_KEY} on the page`);
  }
  return missing;
}

// Returns { problems, notes }.
export function checkSettingsEngine({ sidekickId, before, after, everyEngine }) {
  const missingBefore = missingEngineParts({ sidekickId, copy: before });
  const missingAfter = missingEngineParts({ sidekickId, copy: after });
  const problems = [];
  const notes = [];
  if (missingAfter.length === 0) {
    return { problems, notes };
  }
  if (missingBefore.length === 0) {
    problems.push(`the settings engine was removed: ${missingAfter.join(", ")} gone; the panel may be hidden, the engine stays (D1)`);
    return { problems, notes };
  }
  // Parts the copy had and lost, even when it never had the whole engine
  const lost = missingAfter.filter(function wasPresentBefore(part) {
    return !missingBefore.includes(part);
  });
  if (lost.length > 0) {
    problems.push(`part of the settings engine was removed: ${lost.join(", ")}`);
  }
  if (everyEngine) {
    problems.push(`the settings engine is missing: ${missingAfter.join(", ")}`);
  } else {
    notes.push(`no settings engine yet (${missingAfter.join(", ")}); W5 adds it`);
  }
  return { problems, notes };
}
