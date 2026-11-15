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
