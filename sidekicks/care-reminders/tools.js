// Care reminders tools: every action a person can take in this Sidekick, as functions jess (and later
// any outside agent) can call (jess router, founder 2026-10-21). manifest.json "agent" describes
// each tool; this file does the work. The shell runs it in JavaScriptCore and writes the ops it
// returns through RecordWriter; nothing here touches the store.
//
// The blocks between "copied from index.html" markers are the page's own code, character for
// character: the deploy gate refuses this file when a block no longer appears in index.html, so
// a reminder changed by voice is written exactly as the page writes it. Change the page, then
// copy the block here again.
//
// A plain script: one global (MidasSidekickTools), a CommonJS export at the end for Node.
var MidasSidekickTools = (function createCareRemindersTools() {
  'use strict';

  /* copied from index.html: begin */
var CareLogic = (function createCareLogic() {
  'use strict';

  const DAY_MS = 86400000;
  const MINUTE_MS = 60000;
  // Repeats are searched day by day; this bounds the search (about 110 years).
  const SEARCH_LIMIT_DAYS = 40000;
  // The engine books at most 48 reminders at once, for all Sidekicks together.
  const BOOKING_LIMIT = 48;
  // Early alerts and hourly times are fields on the item (alerts, everyHours) that the shell's
  // engine expands under the ids <itemId>~<ruleId> and <itemId>@<HHMM>; nothing is stored under
  // those ids.
  const ALERT_SEPARATOR = '~';
  const SLOT_SEPARATOR = '@';
  // "Every N Hours" choices (founder, 2026-10-12, change 2); each divides the day evenly
  const HOURLY_INTERVALS = [2, 3, 4];
  const INK = '#111111';
  const WHITE = '#FFFFFF';

  // The founder's 14 list colours (2026-10-12). mark = text and icon colour on the tile.
  const COLOURS = [
    { id: 'butter', name: 'Butter', hex: '#FFE48A', mark: INK },
    { id: 'slate', name: 'Slate', hex: '#46525E', mark: WHITE },
    { id: 'cocoa', name: 'Cocoa', hex: '#6B4430', mark: WHITE },
    { id: 'sky', name: 'Sky', hex: '#7CC8FF', mark: INK },
    { id: 'charcoal', name: 'Charcoal', hex: '#2E2E2E', mark: WHITE },
    { id: 'stone', name: 'Stone', hex: '#BDB6AA', mark: INK },
    { id: 'sand', name: 'Sand', hex: '#EAD9B0', mark: INK },
    { id: 'clay', name: 'Clay', hex: '#D9805F', mark: INK },
    { id: 'lavender', name: 'Lavender', hex: '#C9B3FF', mark: INK },
    { id: 'teal', name: 'Teal', hex: '#0F6E6E', mark: WHITE },
    { id: 'sage', name: 'Sage', hex: '#9CAF88', mark: INK },
    { id: 'pistachio', name: 'Pistachio', hex: '#BFE3A0', mark: INK },
    { id: 'forest', name: 'Forest', hex: '#1E6B45', mark: WHITE },
    { id: 'apricot', name: 'Apricot', hex: '#FFB86B', mark: INK }
  ];

  // Lead times offered for a "before" alert, in minutes
  const BEFORE_STEPS = [5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720];
  const MAX_DAYS_BEFORE = 14;

  // Starter lists on first open (founder brief, 2026-10-12). Editable and deletable.
  const STARTER_LISTS = [
    { id: 'appointments', name: 'Appointments', icon: 'stethoscope', color: 'charcoal', alerts: [
      { id: 'r1', kind: 'daysBefore', days: 1, time: '18:00', text: null },
      { id: 'r2', kind: 'morningOf', time: '08:00', text: null },
      { id: 'r3', kind: 'before', minutes: 60, text: null }
    ] },
    { id: 'medicine', name: 'Medicine', icon: 'pill', color: 'butter', alerts: [] },
    { id: 'injections', name: 'Injections', icon: 'syringe', color: 'clay', alerts: [] },
    { id: 'water', name: 'Water', icon: 'drop', color: 'sky', alerts: [] },
    { id: 'meetings', name: 'Meetings', icon: 'handshake', color: 'sage', alerts: [
      { id: 'r1', kind: 'before', minutes: 60, text: null }
    ] }
  ];

  const formatterCache = {};

  /* ---------- Small helpers ---------- */

  function pad2(number) {
    return number < 10 ? '0' + number : String(number);
  }

  function compareNumbers(first, second) {
    return first - second;
  }

  function deviceTimeZone() {
    const options = Intl.DateTimeFormat().resolvedOptions();
    return options.timeZone || 'UTC';
  }

  // An instant (ISO 8601 text, a Date, or milliseconds this page computed) in milliseconds
  // (NaN if none)
  function instantMs(value) {
    if (value === null || value === undefined || value === '') {
      return NaN;
    }
    if (typeof value === 'number') {
      return value;
    }
    if (value instanceof Date) {
      return value.getTime();
    }
    return Date.parse(String(value));
  }

  // A date field as stored in a record: ISO 8601 text only (null for anything else)
  function storedInstant(value) {
    return typeof value === 'string' && value !== '' ? value : null;
  }

  function copyJson(value) {
    if (value === null || value === undefined) {
      return null;
    }
    return JSON.parse(JSON.stringify(value));
  }

  // Every occurrence of a token replaced, without the $-patterns String.replace would apply
  function replaceEvery(text, token, value) {
    let result = '';
    let position = 0;
    let found = text.indexOf(token, position);
    while (found !== -1) {
      result += text.slice(position, found) + value;
      position = found + token.length;
      found = text.indexOf(token, position);
    }
    return result + text.slice(position);
  }

  /* ---------- Time zones and wall clocks ---------- */

  function partsFormatter(timeZone) {
    const cacheKey = 'parts|' + timeZone;
    const cached = formatterCache[cacheKey];
    if (cached) {
      return cached;
    }
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timeZone, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
      hour: 'numeric', minute: 'numeric', second: 'numeric'
    });
    formatterCache[cacheKey] = formatter;
    return formatter;
  }

  function zonedFields(milliseconds, timeZone) {
    const formatter = partsFormatter(timeZone);
    const parts = formatter.formatToParts(new Date(milliseconds));
    const fields = {};
    for (const part of parts) {
      if (part.type !== 'literal') {
        fields[part.type] = Number(part.value);
      }
    }
    if (fields.hour === 24) {
      fields.hour = 0;
    }
    return fields;
  }

  // How far the zone's wall clock is ahead of UTC at a moment, in milliseconds
  function zoneOffset(milliseconds, timeZone) {
    const fields = zonedFields(milliseconds, timeZone);
    const asUtc = Date.UTC(fields.year, fields.month - 1, fields.day, fields.hour, fields.minute, fields.second);
    const wholeSeconds = Math.floor(milliseconds / 1000) * 1000;
    return asUtc - wholeSeconds;
  }

  function parseDateText(dateText) {
    const pieces = String(dateText).split('-');
    return { year: Number(pieces[0]), month: Number(pieces[1]), day: Number(pieces[2]) };
  }

  function parseTimeText(timeText) {
    const pieces = String(timeText).split(':');
    return { hour: Number(pieces[0]), minute: Number(pieces[1] || 0) };
  }

  function minutesOfTime(timeText) {
    const time = parseTimeText(timeText);
    return time.hour * 60 + time.minute;
  }

  // Wall-clock date and time in a zone, as the instant it names. A time skipped by a
  // daylight-saving jump moves past the jump.
  function wallClockToInstant(dateText, timeText, timeZone) {
    const date = parseDateText(dateText);
    const time = parseTimeText(timeText);
    const zone = timeZone || deviceTimeZone();
    const local = Date.UTC(date.year, date.month - 1, date.day, time.hour, time.minute);
    const firstOffset = zoneOffset(local, zone);
    let candidate = local - firstOffset;
    const secondOffset = zoneOffset(candidate, zone);
    if (secondOffset !== firstOffset) {
      candidate = local - secondOffset;
      const thirdOffset = zoneOffset(candidate, zone);
      if (thirdOffset !== secondOffset) {
        candidate = local - Math.min(firstOffset, secondOffset);
      }
    }
    return new Date(candidate);
  }

  function instantToWallClock(instant, timeZone) {
    const milliseconds = instantMs(instant);
    const fields = zonedFields(milliseconds, timeZone || deviceTimeZone());
    return {
      date: fields.year + '-' + pad2(fields.month) + '-' + pad2(fields.day),
      time: pad2(fields.hour) + ':' + pad2(fields.minute)
    };
  }

  function localDateOf(instant, timeZone) {
    const wallClock = instantToWallClock(instant, timeZone);
    return wallClock.date;
  }

  /* ---------- Calendar days (YYYY-MM-DD) ---------- */

  function dayNumber(dateText) {
    const date = parseDateText(dateText);
    return Math.round(Date.UTC(date.year, date.month - 1, date.day) / DAY_MS);
  }

  function dateOfDayNumber(number) {
    const date = new Date(number * DAY_MS);
    return date.getUTCFullYear() + '-' + pad2(date.getUTCMonth() + 1) + '-' + pad2(date.getUTCDate());
  }

  function addDays(dateText, days) {
    return dateOfDayNumber(dayNumber(dateText) + days);
  }

  function daysBetween(fromText, toText) {
    return dayNumber(toText) - dayNumber(fromText);
  }

  // 0 = Sunday ... 6 = Saturday (1970-01-01 was a Thursday)
  function weekdayOfDayNumber(number) {
    return (((number + 4) % 7) + 7) % 7;
  }

  /* ---------- Locale formatting (the phone's own format, Intl.DateTimeFormat) ---------- */

  function localeFormatter(name, options, timeZone) {
    const cacheKey = name + '|' + (timeZone || '');
    const cached = formatterCache[cacheKey];
    if (cached) {
      return cached;
    }
    const fullOptions = Object.assign({}, options);
    if (timeZone) {
      fullOptions.timeZone = timeZone;
    }
    const formatter = new Intl.DateTimeFormat(undefined, fullOptions);
    formatterCache[cacheKey] = formatter;
    return formatter;
  }

  function formatTime(milliseconds, timeZone) {
    const formatter = localeFormatter('time', { hour: 'numeric', minute: '2-digit' }, timeZone);
    return formatter.format(new Date(milliseconds));
  }

  // A wall-clock "HH:MM" in the phone's format
  function formatClock(timeText) {
    const sample = wallClockToInstant('2026-01-05', timeText, 'UTC');
    return formatTime(sample.getTime(), 'UTC');
  }

  function formatWeekday(milliseconds, timeZone) {
    const formatter = localeFormatter('weekday', { weekday: 'long' }, timeZone);
    return formatter.format(new Date(milliseconds));
  }

  function formatShortWeekday(milliseconds, timeZone) {
    const formatter = localeFormatter('shortWeekday', { weekday: 'short' }, timeZone);
    return formatter.format(new Date(milliseconds));
  }

  function formatShortDate(milliseconds, timeZone) {
    const formatter = localeFormatter('shortDate', { weekday: 'short', day: 'numeric', month: 'short' }, timeZone);
    return formatter.format(new Date(milliseconds));
  }

  /* ---------- Repeats (the engine's format, NOTIFICATIONS.md 4.3) ---------- */

  // Repeat choices offered in the page, each in the engine's format
  const REPEAT_OPTIONS = [
    { key: 'never', label: 'Never', repeat: null },
    { key: 'daily', label: 'Every Day', repeat: { every: 'day' } },
    { key: 'weekdays', label: 'Weekdays', repeat: { every: 'week', weekdays: [1, 2, 3, 4, 5] } },
    { key: 'weekends', label: 'Weekends', repeat: { every: 'week', weekdays: [0, 6] } },
    { key: 'weekly', label: 'Every Week', repeat: { every: 'week' } },
    { key: 'biweekly', label: 'Every 2 Weeks', repeat: { every: 'week', interval: 2 } },
    { key: 'monthly', label: 'Every Month', repeat: { every: 'month' } },
    { key: 'yearly', label: 'Every Year', repeat: { every: 'year' } },
    // Hourly is the page's own form: stored as a daily repeat plus everyHours; the engine expands the other times
    { key: 'every2h', label: 'Every 2 Hours', repeat: { every: 'hour', interval: 2 } },
    { key: 'every3h', label: 'Every 3 Hours', repeat: { every: 'hour', interval: 3 } },
    { key: 'every4h', label: 'Every 4 Hours', repeat: { every: 'hour', interval: 4 } }
  ];

  function repeatForOption(optionKey) {
    for (const option of REPEAT_OPTIONS) {
      if (option.key === optionKey) {
        return copyJson(option.repeat);
      }
    }
    return null;
  }

  // The repeat as the engine wants it: interval only above 1, weekdays sorted and weekly only
  function cleanRepeat(repeat) {
    if (!repeat || !repeat.every) {
      return null;
    }
    if (repeat.every === 'hour') {
      const hours = Number(repeat.interval);
      return HOURLY_INTERVALS.indexOf(hours) === -1 ? null : { every: 'hour', interval: hours };
    }
    const result = { every: repeat.every };
    const interval = Number(repeat.interval || 1);
    if (interval > 1) {
      result.interval = interval;
    }
    if (repeat.every === 'week' && Array.isArray(repeat.weekdays) && repeat.weekdays.length > 0) {
      const sorted = repeat.weekdays.slice();
      sorted.sort(compareNumbers);
      const unique = [];
      for (const day of sorted) {
        if (unique.indexOf(day) === -1) {
          unique.push(day);
        }
      }
      result.weekdays = unique;
    }
    if (repeat.until !== undefined && repeat.until !== null && repeat.until !== '') {
      result.until = repeat.until;
    }
    return result;
  }

  function optionForRepeat(repeat) {
    const cleaned = cleanRepeat(repeat);
    const cleanedText = JSON.stringify(cleaned);
    for (const option of REPEAT_OPTIONS) {
      if (JSON.stringify(option.repeat) === cleanedText) {
        return option.key;
      }
    }
    return 'custom';
  }

  function isRepeating(item) {
    return Boolean(item.repeat && item.repeat.every);
  }

  function isHourly(item) {
    return Boolean(item.repeat && item.repeat.every === 'hour');
  }

  function zoneOfItem(item) {
    return item.timeZone || deviceTimeZone();
  }

  function timeOfMinutes(totalMinutes) {
    return pad2(Math.floor(totalMinutes / 60)) + ':' + pad2(totalMinutes % 60);
  }

  // The wall-clock times an item fires each day. Hourly: around the clock from its Time, so
  // every 3 hours from 08:00 is 08:00, 11:00, ... 23:00, 02:00, 05:00 (Time first).
  function timesOfDay(item) {
    if (!isHourly(item)) {
      return [item.time];
    }
    const stepMinutes = item.repeat.interval * 60;
    const startMinutes = minutesOfTime(item.time);
    const times = [];
    for (let offset = 0; offset < 24 * 60; offset += stepMinutes) {
      times.push(timeOfMinutes((startMinutes + offset) % (24 * 60)));
    }
    return times;
  }

  function repeatMatchesDay(repeat, startDay, day) {
    if (day < startDay) {
      return false;
    }
    const interval = Number(repeat.interval || 1);
    // Hourly runs every day; times before the start on the first day are left out by the caller
    if (repeat.every === 'hour') {
      return true;
    }
    if (repeat.every === 'day') {
      return (day - startDay) % interval === 0;
    }
    if (repeat.every === 'week') {
      const weekday = weekdayOfDayNumber(day);
      const hasWeekdays = Array.isArray(repeat.weekdays) && repeat.weekdays.length > 0;
      const weekdays = hasWeekdays ? repeat.weekdays : [weekdayOfDayNumber(startDay)];
      if (weekdays.indexOf(weekday) === -1) {
        return false;
      }
      // Weeks run Sunday to Saturday, counted from the week of the first date
      const weekStart = day - weekday;
      const firstWeekStart = startDay - weekdayOfDayNumber(startDay);
      const weeks = Math.round((weekStart - firstWeekStart) / 7);
      return weeks % interval === 0;
    }
    const candidate = new Date(day * DAY_MS);
    const start = new Date(startDay * DAY_MS);
    if (repeat.every === 'month') {
      const months = (candidate.getUTCFullYear() - start.getUTCFullYear()) * 12 + candidate.getUTCMonth() - start.getUTCMonth();
      return candidate.getUTCDate() === start.getUTCDate() && months % interval === 0;
    }
    if (repeat.every === 'year') {
      const years = candidate.getUTCFullYear() - start.getUTCFullYear();
      const sameDay = candidate.getUTCMonth() === start.getUTCMonth() && candidate.getUTCDate() === start.getUTCDate();
      return sameDay && years % interval === 0;
    }
    return false;
  }

  function occurrenceAtTime(item, day, timeText) {
    const instant = wallClockToInstant(dateOfDayNumber(day), timeText, zoneOfItem(item));
    return instant.getTime();
  }

  // The item's occurrences on one day, at or after its start (only the first day has any before)
  function occurrencesOnDay(item, day) {
    const startMs = itemAtMs(item);
    const moments = [];
    for (const timeText of timesOfDay(item)) {
      const moment = occurrenceAtTime(item, day, timeText);
      if (moment >= startMs) {
        moments.push(moment);
      }
    }
    moments.sort(compareNumbers);
    return moments;
  }

  // The latest occurrence of one of an hourly item's times at or before a moment, or null.
  // Done tapped on one time's notification completes that time's occurrence, not a later one.
  function latestOccurrenceOfTime(item, timeText, limitMs) {
    const zone = zoneOfItem(item);
    const startMs = itemAtMs(item);
    const lastDay = dayNumber(localDateOf(limitMs, zone));
    const startDay = dayNumber(item.date);
    // Each time occurs once a day, so two days back always reaches its previous occurrence
    for (let day = lastDay; day >= startDay && lastDay - day <= 2; day -= 1) {
      const moment = occurrenceAtTime(item, day, timeText);
      if (moment <= limitMs && moment >= startMs) {
        return moment;
      }
    }
    return null;
  }

  function untilMsOf(item) {
    const until = instantMs(item.repeat.until);
    return Number.isNaN(until) ? Infinity : until;
  }

  // The latest occurrence at or before a moment, or null
  function latestOccurrenceAtOrBefore(item, limitMs) {
    if (!isRepeating(item)) {
      const atMs = itemAtMs(item);
      return atMs <= limitMs ? atMs : null;
    }
    const zone = zoneOfItem(item);
    const startDay = dayNumber(item.date);
    const lastAllowed = Math.min(limitMs, untilMsOf(item));
    if (!Number.isFinite(lastAllowed)) {
      return null;
    }
    const lastDay = dayNumber(localDateOf(lastAllowed, zone));
    for (let day = lastDay; day >= startDay && lastDay - day < SEARCH_LIMIT_DAYS; day -= 1) {
      if (!repeatMatchesDay(item.repeat, startDay, day)) {
        continue;
      }
      const moments = occurrencesOnDay(item, day);
      for (let index = moments.length - 1; index >= 0; index -= 1) {
        if (moments[index] <= lastAllowed) {
          return moments[index];
        }
      }
    }
    return null;
  }

  // The first occurrence strictly after a moment, or null when the repeat has ended
  function firstOccurrenceAfter(item, afterMs) {
    if (!isRepeating(item)) {
      const atMs = itemAtMs(item);
      return atMs > afterMs ? atMs : null;
    }
    const zone = zoneOfItem(item);
    const startDay = dayNumber(item.date);
    const untilMs = untilMsOf(item);
    const fromDay = Number.isFinite(afterMs) ? Math.max(startDay, dayNumber(localDateOf(afterMs, zone))) : startDay;
    const lastDay = untilMs === Infinity ? Infinity : dayNumber(localDateOf(untilMs, zone));
    for (let day = fromDay; day <= lastDay && day - fromDay < SEARCH_LIMIT_DAYS; day += 1) {
      if (!repeatMatchesDay(item.repeat, startDay, day)) {
        continue;
      }
      for (const moment of occurrencesOnDay(item, day)) {
        if (moment > untilMs) {
          return null;
        }
        if (moment > afterMs) {
          return moment;
        }
      }
    }
    return null;
  }

  /* ---------- Alert rules ---------- */

  function leadText(minutes) {
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    if (hours === 0) {
      return rest + ' min';
    }
    if (rest === 0) {
      return hours === 1 ? '1 hour' : hours + ' hours';
    }
    return hours + ' h ' + rest + ' min';
  }

  function shortLeadText(minutes) {
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    if (hours === 0) {
      return rest + ' min';
    }
    if (rest === 0) {
      return hours + ' h';
    }
    return hours + ' h ' + rest + ' min';
  }

  // The wording an alert gets until the person writes their own (WRITING.md: say it, stop)
  function defaultTemplate(rule) {
    if (rule.kind === 'before') {
      return '{title} in ' + leadText(rule.minutes);
    }
    if (rule.kind === 'daysBefore' && rule.days > 1) {
      return '{title} on {day} at {time}';
    }
    return '{title} {day} at {time}';
  }

  function templateOf(rule) {
    const hasOwnText = typeof rule.text === 'string' && rule.text.trim() !== '';
    return hasOwnText ? rule.text : defaultTemplate(rule);
  }

  // The pin's label on the ruler: "1 day before", "Morning of", "1 h before"
  function ruleLabel(rule) {
    if (rule.kind === 'daysBefore') {
      return rule.days === 1 ? '1 day before' : rule.days + ' days before';
    }
    if (rule.kind === 'morningOf') {
      return 'Morning of';
    }
    return shortLeadText(rule.minutes) + ' before';
  }

  // The line under the pin: the clock time for day rules, nothing for "before"
  function ruleSubLabel(rule) {
    if (rule.kind === 'before') {
      return '';
    }
    return formatClock(rule.time);
  }

  // How far ahead of the reminder a rule sits, for ordering pins (earliest first)
  function ruleLeadMinutes(rule) {
    if (rule.kind === 'before') {
      return rule.minutes;
    }
    const days = rule.kind === 'morningOf' ? 0 : rule.days;
    // Day rules sit at least a few hours out; a later clock time is closer to the reminder
    return days * 24 * 60 + (24 * 60 - minutesOfTime(rule.time)) + 12 * 60;
  }

  function compareRulesByLead(first, second) {
    return ruleLeadMinutes(second) - ruleLeadMinutes(first);
  }

  function sortedRules(rules) {
    const copy = (rules || []).slice();
    copy.sort(compareRulesByLead);
    return copy;
  }

  // The moment a rule fires for one occurrence of a reminder
  function alertMoment(rule, occurrence, timeZone) {
    if (rule.kind === 'before') {
      return occurrence - rule.minutes * MINUTE_MS;
    }
    const days = rule.kind === 'morningOf' ? 0 : rule.days;
    const occurrenceDate = localDateOf(occurrence, timeZone);
    const alertDate = addDays(occurrenceDate, -days);
    const instant = wallClockToInstant(alertDate, rule.time, timeZone);
    return instant.getTime();
  }

  // {day}: fixed by the rule ("tomorrow", "today", or the weekday two or more days out)
  function dayWord(rule, occurrence, alertAt, timeZone) {
    let days = 0;
    if (rule.kind === 'daysBefore') {
      days = rule.days;
    } else if (rule.kind === 'before') {
      days = daysBetween(localDateOf(alertAt, timeZone), localDateOf(occurrence, timeZone));
    }
    if (days === 0) {
      return 'today';
    }
    if (days === 1) {
      return 'tomorrow';
    }
    return formatWeekday(occurrence, timeZone);
  }

  function renderWording(rule, title, occurrence, alertAt, timeZone) {
    let text = templateOf(rule);
    text = replaceEvery(text, '{title}', title);
    text = replaceEvery(text, '{time}', formatTime(occurrence, timeZone));
    text = replaceEvery(text, '{day}', dayWord(rule, occurrence, alertAt, timeZone));
    return text.trim();
  }

  function makeRule(kind) {
    if (kind === 'daysBefore') {
      return { id: null, kind: 'daysBefore', days: 1, time: '18:00', text: null };
    }
    if (kind === 'morningOf') {
      return { id: null, kind: 'morningOf', time: '08:00', text: null };
    }
    return { id: null, kind: 'before', minutes: 60, text: null };
  }

  // A rule as stored: only the fields its kind uses; no text field when the wording is the default
  function cleanRule(rule) {
    const text = typeof rule.text === 'string' && rule.text.trim() !== '' ? rule.text.trim() : null;
    let cleaned;
    if (rule.kind === 'daysBefore') {
      const days = Math.min(MAX_DAYS_BEFORE, Math.max(1, Math.round(Number(rule.days) || 1)));
      cleaned = { id: rule.id, kind: 'daysBefore', days: days, time: rule.time || '18:00' };
    } else if (rule.kind === 'morningOf') {
      cleaned = { id: rule.id, kind: 'morningOf', time: rule.time || '08:00' };
    } else {
      const minutes = Math.max(1, Math.round(Number(rule.minutes) || 60));
      cleaned = { id: rule.id, kind: 'before', minutes: minutes };
    }
    if (text !== null) {
      cleaned.text = text;
    }
    return cleaned;
  }

  function stepBefore(minutes, direction) {
    let index = BEFORE_STEPS.indexOf(minutes);
    if (index === -1) {
      index = 0;
      while (index < BEFORE_STEPS.length - 1 && BEFORE_STEPS[index] < minutes) {
        index += 1;
      }
    }
    const nextIndex = Math.min(BEFORE_STEPS.length - 1, Math.max(0, index + direction));
    return BEFORE_STEPS[nextIndex];
  }

  /* ---------- Items and their records ---------- */

  function alertKey(itemId, ruleId) {
    return 'reminder:' + itemId + ALERT_SEPARATOR + ruleId;
  }

  function itemKey(itemId) {
    return 'reminder:' + itemId;
  }

  // The engine's id for the 08:00 time of an hourly repeat, as a key: reminder:<itemId>@0800
  // (in memory only, for counting bookings)
  function slotKey(itemId, timeText) {
    return 'reminder:' + itemId + SLOT_SEPARATOR + timeText.replace(':', '');
  }

  // An item key or an engine id as a key: reminder:<itemId> → { itemId, ruleId: null };
  // reminder:<itemId>~<ruleId> → { itemId, ruleId }; reminder:<itemId>@<HHMM> → { itemId, ruleId: null }
  function splitKey(key) {
    const colon = key.indexOf(':');
    const rest = colon === -1 ? key : key.slice(colon + 1);
    const slotSeparator = rest.indexOf(SLOT_SEPARATOR);
    if (slotSeparator !== -1) {
      return { itemId: rest.slice(0, slotSeparator), ruleId: null };
    }
    const separator = rest.indexOf(ALERT_SEPARATOR);
    if (separator === -1) {
      return { itemId: rest, ruleId: null };
    }
    return { itemId: rest.slice(0, separator), ruleId: rest.slice(separator + 1) };
  }

  function itemAtMs(item) {
    const instant = wallClockToInstant(item.date, item.time, zoneOfItem(item));
    return instant.getTime();
  }

  function setOrDelete(target, field, value) {
    if (value === null || value === undefined || value === '') {
      delete target[field];
    } else {
      target[field] = value;
    }
  }

  // The item's record (care.item in manifest.json): everything the shell's engine needs for the
  // reminder itself, its early alerts (`alerts`, the list's rules copied in) and its hourly times
  // (`everyHours`). Fields the shell writes (snoozedUntil, snoozes, lastDoneAt, slotsDone) and fields
  // this page does not know are kept from the existing value. A field is left out instead of null.
  function recordFromItem(item, existing) {
    const value = {};
    if (existing && typeof existing === 'object') {
      for (const field of Object.keys(existing)) {
        value[field] = existing[field];
      }
    }
    const zone = zoneOfItem(item);
    const at = wallClockToInstant(item.date, item.time, zone).toISOString();
    const previousAt = existing ? instantMs(storedInstant(existing.at)) : NaN;
    const moved = !Number.isNaN(previousAt) && previousAt !== Date.parse(at);
    value.$type = 'care.item';
    value.at = at;
    value.title = item.title;
    value.timeZone = zone;
    value.done = item.done === true;
    setOrDelete(value, 'list', item.list);
    // The engine has no hourly repeat: the record is the Time's daily repeat and everyHours tells
    // the engine to expand the other times. An hourly item has no early alerts.
    if (isHourly(item)) {
      value.repeat = { every: 'day' };
      value.everyHours = item.repeat.interval;
      delete value.alerts;
    } else {
      delete value.everyHours;
      setOrDelete(value, 'repeat', isRepeating(item) ? cleanRepeat(item.repeat) : null);
      setOrDelete(value, 'alerts', cleanedRules(item.alerts));
    }
    setOrDelete(value, 'slotsDone', nonEmptyObject(item.slotsDone));
    // An item built from a record carries the shell's snoozes; one built without them (a draft)
    // leaves the stored ones alone
    if (item.snoozes !== undefined) {
      setOrDelete(value, 'snoozes', nonEmptyObject(item.snoozes));
    }
    setOrDelete(value, 'lastDoneAt', item.lastDoneAt);
    setOrDelete(value, 'doneThrough', item.doneThrough);
    setOrDelete(value, 'completedAt', item.completedAt);
    setOrDelete(value, 'createdAt', item.createdAt);
    // A reminder moved to a new time starts again: its snoozes and its times' Dones go with the
    // old time
    if (moved) {
      delete value.snoozedUntil;
      delete value.snoozes;
      delete value.slotsDone;
    }
    return value;
  }

  // The rules as stored on an item, or null when there are none
  function cleanedRules(rules) {
    if (!Array.isArray(rules) || rules.length === 0) {
      return null;
    }
    const cleaned = [];
    for (const rule of rules) {
      cleaned.push(cleanRule(rule));
    }
    return cleaned;
  }

  function nonEmptyObject(value) {
    if (!value || typeof value !== 'object' || Object.keys(value).length === 0) {
      return null;
    }
    return value;
  }

  // Done tapped by the shell on an hourly time's notification: { "HH:MM": when }
  function snoozesOfRecord(record) {
    const stored = record.snoozes && typeof record.snoozes === 'object' ? record.snoozes : {};
    const snoozes = {};
    for (const suffix of Object.keys(stored)) {
      if (typeof stored[suffix] === 'string') {
        snoozes[suffix] = stored[suffix];
      }
    }
    return snoozes;
  }

  // The snoozes that stay after Done on the event: the hourly times' own (`@HHMM`), not the
  // early alerts' (`~rule`)
  function withoutAlertSnoozes(snoozes) {
    const kept = {};
    for (const suffix of Object.keys(snoozes || {})) {
      if (suffix.indexOf(ALERT_SEPARATOR) !== 0) {
        kept[suffix] = snoozes[suffix];
      }
    }
    return kept;
  }

  function slotsDoneOfRecord(record) {
    const marks = {};
    const stored = record.slotsDone && typeof record.slotsDone === 'object' ? record.slotsDone : {};
    for (const time of Object.keys(stored)) {
      if (!Number.isNaN(instantMs(storedInstant(stored[time])))) {
        marks[time] = stored[time];
      }
    }
    return marks;
  }

  // A daily record with a known everyHours is an hourly repeat; anything else as stored
  function repeatOfRecord(record) {
    const repeat = cleanRepeat(record.repeat);
    const hours = Number(record.everyHours);
    const daily = repeat !== null && repeat.every === 'day' && !repeat.interval && repeat.until === undefined;
    if (daily && HOURLY_INTERVALS.indexOf(hours) !== -1) {
      return { every: 'hour', interval: hours };
    }
    return repeat;
  }

  function itemFromRecord(key, value) {
    const record = value || {};
    const zone = record.timeZone || deviceTimeZone();
    const atMs = instantMs(storedInstant(record.at));
    const wallClock = Number.isNaN(atMs) ? { date: null, time: null } : instantToWallClock(atMs, zone);
    return {
      id: splitKey(key).itemId,
      title: typeof record.title === 'string' ? record.title : '',
      list: record.list || null,
      date: wallClock.date,
      time: wallClock.time,
      repeat: repeatOfRecord(record),
      timeZone: zone,
      done: record.done === true,
      completedAt: storedInstant(record.completedAt),
      doneThrough: storedInstant(record.doneThrough),
      lastDoneAt: storedInstant(record.lastDoneAt),
      // Done tapped by the shell on an hourly repeat's other times: { "HH:MM": when }
      slotsDone: slotsDoneOfRecord(record),
      // Snooze tapped by the shell on an early alert or an hourly time: { "~rule" | "@HHMM": when },
      // each independent of the others and of the item's own snoozedUntil (founder, 2026-10-15)
      snoozes: snoozesOfRecord(record),
      // The list's rules as last copied onto the item, for the engine; rulesForItem is the source
      alerts: Array.isArray(record.alerts) ? cleanedRules(record.alerts) || [] : [],
      createdAt: storedInstant(record.createdAt)
    };
  }

  // Item records are this page's own reminders with a usable time
  function isItemRecord(key, value) {
    if (!value || typeof value !== 'object') {
      return false;
    }
    return !Number.isNaN(instantMs(storedInstant(value.at)));
  }

  // A reminder always uses its list's alerts (founder, 2026-10-12).
  function rulesForItem(item, list) {
    return list && Array.isArray(list.alerts) ? list.alerts : [];
  }

  // The occurrence through which a repeating item is done: the page's own doneThrough, or the
  // occurrence the shell's Done button (lastDoneAt) was tapped for, whichever is later
  function effectiveDoneThrough(item) {
    let through = instantMs(item.doneThrough);
    if (Number.isNaN(through)) {
      through = -Infinity;
    }
    if (isHourly(item)) {
      // A Done on one of the times completes that time's occurrence
      const marks = [{ time: item.time, lastDoneAt: item.lastDoneAt }];
      const slotsDone = item.slotsDone || {};
      for (const time of Object.keys(slotsDone)) {
        marks.push({ time: time, lastDoneAt: slotsDone[time] });
      }
      for (const mark of marks) {
        const markedAt = instantMs(mark.lastDoneAt);
        if (Number.isNaN(markedAt)) {
          continue;
        }
        const markedOccurrence = latestOccurrenceOfTime(item, mark.time, markedAt);
        if (markedOccurrence !== null && markedOccurrence > through) {
          through = markedOccurrence;
        }
      }
      return through;
    }
    const tappedAt = instantMs(item.lastDoneAt);
    if (!Number.isNaN(tappedAt)) {
      const tappedOccurrence = latestOccurrenceAtOrBefore(item, tappedAt);
      if (tappedOccurrence !== null && tappedOccurrence > through) {
        through = tappedOccurrence;
      }
    }
    return through;
  }

  // The occurrence whose early alerts should be booked now: the item's own time for a one-time
  // item, the next not-done occurrence after now for a repeat (alerts for the next one only)
  function targetOccurrence(item, nowMs) {
    if (item.done) {
      return null;
    }
    if (!isRepeating(item)) {
      return itemAtMs(item);
    }
    const after = Math.max(nowMs, effectiveDoneThrough(item));
    return firstOccurrenceAfter(item, after);
  }

  // The early alerts the engine books for an item now. An alert whose time has already passed is
  // skipped (default chosen 2026-10-12, not decided by the founder), as is a "morning of" alert
  // at or after the reminder itself.
  function plannedAlerts(item, rules, nowMs) {
    // An hourly repeat fires only at its own times; the list's early alerts don't apply
    if (isHourly(item)) {
      return [];
    }
    const occurrence = targetOccurrence(item, nowMs);
    if (occurrence === null) {
      return [];
    }
    const zone = zoneOfItem(item);
    const plans = [];
    for (const rule of rules || []) {
      const alertAt = alertMoment(rule, occurrence, zone);
      if (!(alertAt > nowMs) || !(alertAt < occurrence)) {
        continue;
      }
      plans.push({
        key: alertKey(item.id, rule.id),
        ruleId: rule.id,
        at: alertAt,
        occurrence: occurrence,
        title: renderWording(rule, item.title, occurrence, alertAt, zone)
      });
    }
    return plans;
  }

  /* ---------- Hourly repeats (founder, 2026-10-12, change 2): the engine expands the other times ---------- */

  // The other times of an hourly repeat (the item's own record holds its Time). Each first
  // fires the first time it falls on or after the reminder's Date and Time.
  function plannedSlots(item) {
    if (!isHourly(item)) {
      return [];
    }
    const zone = zoneOfItem(item);
    const startMs = itemAtMs(item);
    const times = timesOfDay(item);
    const plans = [];
    for (let index = 1; index < times.length; index += 1) {
      const timeText = times[index];
      let firstMs = wallClockToInstant(item.date, timeText, zone).getTime();
      // A time earlier in the day than the reminder's Time first comes the next day
      if (firstMs < startMs) {
        firstMs = wallClockToInstant(addDays(item.date, 1), timeText, zone).getTime();
      }
      plans.push({ key: slotKey(item.id, timeText), time: timeText, at: firstMs });
    }
    return plans;
  }

  // Bookings an item holds with the engine: its own notification plus its early alerts.
  // A daily, weekly-on-days, monthly or yearly repeat is one iOS repeating trigger per weekday
  // (NOTIFICATIONS.md 6.3); anything else is one booking for its next occurrence.
  function bookingsOfItem(item, rules, nowMs) {
    if (item.done) {
      return 0;
    }
    let slots = 0;
    if (isHourly(item)) {
      // One daily repeat per time: 12, 8 or 6 iOS repeating triggers
      slots += timesOfDay(item).length;
    } else if (isRepeating(item)) {
      const repeat = cleanRepeat(item.repeat);
      const native = !repeat.interval && repeat.until === undefined;
      if (native) {
        slots += repeat.weekdays ? repeat.weekdays.length : 1;
      } else if (firstOccurrenceAfter(item, nowMs) !== null) {
        slots += 1;
      }
    } else if (itemAtMs(item) > nowMs) {
      slots += 1;
    }
    const plans = plannedAlerts(item, rules, nowMs);
    return slots + plans.length;
  }

  /* ---------- What a reminder shows: next, overdue or done ---------- */

  // state: 'overdue' (passed, not done: "When you can"), 'upcoming', 'done', or 'ended'
  function displayState(item, nowMs, deviceZone) {
    const zone = deviceZone || deviceTimeZone();
    const today = localDateOf(nowMs, zone);
    if (!isRepeating(item)) {
      const atMs = itemAtMs(item);
      if (item.done) {
        return { state: 'done', at: atMs };
      }
      return { state: atMs <= nowMs ? 'overdue' : 'upcoming', at: atMs };
    }
    if (item.done) {
      return { state: 'ended', at: null };
    }
    const through = effectiveDoneThrough(item);
    const latest = latestOccurrenceAtOrBefore(item, nowMs);
    // Only today's missed occurrence is shown as overdue; earlier days roll on
    if (latest !== null && latest > through && localDateOf(latest, zone) === today) {
      return { state: 'overdue', at: latest };
    }
    const next = firstOccurrenceAfter(item, Math.max(nowMs, through));
    const doneToday = Number.isFinite(through) && localDateOf(through, zone) === today;
    if (doneToday && (next === null || localDateOf(next, zone) !== today)) {
      return { state: 'done', at: through, next: next };
    }
    if (next === null) {
      return { state: 'ended', at: null };
    }
    return { state: 'upcoming', at: next };
  }

  // "in 19 min", "20:00", "Tomorrow 13:00", "Thu 13:00", "Thu 23 Oct 13:00"
  function whenText(atMs, nowMs, zone) {
    const minutesAway = Math.round((atMs - nowMs) / MINUTE_MS);
    if (minutesAway >= 0 && minutesAway < 60) {
      return minutesAway <= 0 ? 'Now' : 'in ' + minutesAway + ' min';
    }
    const days = daysBetween(localDateOf(nowMs, zone), localDateOf(atMs, zone));
    const clock = formatTime(atMs, zone);
    if (days === 0) {
      return clock;
    }
    if (days === 1) {
      return 'Tomorrow ' + clock;
    }
    if (days === -1) {
      return 'Yesterday ' + clock;
    }
    if (days > 1 && days < 7) {
      return formatShortWeekday(atMs, zone) + ' ' + clock;
    }
    return formatShortDate(atMs, zone) + ' ' + clock;
  }

  // Tile size by how soon the list's next reminder is: within the hour, within 2 days, later
  function tileSize(nextAtMs, nowMs) {
    if (nextAtMs === null) {
      return 'sm';
    }
    const away = nextAtMs - nowMs;
    if (away <= 60 * MINUTE_MS) {
      return 'xl';
    }
    if (away <= 2 * DAY_MS) {
      return 'md';
    }
    return 'sm';
  }

  function colourById(colourId) {
    for (const colour of COLOURS) {
      if (colour.id === colourId) {
        return colour;
      }
    }
    return COLOURS[4];
  }

  return {
    BOOKING_LIMIT: BOOKING_LIMIT, COLOURS: COLOURS, STARTER_LISTS: STARTER_LISTS, REPEAT_OPTIONS: REPEAT_OPTIONS,
    MAX_DAYS_BEFORE: MAX_DAYS_BEFORE, ALERT_SEPARATOR: ALERT_SEPARATOR, SLOT_SEPARATOR: SLOT_SEPARATOR,
    deviceTimeZone: deviceTimeZone, instantMs: instantMs, copyJson: copyJson,
    wallClockToInstant: wallClockToInstant, instantToWallClock: instantToWallClock, localDateOf: localDateOf,
    addDays: addDays, formatTime: formatTime, formatClock: formatClock, formatShortDate: formatShortDate,
    repeatForOption: repeatForOption, optionForRepeat: optionForRepeat, cleanRepeat: cleanRepeat, isRepeating: isRepeating,
    latestOccurrenceAtOrBefore: latestOccurrenceAtOrBefore, firstOccurrenceAfter: firstOccurrenceAfter,
    templateOf: templateOf, defaultTemplate: defaultTemplate, ruleLabel: ruleLabel, ruleSubLabel: ruleSubLabel,
    sortedRules: sortedRules, alertMoment: alertMoment, renderWording: renderWording, makeRule: makeRule, cleanRule: cleanRule,
    stepBefore: stepBefore, leadText: leadText,
    alertKey: alertKey, itemKey: itemKey, splitKey: splitKey, itemAtMs: itemAtMs,
    isHourly: isHourly, timesOfDay: timesOfDay, slotKey: slotKey, plannedSlots: plannedSlots,
    recordFromItem: recordFromItem, itemFromRecord: itemFromRecord, isItemRecord: isItemRecord, rulesForItem: rulesForItem,
    withoutAlertSnoozes: withoutAlertSnoozes,
    effectiveDoneThrough: effectiveDoneThrough, targetOccurrence: targetOccurrence, plannedAlerts: plannedAlerts,
    bookingsOfItem: bookingsOfItem, cleanedRules: cleanedRules, displayState: displayState, whenText: whenText,
    tileSize: tileSize, colourById: colourById
  };
})();
  /* copied from index.html: end */

  /* copied from index.html: begin */
  const ICON_TABS = [
    { name: 'Health', icons: ['pill', 'syringe', 'stethoscope', 'first-aid', 'hospital', 'heartbeat', 'tooth', 'eye', 'bandaids', 'thermometer', 'barbell', 'baby'] },
    { name: 'Water', icons: ['drop', 'drop-half', 'pint-glass', 'coffee', 'fork-knife', 'sparkle'] },
    { name: 'People', icons: ['users', 'handshake', 'phone', 'briefcase', 'cake', 'dog'] },
    { name: 'Day', icons: ['sun', 'moon', 'clock', 'calendar-check', 'calendar-dots', 'bell', 'house', 'car', 'map-pin', 'star', 'list', 'heartbeat'] }
  ];
  /* copied from index.html: end */

  /* copied from index.html: begin */
  function listFromRecord(key, value) {
    const record = value || {};
    const alerts = [];
    for (const rule of Array.isArray(record.alerts) ? record.alerts : []) {
      alerts.push(Logic.cleanRule(rule));
    }
    return {
      id: Logic.splitKey(key).itemId,
      name: String(record.name || 'List'),
      icon: record.icon || 'list',
      color: record.color || 'charcoal',
      alerts: alerts,
      order: Number.isFinite(record.order) ? record.order : 1000,
      createdAt: record.createdAt || null
    };
  }
  /* copied from index.html: end */

  /* copied from index.html: begin */
  function listRecordFromList(list, existing) {
    const value = {};
    if (existing && typeof existing === 'object') {
      for (const field of Object.keys(existing)) {
        value[field] = existing[field];
      }
    }
    const alerts = [];
    for (const rule of list.alerts || []) {
      alerts.push(Logic.cleanRule(rule));
    }
    value.$type = 'care.list';
    value.name = list.name;
    value.icon = list.icon;
    value.color = list.color;
    value.alerts = alerts;
    value.order = list.order;
    value.createdAt = list.createdAt || new Date().toISOString();
    return value;
  }
  /* copied from index.html: end */

  /* copied from index.html: begin */
  function withRuleIds(rules) {
    const result = [];
    for (const rule of rules || []) {
      const cleaned = Logic.cleanRule(rule);
      cleaned.id = cleaned.id || newId('r');
      result.push(cleaned);
    }
    return result;
  }
  /* copied from index.html: end */

  /* copied from index.html: begin */
  // Lead times offered for a "before" alert, in minutes
  const BEFORE_STEPS = [5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720];
  const MAX_DAYS_BEFORE = 14;
  /* copied from index.html: end */

  const Logic = CareLogic;

  function deviceTimeZone() {
    return Logic.deviceTimeZone();
  }

  // The page's newId(prefix): the prefix and 8 base36 characters; JavaScriptCore has no crypto,
  // so Math.random stands in there
  function newId(prefix) {
    const bytes = new Uint8Array(8);
    const cryptoSource = typeof globalThis.crypto === 'object' ? globalThis.crypto : null;
    if (cryptoSource && typeof cryptoSource.getRandomValues === 'function') {
      cryptoSource.getRandomValues(bytes);
    } else {
      for (let index = 0; index < bytes.length; index += 1) {
        bytes[index] = Math.floor(Math.random() * 256);
      }
    }
    let text = '';
    for (const byte of bytes) {
      text += (byte % 36).toString(36);
    }
    return prefix + text;
  }

  /* ======================================================================
     The tools. Each handler is (input, records, now) → { ops, result } or { refused, result }:
     input is the tool's arguments as manifest.json "agent" describes them, with "when" already
     worked out by Midas ({ date, time, allDay, at, repeat, timeZone }, or null); records are this
     Sidekick's records as [{ key, value }]; now is an ISO instant. ops are whole records to set or
     keys to delete; nothing is written by a handler. A refusal changes nothing.
     ====================================================================== */

  const LIST_NAME_LIMIT = 40;
  // The page's MAX_RULES: early alerts per list
  const MAX_ALERTS = 5;
  const CONTEXT_ITEM_LIMIT = 200;
  const CONTEXT_TITLE_LIMIT = 120;
  const LEADING_WORDS = ['the', 'my', 'a', 'an'];

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

  function cleanText(value) {
    return typeof value === 'string' ? value.trim() : '';
  }

  /* ---------- Matching what was said to a reminder or a list ---------- */

  // Lower case, letters and digits only, single spaces
  function normalised(text) {
    return String(text || '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  }

  // "the dentist" is said for "Dentist"
  function withoutLeadingWord(text) {
    const words = text.split(' ');
    if (words.length > 1 && LEADING_WORDS.indexOf(words[0]) !== -1) {
      return words.slice(1).join(' ');
    }
    return text;
  }

  function containsWords(longer, shorter) {
    return (' ' + longer + ' ').indexOf(' ' + shorter + ' ') !== -1;
  }

  // The candidates named by what was said: the exact name first; else every name that holds the
  // words said ("dentist" for "Dentist appointment"). Words that hold a whole name are not a
  // match ("pills for Mom" is not "Pills"). Two or more matches are returned as they are: the
  // caller refuses rather than guess.
  function matchByName(said, candidates, nameOf) {
    const target = normalised(said);
    if (target === '') {
      return [];
    }
    const shortTarget = withoutLeadingWord(target);
    const exact = [];
    for (const candidate of candidates) {
      const name = normalised(nameOf(candidate));
      if (name === target || name === shortTarget) {
        exact.push(candidate);
      }
    }
    if (exact.length > 0) {
      return exact;
    }
    const partial = [];
    for (const candidate of candidates) {
      const name = normalised(nameOf(candidate));
      if (name === '') {
        continue;
      }
      if (containsWords(name, shortTarget)) {
        partial.push(candidate);
      }
    }
    return partial;
  }

  function titleOfEntry(entry) {
    return entry.item.title;
  }

  function nameOfList(list) {
    return list.name;
  }

  function namesOf(entries) {
    const names = [];
    for (const entry of entries) {
      names.push(entry.item.title);
    }
    return names.join(', ');
  }

  /* ---------- Reading the records ---------- */

  function entriesOf(records) {
    const entries = [];
    for (const record of records) {
      if (record.key.indexOf('reminder:') !== 0 || !Logic.isItemRecord(record.key, record.value)) {
        continue;
      }
      entries.push({ item: Logic.itemFromRecord(record.key, record.value), key: record.key, value: record.value });
    }
    return entries;
  }

  function listsOf(records) {
    const lists = {};
    for (const record of records) {
      if (record.key.indexOf('list:') !== 0 || !record.value) {
        continue;
      }
      const list = listFromRecord(record.key, record.value);
      lists[list.id] = { list: list, value: record.value };
    }
    return lists;
  }

  function listArray(lists) {
    const result = [];
    for (const id of Object.keys(lists)) {
      result.push(lists[id].list);
    }
    return result;
  }

  function listOfItem(item, lists) {
    return item.list && lists[item.list] ? lists[item.list].list : undefined;
  }

  // Done for now: a one-time reminder ticked, or a repeat whose shown time is ticked
  function isDoneNow(item, nowMs) {
    if (item.done) {
      return true;
    }
    if (!Logic.isRepeating(item)) {
      return false;
    }
    const shown = Logic.displayState(item, nowMs, deviceTimeZone());
    return shown.state !== 'overdue' && shown.state !== 'upcoming';
  }

  // Something the page lets the user undo: a row it shows as done, with its "Not Done" button.
  // The page shows a done reminder only on the day it was done (its shownItems), so a Done from
  // an earlier day, or a repeat now showing its next time, cannot be undone (founder, 2026-10-21:
  // tools accept only what the page offers).
  function showsNotDone(item, nowMs) {
    const zone = deviceTimeZone();
    const shown = Logic.displayState(item, nowMs, zone);
    if (shown.state !== 'done') {
      return false;
    }
    const today = Logic.localDateOf(nowMs, zone);
    const doneDay = item.completedAt ? Logic.localDateOf(item.completedAt, zone) : Logic.localDateOf(shown.at, zone);
    return doneDay === today || Logic.localDateOf(shown.at, zone) === today;
  }

  function onlyEntries(entries, keep) {
    const kept = [];
    for (const entry of entries) {
      if (keep(entry)) {
        kept.push(entry);
      }
    }
    return kept;
  }

  // One reminder named by what was said. Names are matched over every reminder first, so an
  // exact title wins even when the action cannot apply to it; then only the reminders the action
  // applies to stay. Two that fit refuse.
  function findOne(said, entries, applies, notApplicable) {
    const matches = matchByName(said, entries, titleOfEntry);
    if (matches.length === 0) {
      return { problem: refuse('not-found', 'No reminder named ' + cleanText(said)) };
    }
    const applicable = applies ? onlyEntries(matches, applies) : matches;
    if (applicable.length === 0) {
      return { problem: refuse(notApplicable, notApplicableText(notApplicable) + namesOf(matches)) };
    }
    if (applicable.length > 1) {
      return { problem: refuse('ambiguous', 'More than one match: ' + namesOf(applicable)) };
    }
    return { entry: applicable[0] };
  }

  function notApplicableText(reason) {
    if (reason === 'already-done') {
      return 'Already done: ';
    }
    if (reason === 'not-done') {
      return 'Not done yet: ';
    }
    return 'Can’t change: ';
  }

  function findList(said, lists) {
    const matches = matchByName(said, listArray(lists), nameOfList);
    if (matches.length === 0) {
      return { problem: refuse('unknown-list', 'No list named ' + cleanText(said)) };
    }
    if (matches.length > 1) {
      const names = [];
      for (const list of matches) {
        names.push(list.name);
      }
      return { problem: refuse('ambiguous', 'More than one list: ' + names.join(', ')) };
    }
    return { list: matches[0] };
  }

  /* ---------- Times: what the page's sheet would hold ---------- */

  // The page's nextWholeHour, from now: a new reminder's default time
  function nextWholeHour(nowMs, timeZone) {
    const wallClock = Logic.instantToWallClock(nowMs + 3600000, timeZone);
    return wallClock.time.slice(0, 2) + ':00';
  }

  // Every care reminder has a date and a time. Nothing said: today at the next whole hour, as the
  // page's Add sheet starts. A day without a time: the next whole hour today, else 09:00.
  function dateAndTime(when, nowMs, timeZone) {
    const today = Logic.localDateOf(nowMs, timeZone);
    if (!when || !when.date) {
      return { date: today, time: nextWholeHour(nowMs, timeZone) };
    }
    if (when.allDay || !when.time) {
      return { date: when.date, time: when.date === today ? nextWholeHour(nowMs, timeZone) : '09:00' };
    }
    return { date: when.date, time: when.time };
  }

  // Every N hours is the page's own repeat; else the repeat that was said
  function repeatOf(when, everyHours) {
    if (everyHours === 2 || everyHours === 3 || everyHours === 4) {
      return { every: 'hour', interval: everyHours };
    }
    if (when && when.date && when.repeat) {
      return Logic.cleanRepeat(when.repeat);
    }
    return null;
  }

  // Sunday 0 .. Saturday 6 of a YYYY-MM-DD date
  function weekdayOfDate(date) {
    const parts = date.split('-');
    return new Date(Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))).getUTCDay();
  }

  // The repeat as one of the page's Repeat menu choices, or null when the page has no such choice
  // (founder, 2026-10-21: tools accept only what the page offers). "Every Friday" said for a
  // Friday is the page's Every Week, which repeats on the reminder's own day.
  function pageRepeat(repeat, date) {
    if (repeat === null) {
      return { repeat: null };
    }
    const asPage = Logic.copyJson(repeat);
    const sameDay = asPage.every === 'week' && Array.isArray(asPage.weekdays) && asPage.weekdays.length === 1 && asPage.weekdays[0] === weekdayOfDate(date);
    if (sameDay) {
      delete asPage.weekdays;
    }
    if (Logic.optionForRepeat(asPage) === 'custom') {
      return null;
    }
    return { repeat: Logic.cleanRepeat(asPage) };
  }

  function repeatNotOffered() {
    return refuse('repeat-not-offered', 'No such repeat on the page');
  }

  /* ---------- add ---------- */

  function addReminder(input, records, now) {
    const title = cleanText(input.title);
    if (title === '') {
      return refuse('no-title', 'No title');
    }
    const lists = listsOf(records);
    const found = findList(input.list, lists);
    if (found.problem) {
      return found.problem;
    }
    const nowMs = Date.parse(now);
    const when = input.when || null;
    const timeZone = when && when.timeZone ? when.timeZone : deviceTimeZone();
    const moment = dateAndTime(when, nowMs, timeZone);
    const offered = pageRepeat(repeatOf(when, input.everyHours), moment.date);
    if (offered === null) {
      return repeatNotOffered();
    }
    // The page's saveReminderTask, new reminder
    const itemId = newId('i');
    const item = {
      id: itemId, title: title, list: found.list.id, date: moment.date, time: moment.time, repeat: offered.repeat,
      timeZone: timeZone, done: false, completedAt: null, doneThrough: null, lastDoneAt: null,
      slotsDone: {}, alerts: [], createdAt: now
    };
    item.alerts = Logic.rulesForItem(item, found.list);
    const value = Logic.recordFromItem(item, null);
    return done([setOp(Logic.itemKey(itemId), value)], 'Added ' + title, { at: value.at, allDay: false });
  }

  /* ---------- edit ---------- */

  function editReminder(input, records, now) {
    const found = findOne(input.item, entriesOf(records), null, null);
    if (found.problem) {
      return found.problem;
    }
    const entry = found.entry;
    const lists = listsOf(records);
    const item = Logic.itemFromRecord(entry.key, entry.value);
    const when = input.when || null;
    const title = cleanText(input.title) || item.title;
    let date = item.date;
    let time = item.time;
    let repeat = Logic.cleanRepeat(item.repeat);
    if (when && when.date) {
      const moment = dateAndTime(when, Date.parse(now), item.timeZone);
      date = moment.date;
      time = moment.time;
      repeat = repeatOf(when, input.everyHours);
    } else if (input.everyHours === 2 || input.everyHours === 3 || input.everyHours === 4) {
      repeat = repeatOf(null, input.everyHours);
    }
    // A repeat this edit sets must be one the page offers; one already stored stays as it is
    if (JSON.stringify(repeat) !== JSON.stringify(Logic.cleanRepeat(item.repeat))) {
      const offered = pageRepeat(repeat, date);
      if (offered === null) {
        return repeatNotOffered();
      }
      repeat = offered.repeat;
    }
    // The page's saveReminderTask, edit: a reminder moved to a new time starts again, not done
    const moved = item.date !== date || item.time !== time || JSON.stringify(item.repeat) !== JSON.stringify(repeat);
    if (!moved && title === item.title) {
      return refuse('nothing-to-change', 'Nothing to change');
    }
    item.title = title;
    item.date = date;
    item.time = time;
    item.repeat = repeat;
    if (moved) {
      item.done = false;
      item.completedAt = null;
      item.doneThrough = null;
      item.lastDoneAt = null;
      item.slotsDone = {};
    }
    item.alerts = Logic.rulesForItem(item, listOfItem(item, lists));
    const value = Logic.recordFromItem(item, entry.value);
    if (moved) {
      delete value.lastDoneAt;
    }
    return done([setOp(entry.key, value)], 'Changed ' + title, { at: value.at, allDay: false });
  }

  /* ---------- done and undo ---------- */

  function completeReminder(input, records, now) {
    const nowMs = Date.parse(now);
    const entries = entriesOf(records);
    function isOpenNow(entry) {
      return !isDoneNow(entry.item, nowMs);
    }
    const found = findOne(input.item, entries, isOpenNow, 'already-done');
    if (found.problem) {
      return found.problem;
    }
    const entry = found.entry;
    const lists = listsOf(records);
    const value = entry.value;
    const item = Logic.itemFromRecord(entry.key, value);
    // The page's markDoneTask
    if (Logic.isRepeating(item)) {
      const shown = Logic.displayState(item, nowMs, deviceTimeZone());
      if (shown.state !== 'overdue' && shown.state !== 'upcoming') {
        return refuse('already-done', 'Already done: ' + item.title);
      }
      item.lastDoneAt = now;
      const through = Logic.instantMs(item.doneThrough);
      if (Number.isNaN(through) || shown.at > through) {
        item.doneThrough = new Date(shown.at).toISOString();
      }
    } else {
      item.done = true;
      item.completedAt = now;
    }
    item.alerts = Logic.rulesForItem(item, listOfItem(item, lists));
    item.snoozes = Logic.withoutAlertSnoozes(item.snoozes);
    const record = Logic.recordFromItem(item, value);
    delete record.snoozedUntil;
    return done([setOp(entry.key, record)], 'Marked done: ' + item.title);
  }

  function uncompleteReminder(input, records, now) {
    const nowMs = Date.parse(now);
    function showsNotDoneEntry(entry) {
      return showsNotDone(entry.item, nowMs);
    }
    const found = findOne(input.item, entriesOf(records), showsNotDoneEntry, 'not-done');
    if (found.problem) {
      return found.problem;
    }
    const entry = found.entry;
    const lists = listsOf(records);
    const value = entry.value;
    const item = Logic.itemFromRecord(entry.key, value);
    // The page's markNotDoneTask
    item.alerts = Logic.rulesForItem(item, listOfItem(item, lists));
    const record = Logic.recordFromItem(item, value);
    if (Logic.isRepeating(item)) {
      const through = Logic.effectiveDoneThrough(item);
      const previous = Logic.latestOccurrenceAtOrBefore(item, through - 1);
      if (previous === null) {
        delete record.doneThrough;
      } else {
        record.doneThrough = new Date(previous).toISOString();
      }
      delete record.lastDoneAt;
      delete record.slotsDone;
    } else {
      record.done = false;
      delete record.completedAt;
    }
    return done([setOp(entry.key, record)], 'Marked not done: ' + item.title);
  }

  /* ---------- delete ---------- */

  function deleteReminder(input, records) {
    const found = findOne(input.item, entriesOf(records), null, null);
    if (found.problem) {
      return found.problem;
    }
    return done([deleteOp(found.entry.key)], 'Deleted ' + found.entry.item.title);
  }

  /* ---------- lists ---------- */

  // The page's nextListOrder over the stored lists
  function nextListOrder(lists) {
    let highest = -1;
    for (const list of listArray(lists)) {
      highest = Math.max(highest, list.order);
    }
    return highest + 1;
  }

  function knownColour(colourId) {
    for (const colour of Logic.COLOURS) {
      if (colour.id === colourId) {
        return true;
      }
    }
    return false;
  }

  function knownIcon(iconName) {
    for (const tab of ICON_TABS) {
      if (tab.icons.indexOf(iconName) !== -1) {
        return true;
      }
    }
    return false;
  }

  // The page's saveListTask: the list written, then every reminder of the list rewritten so it
  // carries the list's alert rules. Only the reminders whose record changes are written.
  function listSaveOps(list, lists, records) {
    const existing = lists[list.id] ? lists[list.id].value : null;
    const ops = [setOp('list:' + list.id, listRecordFromList(list, existing))];
    for (const entry of entriesOf(records)) {
      if (entry.item.list !== list.id) {
        continue;
      }
      const item = Logic.itemFromRecord(entry.key, entry.value);
      item.alerts = Logic.rulesForItem(item, list);
      const value = Logic.recordFromItem(item, entry.value);
      if (JSON.stringify(value) !== JSON.stringify(entry.value)) {
        ops.push(setOp(entry.key, value));
      }
    }
    return ops;
  }

  function sameName(lists, name, exceptId) {
    for (const list of listArray(lists)) {
      if (list.id !== exceptId && normalised(list.name) === normalised(name)) {
        return list;
      }
    }
    return null;
  }

  function createList(input, records, now) {
    const name = cleanText(input.name).slice(0, LIST_NAME_LIMIT);
    if (name === '') {
      return refuse('no-name', 'No list name');
    }
    const lists = listsOf(records);
    const clash = sameName(lists, name, null);
    if (clash) {
      return refuse('list-exists', 'Already a list: ' + clash.name);
    }
    if ((input.color && !knownColour(input.color)) || (input.icon && !knownIcon(input.icon))) {
      return refuse('bad-style', 'Unknown colour or icon');
    }
    const list = {
      id: newId('l'), name: name, icon: input.icon || 'list', color: input.color || 'charcoal',
      alerts: [], order: nextListOrder(lists), createdAt: now
    };
    return done(listSaveOps(list, lists, records), 'Added list ' + name);
  }

  function editList(input, records) {
    const lists = listsOf(records);
    const found = findList(input.list, lists);
    if (found.problem) {
      return found.problem;
    }
    const list = Object.assign({}, found.list);
    const name = cleanText(input.name).slice(0, LIST_NAME_LIMIT);
    if (name !== '') {
      const clash = sameName(lists, name, list.id);
      if (clash) {
        return refuse('list-exists', 'Already a list: ' + clash.name);
      }
      list.name = name;
    }
    if ((input.color && !knownColour(input.color)) || (input.icon && !knownIcon(input.icon))) {
      return refuse('bad-style', 'Unknown colour or icon');
    }
    list.color = input.color || list.color;
    list.icon = input.icon || list.icon;
    if (list.name === found.list.name && list.color === found.list.color && list.icon === found.list.icon) {
      return refuse('nothing-to-change', 'Nothing to change');
    }
    list.alerts = withRuleIds(list.alerts);
    return done(listSaveOps(list, lists, records), 'Changed list ' + list.name);
  }

  // The page's deleteListTask: the list and every reminder in it
  function deleteList(input, records) {
    const lists = listsOf(records);
    const found = findList(input.list, lists);
    if (found.problem) {
      return found.problem;
    }
    const ops = [];
    for (const entry of entriesOf(records)) {
      if (entry.item.list === found.list.id) {
        ops.push(deleteOp(entry.key));
      }
    }
    ops.push(deleteOp('list:' + found.list.id));
    return done(ops, 'Deleted list ' + found.list.name);
  }

  // The rule said: the kind's defaults (the page's makeRule) with what was said over them
  function ruleFromInput(input) {
    const rule = Logic.makeRule(input.kind);
    if (input.kind === 'daysBefore' && Number.isInteger(input.days)) {
      rule.days = input.days;
    }
    if (input.kind === 'before' && Number.isInteger(input.minutes)) {
      rule.minutes = input.minutes;
    }
    if ((input.kind === 'daysBefore' || input.kind === 'morningOf') && typeof input.time === 'string' && /^\d{2}:\d{2}$/.test(input.time)) {
      rule.time = input.time;
    }
    return Logic.cleanRule(rule);
  }

  function ruleWithoutId(rule) {
    const copy = Object.assign({}, Logic.cleanRule(rule));
    delete copy.id;
    return JSON.stringify(copy);
  }

  // Only the page's own choices: 1 to 14 days, one of its "How Long" steps (founder, 2026-10-21)
  function alertOffered(input) {
    if (input.kind === 'daysBefore' && Number.isInteger(input.days) && (input.days < 1 || input.days > MAX_DAYS_BEFORE)) {
      return false;
    }
    if (input.kind === 'before' && Number.isInteger(input.minutes) && BEFORE_STEPS.indexOf(input.minutes) === -1) {
      return false;
    }
    return true;
  }

  function addListAlert(input, records) {
    if (!alertOffered(input)) {
      return refuse('alert-not-offered', 'No such alert on the page');
    }
    const lists = listsOf(records);
    const found = findList(input.list, lists);
    if (found.problem) {
      return found.problem;
    }
    const list = Object.assign({}, found.list);
    if (list.alerts.length >= MAX_ALERTS) {
      return refuse('too-many-alerts', 'Already ' + MAX_ALERTS + ' alerts');
    }
    const rule = ruleFromInput(input);
    for (const existing of list.alerts) {
      if (ruleWithoutId(existing) === ruleWithoutId(rule)) {
        return refuse('nothing-to-change', 'Already set: ' + Logic.ruleLabel(rule));
      }
    }
    list.alerts = withRuleIds(list.alerts.concat([rule]));
    return done(listSaveOps(list, lists, records), 'Added alert: ' + Logic.ruleLabel(rule));
  }

  // The rules that fit what was said: same kind, and the same days, minutes or time where said
  function rulesMatching(rules, input) {
    const matches = [];
    for (const rule of rules) {
      if (rule.kind !== input.kind) {
        continue;
      }
      if (Number.isInteger(input.days) && rule.days !== input.days) {
        continue;
      }
      if (Number.isInteger(input.minutes) && rule.minutes !== input.minutes) {
        continue;
      }
      if (typeof input.time === 'string' && rule.time !== undefined && rule.time !== input.time) {
        continue;
      }
      matches.push(rule);
    }
    return matches;
  }

  function removeListAlert(input, records) {
    const lists = listsOf(records);
    const found = findList(input.list, lists);
    if (found.problem) {
      return found.problem;
    }
    const list = Object.assign({}, found.list);
    const matches = rulesMatching(list.alerts, input);
    if (matches.length === 0) {
      return refuse('not-found', 'No such alert on ' + list.name);
    }
    if (matches.length > 1) {
      return refuse('ambiguous', 'More than one alert fits');
    }
    const kept = [];
    for (const rule of list.alerts) {
      if (rule !== matches[0]) {
        kept.push(rule);
      }
    }
    list.alerts = withRuleIds(kept);
    return done(listSaveOps(list, lists, records), 'Removed alert: ' + Logic.ruleLabel(matches[0]));
  }

  /* ---------- What jess is told about this Sidekick's records ---------- */

  function contextRule(rule) {
    return Logic.ruleLabel(rule);
  }

  // The user's own lists (with their alerts) and reminders, small
  function buildContext(records, now) {
    const nowMs = Date.parse(now);
    const lists = listsOf(records);
    const contextLists = [];
    for (const list of listArray(lists)) {
      const alerts = [];
      for (const rule of list.alerts) {
        alerts.push(contextRule(rule));
      }
      contextLists.push({ name: list.name, alerts: alerts });
    }
    const items = [];
    for (const entry of entriesOf(records).slice(0, CONTEXT_ITEM_LIMIT)) {
      const item = entry.item;
      const list = listOfItem(item, lists);
      items.push({
        title: item.title.slice(0, CONTEXT_TITLE_LIMIT), list: list ? list.name : null, when: item.date + ' ' + item.time,
        repeat: Logic.optionForRepeat(item.repeat), done: isDoneNow(item, nowMs)
      });
    }
    return { lists: contextLists, items: items };
  }

  return {
    context: buildContext,
    handlers: {
      add: addReminder,
      edit: editReminder,
      complete: completeReminder,
      uncomplete: uncompleteReminder,
      delete: deleteReminder,
      create_list: createList,
      edit_list: editList,
      delete_list: deleteList,
      add_list_alert: addListAlert,
      remove_list_alert: removeListAlert
    }
  };
})();

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSidekickTools;
}
