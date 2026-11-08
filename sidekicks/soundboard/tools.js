// Sounds tools: every action a person can take in this Sidekick that works without the page, as
// functions jess (and later any outside agent) can call (jess router, founder 2026-10-21).
// manifest.json "agent" describes each tool; this file does the work. The shell runs it in
// JavaScriptCore and writes the ops it returns through RecordWriter; nothing here touches the store.
//
// Not tools (docs/briefs/soundboard-sidekick.md, section 2): playing a sound (only the page can
// make sound; jess playing one needs a shell change) and adding one (the clip and the GIF are
// picked on the page).
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

  // The Name field's first guess from a picked file: "vine_boom-2.mp3" → "Vine boom 2"
  function nameFromFileName(fileName) {
    const text = String(fileName || '');
    const dot = text.lastIndexOf('.');
    const withoutExtension = dot > 0 ? text.slice(0, dot) : text;
    const spaced = withoutExtension.replace(/[_-]+/g, ' ');
    const cleaned = cleanName(spaced);
    if (cleaned === '') {
      return '';
    }
    return withCapitalFirst(cleaned);
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

  // A key for a sound added on the page: the time and a random part, both base 36
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

  // What the Add / Edit sheet can save: a name and a sound; else the fields to mark
  function sheetProblems(name, audio) {
    const problems = [];
    if (cleanName(name) === '') {
      problems.push('name');
    }
    if (!isFileRef(audio) && audio !== 'picked') {
      problems.push('audio');
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
    nameFromFileName: nameFromFileName,
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

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSidekickTools;
}
