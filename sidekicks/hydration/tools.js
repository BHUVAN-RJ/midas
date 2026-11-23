// Water tools: every action a person can take in this Sidekick, as functions jess (and later any
// outside agent) can call (jess router, founder 2026-10-21). manifest.json "agent" describes each
// tool; this file does the work. The shell runs it in JavaScriptCore and writes the ops it returns
// through RecordWriter; nothing here touches the store.
//
// The block between "copied from index.html" markers is the page's own code, character for
// character: the deploy gate refuses this file when it no longer appears in index.html, so a
// drink logged by voice is written exactly as the page writes it. Change the page, then copy the
// block here again.
//
// A plain script: one global (MidasSidekickTools), a CommonJS export at the end for Node.
var MidasSidekickTools = (function createWaterTools() {
  'use strict';

  /* copied from index.html: begin */
var WaterLogic = (function createWaterLogic() {
  'use strict';

  const ML_PER_OZ = 29.5735;
  const UNITS = ['ml', 'l', 'oz'];
  const DAY_PREFIX = 'water:';
  const SETTINGS_KEY = 'settings:main';
  const REMINDER_KEY = 'reminder:water';
  // The shell resolves {today} to the phone's local date for each widget look and each tap
  // (hydration plan W1), so the widget reads and writes the right day without the page open.
  const TODAY_KEY = 'water:{today}';
  const REMINDER_TITLE = 'Drink Water';
  const DEFAULT_GOAL_ML = 2500;
  const GOAL_MIN_ML = 500;
  const GOAL_MAX_ML = 6000;
  const GOAL_STEP_ML = 100;
  const GOAL_MIN_OZ = 20;
  const GOAL_MAX_OZ = 200;
  const AMOUNT_MIN_ML = 1;
  const AMOUNT_MAX_ML = 3000;
  // 250/500/750 ml, or 8/16/24 oz stored in ml (founder defaults, 2026-10-25)
  const PRESETS_ML = [250, 500, 750];
  const PRESETS_OZ_ML = [237, 473, 710];
  const HOURLY_INTERVALS = [2, 3, 4];
  // Reminders skip times in the 45 minutes after a drink (plan N2)
  const QUIET_MINUTES = 45;
  const MINUTE_MS = 60000;
  const STREAK_LIMIT_DAYS = 3650;
  const ENTRY_LIMIT = 200;
  const WEEKDAY_LETTERS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  // Tide colours for the Home Screen widgets, by day and at night (founder, 2026-10-27: every
  // widget gives light and dark; dark is this page's own night Tide). The secondary ink is the ink
  // faded only as far as it still reads over the sand and the sea.
  const WIDGET_SEA = { light: '#9CCFD3', dark: '#2A6970' };
  // The share of the widget's height the sea keeps at 0 L (option A, "Low tide")
  const WIDGET_SEA_FLOOR = 0.1;
  const WIDGET_SAND = { light: '#F4EEE3', dark: '#0E1A1E' };
  const WIDGET_INK = { light: '#24343A', dark: '#E3EEEF' };
  const WIDGET_INK_SECONDARY = { light: '#455255', dark: '#D4DFE0' };
  const WIDGET_ACCENT = { light: '#2F7E87', dark: '#5FB3BA' };
  const WIDGET_TINT = '#2F7E87';
  const WIDGET_VERSION = 1;
  // One widget, "Water" (founder, 2026-10-27); widget:week was the second one and is deleted
  const WIDGET_KEY = 'widget:today';
  const WIDGET_NAME = 'Water';
  const RETIRED_WIDGET_KEYS = ['widget:week'];

  const DEFAULT_SETTINGS = {
    goalMl: DEFAULT_GOAL_ML,
    unit: 'ml',
    presetsMl: PRESETS_ML,
    remindStart: '09:00',
    remindEnd: '21:00',
    everyHours: 2,
    remindersOn: true
  };

  let clockFormatterCache = null;

  /* ---------- Small helpers ---------- */

  function pad2(number) {
    return number < 10 ? '0' + number : String(number);
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

  function isUnit(value) {
    return UNITS.indexOf(value) !== -1;
  }

  function isWholeNumberBetween(value, lowest, highest) {
    return Number.isInteger(value) && value >= lowest && value <= highest;
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

  /* ---------- Units: ml, L and oz ---------- */

  function ouncesToMl(ounces) {
    return Math.round(ounces * ML_PER_OZ);
  }

  // An amount in a unit, as whole ml
  function toMl(amount, unit) {
    if (unit === 'oz') {
      return ouncesToMl(amount);
    }
    if (unit === 'l') {
      return Math.round(amount * 1000);
    }
    return Math.round(amount);
  }

  // ml in a unit, rounded as shown: whole ml, litres to 2 decimals, whole ounces
  function fromMl(ml, unit) {
    if (unit === 'oz') {
      return Math.round(ml / ML_PER_OZ);
    }
    if (unit === 'l') {
      const hundredths = Math.round(ml / 10);
      return hundredths / 100;
    }
    return Math.round(ml);
  }

  function unitLabel(unit) {
    if (unit === 'l') {
      return 'L';
    }
    return unit === 'oz' ? 'oz' : 'ml';
  }

  // The number alone: "1,250", "1.25", "42"
  function formatNumber(ml, unit) {
    const shown = fromMl(ml, unit);
    if (unit === 'l') {
      return String(shown);
    }
    return shown.toLocaleString('en-US');
  }

  // "1,250 ml", "1.25 L", "42 oz"
  function formatAmount(ml, unit) {
    return formatNumber(ml, unit) + ' ' + unitLabel(unit);
  }

  function presetLabel(ml, unit) {
    return '+' + formatAmount(ml, unit);
  }

  function defaultPresets(unit) {
    const presets = unit === 'oz' ? PRESETS_OZ_ML : PRESETS_ML;
    return presets.slice();
  }

  function sameNumbers(first, second) {
    return stableJson(first) === stableJson(second);
  }

  // Changing the unit swaps the default presets for the new unit's; presets the person set stay
  function presetsForUnitChange(presetsMl, oldUnit, newUnit) {
    if (sameNumbers(presetsMl, defaultPresets(oldUnit))) {
      return defaultPresets(newUnit);
    }
    return presetsMl.slice();
  }

  function isAmountAllowed(ml) {
    return Number.isFinite(ml) && ml >= AMOUNT_MIN_ML && ml <= AMOUNT_MAX_ML;
  }

  /* ---------- The daily goal ---------- */

  // The goal wheel: every 100 ml (0.1 L) from 500 ml to 6 L, or every ounce from 20 to 200
  function goalOptions(unit) {
    const options = [];
    if (unit === 'oz') {
      for (let ounces = GOAL_MIN_OZ; ounces <= GOAL_MAX_OZ; ounces += 1) {
        options.push({ ml: ouncesToMl(ounces), label: ounces + ' oz' });
      }
      return options;
    }
    for (let ml = GOAL_MIN_ML; ml <= GOAL_MAX_ML; ml += GOAL_STEP_ML) {
      options.push({ ml: ml, label: formatAmount(ml, unit) });
    }
    return options;
  }

  function nearestGoalOption(goalMl, unit) {
    let nearest = null;
    for (const option of goalOptions(unit)) {
      if (nearest === null || Math.abs(option.ml - goalMl) < Math.abs(nearest.ml - goalMl)) {
        nearest = option;
      }
    }
    return nearest.ml;
  }

  // A goal said in a unit, on the wheel's steps; null when the wheel does not offer it
  function snapGoal(amount, unit) {
    if (typeof amount !== 'number' || !Number.isFinite(amount) || amount <= 0) {
      return null;
    }
    if (unit === 'oz') {
      const ounces = Math.round(amount);
      return ounces >= GOAL_MIN_OZ && ounces <= GOAL_MAX_OZ ? ouncesToMl(ounces) : null;
    }
    const ml = toMl(amount, unit);
    const stepped = Math.round(ml / GOAL_STEP_ML) * GOAL_STEP_ML;
    return stepped >= GOAL_MIN_ML && stepped <= GOAL_MAX_ML ? stepped : null;
  }

  function isGoalAllowed(goalMl) {
    return isWholeNumberBetween(goalMl, GOAL_MIN_ML, GOAL_MAX_ML);
  }

  /* ---------- Settings ---------- */

  function isHourText(text) {
    return typeof text === 'string' && /^([01]\d|2[0-3]):00$/.test(text);
  }

  function minutesOf(timeText) {
    const hours = Number(timeText.slice(0, 2));
    const minutes = Number(timeText.slice(3, 5));
    return hours * 60 + minutes;
  }

  function hourText(hour) {
    return pad2(hour) + ':00';
  }

  function arePresetsAllowed(presets) {
    if (!Array.isArray(presets) || presets.length !== 3) {
      return false;
    }
    for (const preset of presets) {
      if (!Number.isInteger(preset) || !isAmountAllowed(preset)) {
        return false;
      }
    }
    return true;
  }

  // The stored settings with the defaults filling anything missing; null in, defaults out
  function settingsFrom(value) {
    const source = isPlainObject(value) ? value : {};
    const unit = isUnit(source.unit) ? source.unit : DEFAULT_SETTINGS.unit;
    let remindStart = isHourText(source.remindStart) ? source.remindStart : DEFAULT_SETTINGS.remindStart;
    let remindEnd = isHourText(source.remindEnd) ? source.remindEnd : DEFAULT_SETTINGS.remindEnd;
    if (minutesOf(remindStart) >= minutesOf(remindEnd)) {
      remindStart = DEFAULT_SETTINGS.remindStart;
      remindEnd = DEFAULT_SETTINGS.remindEnd;
    }
    const settings = {
      goalMl: isGoalAllowed(source.goalMl) ? source.goalMl : DEFAULT_SETTINGS.goalMl,
      unit: unit,
      presetsMl: arePresetsAllowed(source.presetsMl) ? source.presetsMl.slice() : defaultPresets(unit),
      remindStart: remindStart,
      remindEnd: remindEnd,
      everyHours: HOURLY_INTERVALS.indexOf(source.everyHours) !== -1 ? source.everyHours : DEFAULT_SETTINGS.everyHours,
      remindersOn: source.remindersOn !== false
    };
    if (typeof source.createdAt === 'string') {
      settings.createdAt = source.createdAt;
    }
    return settings;
  }

  // The settings record as stored: the stored one's other fields kept, ours over them
  function settingsRecord(settings, existing, nowIso) {
    const record = isPlainObject(existing) ? copyJson(existing) : {};
    record.goalMl = settings.goalMl;
    record.unit = settings.unit;
    record.presetsMl = settings.presetsMl.slice();
    record.remindStart = settings.remindStart;
    record.remindEnd = settings.remindEnd;
    record.everyHours = settings.everyHours;
    record.remindersOn = settings.remindersOn;
    if (typeof record.createdAt !== 'string') {
      record.createdAt = settings.createdAt || nowIso;
    }
    return record;
  }

  /* ---------- Days ---------- */

  // The phone's local date of a moment, "YYYY-MM-DD"
  function localDateKey(milliseconds) {
    const date = new Date(milliseconds);
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
  }

  function dayKey(milliseconds) {
    return DAY_PREFIX + localDateKey(milliseconds);
  }

  function addDaysToDate(dateKey, days) {
    const year = Number(dateKey.slice(0, 4));
    const month = Number(dateKey.slice(5, 7));
    const day = Number(dateKey.slice(8, 10));
    const shifted = new Date(Date.UTC(year, month - 1, day + days));
    return shifted.getUTCFullYear() + '-' + pad2(shifted.getUTCMonth() + 1) + '-' + pad2(shifted.getUTCDate());
  }

  function weekdayLetter(dateKey) {
    const year = Number(dateKey.slice(0, 4));
    const month = Number(dateKey.slice(5, 7));
    const day = Number(dateKey.slice(8, 10));
    const date = new Date(Date.UTC(year, month - 1, day));
    return WEEKDAY_LETTERS[date.getUTCDay()];
  }

  // A moment on a local date at a wall-clock time, in milliseconds
  function wallClockMs(dateKey, timeText) {
    const year = Number(dateKey.slice(0, 4));
    const month = Number(dateKey.slice(5, 7));
    const day = Number(dateKey.slice(8, 10));
    const minutes = minutesOf(timeText);
    const date = new Date(year, month - 1, day, Math.floor(minutes / 60), minutes % 60, 0, 0);
    return date.getTime();
  }

  function isEntry(entry) {
    return isPlainObject(entry) && typeof entry.at === 'string' && Number.isInteger(entry.ml) && entry.ml > 0;
  }

  // A day record read safely: its total, its own goal when it has one, its logged entries
  function dayFrom(value) {
    const source = isPlainObject(value) ? value : {};
    const entries = [];
    if (Array.isArray(source.entries)) {
      for (const entry of source.entries) {
        if (isEntry(entry)) {
          entries.push({ at: entry.at, ml: entry.ml });
        }
      }
    }
    const day = {
      ml: typeof source.ml === 'number' && Number.isFinite(source.ml) && source.ml > 0 ? source.ml : 0,
      entries: entries
    };
    if (Number.isInteger(source.goalMl) && source.goalMl > 0) {
      day.goalMl = source.goalMl;
    }
    return day;
  }

  function entriesTotal(entries) {
    let total = 0;
    for (const entry of entries) {
      total += entry.ml;
    }
    return total;
  }

  // Widget taps add to ml without an entry; what the entries do not explain came from the widget
  function widgetAmount(value) {
    const day = dayFrom(value);
    const unexplained = day.ml - entriesTotal(day.entries);
    return unexplained > 0 ? unexplained : 0;
  }

  // A day after a drink: the total up, an entry for it, and the goal of that day kept on it so a
  // later goal change does not rewrite the streak
  function dayAfterLog(value, ml, atIso, goalMl) {
    const record = isPlainObject(value) ? copyJson(value) : {};
    const day = dayFrom(value);
    let entries = day.entries.concat([{ at: atIso, ml: ml }]);
    // The type holds at most 200 entries; the oldest drop off the list, their ml stays in the total
    if (entries.length > ENTRY_LIMIT) {
      entries = entries.slice(entries.length - ENTRY_LIMIT);
    }
    record.ml = day.ml + ml;
    record.goalMl = goalMl;
    record.entries = entries;
    return record;
  }

  function indexOfEntryAt(value, atIso) {
    const day = dayFrom(value);
    for (let index = day.entries.length - 1; index >= 0; index -= 1) {
      if (day.entries[index].at === atIso) {
        return index;
      }
    }
    return -1;
  }

  function latestEntryIndex(value) {
    const day = dayFrom(value);
    let latestIndex = -1;
    let latestMs = -Infinity;
    for (let index = 0; index < day.entries.length; index += 1) {
      const entryMs = Date.parse(day.entries[index].at);
      if (entryMs >= latestMs) {
        latestMs = entryMs;
        latestIndex = index;
      }
    }
    return latestIndex;
  }

  // The drink to remove from a day: the latest one, or the latest of that amount when one is
  // given (Water remove, founder 2026-10-31); -1 when the day has none
  function entryIndexToRemove(value, ml) {
    if (typeof ml !== 'number') {
      return latestEntryIndex(value);
    }
    const day = dayFrom(value);
    let pickedIndex = -1;
    let pickedMs = -Infinity;
    for (let index = 0; index < day.entries.length; index += 1) {
      const entry = day.entries[index];
      const entryMs = Date.parse(entry.at);
      if (entry.ml === ml && entryMs >= pickedMs) {
        pickedMs = entryMs;
        pickedIndex = index;
      }
    }
    return pickedIndex;
  }

  // A day without one of its entries: the entry gone and its ml off the total
  function dayAfterRemove(value, entryIndex) {
    const record = isPlainObject(value) ? copyJson(value) : {};
    const day = dayFrom(value);
    const removed = day.entries[entryIndex];
    const kept = [];
    for (let index = 0; index < day.entries.length; index += 1) {
      if (index !== entryIndex) {
        kept.push(day.entries[index]);
      }
    }
    const total = day.ml - (removed ? removed.ml : 0);
    record.ml = total > 0 ? total : 0;
    record.entries = kept;
    return record;
  }

  // A day without what the widget added: the total back to the logged entries
  function dayWithoutWidgetAmount(value) {
    const record = isPlainObject(value) ? copyJson(value) : {};
    const day = dayFrom(value);
    record.ml = entriesTotal(day.entries);
    record.entries = day.entries;
    return record;
  }

  /* ---------- Goals met and streaks ---------- */

  // The goal a day is judged by: its own when it has one (the goal on the day it was logged),
  // else today's goal (a day made only by widget taps)
  function dayGoal(value, currentGoalMl) {
    const day = dayFrom(value);
    return day.goalMl !== undefined ? day.goalMl : currentGoalMl;
  }

  function isMet(value, currentGoalMl) {
    if (!isPlainObject(value)) {
      return false;
    }
    return dayFrom(value).ml >= dayGoal(value, currentGoalMl);
  }

  // Days in a row with the goal met, up to today. Today counts once met; an unmet today does
  // not break the streak until it is over. A day with no record breaks it.
  function streakDays(daysByDate, todayDate, currentGoalMl) {
    let count = 0;
    let dateKey = todayDate;
    if (!isMet(daysByDate[todayDate], currentGoalMl)) {
      dateKey = addDaysToDate(todayDate, -1);
    }
    while (count < STREAK_LIMIT_DAYS && isMet(daysByDate[dateKey], currentGoalMl)) {
      count += 1;
      dateKey = addDaysToDate(dateKey, -1);
    }
    return count;
  }

  // The last 7 days, today last: each day's share of its goal
  function weekDays(daysByDate, todayDate, currentGoalMl) {
    const days = [];
    for (let offset = -6; offset <= 0; offset += 1) {
      const dateKey = addDaysToDate(todayDate, offset);
      const value = daysByDate[dateKey];
      const goal = dayGoal(value, currentGoalMl);
      const total = dayFrom(value).ml;
      days.push({ date: dateKey, letter: weekdayLetter(dateKey), fraction: total / goal, met: isMet(value, currentGoalMl), today: offset === 0 });
    }
    return days;
  }

  // Day records by date from [{ key, value }]
  function daysByDateOf(records) {
    const days = {};
    for (const record of records) {
      if (record.key.indexOf(DAY_PREFIX) === 0 && isPlainObject(record.value)) {
        days[record.key.slice(DAY_PREFIX.length)] = record.value;
      }
    }
    return days;
  }

  /* ---------- Reminders ---------- */

  // Reminder times of a day: from the first hour to the last, every N hours (plan N1)
  function slotTimes(settings) {
    const times = [];
    const endMinutes = minutesOf(settings.remindEnd);
    for (let minutes = minutesOf(settings.remindStart); minutes <= endMinutes; minutes += settings.everyHours * 60) {
      times.push(hourText(Math.floor(minutes / 60)));
    }
    return times;
  }

  // What the Today screen says about reminders: off, done for today, or the next time. Times in
  // the 45 minutes after the latest drink are skipped, as the engine skips them (plan N2).
  function nextReminder(settings, dayValue, nowMs) {
    if (!settings.remindersOn) {
      return { state: 'off' };
    }
    if (isMet(dayValue, settings.goalMl)) {
      return { state: 'done' };
    }
    const day = dayFrom(dayValue);
    const latestIndex = latestEntryIndex(dayValue);
    const quietUntil = latestIndex === -1 ? -Infinity : Date.parse(day.entries[latestIndex].at) + QUIET_MINUTES * MINUTE_MS;
    const today = localDateKey(nowMs);
    for (const timeText of slotTimes(settings)) {
      const slotMs = wallClockMs(today, timeText);
      if (slotMs > nowMs && slotMs >= quietUntil) {
        return { state: 'next', at: slotMs };
      }
    }
    return { state: 'next', at: wallClockMs(addDaysToDate(today, 1), settings.remindStart) };
  }

  function sameWallTime(isoText, timeText) {
    const date = new Date(isoText);
    return !Number.isNaN(date.getTime()) && date.getHours() * 60 + date.getMinutes() === minutesOf(timeText);
  }

  // reminder:water from the settings: daily, every N hours from remindStart to endTime, quiet
  // after a drink and silent for the rest of a day once the goal is met (plan N1, N2). Fields the
  // engine wrote (slotsDone, snoozes) are kept. `at` moves only when the first hour changes.
  function reminderRecord(settings, existing, nowMs, timeZone) {
    const record = isPlainObject(existing) ? copyJson(existing) : {};
    const keepAt = typeof record.at === 'string' && sameWallTime(record.at, settings.remindStart);
    if (!keepAt) {
      const firstMs = wallClockMs(localDateKey(nowMs), settings.remindStart);
      record.at = new Date(firstMs).toISOString();
    }
    record.title = REMINDER_TITLE;
    record.timeZone = timeZone;
    record.repeat = { every: 'day' };
    record.everyHours = settings.everyHours;
    record.endTime = settings.remindEnd;
    record.listen = { key: TODAY_KEY, field: 'ml', goal: SETTINGS_KEY + '.goalMl', dayGoalField: 'goalMl', quietMinutes: QUIET_MINUTES };
    record.done = !settings.remindersOn;
    if (typeof record.createdAt !== 'string') {
      record.createdAt = new Date(nowMs).toISOString();
    }
    return record;
  }

  function clockFormatter() {
    if (clockFormatterCache === null) {
      clockFormatterCache = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
    }
    return clockFormatterCache;
  }

  // "2:00 PM" (or "14:00", by the phone's settings)
  function formatClock(milliseconds) {
    const formatter = clockFormatter();
    const text = formatter.format(new Date(milliseconds));
    return text.replace(/[  ]/g, ' ');
  }

  function formatHour(timeText) {
    const today = localDateKey(Date.now());
    return formatClock(wallClockMs(today, timeText));
  }

  /* ---------- Home Screen widgets (docs/WIDGETS.md, hydration plan W1-W4) ---------- */

  // A widget's colours: every colour light and dark, or (lightAndDark false) only the sand and the
  // sea, for an app build before 2026-10-27 that refuses { light, dark } anywhere else
  function widgetColours(lightAndDark) {
    if (lightAndDark) {
      return { ink: WIDGET_INK, secondary: WIDGET_INK_SECONDARY, accent: WIDGET_ACCENT };
    }
    return { ink: null, secondary: 'secondary', accent: 'accent' };
  }

  // A piece with its colour; no colour field for the ink of an older build (the system's)
  function coloured(piece, colour) {
    if (colour !== null) {
      piece.color = colour;
    }
    return piece;
  }

  function presetButtons(settings, colours) {
    const buttons = [];
    for (const presetMl of settings.presetsMl) {
      const button = { button: presetLabel(presetMl, settings.unit), action: { increment: TODAY_KEY, field: 'ml', by: presetMl } };
      buttons.push(colours.accent === 'accent' ? button : coloured(button, colours.accent));
    }
    return buttons;
  }

  // The day's amount; "0 ml" while today has no record yet
  function amountPieces(settings, style, colours) {
    return [
      coloured({ text: '$day.ml', format: settings.unit, style: style, if: '$day.ml' }, colours.ink),
      coloured({ text: '0 ' + unitLabel(settings.unit), style: style, unless: '$day.ml' }, colours.ink)
    ];
  }

  function goalPiece(settings, colours) {
    return { text: 'of $settings.goalMl', format: settings.unit, style: 'caption', color: colours.secondary };
  }

  function streakPiece(colours) {
    return { text: '$streak.days day streak', style: 'caption', color: colours.secondary, if: '$streak.days' };
  }

  // The sea rises behind the content to the day's share of the goal (plan W4). At 0 a thin low
  // tide stays (floor, founder 2026-10-31, option A of water-zero-and-help-2026-10-27.html);
  // builds before 22 ignore floor and draw sand only
  function seaFill(content) {
    return { fill: { value: '$day.ml', of: '$settings.goalMl' }, floor: WIDGET_SEA_FLOOR, color: WIDGET_SEA, edge: 'wave', content: content };
  }

  function widgetSources() {
    return {
      day: { record: TODAY_KEY },
      settings: { record: SETTINGS_KEY },
      streak: { records: DAY_PREFIX, streak: { field: 'ml', goal: '$settings.goalMl', dayGoalField: 'goalMl' } },
      week: { records: DAY_PREFIX, sum: 'ml', limit: 7 }
    };
  }

  // The one Water widget (founder, 2026-10-27: no separate "today" and "week" widgets): small and
  // medium show the day, large adds the week's chart
  function waterWidget(settings, lightAndDark) {
    const colours = widgetColours(lightAndDark);
    const buttons = presetButtons(settings, colours);
    const chart = { chart: '$week.values', color: colours.accent };
    const dayPieces = amountPieces(settings, 'title', colours).concat([goalPiece(settings, colours), streakPiece(colours)]);
    const smallColumn = dayPieces.concat([{ spacer: true }, buttons[0]]);
    const mediumColumn = dayPieces.concat([{ spacer: true }, { spacing: 6, hstack: buttons }]);
    const largeColumn = dayPieces.concat([chart, { spacer: true }, { spacing: 6, hstack: presetButtons(settings, colours) }]);
    return {
      version: WIDGET_VERSION,
      name: WIDGET_NAME,
      tint: WIDGET_TINT,
      background: WIDGET_SAND,
      sources: widgetSources(),
      small: seaFill({ spacing: 2, align: 'leading', vstack: smallColumn }),
      medium: seaFill({ spacing: 2, align: 'leading', vstack: mediumColumn }),
      large: seaFill({ spacing: 10, align: 'leading', vstack: largeColumn })
    };
  }

  // For a shell that refuses the pieces above: a ring, the amount in ml and the buttons, all
  // pieces every shell has, on the system background (docs/WIDGETS.md)
  function plainWidget(settings) {
    const colours = widgetColours(false);
    const ring = { ring: { value: '$day.ml', of: '$settings.goalMl' } };
    const amountText = { text: '$day.ml of $settings.goalMl ml', style: 'caption', color: 'secondary' };
    const buttons = presetButtons(settings, colours);
    return {
      version: WIDGET_VERSION,
      name: WIDGET_NAME,
      tint: WIDGET_TINT,
      sources: { day: { record: TODAY_KEY }, settings: { record: SETTINGS_KEY }, week: { records: DAY_PREFIX, sum: 'ml', limit: 7 } },
      small: { spacing: 6, vstack: [ring, amountText, { spacer: true }, buttons[0]] },
      medium: { spacing: 14, hstack: [ring, { spacing: 6, align: 'leading', vstack: [amountText, { spacer: true }, { spacing: 6, hstack: buttons }] }] },
      large: { spacing: 10, align: 'leading', vstack: [ring, amountText, { chart: '$week.values', color: 'accent' }, { spacer: true }, { spacing: 6, hstack: buttons }] }
    };
  }

  // Each widget record the page keeps, in the order the page tries them: the Tide widget in light
  // and dark, the Tide widget an app build before 2026-10-27 takes (night sand and sea, system
  // ink), and the plain stand-in
  function widgetRecords(settings) {
    return [
      { key: WIDGET_KEY, value: waterWidget(settings, true), fallback: waterWidget(settings, false), plain: plainWidget(settings) }
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
    ML_PER_OZ: ML_PER_OZ,
    UNITS: UNITS,
    DAY_PREFIX: DAY_PREFIX,
    SETTINGS_KEY: SETTINGS_KEY,
    REMINDER_KEY: REMINDER_KEY,
    TODAY_KEY: TODAY_KEY,
    DEFAULT_SETTINGS: DEFAULT_SETTINGS,
    AMOUNT_MIN_ML: AMOUNT_MIN_ML,
    AMOUNT_MAX_ML: AMOUNT_MAX_ML,
    HOURLY_INTERVALS: HOURLY_INTERVALS,
    QUIET_MINUTES: QUIET_MINUTES,
    copyJson: copyJson,
    isUnit: isUnit,
    toMl: toMl,
    fromMl: fromMl,
    unitLabel: unitLabel,
    formatNumber: formatNumber,
    formatAmount: formatAmount,
    presetLabel: presetLabel,
    defaultPresets: defaultPresets,
    presetsForUnitChange: presetsForUnitChange,
    isAmountAllowed: isAmountAllowed,
    goalOptions: goalOptions,
    nearestGoalOption: nearestGoalOption,
    snapGoal: snapGoal,
    isGoalAllowed: isGoalAllowed,
    isHourText: isHourText,
    minutesOf: minutesOf,
    hourText: hourText,
    settingsFrom: settingsFrom,
    settingsRecord: settingsRecord,
    localDateKey: localDateKey,
    dayKey: dayKey,
    addDaysToDate: addDaysToDate,
    wallClockMs: wallClockMs,
    dayFrom: dayFrom,
    entriesTotal: entriesTotal,
    widgetAmount: widgetAmount,
    dayAfterLog: dayAfterLog,
    indexOfEntryAt: indexOfEntryAt,
    latestEntryIndex: latestEntryIndex,
    dayAfterRemove: dayAfterRemove,
    dayWithoutWidgetAmount: dayWithoutWidgetAmount,
    dayGoal: dayGoal,
    isMet: isMet,
    streakDays: streakDays,
    weekDays: weekDays,
    daysByDateOf: daysByDateOf,
    slotTimes: slotTimes,
    nextReminder: nextReminder,
    reminderRecord: reminderRecord,
    formatClock: formatClock,
    formatHour: formatHour,
    RETIRED_WIDGET_KEYS: RETIRED_WIDGET_KEYS,
    widgetRecords: widgetRecords,
    sameWidget: sameWidget,
    entryIndexToRemove: entryIndexToRemove
  };
})();
  /* copied from index.html: end */

  const Logic = WaterLogic;

  /* ======================================================================
     The tools. Each handler is (input, records, now) → { ops, result } or { refused, result }:
     input is the tool's arguments as manifest.json "agent" describes them; records are this
     Sidekick's records as [{ key, value }]; now is an ISO instant. ops are whole records to set;
     nothing is written by a handler. A refusal changes nothing.
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

  function deviceTimeZone() {
    const options = Intl.DateTimeFormat().resolvedOptions();
    return options.timeZone || 'UTC';
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

  function settingsOf(records) {
    return Logic.settingsFrom(recordValue(records, Logic.SETTINGS_KEY));
  }

  // The settings and the reminder made from them, as the page's saveSettingsTask writes them.
  // The reminder is left out when nothing in it changed.
  function settingsOps(settings, records, nowMs) {
    const nowIso = new Date(nowMs).toISOString();
    const existingSettings = recordValue(records, Logic.SETTINGS_KEY);
    const settingsValue = Logic.settingsRecord(settings, existingSettings, nowIso);
    const existingReminder = recordValue(records, Logic.REMINDER_KEY);
    const reminderValue = Logic.reminderRecord(settings, existingReminder, nowMs, deviceTimeZone());
    const ops = [setOp(Logic.SETTINGS_KEY, settingsValue)];
    if (JSON.stringify(reminderValue) !== JSON.stringify(existingReminder)) {
      ops.push(setOp(Logic.REMINDER_KEY, reminderValue));
    }
    return ops;
  }

  function unitSaid(unit, settings) {
    return Logic.isUnit(unit) ? unit : settings.unit;
  }

  function streakText(days) {
    if (days === 0) {
      return '';
    }
    return days === 1 ? ', 1 day streak' : ', ' + days + ' day streak';
  }

  /* ---------- Handlers ---------- */

  // The page's log-preset and log-custom: a glass with no amount is the first preset
  function logDrink(input, records, now) {
    const nowMs = Date.parse(now);
    const settings = settingsOf(records);
    let ml = settings.presetsMl[0];
    if (typeof input.amount === 'number') {
      ml = Logic.toMl(input.amount, unitSaid(input.unit, settings));
    }
    if (!Logic.isAmountAllowed(ml)) {
      return refuse('amount-not-offered', 'Can’t log ' + Logic.formatAmount(Math.max(ml, 0), settings.unit));
    }
    const key = Logic.dayKey(nowMs);
    const value = Logic.dayAfterLog(recordValue(records, key), ml, new Date(nowMs).toISOString(), settings.goalMl);
    const total = Logic.dayFrom(value).ml;
    return done([setOp(key, value)], 'Added ' + Logic.formatAmount(ml, settings.unit), { ml: ml, totalMl: total });
  }

  // The page's Undo: the latest drink logged today comes off
  function undoDrink(input, records, now) {
    const nowMs = Date.parse(now);
    const settings = settingsOf(records);
    const key = Logic.dayKey(nowMs);
    const existing = recordValue(records, key);
    const index = Logic.latestEntryIndex(existing);
    if (index === -1) {
      return refuse('nothing-to-undo', 'No drink to undo today');
    }
    const removedMl = Logic.dayFrom(existing).entries[index].ml;
    const value = Logic.dayAfterRemove(existing, index);
    return done([setOp(key, value)], 'Removed ' + Logic.formatAmount(removedMl, settings.unit), { ml: removedMl, totalMl: value.ml });
  }

  // The page's × on a drink, today or an earlier day (Log, the Day screen; founder 2026-10-31):
  // the latest drink of that day, or the latest of the amount said, or what the widget added
  function removeDrink(input, records, now) {
    const nowMs = Date.parse(now);
    const settings = settingsOf(records);
    const today = Logic.localDateKey(nowMs);
    const dateKey = typeof input.date === 'string' && input.date !== '' ? input.date : today;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey) || dateKey > today) {
      return refuse('day-not-offered', 'Only today or earlier days');
    }
    const key = Logic.DAY_PREFIX + dateKey;
    const existing = recordValue(records, key);
    if (input.fromWidget === true) {
      const widgetMl = Logic.widgetAmount(existing);
      if (widgetMl === 0) {
        return refuse('nothing-to-remove', 'Nothing from the widget that day');
      }
      const withoutWidget = Logic.dayWithoutWidgetAmount(existing);
      return done([setOp(key, withoutWidget)], 'Removed ' + Logic.formatAmount(widgetMl, settings.unit), { ml: widgetMl, totalMl: withoutWidget.ml });
    }
    let ml = null;
    if (typeof input.amount === 'number') {
      ml = Logic.toMl(input.amount, unitSaid(input.unit, settings));
    }
    const index = Logic.entryIndexToRemove(existing, ml);
    if (index === -1) {
      return refuse('nothing-to-remove', 'No such drink that day');
    }
    const removedMl = Logic.dayFrom(existing).entries[index].ml;
    const value = Logic.dayAfterRemove(existing, index);
    return done([setOp(key, value)], 'Removed ' + Logic.formatAmount(removedMl, settings.unit), { ml: removedMl, totalMl: value.ml, date: dateKey });
  }

  function todayTotal(input, records, now) {
    const nowMs = Date.parse(now);
    const settings = settingsOf(records);
    const days = Logic.daysByDateOf(records);
    const today = Logic.localDateKey(nowMs);
    const total = Logic.dayFrom(days[today]).ml;
    const streak = Logic.streakDays(days, today, settings.goalMl);
    const text = Logic.formatAmount(total, settings.unit) + ' of ' + Logic.formatAmount(settings.goalMl, settings.unit) + streakText(streak);
    return done([], text, { totalMl: total, goalMl: settings.goalMl, streak: streak });
  }

  // The goal wheel's steps only: every 100 ml or every ounce, 500 ml to 6 L or 20 to 200 oz
  function setGoal(input, records, now) {
    const settings = settingsOf(records);
    const goalMl = Logic.snapGoal(input.amount, unitSaid(input.unit, settings));
    if (goalMl === null) {
      return refuse('goal-not-offered', 'Goals run from 500 ml to 6 L');
    }
    const hasSettings = recordValue(records, Logic.SETTINGS_KEY) !== null;
    if (hasSettings && goalMl === settings.goalMl) {
      return refuse('nothing-to-change', 'Goal is already ' + Logic.formatAmount(goalMl, settings.unit));
    }
    settings.goalMl = goalMl;
    return done(settingsOps(settings, records, Date.parse(now)), 'Changed goal to ' + Logic.formatAmount(goalMl, settings.unit), { goalMl: goalMl });
  }

  function setUnit(input, records, now) {
    const settings = settingsOf(records);
    if (!Logic.isUnit(input.unit)) {
      return refuse('unit-not-offered', 'Units are ml, L and oz');
    }
    const hasSettings = recordValue(records, Logic.SETTINGS_KEY) !== null;
    if (hasSettings && input.unit === settings.unit) {
      return refuse('nothing-to-change', 'Already in ' + Logic.unitLabel(input.unit));
    }
    settings.presetsMl = Logic.presetsForUnitChange(settings.presetsMl, settings.unit, input.unit);
    settings.unit = input.unit;
    return done(settingsOps(settings, records, Date.parse(now)), 'Changed unit to ' + Logic.unitLabel(input.unit));
  }

  function remindersText(settings) {
    if (!settings.remindersOn) {
      return 'Reminders off';
    }
    return 'Reminders ' + Logic.formatHour(settings.remindStart) + ' to ' + Logic.formatHour(settings.remindEnd) + ', every ' + settings.everyHours + ' hours';
  }

  // The page's switch, From, To and Every: whole hours, From before To, every 2, 3 or 4 hours
  function setReminders(input, records, now) {
    const settings = settingsOf(records);
    const before = JSON.stringify(settings);
    if (input.from !== null && !Logic.isHourText(input.from)) {
      return refuse('time-not-offered', 'Reminders start on the hour');
    }
    if (input.to !== null && !Logic.isHourText(input.to)) {
      return refuse('time-not-offered', 'Reminders end on the hour');
    }
    if (input.everyHours !== null && Logic.HOURLY_INTERVALS.indexOf(input.everyHours) === -1) {
      return refuse('interval-not-offered', 'Every 2, 3 or 4 hours');
    }
    if (typeof input.on === 'boolean') {
      settings.remindersOn = input.on;
    }
    if (input.from !== null) {
      settings.remindStart = input.from;
    }
    if (input.to !== null) {
      settings.remindEnd = input.to;
    }
    if (input.everyHours !== null) {
      settings.everyHours = input.everyHours;
    }
    if (Logic.minutesOf(settings.remindStart) >= Logic.minutesOf(settings.remindEnd)) {
      return refuse('bad-window', 'The first reminder must come before the last');
    }
    const hasSettings = recordValue(records, Logic.SETTINGS_KEY) !== null;
    if (hasSettings && JSON.stringify(settings) === before) {
      return refuse('nothing-to-change', remindersText(settings));
    }
    return done(settingsOps(settings, records, Date.parse(now)), remindersText(settings));
  }

  /* ---------- What jess is told about this Sidekick's records ---------- */

  function buildContext(records, now) {
    const nowMs = Date.parse(now);
    const settings = settingsOf(records);
    const days = Logic.daysByDateOf(records);
    const today = Logic.localDateKey(nowMs);
    const presets = [];
    for (const presetMl of settings.presetsMl) {
      presets.push(Logic.formatAmount(presetMl, settings.unit));
    }
    return {
      unit: Logic.unitLabel(settings.unit),
      goal: Logic.formatAmount(settings.goalMl, settings.unit),
      today: Logic.formatAmount(Logic.dayFrom(days[today]).ml, settings.unit),
      streakDays: Logic.streakDays(days, today, settings.goalMl),
      presets: presets,
      reminders: remindersText(settings)
    };
  }

  return {
    context: buildContext,
    handlers: {
      log: logDrink,
      undo: undoDrink,
      remove: removeDrink,
      today: todayTotal,
      set_goal: setGoal,
      set_unit: setUnit,
      set_reminders: setReminders
    }
  };
})();

// The settings engine (repair lanes W5), after WaterLogic so WaterLogic stays the first copied block
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
var SETTINGS_CATALOGUE = {"entries":[{"key":"page.colour","label":"Background colour","type":"colour","part":"page","selector":":root","css":"--sand","default":"#F4EEE3"},{"key":"text.colour","label":"Text colour","type":"colour","part":"text","selector":":root","css":"--ink","default":"#24343A"},{"key":"page.size","label":"Size of everything on the page","type":"size","part":"page","selector":"#main","default":"m"},{"key":"accent.colour","label":"Main button and switch colour","type":"colour","part":"accent","selector":":root","css":"--accent","default":"#2F7E87"},{"key":"sea.colour","label":"Sea (the rising water) colour","type":"colour","part":"sea","selector":":root","css":["--sea-top","--sea-bottom","--sea-back"],"default":"#5E9FA8"},{"key":"sea.show","label":"Sea (the rising water)","type":"show","part":"sea","selector":"#sea","default":true},{"key":"streak.colour","label":"Streak (days in a row) colour","type":"colour","part":"streak","selector":".streak-chip","css":"color","default":"#24343A"},{"key":"streak.size","label":"Streak (days in a row) size","type":"size","part":"streak","selector":".streak-chip","default":"m"},{"key":"streak.show","label":"Streak (days in a row)","type":"show","part":"streak","selector":".streak-chip","default":true},{"key":"drop.colour","label":"Water drop icon colour","type":"colour","part":"drop","selector":".streak-chip svg, .first .mark","css":"color","default":"#6FAFB6"},{"key":"help.show","label":"Help (?) button","type":"show","part":"help","selector":".help","default":true},{"key":"amount.colour","label":"Today's amount colour","type":"colour","part":"amount","selector":".amount .big","css":"color","default":"#24343A"},{"key":"amount.size","label":"Today's amount size","type":"size","part":"amount","selector":".amount .big","default":"m"},{"key":"goal.show","label":"Goal line under the amount","type":"show","part":"goal","selector":".amount .of","default":true},{"key":"presets.colour","label":"Amount buttons colour","type":"colour","part":"presets","selector":".preset","css":"background-color","default":"#FFFFFF"},{"key":"presets.textColour","label":"Amount buttons text colour","type":"colour","part":"presets","selector":".preset","css":"color","default":"#24343A"},{"key":"presets.size","label":"Amount buttons size","type":"size","part":"presets","selector":".presets","default":"m"},{"key":"presets.show","label":"Amount buttons","type":"show","part":"presets","selector":".presets","default":true},{"key":"week.colour","label":"Week rings colour","type":"colour","part":"week","selector":":root","css":"--day-ring","default":"#24535A"},{"key":"week.size","label":"Week rings size","type":"size","part":"week","selector":".week","default":"m"},{"key":"week.show","label":"Week rings","type":"show","part":"week","selector":".week","default":true},{"key":"nextLine.show","label":"Next reminder line","type":"show","part":"next-line","selector":".next-line","default":true},{"key":"bottom.size","label":"Log and Settings buttons size","type":"size","part":"bottom","selector":".bottom","default":"m"},{"key":"bottom.show","label":"Log and Settings buttons","type":"show","part":"bottom","selector":".bottom","default":true},{"key":"headings.size","label":"Headings size","type":"size","part":"headings","selector":".h1, .lab","default":"m"},{"key":"headings.colour","label":"Headings colour","type":"colour","part":"headings","selector":".h1, .lab","css":"color","default":"#24343A"},{"key":"dates.format","label":"Date format","type":"dateFormat","part":"dates","default":"auto"}]};
/* copied from index.html: end */

// The settings engine's set_setting, and "turned off" for a hidden feature's tool (repair lanes W5)
MidasSidekickTools = MidasSettings.attachTools(MidasSidekickTools, { sidekickId: "hydration", catalogue: SETTINGS_CATALOGUE });

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSidekickTools;
}
