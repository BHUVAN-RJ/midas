// Page opens, and the widget record is still written (docs/briefs/repair-lanes.md W1): judged from
// the old and the new page opened the same way (page-open.mjs).
//
// The new page must draw its first view and every view a tool's page control opens, with no
// console error, uncaught error, unhandled rejection or refused store write that the old page did
// not already have with the same records. "Already had" keeps a repair from failing on a fault
// it did not cause (and lets a repair that fixes one through); line numbers are left out of the
// comparison because every edit moves them.
import { STEP_OPEN, STEP_WIDGET } from "./page-open.mjs";

const WIDGET_PREFIX = "widget:";

function stepNamed(results, name) {
  const found = results.find(function hasName(result) {
    return result.name === name;
  });
  return found ?? null;
}

// "uncaught: x is not defined (line 1201)" and "(line 1189)" are the same fault
export function normalisedError(text) {
  return text.replace(/\s*\(line \d+\)/g, "").trim();
}

function refusedWrites(report) {
  const refused = report.writes.filter(function wasRefused(write) {
    return write.problem !== null;
  });
  return refused.map(function describeRefusal(write) {
    return `store.${write.op}('${write.key}') refused: ${write.problem}`;
  });
}

function faultsOf(report) {
  const errors = report.errors.map(normalisedError);
  return [...errors, ...refusedWrites(report)];
}

function newFaults(afterReport, beforeReport) {
  const beforeFaults = beforeReport === null ? [] : faultsOf(beforeReport);
  const afterFaults = faultsOf(afterReport);
  const unique = [...new Set(afterFaults)];
  return unique.filter(function wasNotThereBefore(fault) {
    return !beforeFaults.includes(fault);
  });
}

function drewNothing(report) {
  return report.visibleElements === 0 || report.textLength === 0;
}

function describeStep(stepResult) {
  if (stepResult.name === STEP_OPEN) {
    return "the first view";
  }
  if (stepResult.name === STEP_WIDGET) {
    return "the page opened without its widget records";
  }
  return `the view after a tap on "${stepResult.action}"`;
}

// before/after: openPage results. Returns { problems, notes }.
export function checkPageOpens({ beforeResults, afterResults }) {
  const problems = [];
  const notes = [];
  for (const afterStep of afterResults) {
    const beforeStep = stepNamed(beforeResults, afterStep.name);
    const beforeReport = beforeStep?.report ?? null;
    const where = describeStep(afterStep);
    if (afterStep.problem) {
      if (beforeStep?.problem) {
        notes.push(`${where}: ${afterStep.problem} (before the repair too)`);
      } else {
        problems.push(`${where}: ${afterStep.problem}`);
      }
      continue;
    }
    const report = afterStep.report;
    // A tap on a control that is not on this view tests nothing; the control itself is checked
    // by the tools check
    if (report.action && report.action.found === false) {
      continue;
    }
    if (drewNothing(report) && !(beforeReport !== null && drewNothing(beforeReport))) {
      problems.push(`${where} draws nothing`);
    }
    for (const fault of newFaults(report, beforeReport)) {
      problems.push(`${where}: ${fault}`);
    }
  }
  return { problems, notes };
}

function widgetKeysWritten(report) {
  const keys = [];
  for (const write of report.writes) {
    // A page can call store.set with no key at all; that is a refused write, never a widget
    const isWidgetWrite = typeof write.key === "string" && write.key.startsWith(WIDGET_PREFIX) && write.op !== "delete" && write.problem === null;
    if (isWidgetWrite && !keys.includes(write.key)) {
      keys.push(write.key);
    }
  }
  return keys;
}

// Every widget record the old page wrote when its widget records were missing, the new page
// writes too, and the shell accepts it (the store stand-in checks it against shell-types.js).
// Returns { problems, notes }.
export function checkWidgetRecords({ beforeResults, afterResults }) {
  const problems = [];
  const notes = [];
  const beforeStep = stepNamed(beforeResults, STEP_WIDGET);
  const afterStep = stepNamed(afterResults, STEP_WIDGET);
  if (beforeStep === null || beforeStep.problem) {
    notes.push("the old page could not be opened, so its widget records are unknown");
    return { problems, notes };
  }
  const beforeKeys = widgetKeysWritten(beforeStep.report);
  if (beforeKeys.length === 0) {
    notes.push("the copy wrote no widget record before the repair");
    return { problems, notes };
  }
  if (afterStep === null || afterStep.problem) {
    problems.push(`the new page could not be opened to write ${beforeKeys.join(", ")}`);
    return { problems, notes };
  }
  const afterKeys = widgetKeysWritten(afterStep.report);
  for (const key of beforeKeys) {
    if (!afterKeys.includes(key)) {
      problems.push(`${key} is no longer written; the widget would stop updating`);
    }
  }
  return { problems, notes };
}
