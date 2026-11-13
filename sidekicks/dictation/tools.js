// Dictation tools (TEST Sidekick, founder 2026-11-13): what jess (and later any outside agent) can
// ask of this Sidekick. manifest.json "agent" describes each tool; this file does the work. The
// shell runs it in JavaScriptCore; nothing here touches the store. Runs are written only by the
// shell's Dictation Test screen, so both tools only read.
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
      ios: typeof value.ios === 'string' ? value.ios : ''
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
    if (run.firstCall) {
      parts.push('First Call');
    }
    return parts.join(' · ');
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
    sameWidget: sameWidget
  };
})();
  /* copied from index.html: end */

  const Logic = DictationLogic;

  function done(result) {
    return { ops: [], result: result };
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
    return shown;
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
    const summary = Logic.summaryOf(Logic.runsOf(records));
    const result = { text: summaryText(summary) };
    result.runs = summary.runs;
    result.lastCleanupMs = summary.lastCleanupMs;
    result.averageCleanupMs = summary.averageCleanupMs;
    result.worstCleanupMs = summary.worstCleanupMs;
    return done(result);
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
      runs: listRuns
    }
  };
})();

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSidekickTools;
}
