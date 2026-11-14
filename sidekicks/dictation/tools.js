// Dictation tools (TEST Sidekick, founder 2026-11-13): what jess (and later any outside agent) can
// ask of this Sidekick. manifest.json "agent" describes each tool; this file does the work. The
// shell runs it in JavaScriptCore; nothing here touches the store. Runs are written only by the
// shell's Dictation Test screen, so the run tools only read; save_settings returns the one
// settings:main record for the shell to write, exactly as the page's Save does.
//
// The block between "copied from index.html" markers is the page's own code, character for
// character: the deploy gate refuses this file when it no longer appears in index.html.
//
// A plain script: one global (MidasSidekickTools), a CommonJS export at the end for Node.
var MidasSidekickTools = (function createDictationTools() {
  'use strict';

  /* copied from index.html: begin */
var DictationLogic = (function createDictationLogic() {
  'use strict';

  const RUN_PREFIX = 'run:';
  const SUMMARY_KEY = 'summary:main';
  // The native Dictation Test screen; only a Midas Test build carries it out
  const TEST_REQUEST_KIND = 'test.dictation';
  const HOME_SCREEN_REQUEST_KIND = 'home-screen.widget';
  const SOURCES = ['phrase', 'spoken', 'run-all'];
  const SOURCE_LABELS = { 'phrase': 'Phrase', 'spoken': 'Spoken', 'run-all': 'Run All' };
  const DEFAULT_LIMIT = 10;
  const MAX_LIMIT = 50;
  const WIDGET_KEY = 'widget:summary';
  const WIDGET_NAME = 'Dictation';
  const WIDGET_VERSION = 1;

  function isPlainObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  function isWholeMs(value) {
    return typeof value === 'number' && Number.isInteger(value) && value >= 0;
  }

  function copyJson(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function matchedFrom(value) {
    const words = [];
    for (const word of Array.isArray(value) ? value : []) {
      if (typeof word === 'string') {
        words.push(word);
      }
    }
    return words;
  }

  // A stored run as the page and the tools use it; null for a record that is not a run
  function runFrom(key, value) {
    if (!isPlainObject(value) || !isWholeMs(value.cleanupMs) || typeof value.at !== 'string') {
      return null;
    }
    const source = SOURCES.indexOf(value.source) === -1 ? 'phrase' : value.source;
    return {
      key: key,
      at: value.at,
      source: source,
      raw: typeof value.raw === 'string' ? value.raw : '',
      cleaned: typeof value.cleaned === 'string' ? value.cleaned : '',
      cleanupMs: value.cleanupMs,
      releaseToRawMs: isWholeMs(value.releaseToRawMs) ? value.releaseToRawMs : null,
      totalMs: isWholeMs(value.totalMs) ? value.totalMs : null,
      firstCall: value.firstCall === true,
      modelStatus: typeof value.modelStatus === 'string' ? value.modelStatus : '',
      device: typeof value.device === 'string' ? value.device : '',
      ios: typeof value.ios === 'string' ? value.ios : '',
      // The gate's fields; null (or empty) on runs from before the gate
      path: PATHS.indexOf(value.path) === -1 ? null : value.path,
      trigger: typeof value.trigger === 'string' && value.trigger.length > 0 ? value.trigger : null,
      matched: matchedFrom(value.matched),
      gateMs: typeof value.gateMs === 'number' && value.gateMs >= 0 ? value.gateMs : null
    };
  }

  // Newest first: by time, then by key (two runs in the same millisecond keep their order)
  function compareNewestFirst(first, second) {
    const firstMs = Date.parse(first.at);
    const secondMs = Date.parse(second.at);
    if (firstMs !== secondMs) {
      return secondMs - firstMs;
    }
    return first.key < second.key ? 1 : -1;
  }

  // Every run in the records ([{ key, value }]), newest first
  function runsOf(records) {
    const runs = [];
    for (const record of records || []) {
      if (typeof record.key !== 'string' || record.key.indexOf(RUN_PREFIX) !== 0) {
        continue;
      }
      const run = runFrom(record.key, record.value);
      if (run !== null) {
        runs.push(run);
      }
    }
    runs.sort(compareNewestFirst);
    return runs;
  }

  // Over every run: the count, the newest one's cleanup time, the rounded average and the worst.
  // The shell writes the same numbers into summary:main for the widget (DictationRunSummaryRecord).
  function summaryOf(runs) {
    if (runs.length === 0) {
      return { runs: 0, lastCleanupMs: null, averageCleanupMs: null, worstCleanupMs: null, lastAt: null };
    }
    let total = 0;
    let worst = 0;
    for (const run of runs) {
      total += run.cleanupMs;
      worst = Math.max(worst, run.cleanupMs);
    }
    return {
      runs: runs.length,
      lastCleanupMs: runs[0].cleanupMs,
      averageCleanupMs: Math.round(total / runs.length),
      worstCleanupMs: worst,
      lastAt: runs[0].at
    };
  }

  // A limit asked for, kept within 1 to 50; null means the default
  function limitFrom(value) {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return DEFAULT_LIMIT;
    }
    return Math.min(MAX_LIMIT, Math.max(1, Math.round(value)));
  }

  function formatMs(milliseconds) {
    if (milliseconds === null || milliseconds === undefined) {
      return '–';
    }
    const formatter = new Intl.NumberFormat('en-US');
    return formatter.format(milliseconds) + ' ms';
  }

  function sourceLabel(source) {
    return SOURCE_LABELS[source] || SOURCE_LABELS.phrase;
  }

  // One run's timings as a line: cleanup first, then what else was measured
  function timingsLine(run) {
    const parts = ['Cleanup ' + formatMs(run.cleanupMs)];
    if (run.releaseToRawMs !== null) {
      parts.push('Raw ' + formatMs(run.releaseToRawMs));
    }
    if (run.totalMs !== null) {
      parts.push('Total ' + formatMs(run.totalMs));
    }
    parts.push(sourceLabel(run.source));
    if (run.path !== null) {
      parts.push(pathLabel(run));
    }
    if (run.firstCall) {
      parts.push('First Call');
    }
    return parts.join(' · ');
  }

  /* ---------- The gate: paths and settings (docs/briefs/dictation-gate-test.md) ---------- */

  const SETTINGS_KEY = 'settings:main';
  const PATHS = ['skip', 'light', 'rewrite'];
  const PATH_LABELS = { 'skip': 'Skip', 'light': 'Light', 'rewrite': 'Rewrite' };
  // The manifest's limits for settings:main (DictationGateSettings in the shell)
  const SETTINGS_LIMITS = { listItems: 50, phrase: 40, triggers: 20, trigger: 30, instruction: 4000 };
  const LIST_FIELDS = ['fillers', 'positionFillers', 'corrections'];

  // The built-in settings, character for character as DictationGateSettings.builtIn in the shell
  function defaultSettings() {
    return {
      fillers: ['um', 'uh', 'erm', 'hmm', 'you know', 'I mean', 'sort of', 'kind of', 'basically'],
      positionFillers: ['like', 'so'],
      corrections: ['no wait', 'wait no', 'scratch that', 'I mean', 'actually', 'sorry', 'no no', 'make that', 'I meant'],
      triggers: [
        { word: 'email', instruction: 'Turn the dictated text into a short email to the person it names. Remove filler words and apply self-corrections. "tell Sam X" becomes a message to Sam saying X. Keep every fact, name, number and time as said. Start with "Hi <name>," and end with "Thanks" on its own line. No subject line, no notes. Reply with the email only, as plain text.' },
        { word: 'formal', instruction: 'Rewrite the dictated text in a formal, polite tone. Remove filler words and apply self-corrections. Keep every fact, name, number and time as said. Add no new content. Reply with the rewritten text only, as plain text.' },
        { word: 'casual', instruction: 'Rewrite the dictated text in a casual, friendly tone. Remove filler words and apply self-corrections. Keep every fact, name, number and time as said. Add no new content. Reply with the rewritten text only, as plain text.' },
        { word: 'list', instruction: 'Turn the dictated text into a bulleted list: one item per line, each line starting with "- ". Split the items where the speaker lists them, even without commas or "and". Remove filler words and apply self-corrections. Capitalise each item. No heading, nothing else. Reply with the list only, as plain text.' },
        { word: 'bullets', instruction: 'Turn the dictated text into short bullet points, one point per line, each line starting with "- ". Remove filler words and apply self-corrections. Keep every fact, name, number and time as said. No heading, nothing else. Reply with the bullets only, as plain text.' }
      ],
      lightInstruction: [
        'You clean up dictated text. Rules:',
        '1. Remove filler words: um, uh, erm, hmm, like, so, you know, I mean, sort of, kind of, basically, when they are fillers.',
        '2. Apply self-corrections: when the speaker corrects themselves (no wait, scratch that, I mean, actually, make that), keep only the corrected version. "be there at 5 no wait 6" becomes "Be there at 6."',
        '3. Add punctuation and capital letters, including names and the start of each sentence.',
        '4. When the speaker lists several items in a row, write them as a numbered list, one item per line.',
        '5. Keep the person\'s own words otherwise. Never change pronouns, names, numbers or meaning, except what a correction explicitly replaces: "I" stays "I", "you" stays "you". Do not rephrase, summarise or translate.',
        '6. Add nothing: never add words, greetings, explanations, quotes or notes.',
        'Reply with the cleaned text only, as plain text.'
      ].join('\n')
    };
  }

  // A phrase: trimmed, 1 to max characters, with a letter or a digit; null when it does not fit
  function phraseFrom(value, maxLength) {
    if (typeof value !== 'string') {
      return null;
    }
    const text = value.trim();
    if (text.length === 0 || text.length > maxLength || !/[\p{L}\p{N}]/u.test(text)) {
      return null;
    }
    return text;
  }

  function instructionFrom(value) {
    if (typeof value !== 'string') {
      return null;
    }
    const text = value.trim();
    if (text.length === 0 || text.length > SETTINGS_LIMITS.instruction) {
      return null;
    }
    return text;
  }

  function phraseListFrom(value) {
    if (!Array.isArray(value) || value.length > SETTINGS_LIMITS.listItems) {
      return null;
    }
    const phrases = [];
    for (const item of value) {
      const phrase = phraseFrom(item, SETTINGS_LIMITS.phrase);
      if (phrase === null) {
        return null;
      }
      phrases.push(phrase);
    }
    return phrases;
  }

  function triggerListFrom(value) {
    if (!Array.isArray(value) || value.length > SETTINGS_LIMITS.triggers) {
      return null;
    }
    const triggers = [];
    for (const item of value) {
      if (!isPlainObject(item)) {
        return null;
      }
      const word = phraseFrom(item.word, SETTINGS_LIMITS.trigger);
      const instruction = instructionFrom(item.instruction);
      if (word === null || instruction === null) {
        return null;
      }
      triggers.push({ word: word, instruction: instruction });
    }
    return triggers;
  }

  // The first field of a settings value that does not fit, or null when all fit
  function settingsProblem(value) {
    if (!isPlainObject(value)) {
      return 'settings';
    }
    for (const field of LIST_FIELDS) {
      if (phraseListFrom(value[field]) === null) {
        return field;
      }
    }
    if (triggerListFrom(value.triggers) === null) {
      return 'triggers';
    }
    if (instructionFrom(value.lightInstruction) === null) {
      return 'lightInstruction';
    }
    return null;
  }

  // Settings as the shell reads them (trimmed), or null when they do not fit
  function settingsFrom(value) {
    if (settingsProblem(value) !== null) {
      return null;
    }
    return {
      fillers: phraseListFrom(value.fillers),
      positionFillers: phraseListFrom(value.positionFillers),
      corrections: phraseListFrom(value.corrections),
      triggers: triggerListFrom(value.triggers),
      lightInstruction: instructionFrom(value.lightInstruction)
    };
  }

  // The stored settings, or the built-in ones when missing or not fitting (as the shell does)
  function resolvedSettings(storedValue) {
    const stored = settingsFrom(storedValue);
    if (stored === null) {
      return { settings: defaultSettings(), saved: false };
    }
    return { settings: stored, saved: true };
  }

  // A list typed on the page: split at commas and new lines, blanks dropped
  function phrasesFromText(text) {
    const phrases = [];
    for (const piece of String(text || '').split(/[,\n]/)) {
      const trimmed = piece.trim();
      if (trimmed.length > 0) {
        phrases.push(trimmed);
      }
    }
    return phrases;
  }

  function pathLabel(run) {
    const label = PATH_LABELS[run.path] || '';
    if (run.trigger) {
      return label + ': ' + run.trigger;
    }
    return label;
  }

  // A spoken run's total is release to inserted text; a phrase has no speaking, so gate plus cleanup
  function effectiveTotalMs(run) {
    if (run.totalMs !== null) {
      return run.totalMs;
    }
    return run.cleanupMs + (run.gateMs === null ? 0 : run.gateMs);
  }

  // Per path over the runs the gate decided: runs, share in percent, average total ms (null
  // without runs). Null when no run has a path. The shell writes the same into summary:main.
  function pathSummaryOf(runs) {
    const gated = [];
    for (const run of runs) {
      if (run.path !== null) {
        gated.push(run);
      }
    }
    if (gated.length === 0) {
      return null;
    }
    const summary = {};
    for (const path of PATHS) {
      let count = 0;
      let total = 0;
      for (const run of gated) {
        if (run.path === path) {
          count += 1;
          total += effectiveTotalMs(run);
        }
      }
      summary[path] = {
        runs: count,
        sharePercent: Math.round(count * 100 / gated.length),
        averageTotalMs: count === 0 ? null : Math.round(total / count)
      };
    }
    return summary;
  }

  /* ---------- Home Screen widget (docs/WIDGETS.md) ---------- */

  // No background of its own, so the system ink reads in light and dark
  function caption(text, extra) {
    const piece = { text: text, style: 'caption', color: 'secondary' };
    for (const field of Object.keys(extra || {})) {
      piece[field] = extra[field];
    }
    return piece;
  }

  function headerRow() {
    return { spacing: 4, hstack: [
      { symbol: 'waveform', size: 13, color: 'secondary' },
      caption('Cleanup'),
      { spacer: true },
      caption('TEST')
    ] };
  }

  function lastPieces() {
    return [
      { text: '$summary.lastCleanupMs ms', style: 'title', if: '$summary.runs' },
      caption('Last', { if: '$summary.runs' })
    ];
  }

  function averagePieces() {
    return [
      { text: 'Avg $summary.averageCleanupMs ms', style: 'caption', if: '$summary.runs' },
      caption('Worst $summary.worstCleanupMs ms', { if: '$summary.runs' })
    ];
  }

  function emptyPiece() {
    return { text: 'No Runs', style: 'headline', unless: '$summary.runs' };
  }

  function dictationWidget() {
    const smallColumn = [headerRow()].concat(lastPieces(), [emptyPiece(), { spacer: true }], averagePieces());
    const mediumRight = [{ spacer: true }].concat(averagePieces(), [caption('$summary.runs runs', { if: '$summary.runs' })]);
    const mediumRow = { spacing: 12, hstack: [
      { spacing: 2, align: 'leading', vstack: lastPieces().concat([emptyPiece()]) },
      { spacer: true },
      { spacing: 2, align: 'leading', vstack: mediumRight }
    ] };
    return {
      version: WIDGET_VERSION,
      name: WIDGET_NAME,
      sources: { summary: { record: SUMMARY_KEY } },
      small: { spacing: 2, align: 'leading', vstack: smallColumn },
      medium: { spacing: 6, align: 'leading', vstack: [headerRow(), mediumRow] }
    };
  }

  function widgetRecords() {
    return [{ key: WIDGET_KEY, value: dictationWidget() }];
  }

  // A stored widget equals a wanted one when they match apart from the stamped $type
  function sameWidget(stored, wanted) {
    if (!isPlainObject(stored)) {
      return false;
    }
    const withoutType = copyJson(stored);
    delete withoutType.$type;
    return JSON.stringify(withoutType) === JSON.stringify(wanted);
  }

  return {
    RUN_PREFIX: RUN_PREFIX,
    SUMMARY_KEY: SUMMARY_KEY,
    TEST_REQUEST_KIND: TEST_REQUEST_KIND,
    HOME_SCREEN_REQUEST_KIND: HOME_SCREEN_REQUEST_KIND,
    DEFAULT_LIMIT: DEFAULT_LIMIT,
    MAX_LIMIT: MAX_LIMIT,
    runFrom: runFrom,
    runsOf: runsOf,
    summaryOf: summaryOf,
    limitFrom: limitFrom,
    formatMs: formatMs,
    sourceLabel: sourceLabel,
    timingsLine: timingsLine,
    widgetRecords: widgetRecords,
    sameWidget: sameWidget,
    SETTINGS_KEY: SETTINGS_KEY,
    PATHS: PATHS,
    PATH_LABELS: PATH_LABELS,
    SETTINGS_LIMITS: SETTINGS_LIMITS,
    defaultSettings: defaultSettings,
    settingsProblem: settingsProblem,
    settingsFrom: settingsFrom,
    resolvedSettings: resolvedSettings,
    phrasesFromText: phrasesFromText,
    pathLabel: pathLabel,
    effectiveTotalMs: effectiveTotalMs,
    pathSummaryOf: pathSummaryOf
  };
})();
  /* copied from index.html: end */

  const Logic = DictationLogic;

  function done(result) {
    return { ops: [], result: result };
  }

  function refused(reason, text) {
    return { refused: reason, result: { text: text } };
  }

  function storedSettings(records) {
    for (const record of records || []) {
      if (record.key === Logic.SETTINGS_KEY) {
        return record.value;
      }
    }
    return null;
  }

  // What a run looks like to jess: the words and the numbers, no record internals
  function runForAgent(run) {
    const shown = {
      at: run.at,
      source: Logic.sourceLabel(run.source),
      raw: run.raw,
      cleaned: run.cleaned,
      cleanupMs: run.cleanupMs,
      firstCall: run.firstCall
    };
    if (run.releaseToRawMs !== null) {
      shown.releaseToRawMs = run.releaseToRawMs;
    }
    if (run.totalMs !== null) {
      shown.totalMs = run.totalMs;
    }
    // The gate's fields only on runs the gate decided, so older runs read as before
    if (run.path !== null) {
      shown.path = run.path;
      shown.matched = run.matched;
      if (run.trigger !== null) {
        shown.trigger = run.trigger;
      }
      if (run.gateMs !== null) {
        shown.gateMs = run.gateMs;
      }
    }
    return shown;
  }

  // "Skip 3 runs (33%), avg 12 ms; Light ..."
  function pathsText(paths) {
    const parts = [];
    for (const path of Logic.PATHS) {
      const entry = paths[path];
      const runWord = entry.runs === 1 ? ' run' : ' runs';
      let part = Logic.PATH_LABELS[path] + ' ' + entry.runs + runWord + ' (' + entry.sharePercent + '%)';
      if (entry.averageTotalMs !== null) {
        part += ', avg ' + Logic.formatMs(entry.averageTotalMs);
      }
      parts.push(part);
    }
    return parts.join('; ') + '.';
  }

  function summaryText(summary) {
    if (summary.runs === 0) {
      return 'No runs yet';
    }
    const runWord = summary.runs === 1 ? ' run' : ' runs';
    return summary.runs + runWord + '. Last ' + Logic.formatMs(summary.lastCleanupMs) + ', average ' + Logic.formatMs(summary.averageCleanupMs)
      + ', worst ' + Logic.formatMs(summary.worstCleanupMs) + '.';
  }

  /* ---------- The tools ---------- */

  function showSummary(input, records, now) {
    const runs = Logic.runsOf(records);
    const summary = Logic.summaryOf(runs);
    const paths = Logic.pathSummaryOf(runs);
    const result = { text: summaryText(summary) };
    result.runs = summary.runs;
    result.lastCleanupMs = summary.lastCleanupMs;
    result.averageCleanupMs = summary.averageCleanupMs;
    result.worstCleanupMs = summary.worstCleanupMs;
    if (paths !== null) {
      result.text += ' ' + pathsText(paths);
      result.paths = paths;
    }
    return done(result);
  }

  function showSettings(input, records, now) {
    const resolved = Logic.resolvedSettings(storedSettings(records));
    const settings = resolved.settings;
    const triggerWords = [];
    for (const trigger of settings.triggers) {
      triggerWords.push(trigger.word);
    }
    const text = 'Fillers: ' + settings.fillers.join(', ') + '. By position: ' + settings.positionFillers.join(', ') + '. Corrections: '
      + settings.corrections.join(', ') + '. Trigger words: ' + (triggerWords.length > 0 ? triggerWords.join(', ') : 'none') + '.';
    const result = { text: text, saved: resolved.saved };
    result.fillers = settings.fillers;
    result.positionFillers = settings.positionFillers;
    result.corrections = settings.corrections;
    result.triggers = settings.triggers;
    result.lightInstruction = settings.lightInstruction;
    return done(result);
  }

  const SETTING_NAMES = { fillers: 'fillers', positionFillers: 'fillers by position', corrections: 'corrections', triggers: 'trigger words',
    lightInstruction: 'light instruction', settings: 'settings' };

  // Each field given replaces the current one; null (or missing) keeps it
  function saveSettings(input, records, now) {
    const current = Logic.resolvedSettings(storedSettings(records)).settings;
    const wanted = {};
    const changed = [];
    for (const field of ['fillers', 'positionFillers', 'corrections', 'triggers', 'lightInstruction']) {
      const given = input ? input[field] : null;
      if (given === null || given === undefined) {
        wanted[field] = current[field];
      } else {
        wanted[field] = given;
        changed.push(SETTING_NAMES[field]);
      }
    }
    if (changed.length === 0) {
      return refused('nothing to change', 'Nothing to change');
    }
    const problem = Logic.settingsProblem(wanted);
    if (problem !== null) {
      return refused('bad ' + problem, 'Can\u2019t save ' + SETTING_NAMES[problem]);
    }
    const settings = Logic.settingsFrom(wanted);
    const ops = [{ op: 'set', key: Logic.SETTINGS_KEY, value: settings }];
    return { ops: ops, result: { text: 'Saved ' + changed.join(', '), changed: changed } };
  }

  function listRuns(input, records, now) {
    const runs = Logic.runsOf(records);
    const limit = Logic.limitFrom(input ? input.limit : null);
    const shown = [];
    for (const run of runs.slice(0, limit)) {
      shown.push(runForAgent(run));
    }
    if (shown.length === 0) {
      return done({ text: 'No runs yet', runs: [] });
    }
    const lines = [];
    for (const run of runs.slice(0, limit)) {
      lines.push(Logic.timingsLine(run) + ': ' + run.cleaned);
    }
    return done({ text: lines.join('\n'), runs: shown });
  }

  /* ---------- What jess is told about this Sidekick's records ---------- */

  function buildContext(records, now) {
    const summary = Logic.summaryOf(Logic.runsOf(records));
    return {
      runs: summary.runs,
      lastCleanupMs: summary.lastCleanupMs,
      averageCleanupMs: summary.averageCleanupMs,
      worstCleanupMs: summary.worstCleanupMs
    };
  }

  return {
    context: buildContext,
    handlers: {
      summary: showSummary,
      runs: listRuns,
      settings: showSettings,
      save_settings: saveSettings
    }
  };
})();

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSidekickTools;
}
