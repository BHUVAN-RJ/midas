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
      gateMs: typeof value.gateMs === 'number' && value.gateMs >= 0 ? value.gateMs : null,
      // The path a test phrase should take (round 2); null on spoken runs and older runs
      expect: PATHS.indexOf(value.expect) === -1 ? null : value.expect,
      // Round 3: whether the model call used a prewarmed session (null without a model call),
      // and the phone's heat (null on older runs)
      prewarmed: typeof value.prewarmed === 'boolean' ? value.prewarmed : null,
      thermal: THERMAL_STATES.indexOf(value.thermal) === -1 ? null : value.thermal
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
    if (isWrongPath(run)) {
      parts.push('Expected ' + PATH_LABELS[run.expect]);
    }
    if (run.firstCall) {
      parts.push('First Call');
    }
    if (run.prewarmed === true) {
      parts.push('Prewarmed');
    }
    if (run.thermal !== null) {
      parts.push('Heat ' + THERMAL_LABELS[run.thermal]);
    }
    return parts.join(' · ');
  }

  /* ---------- The gate: paths and settings (docs/briefs/dictation-gate-test.md) ---------- */

  const SETTINGS_KEY = 'settings:main';
  // Round 3 (founder 2026-11-14): rule removes fillers or applies a simple correction, no model
  const PATHS = ['skip', 'rule', 'light', 'rewrite'];
  const PATH_LABELS = { 'skip': 'Skip', 'rule': 'Rule', 'light': 'Light', 'rewrite': 'Rewrite' };
  // The phone's heat when a run was measured (ProcessInfo.thermalState in the shell)
  const THERMAL_STATES = ['nominal', 'fair', 'serious', 'critical'];
  const THERMAL_LABELS = { 'nominal': 'Nominal', 'fair': 'Fair', 'serious': 'Serious', 'critical': 'Critical' };
  // The manifest's limits for settings:main (DictationGateSettings in the shell)
  const SETTINGS_LIMITS = { listItems: 50, phrase: 40, triggers: 20, trigger: 30, instruction: 4000 };
  const LIST_FIELDS = ['fillers', 'positionFillers', 'corrections'];
  // Round 2 (founder 2026-11-13): the test phrases and the capitalise list, optional in the record
  // (DictationGateSettings.maxPhrases, maxPhraseTextCharacters, maxNoteCharacters in the shell)
  const PHRASE_LIMITS = { phrases: 60, text: 1000, note: 200 };
  // Round 3: how many times Run All runs each phrase, optional in the record
  // (DictationGateSettings.builtInRepeat and maxRepeat in the shell)
  const REPEAT_LIMITS = { min: 1, max: 20, builtIn: 3 };

  // The built-in settings, character for character as DictationGateSettings.builtIn in the shell.
  // Round 3 (founder 2026-11-14): rules first; no trigger words (parked), four fillers, a one-line
  // light instruction with no examples, fifteen phrases, Run All ×3.
  function defaultSettings() {
    return {
      fillers: ['um', 'uh', 'erm', 'hmm'],
      positionFillers: [],
      corrections: ['no wait', 'wait no', 'scratch that', 'make that', 'I mean', 'I meant', 'actually', 'sorry'],
      triggers: [],
      lightInstruction: 'Remove the correction and the words it replaces. Change nothing else. Reply with the text only.',
      capitalise: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday', 'January', 'February', 'March', 'April', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
      phrases: [
        { text: 'send the deck to Priya by friday', expect: 'skip' },
        { text: 'lunch with Maya on tuesday at 12:30', expect: 'skip' },
        { text: 'I like the new logo a lot', expect: 'skip', note: 'like as a word' },
        { text: 'it was so good to see you yesterday', expect: 'skip', note: 'so as a word' },
        { text: 'call David back before 5 tomorrow', expect: 'skip' },
        { text: 'uh tell mom im on my way', expect: 'rule', note: 'filler' },
        { text: 'um pack the charger the passport and the tickets', expect: 'rule', note: 'filler' },
        { text: 'for the party we need uh cups plates napkins and ice', expect: 'rule', note: 'filler' },
        { text: 'the call is at 2 no wait 3', expect: 'rule', note: 'correction' },
        { text: 'order 3 pizzas make that 4', expect: 'rule', note: 'correction' },
        { text: 'book the table for friday no wait saturday', expect: 'rule', note: 'correction' },
        { text: 'um be there at 5 no wait 6', expect: 'rule', note: 'correction' },
        { text: 'the browser is firefox scratch that chrome', expect: 'light', note: 'backtrack' },
        { text: 'send it to Tom I mean Tim', expect: 'light', note: 'backtrack' },
        { text: 'meet at the cafe on 5th street scratch that the library', expect: 'light', note: 'backtrack' }
      ],
      repeat: REPEAT_LIMITS.builtIn
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

  // One test phrase: text 1 to 1,000 characters, expect a path, an optional note up to 200
  // characters (empty or null is no note); null when it does not fit
  function phraseEntryFrom(value) {
    if (!isPlainObject(value) || typeof value.text !== 'string' || PATHS.indexOf(value.expect) === -1) {
      return null;
    }
    const text = value.text.trim();
    if (text.length === 0 || text.length > PHRASE_LIMITS.text) {
      return null;
    }
    const entry = { text: text, expect: value.expect };
    if (value.note === undefined || value.note === null) {
      return entry;
    }
    if (typeof value.note !== 'string' || value.note.trim().length > PHRASE_LIMITS.note) {
      return null;
    }
    const note = value.note.trim();
    if (note.length > 0) {
      entry.note = note;
    }
    return entry;
  }

  // 1 to 60 phrases, each fitting; null otherwise
  function phraseEntriesFrom(value) {
    if (!Array.isArray(value) || value.length === 0 || value.length > PHRASE_LIMITS.phrases) {
      return null;
    }
    const entries = [];
    for (const item of value) {
      const entry = phraseEntryFrom(item);
      if (entry === null) {
        return null;
      }
      entries.push(entry);
    }
    return entries;
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
    // Round 2's fields may be missing (a record saved by the round 1 page); present, they must fit
    if (value.capitalise !== undefined && phraseListFrom(value.capitalise) === null) {
      return 'capitalise';
    }
    if (value.phrases !== undefined && phraseEntriesFrom(value.phrases) === null) {
      return 'phrases';
    }
    // Round 3's repeat may be missing too; present, a whole number from 1 to 20
    if (value.repeat !== undefined && repeatFrom(value.repeat) === null) {
      return 'repeat';
    }
    return null;
  }

  function repeatFrom(value) {
    if (typeof value !== 'number' || !Number.isInteger(value) || value < REPEAT_LIMITS.min || value > REPEAT_LIMITS.max) {
      return null;
    }
    return value;
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
      lightInstruction: instructionFrom(value.lightInstruction),
      capitalise: value.capitalise === undefined ? defaultSettings().capitalise : phraseListFrom(value.capitalise),
      phrases: value.phrases === undefined ? defaultSettings().phrases : phraseEntriesFrom(value.phrases),
      repeat: value.repeat === undefined ? REPEAT_LIMITS.builtIn : repeatFrom(value.repeat)
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

  // Per heat state over the runs that logged one: runs and share in percent. Null when no run
  // logged its heat. The shell writes the same into summary:main (round 3).
  function thermalSummaryOf(runs) {
    let logged = 0;
    for (const run of runs) {
      if (run.thermal !== null) {
        logged += 1;
      }
    }
    if (logged === 0) {
      return null;
    }
    const summary = {};
    for (const state of THERMAL_STATES) {
      let count = 0;
      for (const run of runs) {
        if (run.thermal === state) {
          count += 1;
        }
      }
      summary[state] = { runs: count, sharePercent: Math.round(count * 100 / logged) };
    }
    return summary;
  }

  // A Run All or tapped phrase run whose path was not the one its phrase expects
  function isWrongPath(run) {
    return run.expect !== null && run.path !== null && run.expect !== run.path;
  }

  // Over the runs that carry an expected path: how many, and how many took another path
  function wrongPathOf(runs) {
    let checked = 0;
    let wrong = 0;
    for (const run of runs) {
      if (run.expect === null || run.path === null) {
        continue;
      }
      checked += 1;
      if (isWrongPath(run)) {
        wrong += 1;
      }
    }
    return { checked: checked, wrong: wrong };
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
    pathSummaryOf: pathSummaryOf,
    PHRASE_LIMITS: PHRASE_LIMITS,
    isWrongPath: isWrongPath,
    wrongPathOf: wrongPathOf,
    THERMAL_STATES: THERMAL_STATES,
    THERMAL_LABELS: THERMAL_LABELS,
    thermalSummaryOf: thermalSummaryOf,
    REPEAT_LIMITS: REPEAT_LIMITS,
    repeatFrom: repeatFrom
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
    if (run.expect !== null) {
      shown.expect = run.expect;
    }
    // Round 3: the prewarmed session and the phone's heat, when logged
    if (run.prewarmed !== null) {
      shown.prewarmed = run.prewarmed;
    }
    if (run.thermal !== null) {
      shown.thermal = run.thermal;
    }
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

  // "Heat nominal 80%, fair 20%, serious 0%, critical 0%."
  function heatText(heat) {
    const parts = [];
    for (const thermal of Logic.THERMAL_STATES) {
      parts.push(thermal + ' ' + heat[thermal].sharePercent + '%');
    }
    return 'Heat ' + parts.join(', ') + '.';
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
    // Test phrases against the path each should take (round 2)
    const check = Logic.wrongPathOf(runs);
    if (check.checked > 0) {
      result.text += ' Wrong path ' + check.wrong + ' of ' + check.checked + ' runs.';
      result.wrongPath = check;
    }
    // The phone's heat over the runs that logged it (round 3)
    const heat = Logic.thermalSummaryOf(runs);
    if (heat !== null) {
      result.text += ' ' + heatText(heat);
      result.thermal = heat;
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
    const text = 'Fillers: ' + settings.fillers.join(', ') + '. By position: ' + (settings.positionFillers.length > 0 ? settings.positionFillers.join(', ') : 'none') + '. Corrections: '
      + settings.corrections.join(', ') + '. Trigger words: ' + (triggerWords.length > 0 ? triggerWords.join(', ') : 'none') + '. Capitalise: '
      + (settings.capitalise.length > 0 ? settings.capitalise.join(', ') : 'none') + '. Test phrases: ' + settings.phrases.length
      + '. Run All repeats: ' + settings.repeat + '.';
    const result = { text: text, saved: resolved.saved };
    result.fillers = settings.fillers;
    result.positionFillers = settings.positionFillers;
    result.corrections = settings.corrections;
    result.triggers = settings.triggers;
    result.lightInstruction = settings.lightInstruction;
    result.capitalise = settings.capitalise;
    result.phrases = settings.phrases;
    result.repeat = settings.repeat;
    return done(result);
  }

  const SETTING_NAMES = { fillers: 'fillers', positionFillers: 'fillers by position', corrections: 'corrections', triggers: 'trigger words',
    lightInstruction: 'light instruction', capitalise: 'capitalise list', phrases: 'test phrases', repeat: 'run all repeats', settings: 'settings' };

  // Each field given replaces the current one; null (or missing) keeps it
  function saveSettings(input, records, now) {
    const current = Logic.resolvedSettings(storedSettings(records)).settings;
    const wanted = {};
    const changed = [];
    for (const field of ['fillers', 'positionFillers', 'corrections', 'triggers', 'lightInstruction', 'capitalise', 'phrases', 'repeat']) {
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
