// To-Do tools: every action a person can take in this Sidekick, as functions jess (and later any
// outside agent) can call (jess router, founder 2026-10-21). manifest.json "agent" describes each
// tool; this file does the work. The shell runs it in JavaScriptCore and writes the ops it returns
// through RecordWriter; nothing here touches the store.
//
// The block between "copied from index.html" markers is the page's own code, character for
// character: the deploy gate refuses this file when it no longer appears in index.html, so a
// to-do added or ticked by voice is written exactly as the page writes it. Change the page, then
// copy the block here again.
//
// A plain script: one global (MidasSidekickTools), a CommonJS export at the end for Node.
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
var SETTINGS_CATALOGUE = {"entries":[{"key":"look","label":"Look (Paper, Notebook, Soft, Wallpaper, Heat)","type":"choice","part":"page","values":["paper","notebook","soft","wallpaper","heat"],"default":"notebook"},{"key":"theme","label":"Appearance (light or dark)","type":"choice","part":"page","values":["auto","light","dark"],"default":"auto"},{"key":"accent","label":"Accent colour (buttons, ticks, Today)","type":"colour","part":"accent","default":"#2F6FEB"},{"key":"textSize","label":"Text size","type":"choice","part":"text","values":["s","m","l","xl"],"default":"m"},{"key":"density","label":"Spacing between to-dos","type":"choice","part":"rows","values":["comfy","compact"],"default":"comfy"},{"key":"font","label":"Font","type":"choice","part":"text","values":["system","serif","rounded","mono"],"default":"system"},{"key":"checkbox","label":"Checkbox shape and place","type":"choice","part":"checkbox","values":["circle","square","end","none"],"default":"end"},{"key":"showMeta","label":"Details line under each to-do","type":"choice","part":"details","values":[true,false],"default":true},{"key":"dateColors","label":"Date colours (late in red, today in green)","type":"choice","part":"details","values":[true,false],"default":true},{"key":"tickSound","label":"Tick sound","type":"choice","part":"sound","values":["ding","chimes","pop","off"],"default":"chimes"},{"key":"haptic","label":"Vibration on tick","type":"choice","part":"sound","values":[true,false],"default":true},{"key":"celebrate","label":"Celebrate (all done or every tick)","type":"choice","part":"celebrate","values":["allDone","confetti","off"],"default":"allDone"},{"key":"doneGoes","label":"Where done to-dos go","type":"choice","part":"rows","values":["stay","sink","hide","logbook"],"default":"stay"},{"key":"add","label":"How to add a to-do (button, drag, bar, new row)","type":"choice","part":"add","values":["fab","dragFab","bar","row"],"default":"row"},{"key":"parse","label":"Read dates from typed words","type":"choice","part":"add","values":[true,false],"default":true},{"key":"swipeRight","label":"Swipe right does","type":"choice","part":"gestures","values":["complete","tomorrow","delete","none"],"default":"complete"},{"key":"swipeLeft","label":"Swipe left does","type":"choice","part":"gestures","values":["delete","tomorrow","complete","none"],"default":"delete"},{"key":"home","label":"Home style (list, tiles, tabs)","type":"choice","part":"home","values":["list","tiles","tabs"],"default":"tabs"},{"key":"todayModel","label":"Unfinished to-dos (carry over, overdue, fresh start, start dates)","type":"choice","part":"today","values":["carry","stay","fresh","gated"],"default":"carry"},{"key":"dayParts","label":"Morning, afternoon and evening in Today","type":"choice","part":"today","values":[false,true],"default":false},{"key":"page.colour","label":"Background colour","type":"colour","part":"page","selector":".screen","css":["--bg","--surface"],"default":"#FCFBF7"},{"key":"text.colour","label":"Text colour","type":"colour","part":"text","selector":".screen","css":"--ink","default":"#191919"},{"key":"fadedText.colour","label":"Grey text colour (dates, counts)","type":"colour","part":"faded-text","selector":".screen","css":"--ink-2","default":"#8D8A82"},{"key":"lines.colour","label":"Divider lines colour","type":"colour","part":"lines","selector":".screen","css":"--line","default":"#E7E3D8"},{"key":"title.colour","label":"Big title colour","type":"colour","part":"title","selector":".big-title","css":"color","default":"#191919"},{"key":"title.size","label":"Big title size","type":"size","part":"title","selector":".big-title","default":"m"},{"key":"title.show","label":"Big title","type":"show","part":"title","selector":".title-wrap","default":true},{"key":"subtitle.colour","label":"Date under Today colour","type":"colour","part":"subtitle","selector":".subtitle","css":"color","default":"#8D8A82"},{"key":"subtitle.show","label":"Date under Today","type":"show","part":"subtitle","selector":".subtitle","default":true},{"key":"headings.colour","label":"Section headings colour","type":"colour","part":"headings","selector":".sec-h","css":"color","default":"#191919"},{"key":"headings.size","label":"Section headings size","type":"size","part":"headings","selector":".sec-h","default":"m"},{"key":"rows.colour","label":"To-do rows background colour","type":"colour","part":"rows","selector":".row-inner","css":"background-color","default":"#FCFBF7"},{"key":"rows.textColour","label":"To-do text colour","type":"colour","part":"rows","selector":".row-title","css":"color","default":"#191919"},{"key":"rows.size","label":"To-do text size","type":"size","part":"rows","selector":".row-title","default":"m"},{"key":"details.colour","label":"Details line colour","type":"colour","part":"details","selector":".row-meta","css":"color","default":"#8D8A82"},{"key":"details.size","label":"Details line size","type":"size","part":"details","selector":".row-meta","default":"m"},{"key":"checkbox.colour","label":"Checkbox ring colour","type":"colour","part":"checkbox","selector":".check","css":"--ring","default":"#CFCBC0"},{"key":"checkbox.size","label":"Checkbox size","type":"size","part":"checkbox","selector":".check","default":"m"},{"key":"addRow.colour","label":"New To-Do row colour","type":"colour","part":"add-row","selector":".add-row","css":"color","default":"#8D8A82"},{"key":"addButton.colour","label":"Round add (+) button colour","type":"colour","part":"add-button","selector":".fab","css":"background-color","default":"#2F6FEB"},{"key":"addButton.size","label":"Round add (+) button size","type":"size","part":"add-button","selector":".fab","default":"m"},{"key":"topButtons.size","label":"Top buttons size","type":"size","part":"top-buttons","selector":".topbar .glass","default":"m"},{"key":"makeItYours.show","label":"Make It Yours (gear) button","type":"show","part":"make-it-yours","selector":".topbar [data-action=\"panel\"]","default":true},{"key":"help.show","label":"Help (?) button","type":"show","part":"help","selector":".help-q","default":true},{"key":"search.show","label":"Search (tab, button and box)","type":"show","part":"search","selector":"[data-action=\"go-search\"], .tab[data-view=\"search\"]","default":true,"tools":["todo.search"]},{"key":"tabs.show","label":"Tab bar at the bottom","type":"show","part":"tabs","selector":".tabbar","default":true},{"key":"tabs.size","label":"Tab bar size","type":"size","part":"tabs","selector":".tabbar","default":"m"},{"key":"tabs.colour","label":"Tab labels colour","type":"colour","part":"tabs","selector":".tab","css":"color","default":"#8D8A82"},{"key":"upcomingDays.colour","label":"Upcoming day numbers colour","type":"colour","part":"upcoming-days","selector":".day-num","css":"color","default":"#191919"},{"key":"suggestions.show","label":"Add to Today suggestions","type":"show","part":"suggestions","selector":".suggest","default":true},{"key":"trash.show","label":"Trash","type":"show","part":"trash","selector":".nav-row[data-view=\"trash\"]","default":true,"tools":["todo.restore"]},{"key":"toast.colour","label":"Undo message colour","type":"colour","part":"toast","selector":".toast","css":"background-color","default":"#1C1C1E"},{"key":"dates.format","label":"Date format","type":"dateFormat","part":"dates","default":"auto"}],"alsoSet":{"preset":"custom"}};
/* copied from index.html: end */

var MidasSidekickTools = (function createTodoTools() {
  'use strict';

  /* copied from index.html: begin */
var TodoLogic = (function createTodoLogic() {
  'use strict';

  // A to-do is a reminder: record (founder, 2026-10-31), so the notification engine, the Done
  // button on a notification and the widget's Today source work on it as built.
  const TODO_PREFIX = 'reminder:';
  const LIST_PREFIX = 'list:';
  const SETTINGS_KEY = 'settings:self';
  const REQUEST_PREFIX = 'request:';
  const IMPORT_KIND = 'import.apple-reminders';
  const INBOX_ID = 'inbox';
  const DAY_MS = 86400000;
  // Trash keeps a deleted to-do 30 days (founder, 2026-10-31)
  const TRASH_DAYS = 30;
  // A second tick within 2 s never finishes the next copy of a repeat (checklist P-new-4)
  const DOUBLE_TICK_MS = 2000;
  const NOTES_LIMIT = 21000;
  const TITLE_LIMIT = 500;

  // The founder's own selections, read from the prototype on 2026-10-31: the start for everyone
  // (docs/briefs/todo-sidekick.md section 2), shown in Make It Yours as "Mine".
  const DEFAULT_SETTINGS = {
    look: 'notebook', theme: 'auto', accent: '#2F6FEB', textSize: 'm', density: 'comfy', font: 'system',
    checkbox: 'end', showMeta: true, dateColors: true, tickSound: 'chimes', haptic: true,
    celebrate: 'allDone', doneGoes: 'stay', add: 'row', parse: true, swipeRight: 'complete',
    swipeLeft: 'delete', home: 'tabs', todayModel: 'carry', dayParts: false
  };
  const DEFAULT_PRESET = 'mine';

  // Each preset sets only the fields named here, over the person's start (prototype PRESETS)
  const PRESETS = {
    mine: { name: 'Mine', values: {} },
    paper: { name: 'Paper', values: { look: 'paper', checkbox: 'square', tickSound: 'off', celebrate: 'off', doneGoes: 'logbook', add: 'dragFab', todayModel: 'stay', swipeRight: 'tomorrow', swipeLeft: 'none', dayParts: true } },
    notebook: { name: 'Notebook', values: { look: 'notebook', checkbox: 'end', tickSound: 'pop', doneGoes: 'stay', add: 'row', home: 'tabs', todayModel: 'carry' } },
    soft: { name: 'Soft', values: { look: 'soft', font: 'serif', accent: '#30A46C', checkbox: 'circle', tickSound: 'chimes', celebrate: 'confetti', dayParts: true, add: 'fab', home: 'tiles' } },
    wallpaper: { name: 'Wallpaper', values: { look: 'wallpaper', accent: '#12A594', tickSound: 'ding', doneGoes: 'sink', add: 'bar', todayModel: 'fresh' } },
    heat: { name: 'Heat', values: { look: 'heat', accent: '#E5484D', font: 'rounded', checkbox: 'none', tickSound: 'chimes', doneGoes: 'sink', add: 'row', swipeRight: 'complete', swipeLeft: 'delete', theme: 'dark' } }
  };
  const PRESET_IDS = ['mine', 'paper', 'notebook', 'soft', 'wallpaper', 'heat'];
  // "custom": the person changed one option after picking a preset
  const CUSTOM_PRESET = 'custom';

  const ACCENTS = ['#2F6FEB', '#E5484D', '#F76B15', '#FFB224', '#30A46C', '#12A594', '#E93D82', '#1C1C1E'];
  const ITEM_COLORS = ['#E5484D', '#F76B15', '#FFB224', '#30A46C', '#12A594', '#2F6FEB', '#E93D82', '#8D8A82'];
  const EMOJIS = ['🚀', '📝', '🏠', '🛒', '💪', '📞', '💼', '📚', '🎯', '✈️', '💰', '🧺', '☕', '🎉', '❤️', '🌱'];
  const WALLPAPER_NAMES = ['ocean', 'sunset', 'forest', 'sand', 'sky', 'graphite'];

  // Make It Yours, group by group: [settings field, label, choices as [value, label]]. The
  // accent row offers ACCENTS. A tool may set only these values (tools.js set_setting).
  const PANEL = [
    ['Look', [
      ['look', 'Page', [['paper', 'Paper'], ['notebook', 'Notebook'], ['soft', 'Soft'], ['wallpaper', 'Wallpaper'], ['heat', 'Heat']]],
      ['theme', 'Appearance', [['auto', 'Auto'], ['light', 'Light'], ['dark', 'Dark']]],
      ['accent', 'Colour', 'accent'],
      ['textSize', 'Text Size', [['s', 'S'], ['m', 'M'], ['l', 'L'], ['xl', 'XL']]],
      ['density', 'Spacing', [['comfy', 'Roomy'], ['compact', 'Compact']]],
      ['font', 'Font', [['system', 'System'], ['serif', 'Serif'], ['rounded', 'Rounded'], ['mono', 'Mono']]]
    ]],
    ['Rows', [
      ['checkbox', 'Checkbox', [['circle', 'Circle'], ['square', 'Square'], ['end', 'At End'], ['none', 'None']]],
      ['showMeta', 'Details Line', [[true, 'Show'], [false, 'Hide']]],
      ['dateColors', 'Date Colours', [[true, 'On'], [false, 'Off']]]
    ]],
    ['Ticking Off', [
      ['tickSound', 'Sound', [['ding', 'Ding'], ['chimes', 'Chimes'], ['pop', 'Pop'], ['off', 'Off']]],
      ['haptic', 'Vibration', [[true, 'On'], [false, 'Off']]],
      ['celebrate', 'Celebrate', [['allDone', 'All Done'], ['confetti', 'Every Tick'], ['off', 'Off']]],
      ['doneGoes', 'Done Items', [['stay', 'Stay'], ['sink', 'Sink'], ['hide', 'Hide'], ['logbook', 'Logbook']]]
    ]],
    ['Adding', [
      ['add', 'Add With', [['fab', '+ Button'], ['dragFab', 'Drag +'], ['bar', 'Bar'], ['row', 'New Row']]],
      ['parse', 'Read Dates', [[true, 'On'], [false, 'Off']]]
    ]],
    ['Gestures', [
      ['swipeRight', 'Swipe Right', [['complete', 'Done'], ['tomorrow', 'Tomorrow'], ['delete', 'Delete'], ['none', 'Off']]],
      ['swipeLeft', 'Swipe Left', [['delete', 'Delete'], ['tomorrow', 'Tomorrow'], ['complete', 'Done'], ['none', 'Off']]]
    ]],
    ['Navigation', [
      ['home', 'Home', [['list', 'List'], ['tiles', 'Tiles'], ['tabs', 'Tabs']]]
    ]],
    ['Today', [
      ['todayModel', 'Unfinished', [['carry', 'Carry Over'], ['stay', 'Overdue'], ['fresh', 'Fresh Start'], ['gated', 'Start Dates']]],
      ['dayParts', 'Parts of Day', [[false, 'Off'], [true, 'On']]]
    ]]
  ];

  const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const REPEAT_LABEL = { day: 'Daily', weekday: 'Weekdays', week: 'Weekly', month: 'Monthly' };
  const REPEAT_EVERY = ['day', 'weekday', 'week', 'month'];
  const REPEAT_FROM = ['schedule', 'done'];
  const PARTS = ['morning', 'afternoon', 'evening'];
  const PART_LABEL = { morning: 'Morning', afternoon: 'Afternoon', evening: 'Evening', none: 'Anytime' };
  const WHEN_CHOICES = ['today', 'tomorrow', 'someday', 'none'];
  const WHEN_CHOICE_LABEL = { today: 'Today', tomorrow: 'Tomorrow', someday: 'Someday', none: 'No Date' };
  const INBOX_LIST = { id: INBOX_ID, name: 'Inbox', emoji: null, color: '#2F6FEB', wallpaper: 'sky', order: 0 };

  // The fields of a to-do this page owns. Anything else on the record (written by the shell's
  // Done and Snooze, or by a later version) is kept as it is on every write.
  const OWN_TODO_FIELDS = ['title', 'notes', 'list', 'when', 'part', 'time', 'deadline', 'recur', 'subtasks', 'done',
    'completedAt', 'createdAt', 'order', 'emoji', 'color', 'inToday', 'someday', 'deletedAt', 'externalId', 'nextId'];
  const OWN_LIST_FIELDS = ['name', 'emoji', 'color', 'wallpaper', 'order', 'externalId'];

  /* ---------- Small helpers ---------- */

  function pad2(number) {
    return (number < 10 ? '0' : '') + number;
  }

  function copyJson(value) {
    if (value === null || value === undefined) {
      return null;
    }
    return JSON.parse(JSON.stringify(value));
  }

  function isPlainObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  function isText(value) {
    return typeof value === 'string' && value.length > 0;
  }

  function isHexColor(value) {
    return typeof value === 'string' && /^#[0-9A-Fa-f]{6}$/.test(value);
  }

  function isDayKey(value) {
    return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
  }

  function isWallTime(value) {
    return typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
  }

  function escapeHtml(text) {
    return String(text === null || text === undefined ? '' : text).replace(/[&<>"']/g, escapeHtmlChar);
  }

  function escapeHtmlChar(character) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
  }

  function valuesOf(object) {
    const values = [];
    for (const name of Object.keys(object)) {
      values.push(object[name]);
    }
    return values;
  }

  /* ---------- Dates: day keys YYYY-MM-DD in the phone's own time ---------- */

  function dayKeyOf(date) {
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
  }

  function localDateKey(ms) {
    return dayKeyOf(new Date(ms));
  }

  function parseDay(key) {
    const parts = key.split('-');
    return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  }

  function addDays(key, count) {
    const date = parseDay(key);
    date.setDate(date.getDate() + count);
    return dayKeyOf(date);
  }

  function daysBetween(fromKey, toKey) {
    return Math.round((parseDay(toKey) - parseDay(fromKey)) / DAY_MS);
  }

  function shortDate(key) {
    const date = parseDay(key);
    return MONTHS[date.getMonth()] + ' ' + date.getDate();
  }

  function longDay(key) {
    const date = parseDay(key);
    return WEEKDAYS[date.getDay()] + ', ' + MONTHS[date.getMonth()] + ' ' + date.getDate();
  }

  // "Today", "Tomorrow", "Yesterday", a weekday within the week, else "Nov 12"
  function friendlyDay(key, today) {
    const difference = daysBetween(today, key);
    if (difference === 0) {
      return 'Today';
    }
    if (difference === 1) {
      return 'Tomorrow';
    }
    if (difference === -1) {
      return 'Yesterday';
    }
    if (difference > 1 && difference < 7) {
      return WEEKDAYS[parseDay(key).getDay()].slice(0, 3);
    }
    return shortDate(key);
  }

  function friendlyTime(hhmm) {
    const parts = hhmm.split(':');
    const hour = Number(parts[0]);
    const suffix = hour >= 12 ? 'PM' : 'AM';
    const hour12 = hour % 12 === 0 ? 12 : hour % 12;
    return hour12 + ':' + parts[1] + ' ' + suffix;
  }

  // The moment a day and a wall time stand for on this phone, as the engine's `at`
  function instantOf(dayKey, hhmm) {
    const day = parseDay(dayKey);
    const timeParts = hhmm.split(':');
    day.setHours(Number(timeParts[0]), Number(timeParts[1]), 0, 0);
    return day.toISOString();
  }

  /* ---------- Repeats (TD-ITEM-04): from the schedule, or from the tick day ---------- */

  function stepRepeat(key, every) {
    if (every === 'day') {
      return addDays(key, 1);
    }
    if (every === 'week') {
      return addDays(key, 7);
    }
    if (every === 'weekday') {
      let next = addDays(key, 1);
      const weekday = parseDay(next).getDay();
      if (weekday === 6) {
        next = addDays(next, 2);
      }
      if (weekday === 0) {
        next = addDays(next, 1);
      }
      return next;
    }
    const date = parseDay(key);
    date.setMonth(date.getMonth() + 1);
    return dayKeyOf(date);
  }

  function nextRepeatDay(todo, today) {
    const rule = todo.recur;
    const base = rule.from === 'done' ? today : (todo.when || today);
    let next = stepRepeat(base, rule.every);
    // A fixed schedule that fell behind jumps to the first day after today
    while (rule.from !== 'done' && next <= today) {
      next = stepRepeat(next, rule.every);
    }
    return next;
  }

  function isRecur(value) {
    return isPlainObject(value) && REPEAT_EVERY.indexOf(value.every) !== -1 && REPEAT_FROM.indexOf(value.from) !== -1;
  }

  /* ---------- Settings (records.md section 3) ---------- */

  function panelOption(field) {
    for (const group of PANEL) {
      for (const option of group[1]) {
        if (option[0] === field) {
          return option;
        }
      }
    }
    return null;
  }

  function settingFields() {
    return Object.keys(DEFAULT_SETTINGS);
  }

  // The values Make It Yours offers for a field
  function settingChoices(field) {
    const option = panelOption(field);
    if (option === null) {
      return [];
    }
    if (option[2] === 'accent') {
      return ACCENTS.slice();
    }
    const choices = [];
    for (const choice of option[2]) {
      choices.push(choice[0]);
    }
    return choices;
  }

  function isSettingValue(field, value) {
    return settingChoices(field).indexOf(value) !== -1;
  }

  // The stored settings over the start; a value the page does not offer falls back to the start
  function settingsFrom(value) {
    const settings = copyJson(DEFAULT_SETTINGS);
    let preset = DEFAULT_PRESET;
    if (!isPlainObject(value)) {
      return { settings: settings, preset: preset };
    }
    for (const field of settingFields()) {
      const stored = value[field];
      // The accent stays when it is any colour: Make It Yours only offers the eight
      if (field === 'accent' ? isHexColor(stored) : isSettingValue(field, stored)) {
        settings[field] = stored;
      }
    }
    if (PRESET_IDS.indexOf(value.preset) !== -1 || value.preset === CUSTOM_PRESET) {
      preset = value.preset;
    }
    return { settings: settings, preset: preset };
  }

  // The settings:self value: Make It Yours's fields and the preset over what is stored, so every
  // other field there (the settings engine's keys, repair lanes W5) is kept on every write
  function settingsRecordValue(settings, preset, stored) {
    const value = isPlainObject(stored) ? copyJson(stored) : {};
    const fields = copyJson(settings);
    for (const field of Object.keys(fields)) {
      value[field] = fields[field];
    }
    value.preset = preset;
    return value;
  }

  function presetSettings(presetId) {
    const settings = copyJson(DEFAULT_SETTINGS);
    const values = PRESETS[presetId].values;
    for (const field of Object.keys(values)) {
      settings[field] = values[field];
    }
    return settings;
  }

  /* ---------- Records: reminder:<id> (a to-do), list:<id> ---------- */

  function newId(nowMs) {
    return nowMs.toString(36) + Math.random().toString(36).slice(2, 7);
  }

  function todoKey(id) {
    return TODO_PREFIX + id;
  }

  function listKey(id) {
    return LIST_PREFIX + id;
  }

  function blankTodo(fields, nowMs, id) {
    const todo = {
      id: id, title: '', notes: '', list: INBOX_ID, when: null, part: null, time: null, deadline: null,
      recur: null, subtasks: [], done: false, completedAt: null, createdAt: new Date(nowMs).toISOString(),
      order: nowMs, emoji: null, color: null, inToday: null, someday: false, deletedAt: null,
      externalId: null, nextId: null, stored: null
    };
    for (const field of Object.keys(fields)) {
      todo[field] = fields[field];
    }
    return todo;
  }

  function textOr(value, fallback) {
    return typeof value === 'string' ? value : fallback;
  }

  function dayOrNull(value) {
    return isDayKey(value) ? value : null;
  }

  function subtasksFrom(value) {
    const subtasks = [];
    if (!Array.isArray(value)) {
      return subtasks;
    }
    for (const subtask of value) {
      if (isPlainObject(subtask) && isText(subtask.id) && isText(subtask.title)) {
        subtasks.push({ id: subtask.id, title: subtask.title, done: subtask.done === true });
      }
    }
    return subtasks;
  }

  // A stored record as the page's to-do; the record itself is kept in `stored`
  function todoFromRecord(key, value) {
    const record = isPlainObject(value) ? value : {};
    const id = key.slice(TODO_PREFIX.length);
    return {
      id: id,
      title: textOr(record.title, ''),
      notes: textOr(record.notes, ''),
      list: isText(record.list) ? record.list : INBOX_ID,
      when: dayOrNull(record.when),
      part: PARTS.indexOf(record.part) !== -1 ? record.part : null,
      time: isWallTime(record.time) ? record.time : null,
      deadline: dayOrNull(record.deadline),
      recur: isRecur(record.recur) ? { every: record.recur.every, from: record.recur.from } : null,
      subtasks: subtasksFrom(record.subtasks),
      done: record.done === true,
      completedAt: isText(record.completedAt) ? record.completedAt : null,
      createdAt: isText(record.createdAt) ? record.createdAt : null,
      order: typeof record.order === 'number' ? record.order : 0,
      emoji: isText(record.emoji) ? record.emoji : null,
      color: isHexColor(record.color) ? record.color : null,
      inToday: dayOrNull(record.inToday),
      someday: record.someday === true,
      deletedAt: isText(record.deletedAt) ? record.deletedAt : null,
      externalId: isText(record.externalId) ? record.externalId : null,
      nextId: isText(record.nextId) ? record.nextId : null,
      stored: copyJson(record)
    };
  }

  // The engine's `at`: a timed to-do on a day notifies at that moment (TD-OUT-01). An untimed,
  // undated or deleted to-do carries no `at`, so it never notifies.
  function engineAt(todo) {
    if (todo.deletedAt || !todo.when || !todo.time) {
      return null;
    }
    return instantOf(todo.when, todo.time);
  }

  // The record the page writes for a to-do: what the shell wrote stays, the page's own fields
  // are written fresh, and a field with no value is left out (never null).
  function todoRecordValue(todo, timeZone) {
    const value = isPlainObject(todo.stored) ? copyJson(todo.stored) : {};
    const previousAt = value.at;
    for (const field of OWN_TODO_FIELDS) {
      delete value[field];
    }
    delete value.at;
    delete value.timeZone;
    value.title = String(todo.title).slice(0, TITLE_LIMIT);
    if (todo.notes) {
      value.notes = String(todo.notes).slice(0, NOTES_LIMIT);
    }
    value.list = todo.list || INBOX_ID;
    const optionalFields = ['when', 'part', 'time', 'deadline', 'completedAt', 'createdAt', 'emoji', 'color', 'inToday', 'deletedAt', 'externalId', 'nextId'];
    for (const field of optionalFields) {
      if (todo[field] !== null && todo[field] !== undefined && todo[field] !== '') {
        value[field] = todo[field];
      }
    }
    if (todo.recur) {
      value.recur = { every: todo.recur.every, from: todo.recur.from };
    }
    value.subtasks = copyJson(todo.subtasks || []);
    value.done = todo.done === true;
    value.order = todo.order;
    value.someday = todo.someday === true;
    const at = engineAt(todo);
    if (at !== null) {
      value.at = at;
      value.timeZone = timeZone;
    }
    // A to-do moved to another time is no longer snoozed
    if (previousAt !== value.at) {
      delete value.snoozedUntil;
      delete value.snoozes;
    }
    return value;
  }

  function listFromRecord(key, value) {
    const record = isPlainObject(value) ? value : {};
    return {
      id: key.slice(LIST_PREFIX.length),
      name: textOr(record.name, ''),
      emoji: isText(record.emoji) ? record.emoji : null,
      color: isHexColor(record.color) ? record.color : INBOX_LIST.color,
      wallpaper: isText(record.wallpaper) ? record.wallpaper : 'ocean',
      order: typeof record.order === 'number' ? record.order : 0,
      externalId: isText(record.externalId) ? record.externalId : null,
      stored: copyJson(record)
    };
  }

  function listRecordValue(list) {
    const value = isPlainObject(list.stored) ? copyJson(list.stored) : {};
    for (const field of OWN_LIST_FIELDS) {
      delete value[field];
    }
    value.name = list.name;
    if (list.emoji) {
      value.emoji = list.emoji;
    }
    if (list.color) {
      value.color = list.color;
    }
    if (list.wallpaper) {
      value.wallpaper = list.wallpaper;
    }
    value.order = list.order;
    if (list.externalId) {
      value.externalId = list.externalId;
    }
    return value;
  }

  function inboxList() {
    const inbox = copyJson(INBOX_LIST);
    inbox.externalId = null;
    inbox.stored = null;
    return inbox;
  }

  // Everything the page and the tools work from: { todos: { id: todo }, lists: { id: list },
  // settings, preset }. The Inbox needs no record (records.md section 1).
  function modelFromRecords(records) {
    const model = { todos: {}, lists: {}, settings: copyJson(DEFAULT_SETTINGS), preset: DEFAULT_PRESET };
    for (const record of records) {
      if (record.key.indexOf(TODO_PREFIX) === 0) {
        const todo = todoFromRecord(record.key, record.value);
        model.todos[todo.id] = todo;
      } else if (record.key.indexOf(LIST_PREFIX) === 0) {
        const list = listFromRecord(record.key, record.value);
        model.lists[list.id] = list;
      } else if (record.key === SETTINGS_KEY) {
        const read = settingsFrom(record.value);
        model.settings = read.settings;
        model.preset = read.preset;
      }
    }
    if (!model.lists[INBOX_ID]) {
      model.lists[INBOX_ID] = inboxList();
    }
    return model;
  }

  /* ---------- Queries: what each view shows ---------- */

  function byOrder(first, second) {
    return first.order - second.order;
  }

  function byCompletedDesc(first, second) {
    return (second.completedAt || '').localeCompare(first.completedAt || '');
  }

  function byDeletedDesc(first, second) {
    return (second.deletedAt || '').localeCompare(first.deletedAt || '');
  }

  // Every to-do not in the Trash
  function liveTodos(model) {
    const live = [];
    for (const todo of valuesOf(model.todos)) {
      if (!todo.deletedAt) {
        live.push(todo);
      }
    }
    return live;
  }

  function trashItems(model) {
    const trashed = [];
    for (const todo of valuesOf(model.todos)) {
      if (todo.deletedAt) {
        trashed.push(todo);
      }
    }
    trashed.sort(byDeletedDesc);
    return trashed;
  }

  function doneOn(todo, today) {
    return todo.done && todo.completedAt !== null && localDateKey(Date.parse(todo.completedAt)) === today;
  }

  // A done item shows in a list only on the day it was ticked; with Logbook it leaves at once,
  // after the moment it was ticked (justTicked)
  function visibleDone(model, todo, today, justTicked) {
    if (!doneOn(todo, today)) {
      return false;
    }
    if (model.settings.doneGoes === 'logbook') {
      return justTicked === todo.id;
    }
    return true;
  }

  function isInToday(model, todo, today) {
    if (todo.someday || todo.deletedAt) {
      return false;
    }
    if (model.settings.todayModel === 'fresh') {
      return todo.inToday === today;
    }
    return Boolean(todo.when) && todo.when <= today;
  }

  function todayItems(model, today, justTicked) {
    const picked = [];
    for (const todo of liveTodos(model)) {
      if (!isInToday(model, todo, today)) {
        continue;
      }
      if (todo.done && !visibleDone(model, todo, today, justTicked)) {
        continue;
      }
      picked.push(todo);
    }
    picked.sort(byOrder);
    return picked;
  }

  function openCount(items) {
    let count = 0;
    for (const item of items) {
      if (!item.done) {
        count += 1;
      }
    }
    return count;
  }

  function openTodayCount(model, today) {
    return openCount(todayItems(model, today, null));
  }

  function overdueCount(model, today) {
    let count = 0;
    for (const todo of liveTodos(model)) {
      if (!todo.done && !todo.someday && todo.when && todo.when < today) {
        count += 1;
      }
    }
    return count;
  }

  // Fresh start: what can be added back to Today (unfinished from before, or planned for today)
  function freshSuggestions(model, today) {
    const suggestions = [];
    for (const todo of liveTodos(model)) {
      if (todo.done || todo.someday || todo.inToday === today) {
        continue;
      }
      const leftover = Boolean(todo.inToday) && todo.inToday < today;
      const planned = Boolean(todo.when) && todo.when <= today;
      if (leftover || planned) {
        suggestions.push(todo);
      }
    }
    suggestions.sort(byOrder);
    return suggestions;
  }

  function listItems(model, listId, today, justTicked) {
    const items = [];
    for (const todo of liveTodos(model)) {
      if (todo.list !== listId) {
        continue;
      }
      if (todo.done && !visibleDone(model, todo, today, justTicked)) {
        continue;
      }
      // Start dates: hidden until their day (TD-DAY-01 "gated")
      if (model.settings.todayModel === 'gated' && todo.when && todo.when > today && !todo.done) {
        continue;
      }
      items.push(todo);
    }
    items.sort(byOrder);
    return items;
  }

  function laterCount(model, listId, today) {
    let count = 0;
    for (const todo of liveTodos(model)) {
      if (todo.list === listId && !todo.done && todo.when && todo.when > today) {
        count += 1;
      }
    }
    return count;
  }

  function openCountInList(model, listId) {
    let count = 0;
    for (const todo of liveTodos(model)) {
      if (todo.list === listId && !todo.done) {
        count += 1;
      }
    }
    return count;
  }

  function upcomingDay(model, key, today, justTicked) {
    const items = [];
    for (const todo of liveTodos(model)) {
      if (todo.when === key && !todo.someday && (!todo.done || visibleDone(model, todo, today, justTicked))) {
        items.push(todo);
      }
    }
    items.sort(byOrder);
    return items;
  }

  function somedayItems(model, today, justTicked) {
    const items = [];
    for (const todo of liveTodos(model)) {
      if (todo.someday && (!todo.done || visibleDone(model, todo, today, justTicked))) {
        items.push(todo);
      }
    }
    items.sort(byOrder);
    return items;
  }

  function logbookItems(model) {
    const items = [];
    for (const todo of liveTodos(model)) {
      if (todo.done) {
        items.push(todo);
      }
    }
    items.sort(byCompletedDesc);
    return items;
  }

  // Search everywhere, done included (TD-NAV-04); the Trash is not searched
  function searchItems(model, query) {
    const words = query.trim().toLowerCase();
    const open = [];
    const done = [];
    if (!words) {
      return { open: open, done: done };
    }
    for (const todo of liveTodos(model)) {
      const haystack = (todo.title + ' ' + (todo.notes || '')).toLowerCase();
      if (haystack.indexOf(words) === -1) {
        continue;
      }
      if (todo.done) {
        done.push(todo);
      } else {
        open.push(todo);
      }
    }
    open.sort(byOrder);
    done.sort(byCompletedDesc);
    return { open: open, done: done };
  }

  function sortedLists(model) {
    const lists = valuesOf(model.lists);
    lists.sort(byOrder);
    return lists;
  }

  function countUpcoming(model, today) {
    let count = 0;
    for (const todo of liveTodos(model)) {
      if (!todo.done && todo.when && todo.when > today) {
        count += 1;
      }
    }
    return count;
  }

  function countOpen(model) {
    return openCount(liveTodos(model));
  }

  // Where done items go in a section (TD-DONE-05): stay in place, sink to the end, or hide
  // behind "Show Done"
  function arrangeDone(items, mode) {
    const open = [];
    const done = [];
    for (const item of items) {
      if (item.done) {
        done.push(item);
      } else {
        open.push(item);
      }
    }
    if (mode === 'sink') {
      return { main: open.concat(done), done: [] };
    }
    if (mode === 'hide') {
      return { main: open, done: done };
    }
    return { main: items, done: [] };
  }

  // Today's sections: Overdue first in the Overdue model, then parts of day when they are on
  function todaySections(model, items, today) {
    const sections = [];
    const overdue = [];
    const current = [];
    for (const item of items) {
      if (model.settings.todayModel === 'stay' && !item.done && item.when < today) {
        overdue.push(item);
      } else {
        current.push(item);
      }
    }
    if (overdue.length) {
      sections.push({ kind: 'overdue', part: null, items: overdue });
    }
    if (!model.settings.dayParts) {
      sections.push({ kind: 'today', part: null, items: current });
      return sections;
    }
    const groups = { none: [], morning: [], afternoon: [], evening: [] };
    for (const item of current) {
      groups[item.part || 'none'].push(item);
    }
    for (const part of ['none', 'morning', 'afternoon', 'evening']) {
      if (!groups[part].length && part === 'none') {
        continue;
      }
      sections.push({ kind: 'part', part: part, items: groups[part] });
    }
    return sections;
  }

  /* ---------- Natural language (TD-ADD-05) ----------
     today, tomorrow, weekdays, next week, in 3 days, at 5pm, morning/afternoon/evening/tonight,
     every day/weekday/week/month/<weekday>, daily/weekly/monthly, by <day>, #list, someday */

  const DAY_WORDS = { sun: 0, sunday: 0, mon: 1, monday: 1, tue: 2, tues: 2, tuesday: 2, wed: 3, wednesday: 3, thu: 4, thur: 4, thurs: 4, thursday: 4, fri: 5, friday: 5, sat: 6, saturday: 6 };

  function nextWeekday(weekday, today) {
    const difference = (weekday - parseDay(today).getDay() + 7) % 7;
    return addDays(today, difference === 0 ? 7 : difference);
  }

  function dayFromWord(word, today) {
    const lower = word.toLowerCase();
    if (lower === 'today') {
      return today;
    }
    if (lower === 'tomorrow' || lower === 'tmrw' || lower === 'tmr') {
      return addDays(today, 1);
    }
    if (Object.prototype.hasOwnProperty.call(DAY_WORDS, lower)) {
      return nextWeekday(DAY_WORDS[lower], today);
    }
    return null;
  }

  function applyEvery(match, result, context) {
    const word = match[1].toLowerCase();
    if (word === 'day' || word === 'weekday' || word === 'week' || word === 'month') {
      result.recur = { every: word, from: 'schedule' };
    } else {
      result.recur = { every: 'week', from: 'schedule' };
      result.firstDay = dayFromWord(word, context.today);
    }
    return true;
  }

  function applyEveryWord(match, result) {
    const everyByWord = { daily: 'day', weekly: 'week', monthly: 'month' };
    result.recur = { every: everyByWord[match[1].toLowerCase()], from: 'schedule' };
    return true;
  }

  function applyDeadline(match, result, context) {
    result.deadline = dayFromWord(match[1], context.today);
    return Boolean(result.deadline);
  }

  function applyNextWeek(match, result, context) {
    if (result.when) {
      return false;
    }
    result.when = nextWeekday(1, context.today);
    return true;
  }

  function applyInDays(match, result, context) {
    if (result.when) {
      return false;
    }
    result.when = addDays(context.today, Number(match[1]));
    return true;
  }

  function applyDayWord(match, result, context) {
    if (result.when) {
      return false;
    }
    const word = match[1].toLowerCase();
    if (word === 'tonight') {
      result.when = context.today;
      result.part = 'evening';
      return true;
    }
    result.when = dayFromWord(word, context.today);
    return Boolean(result.when);
  }

  function applyTime12(match, result) {
    let hour = Number(match[1]) % 12;
    if (match[3].toLowerCase() === 'pm') {
      hour += 12;
    }
    if (hour > 23 || (match[2] && Number(match[2]) > 59)) {
      return false;
    }
    result.time = pad2(hour) + ':' + (match[2] || '00');
    return true;
  }

  function applyTime24(match, result) {
    if (result.time || Number(match[1]) > 23 || Number(match[2]) > 59) {
      return false;
    }
    result.time = pad2(Number(match[1])) + ':' + match[2];
    return true;
  }

  function applyPart(match, result) {
    if (result.part) {
      return false;
    }
    result.part = match[1].toLowerCase();
    return true;
  }

  function applySomeday(match, result) {
    result.someday = true;
    return true;
  }

  function applyListTag(match, result, context) {
    const tag = match[2].toLowerCase();
    for (const list of context.lists) {
      const name = list.name.toLowerCase().replace(/\s+/g, '');
      if (name.indexOf(tag) === 0) {
        result.list = list.id;
        return true;
      }
    }
    return false;
  }

  const ENTRY_RULES = [
    { pattern: /\bevery\s+(day|weekday|week|month|sun(?:day)?|mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?|fri(?:day)?|sat(?:urday)?)\b/i, apply: applyEvery },
    { pattern: /\b(daily|weekly|monthly)\b/i, apply: applyEveryWord },
    { pattern: /\b(?:by|due)\s+(today|tomorrow|tmrw|sun(?:day)?|mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?|fri(?:day)?|sat(?:urday)?)\b/i, apply: applyDeadline },
    { pattern: /\bnext week\b/i, apply: applyNextWeek },
    { pattern: /\bin\s+(\d{1,2})\s+days?\b/i, apply: applyInDays },
    { pattern: /\b(today|tomorrow|tmrw|tonight|sun(?:day)?|mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?|fri(?:day)?|sat(?:urday)?)\b/i, apply: applyDayWord },
    { pattern: /\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b/i, apply: applyTime12 },
    { pattern: /\bat\s+(\d{1,2}):(\d{2})\b/i, apply: applyTime24 },
    { pattern: /\b(morning|afternoon|evening)\b/i, apply: applyPart },
    { pattern: /\bsomeday\b/i, apply: applySomeday },
    { pattern: /(^|\s)#(\w+)/, apply: applyListTag }
  ];

  function stripSpans(text, spans) {
    const characters = text.split('');
    for (const span of spans) {
      for (let index = span.start; index < span.end; index += 1) {
        characters[index] = '';
      }
    }
    return characters.join('').replace(/\s{2,}/g, ' ').trim();
  }

  // What a typed line means: the title without the understood words, and the fields they set.
  // With "Read Dates" off the text stays as typed.
  function parseEntry(text, model, today) {
    const result = { title: text, when: null, time: null, part: null, recur: null, deadline: null, list: null, someday: false, spans: [], firstDay: null };
    if (!model.settings.parse) {
      return result;
    }
    const context = { today: today, lists: sortedLists(model) };
    for (const rule of ENTRY_RULES) {
      const match = rule.pattern.exec(text);
      if (match && rule.apply(match, result, context)) {
        result.spans.push({ start: match.index, end: match.index + match[0].length });
      }
    }
    result.title = stripSpans(text, result.spans);
    if (result.time && !result.when && !result.recur) {
      result.when = today;
    }
    if (result.recur && !result.when) {
      result.when = result.firstDay || today;
    }
    delete result.firstDay;
    return result;
  }

  function compareSpanStart(first, second) {
    return first.start - second.start;
  }

  // The typed text with the understood parts highlighted; every part of it escaped
  function previewHtml(text, parsed) {
    if (!text.trim() || parsed.spans.length === 0) {
      return '';
    }
    const spans = parsed.spans.slice();
    spans.sort(compareSpanStart);
    let html = '';
    let cursor = 0;
    for (const span of spans) {
      html += escapeHtml(text.slice(cursor, span.start)) + '<span class="hl">' + escapeHtml(text.slice(span.start, span.end)) + '</span>';
      cursor = span.end;
    }
    html += escapeHtml(text.slice(cursor));
    return html;
  }

  function parsedChipLabels(parsed, model, today) {
    const labels = [];
    if (parsed.someday) {
      labels.push('Someday');
    }
    if (parsed.when) {
      labels.push(friendlyDay(parsed.when, today));
    }
    if (parsed.part) {
      labels.push(PART_LABEL[parsed.part]);
    }
    if (parsed.time) {
      labels.push(friendlyTime(parsed.time));
    }
    if (parsed.recur) {
      labels.push('↻ ' + REPEAT_LABEL[parsed.recur.every]);
    }
    if (parsed.deadline) {
      labels.push('⚑ ' + friendlyDay(parsed.deadline, today));
    }
    if (parsed.list && model.lists[parsed.list]) {
      labels.push(model.lists[parsed.list].name);
    }
    return labels;
  }

  /* ---------- Changes: each returns new to-dos, never changes the ones given ---------- */

  function isDoubleTick(todo, lastTickMs, nowMs) {
    return Boolean(todo.recur) && typeof lastTickMs === 'number' && nowMs - lastTickMs < DOUBLE_TICK_MS;
  }

  function resetSubtasks(subtasks, nowMs) {
    const fresh = [];
    for (const subtask of subtasks || []) {
      fresh.push({ id: newId(nowMs), title: subtask.title, done: false });
    }
    return fresh;
  }

  // Ticking a to-do: done now; a repeat also gets its next copy, once (the ticked one keeps the
  // next one's id in nextId, so ticking it again, from any writer, never makes a second copy).
  // Returns { todos: [changed and new to-dos], created: [ids of new ones] }.
  function completeTodo(model, id, nowMs, today) {
    const ticked = copyJson(model.todos[id]);
    ticked.done = true;
    ticked.completedAt = new Date(nowMs).toISOString();
    const changes = { todos: [ticked], created: [] };
    if (!ticked.recur) {
      return changes;
    }
    const existingNext = ticked.nextId ? model.todos[ticked.nextId] : null;
    if (existingNext && !existingNext.deletedAt) {
      return changes;
    }
    const nextFields = {
      title: ticked.title, notes: ticked.notes, list: ticked.list, part: ticked.part, time: ticked.time,
      recur: copyJson(ticked.recur), emoji: ticked.emoji, color: ticked.color, order: ticked.order + 0.001,
      when: nextRepeatDay(ticked, today), subtasks: resetSubtasks(ticked.subtasks, nowMs)
    };
    const next = blankTodo(nextFields, nowMs, newId(nowMs));
    ticked.nextId = next.id;
    changes.todos.push(next);
    changes.created.push(next.id);
    return changes;
  }

  function uncompleteTodo(todo) {
    const changed = copyJson(todo);
    changed.done = false;
    changed.completedAt = null;
    return changed;
  }

  // Repeats ticked outside the page (a notification's Done writes done and completedAt) get
  // their next copy when the page or a tool next sees them
  function missingNextCopies(model, nowMs, today) {
    const changes = { todos: [], created: [] };
    for (const todo of liveTodos(model)) {
      if (!todo.done || !todo.recur || todo.nextId) {
        continue;
      }
      // After done: counted from the day it was ticked; on schedule: the first day after today
      const tickDay = todo.completedAt ? localDateKey(Date.parse(todo.completedAt)) : today;
      const baseDay = todo.recur.from === 'done' && tickDay < today ? tickDay : today;
      const step = completeTodo(model, todo.id, nowMs, baseDay);
      // Done keeps the moment it was ticked, from wherever it was ticked
      step.todos[0].completedAt = todo.completedAt;
      for (const changed of step.todos) {
        changes.todos.push(changed);
      }
      for (const createdId of step.created) {
        changes.created.push(createdId);
      }
    }
    return changes;
  }

  // The day choices of the menu and the card: Today, Tomorrow, Someday, No Date
  function withWhenChoice(todo, choice, settings, today) {
    const changed = copyJson(todo);
    changed.someday = false;
    if (choice === 'today') {
      changed.when = today;
      if (settings.todayModel === 'fresh') {
        changed.inToday = today;
      }
    }
    if (choice === 'tomorrow') {
      changed.when = addDays(today, 1);
      changed.inToday = null;
    }
    if (choice === 'someday') {
      changed.when = null;
      changed.someday = true;
      changed.inToday = null;
    }
    if (choice === 'none') {
      changed.when = null;
      changed.inToday = null;
    }
    return changed;
  }

  // Swipe to Tomorrow (TD-GEST-01)
  function movedToTomorrow(todo, settings, today) {
    const changed = copyJson(todo);
    changed.when = addDays(today, 1);
    changed.someday = false;
    if (settings.todayModel === 'fresh') {
      changed.inToday = null;
    }
    return changed;
  }

  // A day from the date field (or a day said to jess); a time comes with it when given
  function withWhenDay(todo, dayKey, time, settings, today) {
    const changed = copyJson(todo);
    changed.when = dayKey;
    changed.someday = false;
    if (time !== undefined) {
      changed.time = time;
    }
    if (settings.todayModel === 'fresh') {
      changed.inToday = dayKey === today ? today : null;
    }
    return changed;
  }

  function addedToToday(todo, today) {
    const changed = copyJson(todo);
    changed.inToday = today;
    if (!changed.when || changed.when < today) {
      changed.when = today;
    }
    return changed;
  }

  function trashedTodo(todo, nowMs) {
    const changed = copyJson(todo);
    changed.deletedAt = new Date(nowMs).toISOString();
    return changed;
  }

  function restoredTodo(todo) {
    const changed = copyJson(todo);
    changed.deletedAt = null;
    return changed;
  }

  // To-dos in the Trash longer than 30 days: removed when the page opens
  function expiredTrashIds(model, nowMs) {
    const expired = [];
    for (const todo of trashItems(model)) {
      if (nowMs - Date.parse(todo.deletedAt) > TRASH_DAYS * DAY_MS) {
        expired.push(todo.id);
      }
    }
    return expired;
  }

  // Order between two neighbours, so an insert writes one record (records.md section 1)
  function orderBetween(previousOrder, nextOrder, nowMs) {
    if (previousOrder === null && nextOrder === null) {
      return nowMs;
    }
    if (previousOrder === null) {
      return nextOrder - 1;
    }
    if (nextOrder === null) {
      return previousOrder + 1;
    }
    return (previousOrder + nextOrder) / 2;
  }

  // A new to-do from a typed line and where it was typed (baseFields)
  function todoFromEntry(text, baseFields, model, today, nowMs) {
    const parsed = parseEntry(text, model, today);
    if (!parsed.title) {
      return null;
    }
    const fields = copyJson(baseFields) || {};
    fields.title = parsed.title.slice(0, TITLE_LIMIT);
    if (parsed.when) {
      fields.when = parsed.when;
    }
    if (parsed.time) {
      fields.time = parsed.time;
    }
    if (parsed.part) {
      fields.part = parsed.part;
    }
    if (parsed.recur) {
      fields.recur = parsed.recur;
    }
    if (parsed.deadline) {
      fields.deadline = parsed.deadline;
    }
    if (parsed.list) {
      fields.list = parsed.list;
    }
    if (parsed.someday) {
      fields.someday = true;
      fields.when = null;
    }
    // Fresh start: a to-do added for today goes into Today
    if (model.settings.todayModel === 'fresh' && fields.when === today) {
      fields.inToday = today;
    }
    return blankTodo(fields, nowMs, newId(nowMs));
  }

  // A done to-do found in search, back as a new one for today (grocery reuse, P-new-21)
  function againTodo(source, today, nowMs) {
    const fields = { title: source.title, list: source.list, emoji: source.emoji, color: source.color, when: today, inToday: today };
    return blankTodo(fields, nowMs, newId(nowMs));
  }

  // Deleting a list moves its to-dos to the Trash; with open ones it asks first (P-new-24)
  function listDeletePlan(model, listId) {
    const todoIds = [];
    for (const todo of liveTodos(model)) {
      if (todo.list === listId) {
        todoIds.push(todo.id);
      }
    }
    const open = openCountInList(model, listId);
    return { todoIds: todoIds, openCount: open, asksFirst: open > 0, allowed: listId !== INBOX_ID };
  }

  // The to-dos whose title is the words given, ignoring case and spaces at the ends
  function todosTitled(todos, title) {
    const wanted = String(title || '').trim().toLowerCase();
    const found = [];
    for (const todo of todos) {
      if (todo.title.trim().toLowerCase() === wanted) {
        found.push(todo);
      }
    }
    return found;
  }

  function listNamed(model, name) {
    const wanted = String(name || '').trim().toLowerCase();
    for (const list of sortedLists(model)) {
      if (list.name.trim().toLowerCase() === wanted) {
        return list;
      }
    }
    return null;
  }

  /* ---------- Import from Apple Reminders (TD-SET-04) ---------- */

  function partNumber(record) {
    return isPlainObject(record.value) && typeof record.value.part === 'number' ? record.value.part : 0;
  }

  function byPartNumber(first, second) {
    return partNumber(first) - partNumber(second);
  }

  // The shell's import:<id>:<nnnn> parts as one export { lists, reminders }, or null
  function joinImportParts(partRecords) {
    if (!Array.isArray(partRecords) || partRecords.length === 0) {
      return null;
    }
    const ordered = partRecords.slice();
    ordered.sort(byPartNumber);
    const exported = { lists: [], reminders: [] };
    for (const record of ordered) {
      const part = record.value;
      if (!isPlainObject(part)) {
        return null;
      }
      for (const list of Array.isArray(part.lists) ? part.lists : []) {
        exported.lists.push(list);
      }
      for (const reminder of Array.isArray(part.reminders) ? part.reminders : []) {
        exported.reminders.push(reminder);
      }
    }
    return exported;
  }

  // Apple counts weekdays 1 (Sunday) to 7; Monday to Friday is 2 to 6
  function isWorkweek(daysOfWeek) {
    if (!Array.isArray(daysOfWeek) || daysOfWeek.length !== 5) {
      return false;
    }
    const weekdays = [];
    for (const day of daysOfWeek) {
      if (!isPlainObject(day) || (day.weekNumber && day.weekNumber !== 0)) {
        return false;
      }
      weekdays.push(day.weekday);
    }
    weekdays.sort();
    return weekdays.join(',') === '2,3,4,5,6';
  }

  function hasNumbers(value) {
    return Array.isArray(value) && value.length > 0;
  }

  // An Apple repeat as a to-do's recur, or null when the to-do cannot hold it (yearly, every N,
  // chosen weekdays, set days, an end: later, on request)
  function recurFromApple(rules) {
    if (!Array.isArray(rules) || rules.length !== 1 || !isPlainObject(rules[0])) {
      return null;
    }
    const rule = rules[0];
    const interval = typeof rule.interval === 'number' ? rule.interval : 1;
    const hasSetDays = hasNumbers(rule.daysOfMonth) || hasNumbers(rule.monthsOfYear) || hasNumbers(rule.weeksOfYear) || hasNumbers(rule.daysOfYear) || hasNumbers(rule.setPositions);
    if (interval !== 1 || isPlainObject(rule.end) || hasSetDays) {
      return null;
    }
    const days = Array.isArray(rule.daysOfWeek) ? rule.daysOfWeek : [];
    if (rule.frequency === 'daily' && days.length === 0) {
      return { every: 'day', from: 'schedule' };
    }
    if (rule.frequency === 'weekly' && days.length <= 1) {
      return { every: 'week', from: 'schedule' };
    }
    if (rule.frequency === 'weekly' && isWorkweek(days)) {
      return { every: 'weekday', from: 'schedule' };
    }
    if (rule.frequency === 'monthly' && days.length === 0) {
      return { every: 'month', from: 'schedule' };
    }
    return null;
  }

  // Apple's colour as #RRGGBB, or the Inbox blue
  function hexFromApple(color) {
    if (typeof color !== 'string' || color.charAt(0) !== '#') {
      return INBOX_LIST.color;
    }
    const digits = color.slice(1).toUpperCase();
    if (/^[0-9A-F]{6}([0-9A-F]{2})?$/.test(digits)) {
      return '#' + digits.slice(0, 6);
    }
    return INBOX_LIST.color;
  }

  // An imported reminder's notes, with its link on its own last line
  function notesFromApple(reminder) {
    let notes = typeof reminder.notes === 'string' ? reminder.notes : '';
    if (isText(reminder.url)) {
      notes = notes ? notes + '\n' + reminder.url : reminder.url;
    }
    return notes.slice(0, NOTES_LIMIT);
  }

  // The fields importing sets on a to-do: the phone's version wins for these; the to-do's own
  // fields (subtasks, part, deadline, emoji, colour, order) stay as they are
  function importedFields(reminder, listId) {
    const due = isPlainObject(reminder.due) ? reminder.due : null;
    const when = due && isDayKey(due.date) ? due.date : null;
    const time = when && due.allDay !== true && isWallTime(due.time) ? due.time : null;
    const completed = reminder.completed === true;
    return {
      title: String(reminder.title || '').trim().slice(0, TITLE_LIMIT) || 'Untitled',
      notes: notesFromApple(reminder),
      list: listId,
      when: when,
      time: time,
      recur: when ? recurFromApple(reminder.recurrence) : null,
      done: completed,
      completedAt: completed && isText(reminder.completionDate) && !Number.isNaN(Date.parse(reminder.completionDate)) ? new Date(Date.parse(reminder.completionDate)).toISOString() : null
    };
  }

  function sameImportedFields(todo, fields) {
    for (const field of Object.keys(fields)) {
      if (JSON.stringify(todo[field]) !== JSON.stringify(fields[field])) {
        return false;
      }
    }
    return true;
  }

  function lastOrderInList(todos, listId) {
    let last = null;
    for (const todo of todos) {
      if (todo.list === listId && (last === null || todo.order > last)) {
        last = todo.order;
      }
    }
    return last;
  }

  function hasAppleRepeat(reminder) {
    return Array.isArray(reminder.recurrence) && reminder.recurrence.length > 0;
  }

  // What importing writes: lists and to-dos matched on Apple's externalId, so importing again
  // updates instead of adding twice; nothing is removed. Returns { lists, todos, counts }.
  function importPlan(model, exported, nowMs) {
    const plan = { lists: [], todos: [], counts: { imported: 0, updated: 0, upToDate: 0, repeatsNotImported: 0 } };
    const listIdByApple = {};
    const knownLists = sortedLists(model);
    let nextListOrder = knownLists.length ? knownLists[knownLists.length - 1].order + 1 : 1;
    for (const appleList of exported.lists) {
      if (!isPlainObject(appleList) || !isText(appleList.id)) {
        continue;
      }
      let list = null;
      for (const known of knownLists) {
        if (known.externalId === appleList.id) {
          list = known;
        }
      }
      if (list === null) {
        list = { id: newId(nowMs), name: String(appleList.title || 'Reminders').slice(0, 80), emoji: null, color: hexFromApple(appleList.color), wallpaper: 'ocean', order: nextListOrder, externalId: appleList.id, stored: null };
        nextListOrder += 1;
        plan.lists.push(list);
      }
      listIdByApple[appleList.id] = list.id;
    }
    const todos = valuesOf(model.todos);
    const byExternalId = {};
    for (const todo of todos) {
      if (todo.externalId) {
        byExternalId[todo.externalId] = todo;
      }
    }
    for (const reminder of exported.reminders) {
      if (!isPlainObject(reminder) || !isText(reminder.externalId)) {
        continue;
      }
      const listId = listIdByApple[reminder.listId] || INBOX_ID;
      const fields = importedFields(reminder, listId);
      if (hasAppleRepeat(reminder) && fields.recur === null) {
        plan.counts.repeatsNotImported += 1;
      }
      const existing = byExternalId[reminder.externalId];
      if (existing) {
        if (sameImportedFields(existing, fields)) {
          plan.counts.upToDate += 1;
          continue;
        }
        const changed = copyJson(existing);
        for (const field of Object.keys(fields)) {
          changed[field] = fields[field];
        }
        plan.todos.push(changed);
        plan.counts.updated += 1;
        continue;
      }
      const lastOrder = lastOrderInList(todos.concat(plan.todos), listId);
      fields.order = lastOrder === null ? nowMs : lastOrder + 1;
      fields.externalId = reminder.externalId;
      if (isText(reminder.creationDate) && !Number.isNaN(Date.parse(reminder.creationDate))) {
        fields.createdAt = new Date(Date.parse(reminder.creationDate)).toISOString();
      }
      const created = blankTodo(fields, nowMs, newId(nowMs));
      plan.todos.push(created);
      byExternalId[reminder.externalId] = created;
      plan.counts.imported += 1;
    }
    return plan;
  }

  return {
    TODO_PREFIX: TODO_PREFIX,
    LIST_PREFIX: LIST_PREFIX,
    SETTINGS_KEY: SETTINGS_KEY,
    REQUEST_PREFIX: REQUEST_PREFIX,
    IMPORT_KIND: IMPORT_KIND,
    INBOX_ID: INBOX_ID,
    TRASH_DAYS: TRASH_DAYS,
    DOUBLE_TICK_MS: DOUBLE_TICK_MS,
    DEFAULT_SETTINGS: DEFAULT_SETTINGS,
    DEFAULT_PRESET: DEFAULT_PRESET,
    CUSTOM_PRESET: CUSTOM_PRESET,
    PRESETS: PRESETS,
    PRESET_IDS: PRESET_IDS,
    ACCENTS: ACCENTS,
    ITEM_COLORS: ITEM_COLORS,
    EMOJIS: EMOJIS,
    WALLPAPER_NAMES: WALLPAPER_NAMES,
    PANEL: PANEL,
    WEEKDAYS: WEEKDAYS,
    REPEAT_LABEL: REPEAT_LABEL,
    REPEAT_EVERY: REPEAT_EVERY,
    REPEAT_FROM: REPEAT_FROM,
    PARTS: PARTS,
    PART_LABEL: PART_LABEL,
    WHEN_CHOICES: WHEN_CHOICES,
    WHEN_CHOICE_LABEL: WHEN_CHOICE_LABEL,
    copyJson: copyJson,
    escapeHtml: escapeHtml,
    isDayKey: isDayKey,
    isWallTime: isWallTime,
    isHexColor: isHexColor,
    dayKeyOf: dayKeyOf,
    localDateKey: localDateKey,
    parseDay: parseDay,
    addDays: addDays,
    daysBetween: daysBetween,
    longDay: longDay,
    friendlyDay: friendlyDay,
    friendlyTime: friendlyTime,
    instantOf: instantOf,
    nextRepeatDay: nextRepeatDay,
    settingFields: settingFields,
    settingChoices: settingChoices,
    isSettingValue: isSettingValue,
    settingsFrom: settingsFrom,
    settingsRecordValue: settingsRecordValue,
    presetSettings: presetSettings,
    newId: newId,
    todoKey: todoKey,
    listKey: listKey,
    blankTodo: blankTodo,
    todoFromRecord: todoFromRecord,
    todoRecordValue: todoRecordValue,
    listFromRecord: listFromRecord,
    listRecordValue: listRecordValue,
    modelFromRecords: modelFromRecords,
    liveTodos: liveTodos,
    trashItems: trashItems,
    visibleDone: visibleDone,
    isInToday: isInToday,
    todayItems: todayItems,
    openCount: openCount,
    openTodayCount: openTodayCount,
    overdueCount: overdueCount,
    freshSuggestions: freshSuggestions,
    listItems: listItems,
    laterCount: laterCount,
    openCountInList: openCountInList,
    upcomingDay: upcomingDay,
    somedayItems: somedayItems,
    logbookItems: logbookItems,
    searchItems: searchItems,
    sortedLists: sortedLists,
    countUpcoming: countUpcoming,
    countOpen: countOpen,
    arrangeDone: arrangeDone,
    todaySections: todaySections,
    dayFromWord: dayFromWord,
    parseEntry: parseEntry,
    previewHtml: previewHtml,
    parsedChipLabels: parsedChipLabels,
    isDoubleTick: isDoubleTick,
    completeTodo: completeTodo,
    uncompleteTodo: uncompleteTodo,
    missingNextCopies: missingNextCopies,
    withWhenChoice: withWhenChoice,
    movedToTomorrow: movedToTomorrow,
    withWhenDay: withWhenDay,
    addedToToday: addedToToday,
    trashedTodo: trashedTodo,
    restoredTodo: restoredTodo,
    expiredTrashIds: expiredTrashIds,
    orderBetween: orderBetween,
    todoFromEntry: todoFromEntry,
    againTodo: againTodo,
    listDeletePlan: listDeletePlan,
    todosTitled: todosTitled,
    listNamed: listNamed,
    joinImportParts: joinImportParts,
    recurFromApple: recurFromApple,
    importPlan: importPlan
  };
})();
  /* copied from index.html: end */

  const Logic = TodoLogic;

  /* ======================================================================
     The tools. Each handler is (input, records, now) → { ops, result } or { refused, result }:
     input is the tool's arguments as manifest.json "agent" describes them (a when already worked
     out by Midas: { date, time, allDay, at, repeat, timeZone } or null); records are this
     Sidekick's records as [{ key, value }]; now is an ISO instant. ops are whole records to set
     or delete; nothing is written by a handler. A refusal changes nothing.
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

  function deviceTimeZone() {
    const options = Intl.DateTimeFormat().resolvedOptions();
    return options.timeZone || 'UTC';
  }

  function todoOp(todo) {
    return { op: 'set', key: Logic.todoKey(todo.id), value: Logic.todoRecordValue(todo, deviceTimeZone()) };
  }

  function todoOps(todos) {
    const ops = [];
    for (const todo of todos) {
      ops.push(todoOp(todo));
    }
    return ops;
  }

  // The stored settings:self value, or null before the page first saved one
  function storedSettingsValue(records) {
    for (const record of records || []) {
      if (record.key === Logic.SETTINGS_KEY) {
        return record.value;
      }
    }
    return null;
  }

  // Keeps every other field of settings:self (the settings engine's keys) as stored
  function settingsOp(settings, preset, records) {
    const stored = storedSettingsValue(records);
    return { op: 'set', key: Logic.SETTINGS_KEY, value: Logic.settingsRecordValue(settings, preset, stored) };
  }

  /* ---------- Reading the records ---------- */

  function modelOf(records) {
    return Logic.modelFromRecords(records || []);
  }

  function todayOf(now) {
    return Logic.localDateKey(Date.parse(now));
  }

  function openTodos(model) {
    const open = [];
    for (const todo of Logic.liveTodos(model)) {
      if (!todo.done) {
        open.push(todo);
      }
    }
    open.sort(byOrder);
    return open;
  }

  function doneTodos(model) {
    const ticked = [];
    for (const todo of Logic.liveTodos(model)) {
      if (todo.done) {
        ticked.push(todo);
      }
    }
    return ticked;
  }

  function byOrder(first, second) {
    return first.order - second.order;
  }

  function titlesOf(todos) {
    const titles = [];
    for (const todo of todos) {
      titles.push(todo.title);
    }
    return titles;
  }

  // The one to-do the words name, among those given: none or two is a refusal, never a guess
  function pickTodo(candidates, words, emptyText) {
    const found = Logic.todosTitled(candidates, words);
    if (found.length === 0) {
      return { problem: refuse('no-such-to-do', emptyText + ': ' + String(words || '').trim()) };
    }
    if (found.length > 1) {
      return { problem: refuse('two-match', 'Two to-dos called ' + found[0].title) };
    }
    return { todo: found[0] };
  }

  function listFor(model, name) {
    if (name === null || name === undefined) {
      return { list: null };
    }
    const list = Logic.listNamed(model, name);
    if (list === null) {
      return { problem: refuse('no-such-list', 'No list called ' + String(name).trim()) };
    }
    return { list: list };
  }

  /* ---------- A when worked out by Midas, as the page's fields ---------- */

  const WORKWEEK = [1, 2, 3, 4, 5];

  function isWorkweek(weekdays) {
    if (!Array.isArray(weekdays) || weekdays.length !== WORKWEEK.length) {
      return false;
    }
    const sorted = weekdays.slice();
    sorted.sort(compareNumbers);
    return JSON.stringify(sorted) === JSON.stringify(WORKWEEK);
  }

  function compareNumbers(first, second) {
    return first - second;
  }

  // The page's repeats only: daily, weekdays, weekly, monthly; every N, years and chosen days are
  // not offered (founder 2026-10-31: later, on request)
  function recurFromWhen(repeat) {
    if (!repeat) {
      return { recur: null };
    }
    const interval = typeof repeat.interval === 'number' ? repeat.interval : 1;
    const weekdays = Array.isArray(repeat.weekdays) ? repeat.weekdays : [];
    let every = null;
    if (interval === 1 && repeat.every === 'day') {
      every = 'day';
    }
    if (interval === 1 && repeat.every === 'month') {
      every = 'month';
    }
    if (interval === 1 && repeat.every === 'week') {
      if (isWorkweek(weekdays)) {
        every = 'weekday';
      } else if (weekdays.length <= 1) {
        every = 'week';
      }
    }
    if (every === null) {
      return { problem: refuse('repeat-not-offered', 'Repeats are daily, weekdays, weekly or monthly') };
    }
    return { recur: { every: every, from: 'schedule' } };
  }

  function whenFields(when) {
    if (!when || !Logic.isDayKey(when.date)) {
      return { fields: null };
    }
    const repeat = recurFromWhen(when.repeat);
    if (repeat.problem) {
      return { problem: repeat.problem };
    }
    const time = !when.allDay && Logic.isWallTime(when.time) ? when.time : null;
    return { fields: { when: when.date, time: time, recur: repeat.recur } };
  }

  function dayText(todo, today) {
    if (todo.someday) {
      return 'Someday';
    }
    if (!todo.when) {
      return 'No Date';
    }
    const dayWords = Logic.friendlyDay(todo.when, today);
    return todo.time ? dayWords + ' ' + Logic.friendlyTime(todo.time) : dayWords;
  }

  /* ---------- Handlers ---------- */

  // The page's New To-Do (a new row, the + card or the bar)
  function addTodo(input, records, now) {
    const model = modelOf(records);
    const today = todayOf(now);
    const nowMs = Date.parse(now);
    const title = String(input.title || '').trim();
    if (!title) {
      return refuse('no-title', 'Say what to do');
    }
    const listPick = listFor(model, input.list);
    if (listPick.problem) {
      return listPick.problem;
    }
    const when = whenFields(input.when);
    if (when.problem) {
      return when.problem;
    }
    const fields = { title: title.slice(0, 500) };
    if (input.notes) {
      fields.notes = String(input.notes);
    }
    if (listPick.list) {
      fields.list = listPick.list.id;
    }
    if (when.fields) {
      fields.when = when.fields.when;
      fields.time = when.fields.time;
      fields.recur = when.fields.recur;
    }
    if (input.someday === true && !when.fields) {
      fields.someday = true;
    }
    // Fresh start: a to-do added for today goes into Today, as on the page
    if (model.settings.todayModel === 'fresh' && fields.when === today) {
      fields.inToday = today;
    }
    const todo = Logic.blankTodo(fields, nowMs, Logic.newId(nowMs));
    return done([todoOp(todo)], 'Added ' + todo.title, { id: todo.id, when: dayText(todo, today) });
  }

  // The page's tick: done now, and a repeat's next copy, once
  function completeTodo(input, records, now) {
    const model = modelOf(records);
    const pick = pickTodo(openTodos(model), input.item, 'No open to-do called');
    if (pick.problem) {
      return pick.problem;
    }
    const changes = Logic.completeTodo(model, pick.todo.id, Date.parse(now), todayOf(now));
    const text = changes.created.length ? 'Done: ' + pick.todo.title + ', next one added' : 'Done: ' + pick.todo.title;
    return done(todoOps(changes.todos), text, { id: pick.todo.id });
  }

  function uncompleteTodo(input, records, now) {
    const model = modelOf(records);
    const pick = pickTodo(doneTodos(model), input.item, 'No done to-do called');
    if (pick.problem) {
      return pick.problem;
    }
    return done([todoOp(Logic.uncompleteTodo(pick.todo))], 'Not done: ' + pick.todo.title, { id: pick.todo.id });
  }

  // The menu's Today / Tomorrow / Someday, the card's When and List, a drop on another list
  function moveTodo(input, records, now) {
    const model = modelOf(records);
    const today = todayOf(now);
    const pick = pickTodo(openTodos(model), input.item, 'No open to-do called');
    if (pick.problem) {
      return pick.problem;
    }
    const listPick = listFor(model, input.list);
    if (listPick.problem) {
      return listPick.problem;
    }
    const when = whenFields(input.when);
    if (when.problem) {
      return when.problem;
    }
    const saidSomething = when.fields || input.someday === true || input.clearDate === true || listPick.list;
    if (!saidSomething) {
      return refuse('nothing-to-change', 'Say a day or a list');
    }
    let todo = Logic.copyJson(pick.todo);
    if (when.fields) {
      todo = Logic.withWhenDay(todo, when.fields.when, when.fields.time, model.settings, today);
      if (when.fields.recur) {
        todo.recur = when.fields.recur;
      }
    } else if (input.someday === true) {
      todo = Logic.withWhenChoice(todo, 'someday', model.settings, today);
    } else if (input.clearDate === true) {
      todo = Logic.withWhenChoice(todo, 'none', model.settings, today);
    }
    if (listPick.list) {
      todo.list = listPick.list.id;
    }
    const listText = listPick.list ? ' in ' + listPick.list.name : '';
    const dayChanged = when.fields || input.someday === true || input.clearDate === true;
    const text = 'Moved ' + todo.title + (dayChanged ? ' to ' + dayText(todo, today) : '') + listText;
    return done([todoOp(todo)], text, { id: todo.id });
  }

  // The detail card: title, notes, part of day, repeat
  function editTodo(input, records, now) {
    const model = modelOf(records);
    const today = todayOf(now);
    const pick = pickTodo(openTodos(model), input.item, 'No open to-do called');
    if (pick.problem) {
      return pick.problem;
    }
    const todo = Logic.copyJson(pick.todo);
    const changed = [];
    if (typeof input.title === 'string' && input.title.trim()) {
      todo.title = input.title.trim().slice(0, 500);
      changed.push('title');
    }
    if (typeof input.notes === 'string') {
      todo.notes = input.notes;
      changed.push('notes');
    }
    if (input.part !== null && input.part !== undefined) {
      todo.part = input.part === 'anytime' ? null : input.part;
      changed.push('part');
    }
    if (input.repeat !== null && input.repeat !== undefined) {
      if (input.repeat === 'never') {
        todo.recur = null;
      } else {
        const from = input.repeatFrom || (todo.recur ? todo.recur.from : 'schedule');
        todo.recur = { every: input.repeat, from: from };
        // A repeat starts from a day: today when the to-do has none
        if (!todo.when) {
          todo.when = today;
          todo.someday = false;
        }
      }
      changed.push('repeat');
    } else if (input.repeatFrom !== null && input.repeatFrom !== undefined) {
      if (!todo.recur) {
        return refuse('no-repeat', pick.todo.title + ' doesn’t repeat');
      }
      todo.recur.from = input.repeatFrom;
      changed.push('repeat');
    }
    if (!changed.length) {
      return refuse('nothing-to-change', 'Say what to change');
    }
    return done([todoOp(todo)], 'Changed ' + todo.title, { id: todo.id, changed: changed });
  }

  // Delete moves to the Trash for 30 days, as on the page
  function deleteTodo(input, records, now) {
    const model = modelOf(records);
    const pick = pickTodo(Logic.liveTodos(model), input.item, 'No to-do called');
    if (pick.problem) {
      return pick.problem;
    }
    return done([todoOp(Logic.trashedTodo(pick.todo, Date.parse(now)))], 'Deleted: ' + pick.todo.title, { id: pick.todo.id });
  }

  // The Trash's Restore
  function restoreTodo(input, records, now) {
    const model = modelOf(records);
    const pick = pickTodo(Logic.trashItems(model), input.item, 'Nothing in the Trash called');
    if (pick.problem) {
      return pick.problem;
    }
    return done([todoOp(Logic.restoredTodo(pick.todo))], 'Restored: ' + pick.todo.title, { id: pick.todo.id });
  }

  // Search, done ones included
  function searchTodos(input, records, now) {
    const model = modelOf(records);
    const today = todayOf(now);
    const words = String(input.query || '').trim();
    if (!words) {
      return refuse('no-query', 'Say what to find');
    }
    const found = Logic.searchItems(model, words);
    const count = found.open.length + found.done.length;
    if (count === 0) {
      return done([], 'No results for ' + words, { open: [], done: [] });
    }
    const open = [];
    for (const todo of found.open) {
      open.push({ title: todo.title, when: dayText(todo, today) });
    }
    const text = 'Found ' + count + (count === 1 ? ' to-do' : ' to-dos');
    return done([], text, { open: open, done: titlesOf(found.done) });
  }

  // What Today shows, in the person's today model
  function listToday(input, records, now) {
    const model = modelOf(records);
    const today = todayOf(now);
    const items = Logic.todayItems(model, today, null);
    const open = [];
    for (const todo of items) {
      if (!todo.done) {
        open.push(todo);
      }
    }
    if (!open.length) {
      return done([], 'Nothing left today', { open: [] });
    }
    const text = open.length + (open.length === 1 ? ' to-do today' : ' to-dos today');
    return done([], text, { open: titlesOf(open), overdue: Logic.overdueCount(model, today) });
  }

  function settingValueFrom(field, said) {
    const choices = Logic.settingChoices(field);
    const text = String(said === null || said === undefined ? '' : said).trim();
    for (const choice of choices) {
      if (typeof choice === 'boolean') {
        const onWords = ['true', 'on', 'yes', 'show'];
        const offWords = ['false', 'off', 'no', 'hide'];
        const lower = text.toLowerCase();
        if (choice === true && onWords.indexOf(lower) !== -1) {
          return { value: true };
        }
        if (choice === false && offWords.indexOf(lower) !== -1) {
          return { value: false };
        }
      } else if (String(choice).toLowerCase() === text.toLowerCase()) {
        return { value: choice };
      }
    }
    return { problem: refuse('value-not-offered', 'Make It Yours doesn’t offer that') };
  }

  // Make It Yours: a preset (Mine resets to the person's start), or one option it offers
  function setSetting(input, records, now) {
    const model = modelOf(records);
    if (input.preset) {
      if (Logic.PRESET_IDS.indexOf(input.preset) === -1) {
        return refuse('preset-not-offered', 'Make It Yours doesn’t offer that');
      }
      const presetName = Logic.PRESETS[input.preset].name;
      return done([settingsOp(Logic.presetSettings(input.preset), input.preset, records)], 'Changed to ' + presetName, { preset: input.preset });
    }
    if (!input.field || Logic.settingFields().indexOf(input.field) === -1) {
      return refuse('nothing-to-change', 'Say what to change');
    }
    const picked = settingValueFrom(input.field, input.value);
    if (picked.problem) {
      return picked.problem;
    }
    if (model.settings[input.field] === picked.value) {
      return refuse('nothing-to-change', 'Already set');
    }
    const settings = Logic.copyJson(model.settings);
    settings[input.field] = picked.value;
    return done([settingsOp(settings, Logic.CUSTOM_PRESET, records)], 'Changed', { field: input.field, value: picked.value });
  }

  /* ---------- Context: what jess sees before choosing a tool ---------- */

  function buildContext(records, now) {
    const model = modelOf(records);
    const today = todayOf(now);
    const lists = [];
    for (const list of Logic.sortedLists(model)) {
      lists.push(list.name);
    }
    const todayOpen = [];
    for (const todo of Logic.todayItems(model, today, null)) {
      if (!todo.done) {
        todayOpen.push(todo.title);
      }
    }
    const open = [];
    for (const todo of openTodos(model).slice(0, 200)) {
      open.push(todo.title);
    }
    const doneToday = [];
    for (const todo of doneTodos(model)) {
      if (todo.completedAt && Logic.localDateKey(Date.parse(todo.completedAt)) === today) {
        doneToday.push(todo.title);
      }
    }
    const trash = titlesOf(Logic.trashItems(model).slice(0, 50));
    return {
      lists: lists,
      today: todayOpen,
      open: open,
      doneToday: doneToday,
      trash: trash,
      look: Logic.PRESETS[model.preset] ? Logic.PRESETS[model.preset].name : 'Custom',
      todayModel: model.settings.todayModel
    };
  }

  return {
    context: buildContext,
    handlers: {
      add: addTodo,
      complete: completeTodo,
      uncomplete: uncompleteTodo,
      move: moveTodo,
      edit: editTodo,
      delete: deleteTodo,
      restore: restoreTodo,
      search: searchTodos,
      today: listToday,
      set_setting: setSetting
    }
  };
})();

// The settings engine's set_setting, and "turned off" for a hidden feature's tool (repair lanes W5)
MidasSidekickTools = MidasSettings.attachTools(MidasSidekickTools, { sidekickId: "todo", catalogue: SETTINGS_CATALOGUE, ownKeys: ["look","theme","accent","textSize","density","font","checkbox","showMeta","dateColors","tickSound","haptic","celebrate","doneGoes","add","parse","swipeRight","swipeLeft","home","todayModel","dayParts"] });

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSidekickTools;
}
