// Sounds tools: every action a person can take in this Sidekick that works without the page, as
// functions jess (and later any outside agent) can call (jess router, founder 2026-10-21).
// manifest.json "agent" describes each tool; this file does the work. The shell runs it in
// JavaScriptCore and writes the ops it returns through RecordWriter; nothing here touches the store.
//
// Not tools (docs/briefs/soundboard-sidekick.md, section 2): playing a sound (only the page can
// make sound; jess playing one needs a shell change) and adding one (sounds are added by Midas as
// starters, never by the person; founder, 2026-11-07: "remove that completely").
//
// The block between "copied from index.html" markers is the page's own code, character for
// character: the deploy gate refuses this file when it no longer appears in index.html, so a
// sound renamed by voice is written exactly as the page writes it. Change the page, then copy the
// block here again.
//
// A plain script: one global (MidasSidekickTools), a CommonJS export at the end for Node.
var MidasSidekickTools = (function createSoundsTools() {
  'use strict';

  /* copied from index.html: begin */
var SoundsLogic = (function createSoundsLogic() {
  'use strict';

  const SOUND_PREFIX = 'sound:';
  const SETTINGS_KEY = 'settings:self';
  const NAME_MAX = 60;
  const TAG_MAX = 30;
  const TAGS_MAX = 20;
  const SEEDED_MAX = 200;
  const STARTER_KEY_MAX = 40;
  const FILE_REF_PATTERN = /^file:[A-Za-z0-9_-]{1,64}$/;
  // The Home Screen widget (docs/WIDGETS.md, "Every Sidekick ships a widget"): the count and the
  // first names, on the home grid's Lemon by day and the page's own night black in dark mode
  // (founder, 2026-10-27: every widget gives light and dark). A widget cannot draw a GIF or play
  // a sound, so a tap opens Sounds.
  const WIDGET_KEY = 'widget:sounds';
  const WIDGET_NAME = 'Sounds';
  const WIDGET_VERSION = 1;
  const WIDGET_SYMBOL = 'speaker.wave.2.fill';
  const WIDGET_BACKGROUND = { light: '#FFE600', dark: '#1A1A1A' };
  const WIDGET_INK = { light: '#111111', dark: '#FFFFFF' };
  const WIDGET_INK_SECONDARY = { light: '#3D3A00', dark: '#C8C8C8' };
  const WIDGET_MARK = { light: '#111111', dark: '#FFE600' };
  // The widget's list reads at most 50 records (the shell's limit), so "+N more" stays right up to 50
  const WIDGET_SOURCE_LIMIT = 50;
  const WIDGET_ROWS = { small: 3, medium: 4 };

  /* ---------- Small helpers ---------- */

  function copyJson(value) {
    if (value === null || value === undefined) {
      return null;
    }
    return JSON.parse(JSON.stringify(value));
  }

  function isPlainObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  // JSON with object keys sorted, so two descriptions compare equal whatever order the shell
  // stored their keys in
  function stableJson(value) {
    if (Array.isArray(value)) {
      const parts = [];
      for (const element of value) {
        parts.push(stableJson(element));
      }
      return '[' + parts.join(',') + ']';
    }
    if (isPlainObject(value)) {
      const names = Object.keys(value);
      names.sort();
      const parts = [];
      for (const name of names) {
        parts.push(JSON.stringify(name) + ':' + stableJson(value[name]));
      }
      return '{' + parts.join(',') + '}';
    }
    return JSON.stringify(value);
  }

  // Runs of spaces become one; ends trimmed
  function squeezeSpaces(text) {
    const words = String(text === null || text === undefined ? '' : text).split(/\s+/);
    const kept = [];
    for (const word of words) {
      if (word !== '') {
        kept.push(word);
      }
    }
    return kept.join(' ');
  }

  function isFileRef(value) {
    return typeof value === 'string' && FILE_REF_PATTERN.test(value);
  }

  /* ---------- Names and tags ---------- */

  // A name as stored: spaces squeezed, at most 60 characters; '' when nothing is left
  function cleanName(text) {
    const squeezed = squeezeSpaces(text);
    const cut = squeezed.slice(0, NAME_MAX);
    return cut.trim();
  }

  function withCapitalFirst(text) {
    const first = text.charAt(0);
    return first.toUpperCase() + text.slice(1);
  }

  function cleanTag(text) {
    const squeezed = squeezeSpaces(text);
    const lowered = squeezed.toLowerCase();
    const cut = lowered.slice(0, TAG_MAX);
    return cut.trim();
  }

  // Tags as stored: lower case, no empties, no repeats, at most 20
  function cleanTags(list) {
    const tags = [];
    for (const item of Array.isArray(list) ? list : []) {
      const tag = cleanTag(item);
      if (tag !== '' && tags.indexOf(tag) === -1 && tags.length < TAGS_MAX) {
        tags.push(tag);
      }
    }
    return tags;
  }

  // The Tags field: tags between commas ("fail, sad trombone")
  function parseTags(text) {
    const parts = String(text === null || text === undefined ? '' : text).split(',');
    return cleanTags(parts);
  }

  function tagsText(tags) {
    return cleanTags(tags).join(', ');
  }

  /* ---------- Sounds ---------- */

  // A stored sound, read with defaults
  function soundFrom(value) {
    const source = isPlainObject(value) ? value : {};
    return {
      name: typeof source.name === 'string' ? source.name : '',
      tags: cleanTags(source.tags),
      audio: isFileRef(source.audio) ? source.audio : null,
      image: isFileRef(source.image) ? source.image : null,
      order: Number.isFinite(source.order) ? source.order : null,
      starter: typeof source.starter === 'string' ? source.starter : null,
      createdAt: typeof source.createdAt === 'string' ? source.createdAt : ''
    };
  }

  // Board order: by order (sounds without one last), then when added, then key
  function compareEntries(first, second) {
    const firstOrder = first.sound.order === null ? Infinity : first.sound.order;
    const secondOrder = second.sound.order === null ? Infinity : second.sound.order;
    if (firstOrder !== secondOrder) {
      return firstOrder < secondOrder ? -1 : 1;
    }
    if (first.sound.createdAt !== second.sound.createdAt) {
      return first.sound.createdAt < second.sound.createdAt ? -1 : 1;
    }
    if (first.key === second.key) {
      return 0;
    }
    return first.key < second.key ? -1 : 1;
  }

  // The board: [{ key, sound }] in order, from [{ key, value }] records
  function soundsInOrder(records) {
    const entries = [];
    for (const record of Array.isArray(records) ? records : []) {
      if (typeof record.key === 'string' && record.key.indexOf(SOUND_PREFIX) === 0) {
        entries.push({ key: record.key, sound: soundFrom(record.value) });
      }
    }
    entries.sort(compareEntries);
    return entries;
  }

  function searchTextOf(sound) {
    const words = [sound.name].concat(sound.tags);
    return words.join(' ').toLowerCase();
  }

  // Every word of the query is somewhere in the name or the tags, any case; an empty query matches
  function matchesQuery(sound, query) {
    const queryText = String(query === null || query === undefined ? '' : query);
    const lowered = queryText.toLowerCase();
    const words = squeezeSpaces(lowered).split(' ');
    const haystack = searchTextOf(sound);
    for (const word of words) {
      if (word !== '' && haystack.indexOf(word) === -1) {
        return false;
      }
    }
    return true;
  }

  function filterEntries(entries, query) {
    const shown = [];
    for (const entry of entries) {
      if (matchesQuery(entry.sound, query)) {
        shown.push(entry);
      }
    }
    return shown;
  }

  // A new sound goes after the last one
  function nextOrder(entries) {
    let highest = 0;
    for (const entry of entries) {
      if (entry.sound.order !== null && entry.sound.order > highest) {
        highest = entry.sound.order;
      }
    }
    return Math.floor(highest) + 1;
  }

  // A key that differs from any other: the time and a random part, both base 36 (the page uses
  // its tail for the Add Widget request; sounds are added by Midas under their starter key)
  function newSoundKey(nowMs, randomFraction) {
    const wholeMs = Math.floor(nowMs);
    const wholeRandom = Math.floor(randomFraction * 1e9);
    return SOUND_PREFIX + wholeMs.toString(36) + wholeRandom.toString(36);
  }

  // The record to store: the existing record's fields (ones this page does not know are kept),
  // with these changes. changes: { name, tags, audio, image, order, starter }; a field left out
  // (undefined) stays as it was; image null removes the GIF. Empty tags are left out.
  function soundRecord(changes, existing, nowIso) {
    const value = isPlainObject(existing) ? copyJson(existing) : {};
    delete value.$type;
    if (changes.name !== undefined) {
      value.name = cleanName(changes.name);
    }
    if (changes.tags !== undefined) {
      value.tags = cleanTags(changes.tags);
    }
    if (changes.audio !== undefined) {
      value.audio = changes.audio;
    }
    if (changes.image !== undefined) {
      value.image = changes.image;
    }
    if (changes.order !== undefined) {
      value.order = changes.order;
    }
    if (changes.starter !== undefined) {
      value.starter = changes.starter;
    }
    if (Array.isArray(value.tags) && value.tags.length === 0) {
      delete value.tags;
    }
    if (value.image === null || value.image === undefined) {
      delete value.image;
    }
    if (value.starter === null || value.starter === undefined) {
      delete value.starter;
    }
    if (typeof value.createdAt !== 'string') {
      value.createdAt = nowIso;
    }
    return value;
  }

  // What the Edit sheet can save: a name; else the fields to mark
  function sheetProblems(name) {
    const problems = [];
    if (cleanName(name) === '') {
      problems.push('name');
    }
    return problems;
  }

  /* ---------- Finding a sound by what was said (tools) ---------- */

  // { entry } for one sound; { matches } when the words fit none or several. An exact name (any
  // case) wins; else the sounds whose name holds the words.
  function findByName(entries, said) {
    const wanted = cleanName(said).toLowerCase();
    if (wanted === '') {
      return { matches: [] };
    }
    const exact = [];
    const partial = [];
    for (const entry of entries) {
      const name = entry.sound.name.toLowerCase();
      if (name === wanted) {
        exact.push(entry);
      } else if (name.indexOf(wanted) !== -1 || wanted.indexOf(name) !== -1) {
        partial.push(entry);
      }
    }
    if (exact.length === 1) {
      return { entry: exact[0] };
    }
    if (exact.length > 1) {
      return { matches: exact };
    }
    if (partial.length === 1) {
      return { entry: partial[0] };
    }
    return { matches: partial };
  }

  function namesOf(entries) {
    const names = [];
    for (const entry of entries) {
      names.push(entry.sound.name);
    }
    return names;
  }

  // Tags after adding some and taking some off
  function retagged(tags, add, remove) {
    const removeSet = cleanTags(remove);
    const kept = [];
    for (const tag of cleanTags(tags)) {
      if (removeSet.indexOf(tag) === -1) {
        kept.push(tag);
      }
    }
    return cleanTags(kept.concat(cleanTags(add)));
  }

  /* ---------- Settings ---------- */

  function settingsFrom(value) {
    const source = isPlainObject(value) ? value : {};
    const seeded = [];
    for (const key of Array.isArray(source.seeded) ? source.seeded : []) {
      if (typeof key === 'string' && key !== '' && seeded.indexOf(key) === -1) {
        seeded.push(key);
      }
    }
    return { seeded: seeded, overlap: source.overlap !== false };
  }

  function settingsRecord(settings, existing, nowIso) {
    const value = isPlainObject(existing) ? copyJson(existing) : {};
    delete value.$type;
    value.seeded = settings.seeded.slice(0, SEEDED_MAX);
    value.overlap = settings.overlap;
    if (typeof value.createdAt !== 'string') {
      value.createdAt = nowIso;
    }
    return value;
  }

  /* ---------- Starter sounds (the page's starter-sounds block) ---------- */

  function isStarter(starter) {
    return isPlainObject(starter) && typeof starter.key === 'string' && starter.key !== '' && starter.key.length <= STARTER_KEY_MAX &&
      typeof starter.name === 'string' && typeof starter.audioBase64 === 'string' && starter.audioBase64 !== '';
  }

  // The starters not yet copied in: a deleted starter stays deleted, since its key stays in seeded
  function unseededStarters(starters, settings) {
    const waiting = [];
    for (const starter of Array.isArray(starters) ? starters : []) {
      if (isStarter(starter) && settings.seeded.indexOf(starter.key) === -1) {
        waiting.push(starter);
      }
    }
    return waiting;
  }

  // A starter's key is fixed, so two phones that copy it in before they sync write the same record
  function starterSoundKey(starter) {
    return SOUND_PREFIX + starter.key;
  }

  function starterSoundRecord(starter, audioRef, imageRef, order, nowIso) {
    const changes = { name: starter.name, tags: starter.tags, audio: audioRef, image: imageRef, order: order, starter: starter.key };
    return soundRecord(changes, null, nowIso);
  }

  /* ---------- Home Screen widget (docs/WIDGETS.md) ---------- */

  // colourMode: 'full' (every colour light and dark), 'background' (pairs on the background only,
  // for a build before 2026-10-27), 'plain' (no colours, the system background, any build)
  function coloured(piece, colour, colourMode) {
    if (colourMode === 'full') {
      piece.color = colour;
    }
    return piece;
  }

  function widgetHeader(colourMode) {
    return {
      spacing: 6,
      hstack: [
        coloured({ symbol: WIDGET_SYMBOL, size: 14 }, WIDGET_MARK, colourMode),
        coloured({ text: WIDGET_NAME, style: 'headline' }, WIDGET_INK, colourMode),
        { spacer: true },
        coloured({ text: '$sounds.count', style: 'headline' }, WIDGET_INK, colourMode)
      ]
    };
  }

  function widgetList(rows, colourMode) {
    const row = coloured({ text: '$item.name', style: 'caption', lines: 1 }, WIDGET_INK_SECONDARY, colourMode);
    return { list: '$sounds.items', limit: rows, empty: 'No Sounds', more: '+$more more', row: row };
  }

  function widgetSize(rows, colourMode) {
    return { spacing: 6, align: 'leading', vstack: [widgetHeader(colourMode), widgetList(rows, colourMode), { spacer: true }] };
  }

  function soundsWidget(colourMode) {
    const widget = {
      version: WIDGET_VERSION,
      name: WIDGET_NAME,
      sources: { sounds: { records: SOUND_PREFIX, limit: WIDGET_SOURCE_LIMIT } },
      small: widgetSize(WIDGET_ROWS.small, colourMode),
      medium: widgetSize(WIDGET_ROWS.medium, colourMode)
    };
    if (colourMode !== 'plain') {
      widget.background = WIDGET_BACKGROUND;
    }
    return widget;
  }

  // Each widget record the page keeps, in the order the page tries them
  function widgetRecords() {
    return [
      { key: WIDGET_KEY, value: soundsWidget('full'), fallback: soundsWidget('background'), plain: soundsWidget('plain') }
    ];
  }

  // A stored widget equals a wanted one when they match apart from the stamped $type
  function sameWidget(stored, wanted) {
    if (!isPlainObject(stored)) {
      return false;
    }
    const withoutType = copyJson(stored);
    delete withoutType.$type;
    return stableJson(withoutType) === stableJson(wanted);
  }

  return {
    SOUND_PREFIX: SOUND_PREFIX,
    SETTINGS_KEY: SETTINGS_KEY,
    NAME_MAX: NAME_MAX,
    WIDGET_KEY: WIDGET_KEY,
    copyJson: copyJson,
    isFileRef: isFileRef,
    cleanName: cleanName,
    withCapitalFirst: withCapitalFirst,
    cleanTags: cleanTags,
    parseTags: parseTags,
    tagsText: tagsText,
    soundFrom: soundFrom,
    soundsInOrder: soundsInOrder,
    matchesQuery: matchesQuery,
    filterEntries: filterEntries,
    nextOrder: nextOrder,
    newSoundKey: newSoundKey,
    soundRecord: soundRecord,
    sheetProblems: sheetProblems,
    findByName: findByName,
    namesOf: namesOf,
    retagged: retagged,
    settingsFrom: settingsFrom,
    settingsRecord: settingsRecord,
    unseededStarters: unseededStarters,
    starterSoundKey: starterSoundKey,
    starterSoundRecord: starterSoundRecord,
    widgetRecords: widgetRecords,
    sameWidget: sameWidget
  };
})();
  /* copied from index.html: end */

  const Logic = SoundsLogic;
  // What jess is told: the names, at most this many
  const CONTEXT_NAMES_MAX = 100;

  /* ======================================================================
     The tools. Each handler is (input, records, now) → { ops, result } or { refused, result }:
     input is the tool's arguments as manifest.json "agent" describes them; records are this
     Sidekick's records as [{ key, value }]; now is an ISO instant. ops are whole records to set
     or keys to delete; nothing is written by a handler. A refusal changes nothing.
     ====================================================================== */

  function done(ops, text, extra) {
    const result = { text: text };
    if (extra) {
      for (const field of Object.keys(extra)) {
        result[field] = extra[field];
      }
    }
    return { ops: ops, result: result };
  }

  function refuse(reason, text) {
    return { refused: reason, result: { text: text } };
  }

  function setOp(key, value) {
    return { op: 'set', key: key, value: value };
  }

  function deleteOp(key) {
    return { op: 'delete', key: key };
  }

  /* ---------- Reading the records ---------- */

  function recordValue(records, key) {
    for (const record of records) {
      if (record.key === key) {
        return record.value;
      }
    }
    return null;
  }

  function textList(list) {
    return Array.isArray(list) ? list : [];
  }

  function soundsText(count) {
    return count === 1 ? '1 sound' : count + ' sounds';
  }

  // The one sound the words name, or the refusal saying why not
  function soundNamed(records, said) {
    const entries = Logic.soundsInOrder(records);
    const found = Logic.findByName(entries, typeof said === 'string' ? said : '');
    if (found.entry) {
      return { entry: found.entry };
    }
    if (found.matches.length > 1) {
      const names = Logic.namesOf(found.matches);
      return { refusal: refuse('which-sound', 'Which one: ' + names.join(', ') + '?') };
    }
    return { refusal: refuse('no-such-sound', 'No sound named ' + Logic.cleanName(said)) };
  }

  /* ---------- Handlers ---------- */

  // The board, as the page shows it with the search cleared
  function listSounds(input, records, now) {
    const entries = Logic.soundsInOrder(records);
    const names = Logic.namesOf(entries);
    if (names.length === 0) {
      return done([], 'No Sounds', { names: names });
    }
    return done([], soundsText(names.length) + ': ' + names.join(', '), { names: names });
  }

  // The page's search field: every word in the name or the tags, any case
  function searchSounds(input, records, now) {
    const query = Logic.cleanName(input.query);
    if (query === '') {
      return refuse('empty-query', 'Say what to look for');
    }
    const entries = Logic.soundsInOrder(records);
    const shown = Logic.filterEntries(entries, query);
    const names = Logic.namesOf(shown);
    if (names.length === 0) {
      return done([], 'No Sounds', { names: names });
    }
    return done([], 'Found ' + names.length + ': ' + names.join(', '), { names: names });
  }

  // The Edit sheet's Name
  function renameSound(input, records, now) {
    const named = soundNamed(records, input.name);
    if (named.refusal) {
      return named.refusal;
    }
    const newName = Logic.cleanName(input.newName);
    if (newName === '') {
      return refuse('name-not-offered', 'A sound needs a name');
    }
    if (newName === named.entry.sound.name) {
      return refuse('nothing-to-change', 'Already named ' + newName);
    }
    const existing = recordValue(records, named.entry.key);
    const value = Logic.soundRecord({ name: newName }, existing, now);
    return done([setOp(named.entry.key, value)], 'Renamed to ' + newName, { key: named.entry.key });
  }

  // The Edit sheet's Tags
  function tagSound(input, records, now) {
    const named = soundNamed(records, input.name);
    if (named.refusal) {
      return named.refusal;
    }
    const sound = named.entry.sound;
    const tags = Logic.retagged(sound.tags, textList(input.add), textList(input.remove));
    const tagsLine = tags.length === 0 ? 'no tags' : tags.join(', ');
    if (JSON.stringify(tags) === JSON.stringify(sound.tags)) {
      return refuse('nothing-to-change', sound.name + ' already has ' + tagsLine);
    }
    const existing = recordValue(records, named.entry.key);
    const value = Logic.soundRecord({ tags: tags }, existing, now);
    return done([setOp(named.entry.key, value)], sound.name + ': ' + tagsLine, { tags: tags });
  }

  // The touch-and-hold Delete. A starter's key stays in seeded, so it is not copied in again.
  function deleteSound(input, records, now) {
    const named = soundNamed(records, input.name);
    if (named.refusal) {
      return named.refusal;
    }
    const ops = [deleteOp(named.entry.key)];
    const starterKey = named.entry.sound.starter;
    const existingSettings = recordValue(records, Logic.SETTINGS_KEY);
    const settings = Logic.settingsFrom(existingSettings);
    if (starterKey !== null && settings.seeded.indexOf(starterKey) === -1) {
      settings.seeded.push(starterKey);
      ops.push(setOp(Logic.SETTINGS_KEY, Logic.settingsRecord(settings, existingSettings, now)));
    }
    return done(ops, 'Deleted ' + named.entry.sound.name, { key: named.entry.key });
  }

  function overlapText(overlap) {
    return overlap ? 'Sounds play over each other' : 'One sound at a time';
  }

  // The "?" menu's One at a Time
  function setOverlap(input, records, now) {
    if (typeof input.overlap !== 'boolean') {
      return refuse('overlap-not-offered', 'Over each other, or one at a time');
    }
    const existing = recordValue(records, Logic.SETTINGS_KEY);
    const settings = Logic.settingsFrom(existing);
    if (settings.overlap === input.overlap) {
      return refuse('nothing-to-change', overlapText(settings.overlap));
    }
    settings.overlap = input.overlap;
    return done([setOp(Logic.SETTINGS_KEY, Logic.settingsRecord(settings, existing, now))], overlapText(settings.overlap));
  }

  /* ---------- What jess is told about this Sidekick's records ---------- */

  function buildContext(records, now) {
    const entries = Logic.soundsInOrder(records);
    const names = Logic.namesOf(entries);
    const settings = Logic.settingsFrom(recordValue(records, Logic.SETTINGS_KEY));
    return {
      count: names.length,
      sounds: names.slice(0, CONTEXT_NAMES_MAX),
      playing: settings.overlap ? 'over each other' : 'one at a time'
    };
  }

  return {
    context: buildContext,
    handlers: {
      list: listSounds,
      search: searchSounds,
      rename: renameSound,
      tag: tagSound,
      delete: deleteSound,
      set_overlap: setOverlap
    }
  };
})();

// The settings engine (repair lanes W5, founder 2026-11-22), after the tools so SoundsLogic stays the first copied block
/* copied from index.html: begin */
// Midas settings engine for Sidekicks (repair lanes W5, founder D1, 2026-11-13). Paste this into
// the Sidekick page's inline script, after the store helper, and into tools.js between
// "copied from index.html" markers. It is core: the Make It Yours panel may be hidden, this engine
// may not be removed (runner/core-checks/settings-engine.mjs).
//
// The Sidekick's manifest.json "settings" is its catalogue: every setting a person can change by
// saying it, with its type, allowed values, default and the page part it changes:
//
//   "settings": {
//     "entries": [
//       { "key": "drop.colour", "label": "Water drop colour", "type": "colour", "part": "drop",
//         "selector": ".drop", "css": "--drop-colour", "default": "#2F9BEA" },
//       { "key": "streak.show", "label": "Streak chip", "type": "show", "part": "streak",
//         "selector": ".streak", "default": true, "tools": [] },
//       { "key": "dates.format", "label": "Date format", "type": "dateFormat", "part": "dates",
//         "values": ["day-month", "month-day"], "default": "day-month" }
//     ],
//     "alsoSet": { "preset": "custom" }          (optional: written with every change)
//   }
//
// Types:
//   colour      "#RRGGBB"; with a selector the engine sets `css` (a property, or a --custom one)
//   size        s | m | l | xl; with a selector the engine scales the part (zoom)
//   show        true | false; with a selector false hides the part; a tool it names answers
//               "turned off" while it is off (D1: the code and the tool stay)
//   dateFormat  one of DATE_FORMATS; the page formats its dates through formatDate
//   choice      one of `values`; the page's own code reads it
// An entry with a selector is drawn by this engine alone; one without is read by the page.
//
// Every value lives in one record, settings:self, next to anything else the page keeps there.
// The page:
//
//   var settingsWatch = MidasSettings.watch({ catalogue: SETTINGS_CATALOGUE,
//     read: readSettingsRecord,                    (the page's own read of settings:self)
//     onChange: function redrawForSettings(values) { renderAll(); } });
//   MidasSettings.formatDate(SETTINGS_CATALOGUE, settingsWatch.record(), 'dates.format', date)
//     || pageOwnFormat(date);                      (null while the format is auto, the page's own)
//
// tools.js, before its export:
//
//   MidasSidekickTools = MidasSettings.attachTools(MidasSidekickTools, { sidekickId: 'hydration',
//     catalogue: SETTINGS_CATALOGUE });
//
// It is a plain script: no imports, one global, a CommonJS export at the end for Node and the
// Worker (backend/src/repair-setting.ts checks and writes the same values with it).
var MidasSettings = (function createMidasSettings() {
  'use strict';

  var RECORD_KEY = 'settings:self';
  var TYPES = ['colour', 'size', 'show', 'dateFormat', 'choice'];
  var SIZES = ['s', 'm', 'l', 'xl'];
  // How much each size scales a part; m is the page as drawn
  var SIZE_ZOOM = { s: 0.85, m: 1, l: 1.2, xl: 1.4 };
  // auto: the page's own format, as built
  var DATE_FORMATS = ['auto', 'day-month', 'month-day', 'day-month-year', 'month-day-year', 'weekday-day-month', 'weekday-month-day', 'numeric-day-first', 'numeric-month-first'];
  var COLOUR_PATTERN = /^#[0-9A-Fa-f]{6}$/;
  var KEY_PATTERN = /^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)?$/;
  var PART_PATTERN = /^[a-z][a-z0-9-]{0,40}$/;
  // A CSS property name, or a custom property (--name)
  var CSS_PATTERN = /^(--)?[a-z][a-z0-9-]{0,60}$/;
  // A selector may not leave its rule or load anything
  var SELECTOR_FORBIDDEN = /[{};@\\<>]|url\s*\(/i;
  var MAX_ENTRIES = 120;
  var STYLE_ID = 'midas-settings';
  var WATCH_INTERVAL_MS = 1000;
  var MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  var WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  var ON_WORDS = ['true', 'on', 'yes', 'show', 'shown', 'visible'];
  var OFF_WORDS = ['false', 'off', 'no', 'hide', 'hidden', 'remove'];

  function isPlainObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
  }

  function copyJson(value) {
    return JSON.parse(JSON.stringify(value));
  }

  /* ---------- The catalogue ---------- */

  function entriesOf(catalogue) {
    if (!isPlainObject(catalogue) || !Array.isArray(catalogue.entries)) {
      return [];
    }
    return catalogue.entries;
  }

  function entryFor(catalogue, key) {
    var entries = entriesOf(catalogue);
    for (var index = 0; index < entries.length; index += 1) {
      if (entries[index].key === key) {
        return entries[index];
      }
    }
    return null;
  }

  // The values an entry may take, as a list; a colour takes any #RRGGBB and gives null
  function allowedValues(entry) {
    if (entry.type === 'show') {
      return [true, false];
    }
    if (entry.type === 'size') {
      return Array.isArray(entry.values) ? entry.values : SIZES;
    }
    if (entry.type === 'dateFormat') {
      return Array.isArray(entry.values) ? entry.values : DATE_FORMATS;
    }
    if (entry.type === 'choice') {
      return Array.isArray(entry.values) ? entry.values : [];
    }
    return null;
  }

  function entryProblems(entry, index, seenKeys) {
    var where = 'settings.entries[' + index + ']';
    if (!isPlainObject(entry)) {
      return [where + ' must be an object'];
    }
    var problems = [];
    if (typeof entry.key !== 'string' || !KEY_PATTERN.test(entry.key)) {
      problems.push(where + '.key must be a name like "title.colour"');
    } else if (seenKeys.indexOf(entry.key) !== -1) {
      problems.push(where + '.key "' + entry.key + '" is listed twice');
    } else {
      seenKeys.push(entry.key);
    }
    if (typeof entry.label !== 'string' || entry.label.trim().length === 0 || entry.label.length > 80) {
      problems.push(where + '.label must be a few words');
    }
    if (TYPES.indexOf(entry.type) === -1) {
      problems.push(where + '.type must be one of ' + TYPES.join(', '));
      return problems;
    }
    if (typeof entry.part !== 'string' || !PART_PATTERN.test(entry.part)) {
      problems.push(where + '.part must name the page part it changes');
    }
    if (entry.selector !== undefined) {
      var selectorIsText = typeof entry.selector === 'string' && entry.selector.trim().length > 0 && entry.selector.length <= 300;
      if (!selectorIsText || SELECTOR_FORBIDDEN.test(entry.selector)) {
        problems.push(where + '.selector must be a plain CSS selector');
      }
      if (entry.type === 'dateFormat' || entry.type === 'choice') {
        problems.push(where + ' is read by the page; it has no selector');
      }
    }
    if (entry.type === 'colour') {
      if (entry.selector !== undefined && cssProperties(entry).length === 0) {
        problems.push(where + '.css must name the property (or properties) the colour sets');
      }
    }
    var values = allowedValues(entry);
    if (entry.values !== undefined) {
      var listFits = Array.isArray(entry.values) && entry.values.length > 0;
      if (!listFits || entry.type === 'colour' || entry.type === 'show') {
        problems.push(where + '.values must be a list, for size, dateFormat and choice only');
      } else if (entry.type === 'size' || entry.type === 'dateFormat') {
        var known = entry.type === 'size' ? SIZES : DATE_FORMATS;
        for (var valueIndex = 0; valueIndex < entry.values.length; valueIndex += 1) {
          if (known.indexOf(entry.values[valueIndex]) === -1) {
            problems.push(where + '.values has "' + entry.values[valueIndex] + '", not a ' + entry.type);
          }
        }
      }
    }
    if (entry.type === 'choice' && !Array.isArray(entry.values)) {
      problems.push(where + ' is a choice and needs values');
    }
    var defaultFits = values === null ? COLOUR_PATTERN.test(String(entry['default'])) : values.indexOf(entry['default']) !== -1;
    if (!defaultFits) {
      problems.push(where + '.default must be one of its values');
    }
    if (entry.tools !== undefined) {
      var toolsFit = Array.isArray(entry.tools) && entry.type === 'show';
      if (!toolsFit) {
        problems.push(where + '.tools is a list, for show only');
      }
    }
    return problems;
  }

  // Why a manifest's "settings" is not a catalogue; empty when it is.
  function catalogueProblems(catalogue) {
    if (!isPlainObject(catalogue)) {
      return ['settings must be an object with entries'];
    }
    if (!Array.isArray(catalogue.entries) || catalogue.entries.length === 0) {
      return ['settings.entries must list at least one setting'];
    }
    if (catalogue.entries.length > MAX_ENTRIES) {
      return ['settings.entries holds at most ' + MAX_ENTRIES];
    }
    var problems = [];
    var seenKeys = [];
    for (var index = 0; index < catalogue.entries.length; index += 1) {
      problems = problems.concat(entryProblems(catalogue.entries[index], index, seenKeys));
    }
    if (catalogue.alsoSet !== undefined && !isPlainObject(catalogue.alsoSet)) {
      problems.push('settings.alsoSet must be an object');
    }
    return problems;
  }

  // The CSS properties a colour entry sets: "color", "--accent" or a list of them; empty when
  // any of them is not a property name
  function cssProperties(entry) {
    var names = Array.isArray(entry.css) ? entry.css : [entry.css];
    if (names.length === 0 || names.length > 6) {
      return [];
    }
    for (var index = 0; index < names.length; index += 1) {
      if (typeof names[index] !== 'string' || !CSS_PATTERN.test(names[index])) {
        return [];
      }
    }
    return names;
  }

  /* ---------- Values ---------- */

  // The value an entry takes from what was said or stored, or { problem }. "On", "hide", "blue"
  // as "#0000FF" are a person's words; the backend's model gives the exact value.
  function checkValue(entry, said) {
    if (entry === null || entry === undefined) {
      return { problem: 'no such setting' };
    }
    if (entry.type === 'colour') {
      var colour = typeof said === 'string' ? said.trim() : '';
      if (!COLOUR_PATTERN.test(colour)) {
        return { problem: entry.label + ' takes a colour like #2F6FEB' };
      }
      return { value: colour.toUpperCase() };
    }
    if (entry.type === 'show') {
      if (typeof said === 'boolean') {
        return { value: said };
      }
      var word = String(said === null || said === undefined ? '' : said).trim().toLowerCase();
      if (ON_WORDS.indexOf(word) !== -1) {
        return { value: true };
      }
      if (OFF_WORDS.indexOf(word) !== -1) {
        return { value: false };
      }
      return { problem: entry.label + ' is on or off' };
    }
    var values = allowedValues(entry);
    for (var index = 0; index < values.length; index += 1) {
      if (values[index] === said) {
        return { value: said };
      }
    }
    // Choices may be booleans written as words ("on" / "off")
    var text = String(said === null || said === undefined ? '' : said).trim().toLowerCase();
    for (var choiceIndex = 0; choiceIndex < values.length; choiceIndex += 1) {
      var choice = values[choiceIndex];
      var matchesText = typeof choice === 'string' && choice.toLowerCase() === text;
      var matchesOn = choice === true && ON_WORDS.indexOf(text) !== -1;
      var matchesOff = choice === false && OFF_WORDS.indexOf(text) !== -1;
      if (matchesText || matchesOn || matchesOff) {
        return { value: choice };
      }
    }
    return { problem: entry.label + ' takes ' + values.join(', ') };
  }

  // Every setting's value: the stored one when it fits, else the default
  function valuesFrom(catalogue, record) {
    var values = {};
    var stored = isPlainObject(record) ? record : {};
    var entries = entriesOf(catalogue);
    for (var index = 0; index < entries.length; index += 1) {
      var entry = entries[index];
      var picked = Object.prototype.hasOwnProperty.call(stored, entry.key) ? checkValue(entry, stored[entry.key]) : { problem: 'unset' };
      values[entry.key] = picked.problem ? entry['default'] : picked.value;
    }
    return values;
  }

  // The settings:self value with these changes (and alsoSet) over what is stored; nothing else in
  // the record is touched. A change to null removes the key (Undo of a setting never set).
  function recordWith(catalogue, record, changes) {
    var next = isPlainObject(record) ? copyJson(record) : {};
    var changedKeys = Object.keys(changes);
    for (var index = 0; index < changedKeys.length; index += 1) {
      var key = changedKeys[index];
      if (changes[key] === null) {
        delete next[key];
      } else {
        next[key] = changes[key];
      }
    }
    var alsoSet = isPlainObject(catalogue) && isPlainObject(catalogue.alsoSet) ? catalogue.alsoSet : {};
    var alsoKeys = Object.keys(alsoSet);
    for (var alsoIndex = 0; alsoIndex < alsoKeys.length; alsoIndex += 1) {
      next[alsoKeys[alsoIndex]] = alsoSet[alsoKeys[alsoIndex]];
    }
    return next;
  }

  // The JSON Schema of an entry's field in settings:self (manifest "types", "settings:")
  function propertySchemaFor(entry) {
    if (entry.type === 'colour') {
      return { type: 'string', pattern: '^#[0-9A-Fa-f]{6}$' };
    }
    if (entry.type === 'show') {
      return { type: 'boolean' };
    }
    var values = allowedValues(entry);
    var jsonTypes = [];
    for (var index = 0; index < values.length; index += 1) {
      var jsonType = typeof values[index];
      if (jsonTypes.indexOf(jsonType) === -1) {
        jsonTypes.push(jsonType);
      }
    }
    return { type: jsonTypes.length === 1 ? jsonTypes[0] : jsonTypes, enum: values.slice() };
  }

  /* ---------- Drawing ---------- */

  function cssRuleFor(entry, value) {
    if (entry.type === 'colour') {
      var declarations = [];
      var properties = cssProperties(entry);
      for (var index = 0; index < properties.length; index += 1) {
        declarations.push(properties[index] + ': ' + value + ' !important;');
      }
      return entry.selector + ' { ' + declarations.join(' ') + ' }';
    }
    if (entry.type === 'size') {
      if (value === 'm') {
        return '';
      }
      return entry.selector + ' { zoom: ' + SIZE_ZOOM[value] + ' !important; }';
    }
    if (entry.type === 'show') {
      return value === false ? entry.selector + ' { display: none !important; }' : '';
    }
    return '';
  }

  // The style sheet for the stored settings. A setting left at its default draws nothing, so the
  // page is exactly as built until the person changes something.
  function cssFor(catalogue, record) {
    var stored = isPlainObject(record) ? record : {};
    var rules = [];
    var entries = entriesOf(catalogue);
    for (var index = 0; index < entries.length; index += 1) {
      var entry = entries[index];
      if (typeof entry.selector !== 'string' || !Object.prototype.hasOwnProperty.call(stored, entry.key)) {
        continue;
      }
      var picked = checkValue(entry, stored[entry.key]);
      if (picked.problem) {
        continue;
      }
      var rule = cssRuleFor(entry, picked.value);
      if (rule !== '') {
        rules.push(rule);
      }
    }
    return rules.join('\n');
  }

  function pad(number) {
    return number < 10 ? '0' + number : String(number);
  }

  // A date in one of DATE_FORMATS (English month and weekday names, as the pages write them);
  // null for auto, when the page writes the date its own way
  function formatDateAs(format, date) {
    if (format === 'auto') {
      return null;
    }
    var day = date.getDate();
    var month = MONTHS[date.getMonth()];
    var year = date.getFullYear();
    var weekday = WEEKDAYS[date.getDay()];
    if (format === 'month-day') {
      return month + ' ' + day;
    }
    if (format === 'day-month-year') {
      return day + ' ' + month + ' ' + year;
    }
    if (format === 'month-day-year') {
      return month + ' ' + day + ', ' + year;
    }
    if (format === 'weekday-day-month') {
      return weekday + ' ' + day + ' ' + month;
    }
    if (format === 'weekday-month-day') {
      return weekday + ', ' + month + ' ' + day;
    }
    if (format === 'numeric-day-first') {
      return pad(day) + '/' + pad(date.getMonth() + 1) + '/' + year;
    }
    if (format === 'numeric-month-first') {
      return pad(date.getMonth() + 1) + '/' + pad(day) + '/' + year;
    }
    return day + ' ' + month;
  }

  function formatDate(catalogue, record, key, date) {
    var entry = entryFor(catalogue, key);
    var values = valuesFrom(catalogue, record);
    var format = entry === null ? 'auto' : values[key];
    return formatDateAs(format, date);
  }

  /* ---------- The page: draw now, and again whenever settings:self changes ---------- */

  function styleElement() {
    var element = document.getElementById(STYLE_ID);
    if (element === null) {
      element = document.createElement('style');
      element.id = STYLE_ID;
    }
    // Last in the head, so a person's setting wins over the page's own rules
    document.head.appendChild(element);
    return element;
  }

  // options: { catalogue, read() -> Promise<record|null>, onChange(values, record), intervalMs }.
  // Reads settings:self at once, then every second while the page is shown and whenever it is
  // shown again; draws and calls onChange only when the record changed.
  function watch(options) {
    var lastText = null;
    var lastRecord = null;
    var checking = false;
    var intervalMs = options.intervalMs || WATCH_INTERVAL_MS;

    // The page control a set_setting tool names (manifest _meta "midas/page-actions")
    function drawSettings(record) {
      styleElement().textContent = cssFor(options.catalogue, record);
    }

    async function check() {
      if (checking) {
        return;
      }
      checking = true;
      try {
        var record = await options.read();
        var text = JSON.stringify(record === undefined ? null : record);
        if (text !== lastText) {
          var isFirst = lastText === null;
          lastText = text;
          lastRecord = record === undefined ? null : record;
          drawSettings(lastRecord);
          if (!isFirst && typeof options.onChange === 'function') {
            options.onChange(valuesFrom(options.catalogue, lastRecord), lastRecord);
          }
        }
      } catch (error) {
        // The page keeps its last settings when the shell is busy; the next check tries again
      } finally {
        checking = false;
      }
    }

    function checkWhenShown() {
      if (!document.hidden) {
        check();
      }
    }

    document.addEventListener('visibilitychange', checkWhenShown);
    var timer = setInterval(checkWhenShown, intervalMs);
    var ready = check();

    return {
      ready: ready,
      check: check,
      record: function currentRecord() {
        return lastRecord;
      },
      values: function currentValues() {
        return valuesFrom(options.catalogue, lastRecord);
      },
      stop: function stopWatching() {
        clearInterval(timer);
        document.removeEventListener('visibilitychange', checkWhenShown);
      }
    };
  }

  /* ---------- tools.js: set_setting, and "turned off" for hidden features ---------- */

  function settingsRecordIn(records) {
    var list = Array.isArray(records) ? records : [];
    for (var index = 0; index < list.length; index += 1) {
      if (list[index] && list[index].key === RECORD_KEY) {
        return list[index].value;
      }
    }
    return null;
  }

  // The show setting that has turned this tool off, or null
  function offSettingFor(catalogue, record, toolName) {
    var values = valuesFrom(catalogue, record);
    var entries = entriesOf(catalogue);
    for (var index = 0; index < entries.length; index += 1) {
      var entry = entries[index];
      var namesTool = entry.type === 'show' && Array.isArray(entry.tools) && entry.tools.indexOf(toolName) !== -1;
      if (namesTool && values[entry.key] === false) {
        return entry;
      }
    }
    return null;
  }

  // set_setting through the catalogue: { key, value } (or { field, value }, To-Do's words)
  function setSettingFrom(catalogue, input, records) {
    var fields = isPlainObject(input) ? input : {};
    var key = typeof fields.key === 'string' ? fields.key : fields.field;
    var entry = typeof key === 'string' ? entryFor(catalogue, key) : null;
    if (entry === null) {
      return { refused: 'nothing-to-change', result: { text: 'Say what to change' } };
    }
    var picked = checkValue(entry, fields.value);
    if (picked.problem) {
      return { refused: 'value-not-offered', result: { text: picked.problem } };
    }
    var record = settingsRecordIn(records);
    var current = valuesFrom(catalogue, record);
    var isStored = isPlainObject(record) && Object.prototype.hasOwnProperty.call(record, key);
    if (isStored && current[key] === picked.value) {
      return { refused: 'nothing-to-change', result: { text: 'Already set' } };
    }
    var changes = {};
    changes[key] = picked.value;
    var value = recordWith(catalogue, record, changes);
    return { ops: [{ op: 'set', key: RECORD_KEY, value: value }], result: { text: 'Changed', key: key, value: picked.value } };
  }

  function turnedOffHandler(verb, handler, sidekickId, catalogue) {
    var toolName = sidekickId + '.' + verb;
    return function handleUnlessTurnedOff(input, records, now) {
      var entry = offSettingFor(catalogue, settingsRecordIn(records), toolName);
      if (entry !== null) {
        return { refused: 'turned-off', result: { text: entry.label + ' is turned off' } };
      }
      return handler(input, records, now);
    };
  }

  // options: { sidekickId, catalogue, ownKeys }. Gives the tools a set_setting when they have
  // none; with their own (To-Do's Make It Yours), keys in ownKeys and presets stay theirs and the
  // rest of the catalogue goes through the engine. Every other tool a hidden feature names answers
  // "turned off".
  function attachTools(tools, options) {
    var catalogue = options.catalogue;
    var ownKeys = Array.isArray(options.ownKeys) ? options.ownKeys : [];
    var handlers = isPlainObject(tools) && isPlainObject(tools.handlers) ? tools.handlers : {};
    var ownSetSetting = typeof handlers.set_setting === 'function' ? handlers.set_setting : null;
    var wrapped = {};
    var verbs = Object.keys(handlers);
    for (var index = 0; index < verbs.length; index += 1) {
      var verb = verbs[index];
      wrapped[verb] = verb === 'set_setting' ? handlers[verb] : turnedOffHandler(verb, handlers[verb], options.sidekickId, catalogue);
    }

    function setSetting(input, records, now) {
      var fields = isPlainObject(input) ? input : {};
      var key = typeof fields.key === 'string' ? fields.key : fields.field;
      var isOwn = Boolean(fields.preset) || ownKeys.indexOf(key) !== -1;
      if (ownSetSetting !== null && isOwn) {
        return ownSetSetting(input, records, now);
      }
      return setSettingFrom(catalogue, input, records);
    }

    wrapped.set_setting = setSetting;
    var attached = {};
    var toolFields = isPlainObject(tools) ? Object.keys(tools) : [];
    for (var fieldIndex = 0; fieldIndex < toolFields.length; fieldIndex += 1) {
      attached[toolFields[fieldIndex]] = tools[toolFields[fieldIndex]];
    }
    attached.handlers = wrapped;
    return attached;
  }

  return {
    RECORD_KEY: RECORD_KEY,
    TYPES: TYPES,
    SIZES: SIZES,
    SIZE_ZOOM: SIZE_ZOOM,
    DATE_FORMATS: DATE_FORMATS,
    catalogueProblems: catalogueProblems,
    entryFor: entryFor,
    allowedValues: allowedValues,
    checkValue: checkValue,
    valuesFrom: valuesFrom,
    recordWith: recordWith,
    propertySchemaFor: propertySchemaFor,
    cssFor: cssFor,
    formatDate: formatDate,
    formatDateAs: formatDateAs,
    watch: watch,
    setSettingFrom: setSettingFrom,
    offSettingFor: offSettingFor,
    attachTools: attachTools
  };
})();

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSettings;
}
var SETTINGS_CATALOGUE = {"entries":[{"key":"page.colour","label":"Background colour","type":"colour","part":"page","selector":":root","css":"--bg","default":"#FFFFFF"},{"key":"text.colour","label":"Text colour","type":"colour","part":"text","selector":":root","css":"--fg","default":"#111111"},{"key":"greyText.colour","label":"Grey text colour (letters, No Sounds)","type":"colour","part":"grey-text","selector":":root","css":"--fg2","default":"#6B6B6B"},{"key":"accent.colour","label":"Main colour (the edge and speaker of a playing sound)","type":"colour","part":"accent","selector":":root","css":"--playing","default":"#CEFF00"},{"key":"accentText.colour","label":"Speaker icon colour while a sound plays","type":"colour","part":"accent-text","selector":":root","css":"--playing-fg","default":"#111111"},{"key":"page.size","label":"Text size (everything on the page)","type":"size","part":"page","selector":"#main","default":"m"},{"key":"page.theme","label":"Appearance (light or dark)","type":"choice","part":"page","values":["auto","light","dark"],"default":"auto"},{"key":"title.colour","label":"Sounds title colour","type":"colour","part":"title","selector":".top h1","css":"color","default":"#111111"},{"key":"title.size","label":"Sounds title size","type":"size","part":"title","selector":".top h1","default":"m"},{"key":"title.show","label":"Sounds title","type":"show","part":"title","selector":".top h1","default":true},{"key":"buttons.colour","label":"Round top buttons colour","type":"colour","part":"buttons","selector":".iconbtn","css":"background-color","default":"#F2F2F2"},{"key":"buttons.size","label":"Round top buttons size","type":"size","part":"buttons","selector":".actions","default":"m"},{"key":"help.show","label":"Help (?) button","type":"show","part":"help","selector":".iconbtn.help","default":true},{"key":"search.colour","label":"Search box colour","type":"colour","part":"search","selector":".search input","css":"background-color","default":"#F2F2F2"},{"key":"search.size","label":"Search box size","type":"size","part":"search","selector":".search","default":"m"},{"key":"search.show","label":"Search box","type":"show","part":"search","selector":".search","default":true,"tools":["soundboard.search"]},{"key":"tiles.colour","label":"Sound tiles colour","type":"colour","part":"tiles","selector":":root","css":"--tile","default":"#F4F4F4"},{"key":"tiles.size","label":"Sound tiles size","type":"size","part":"tiles","selector":".grid","default":"m"},{"key":"pictures.colour","label":"Picture background colour (behind a GIF or letter)","type":"colour","part":"pictures","selector":".gif","css":"background-color","default":"#F2F2F2"},{"key":"pictures.show","label":"Pictures (GIFs) on the tiles","type":"show","part":"pictures","selector":".gif","default":true},{"key":"letters.colour","label":"Letter on a tile with no picture colour","type":"colour","part":"letters","selector":".gif .letter","css":"color","default":"#6B6B6B"},{"key":"names.colour","label":"Sound names colour","type":"colour","part":"names","selector":".tile .name","css":"color","default":"#111111"},{"key":"names.size","label":"Sound names size","type":"size","part":"names","selector":".tile .name","default":"m"},{"key":"names.show","label":"Sound names under the tiles","type":"show","part":"names","selector":".tile .name","default":true},{"key":"speaker.size","label":"Speaker chip on the tiles size","type":"size","part":"speaker","selector":".speaker","default":"m"},{"key":"speaker.show","label":"Speaker chip on the tiles","type":"show","part":"speaker","selector":".speaker","default":true},{"key":"empty.colour","label":"No Sounds text colour","type":"colour","part":"empty","selector":".empty","css":"color","default":"#6B6B6B"},{"key":"stop.colour","label":"Stop button colour","type":"colour","part":"stop","selector":".stop","css":"background-color","default":"#111111"},{"key":"stop.textColour","label":"Stop button text colour","type":"colour","part":"stop","selector":".stop","css":"color","default":"#FFFFFF"},{"key":"stop.size","label":"Stop button size","type":"size","part":"stop","selector":".stop","default":"m"},{"key":"menus.colour","label":"Menus background colour (? and touch and hold)","type":"colour","part":"menus","selector":".menu, .help-menu","css":"background-color","default":"#FFFFFF"},{"key":"sheet.colour","label":"Edit Sound sheet background colour","type":"colour","part":"sheet","selector":".sheet","css":"background-color","default":"#FFFFFF"},{"key":"fields.colour","label":"Name and Tags boxes colour","type":"colour","part":"fields","selector":".field","css":"background-color","default":"#F2F2F2"},{"key":"delete.colour","label":"Delete colour","type":"colour","part":"delete","selector":":root","css":"--danger","default":"#FF3B30"},{"key":"toast.colour","label":"Message at the bottom colour","type":"colour","part":"toast","selector":".toast","css":"background-color","default":"#111111"},{"key":"toast.textColour","label":"Message at the bottom text colour","type":"colour","part":"toast","selector":".toast","css":"color","default":"#FFFFFF"}]};
/* copied from index.html: end */

// The settings engine's set_setting, and "turned off" for a hidden feature's tool (repair lanes W5)
MidasSidekickTools = MidasSettings.attachTools(MidasSidekickTools, { sidekickId: "soundboard", catalogue: SETTINGS_CATALOGUE });

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSidekickTools;
}
