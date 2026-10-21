// Reminders tools: every action a person can take in this Sidekick, as functions jess (and later
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
var MidasSidekickTools = (function createRemindersTools() {
  'use strict';

  /* copied from index.html: begin */
var RemindersLogic = (function createRemindersLogic() {
  'use strict';

  const DAY_MS = 86400000;
  // An all-day reminder is booked at 09:00 local (the engine needs a moment to notify).
  const ALL_DAY_TIME = '09:00';
  const HISTORY_PER_RECORD = 200;
  // Repeats are searched day by day; this bounds the search (about 110 years).
  const SEARCH_LIMIT_DAYS = 40000;
  const BUILTIN_IDS = ['today', 'next7', 'scheduled', 'unscheduled', 'all', 'pastDue', 'completed'];
  // Built-in lists added after people already saved an order, and the list each goes after
  const LATER_BUILTINS = [{ id: 'next7', after: 'today' }];
  const REPEAT_OPTION_KEYS = ['never', 'daily', 'weekdays', 'weekends', 'weekly', 'monthly'];
  const UNTITLED = 'Untitled';
  const formatterCache = {};

  /* ---------- Small helpers ---------- */

  function pad2(number) {
    return number < 10 ? '0' + number : String(number);
  }

  function pad4(number) {
    const text = String(number);
    return text.length >= 4 ? text : '0000'.slice(text.length) + text;
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
    if (value instanceof Date || (typeof value === 'object' && typeof value.getTime === 'function')) {
      return value.getTime();
    }
    return Date.parse(String(value));
  }

  // A date field as stored in a record: ISO 8601 text only (null for anything else)
  function storedInstant(value) {
    return typeof value === 'string' && value !== '' ? value : null;
  }

  function isoOrNull(value) {
    const milliseconds = instantMs(value);
    if (Number.isNaN(milliseconds)) {
      return null;
    }
    return new Date(milliseconds).toISOString();
  }

  function copyJson(value) {
    if (value === null || value === undefined) {
      return null;
    }
    return JSON.parse(JSON.stringify(value));
  }

  /* ---------- Time zones ---------- */

  function partsFormatter(timeZone) {
    const cached = formatterCache[timeZone];
    if (cached) {
      return cached;
    }
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timeZone, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
      hour: 'numeric', minute: 'numeric', second: 'numeric'
    });
    formatterCache[timeZone] = formatter;
    return formatter;
  }

  function zonedFields(milliseconds, timeZone) {
    const parts = partsFormatter(timeZone).formatToParts(new Date(milliseconds));
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

  // Wall-clock date and time in a zone, as the instant it names. A time skipped by a
  // daylight-saving jump moves past the jump.
  function wallClockToInstant(dateText, timeText, timeZone) {
    const date = parseDateText(dateText);
    const time = parseTimeText(timeText || ALL_DAY_TIME);
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
    const weekday = new Date(Date.UTC(fields.year, fields.month - 1, fields.day)).getUTCDay();
    return {
      date: fields.year + '-' + pad2(fields.month) + '-' + pad2(fields.day),
      time: pad2(fields.hour) + ':' + pad2(fields.minute),
      weekday: weekday
    };
  }

  function localDateOf(instant, timeZone) {
    return instantToWallClock(instant, timeZone).date;
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

  function weekdayOf(dateText) {
    return weekdayOfDayNumber(dayNumber(dateText));
  }

  /* Weeks start on Monday, months on the 1st */
  function weekRange(now, timeZone) {
    const today = localDateOf(now, timeZone);
    const sinceMonday = (weekdayOf(today) + 6) % 7;
    const start = addDays(today, -sinceMonday);
    return { start: start, end: addDays(start, 6) };
  }

  function monthRange(now, timeZone) {
    const today = parseDateText(localDateOf(now, timeZone));
    const start = today.year + '-' + pad2(today.month) + '-01';
    const nextMonth = today.month === 12 ? (today.year + 1) + '-01-01' : today.year + '-' + pad2(today.month + 1) + '-01';
    return { start: start, end: addDays(nextMonth, -1) };
  }

  /* 12-hour times everywhere, e.g. 6:00 PM */
  function formatTime12(timeText) {
    const time = parseTimeText(timeText);
    const suffix = time.hour < 12 ? 'AM' : 'PM';
    const shown = time.hour % 12 === 0 ? 12 : time.hour % 12;
    return shown + ':' + pad2(time.minute) + ' ' + suffix;
  }

  /* ---------- Repeats (NOTIFICATIONS.md 4.3) ---------- */

  function presetRepeat(optionKey) {
    if (optionKey === 'daily') {
      return { every: 'day' };
    }
    if (optionKey === 'weekdays') {
      return { every: 'week', weekdays: [1, 2, 3, 4, 5] };
    }
    if (optionKey === 'weekends') {
      return { every: 'week', weekdays: [0, 6] };
    }
    if (optionKey === 'weekly') {
      return { every: 'week' };
    }
    if (optionKey === 'monthly') {
      return { every: 'month' };
    }
    return null;
  }

  function repeatForOption(optionKey) {
    return presetRepeat(optionKey);
  }

  // The repeat as the engine wants it: interval only above 1, weekdays sorted and weekly only
  function cleanRepeat(repeat) {
    if (!repeat || !repeat.every) {
      return null;
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
    if (!cleaned) {
      return 'never';
    }
    if (cleaned.until !== undefined) {
      return 'custom';
    }
    const cleanedText = JSON.stringify(cleaned);
    for (const key of REPEAT_OPTION_KEYS) {
      const preset = presetRepeat(key);
      if (preset && JSON.stringify(preset) === cleanedText) {
        return key;
      }
    }
    return 'custom';
  }

  function isRepeating(item) {
    return Boolean(item.date && item.repeat && item.repeat.every);
  }

  function zoneOfItem(item) {
    return item.timeZone || deviceTimeZone();
  }

  function repeatMatchesDay(repeat, startDay, day) {
    if (day < startDay) {
      return false;
    }
    const interval = Number(repeat.interval || 1);
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

  function occurrenceMs(item, day) {
    return wallClockToInstant(dateOfDayNumber(day), item.time, zoneOfItem(item)).getTime();
  }

  function untilMsOf(item) {
    const until = instantMs(item.repeat.until);
    return Number.isNaN(until) ? Infinity : until;
  }

  // The latest occurrence at or before a moment, or null
  function latestOccurrenceAtOrBefore(item, limitMs) {
    const zone = zoneOfItem(item);
    const startDay = dayNumber(item.date);
    const untilMs = untilMsOf(item);
    const lastAllowed = Math.min(limitMs, untilMs);
    if (lastAllowed === -Infinity || Number.isNaN(lastAllowed)) {
      return null;
    }
    const lastDay = dayNumber(localDateOf(lastAllowed, zone));
    for (let day = lastDay; day >= startDay && lastDay - day < SEARCH_LIMIT_DAYS; day -= 1) {
      if (!repeatMatchesDay(item.repeat, startDay, day)) {
        continue;
      }
      const moment = occurrenceMs(item, day);
      if (moment <= lastAllowed) {
        return moment;
      }
    }
    return null;
  }

  // The first occurrence strictly after a moment, or null when the repeat has ended
  function firstOccurrenceAfter(item, afterMs) {
    const zone = zoneOfItem(item);
    const startDay = dayNumber(item.date);
    const untilMs = untilMsOf(item);
    const fromDay = Number.isFinite(afterMs) ? Math.max(startDay, dayNumber(localDateOf(afterMs, zone))) : startDay;
    const lastDay = untilMs === Infinity ? Infinity : dayNumber(localDateOf(untilMs, zone));
    for (let day = fromDay; day <= lastDay && day - fromDay < SEARCH_LIMIT_DAYS; day += 1) {
      if (!repeatMatchesDay(item.repeat, startDay, day)) {
        continue;
      }
      const moment = occurrenceMs(item, day);
      if (moment > afterMs && moment <= untilMs) {
        return moment;
      }
      if (moment > untilMs) {
        return null;
      }
    }
    return null;
  }

  function nthOccurrence(item, count) {
    let moment = -Infinity;
    for (let index = 0; index < count; index += 1) {
      const next = firstOccurrenceAfter(item, moment);
      if (next === null) {
        return null;
      }
      moment = next;
    }
    return moment;
  }

  /* ---------- Records (NOTIFICATIONS.md 4.2) ---------- */

  // Every item is a reminder:, dated or not (unified data, 2026-10-15)
  function recordKey(item) {
    return 'reminder:' + item.id;
  }

  function idFromKey(key) {
    const colon = key.indexOf(':');
    return colon === -1 ? key : key.slice(colon + 1);
  }

  function setOrDelete(target, field, value) {
    if (value === null || value === undefined || value === '') {
      delete target[field];
    } else {
      target[field] = value;
    }
  }

  // The record for an item (reminders.item in manifest.json). Fields written by the shell
  // (snoozedUntil, lastDoneAt) and fields this page does not know are kept from the existing
  // value; a new time clears an old snooze. A field is left out instead of null.
  function recordFromItem(item, existing) {
    const value = {};
    if (existing && typeof existing === 'object') {
      for (const field of Object.keys(existing)) {
        value[field] = existing[field];
      }
    }
    const zone = item.timeZone || value.timeZone || deviceTimeZone();
    value.$type = 'reminders.item';
    value.title = item.title;
    setOrDelete(value, 'notes', item.notes);
    setOrDelete(value, 'list', item.list);
    value.done = item.done === true;
    value.timeZone = zone;
    setOrDelete(value, 'completedAt', item.completedAt);
    setOrDelete(value, 'createdAt', item.createdAt);
    setOrDelete(value, 'source', item.source);
    setOrDelete(value, 'lastDoneAt', item.lastDoneAt);
    if (item.date) {
      const at = wallClockToInstant(item.date, item.time, zone).toISOString();
      const previousAt = existing ? instantMs(storedInstant(existing.at)) : NaN;
      const moved = !Number.isNaN(previousAt) && previousAt !== Date.parse(at);
      value.at = at;
      value.allDay = !item.time;
      const repeat = isRepeating(item) ? cleanRepeat(item.repeat) : null;
      setOrDelete(value, 'repeat', repeat);
      if (moved) {
        delete value.snoozedUntil;
        delete value.doneThrough;
      } else {
        setOrDelete(value, 'snoozedUntil', item.snoozedUntil);
        setOrDelete(value, 'doneThrough', repeat ? item.doneThrough : null);
      }
    } else {
      delete value.at;
      delete value.allDay;
      delete value.repeat;
      delete value.snoozedUntil;
      delete value.doneThrough;
    }
    return value;
  }

  function itemFromRecord(key, value) {
    const record = value || {};
    const zone = record.timeZone || deviceTimeZone();
    const item = {
      id: idFromKey(key),
      title: typeof record.title === 'string' ? record.title : '',
      notes: typeof record.notes === 'string' ? record.notes : '',
      list: record.list || null,
      date: null,
      time: null,
      repeat: null,
      timeZone: zone,
      done: record.done === true,
      completedAt: storedInstant(record.completedAt),
      snoozedUntil: storedInstant(record.snoozedUntil),
      lastDoneAt: storedInstant(record.lastDoneAt),
      doneThrough: storedInstant(record.doneThrough),
      createdAt: storedInstant(record.createdAt),
      source: record.source || null
    };
    const atMs = instantMs(storedInstant(record.at));
    if (!Number.isNaN(atMs)) {
      const wallClock = instantToWallClock(atMs, zone);
      item.date = wallClock.date;
      item.time = record.allDay === true ? null : wallClock.time;
      item.repeat = cleanRepeat(record.repeat);
    }
    return item;
  }

  /* Completed history, packed many items to a record (the shell rewrites a file per write) */
  function packHistory(items, firstNumber) {
    const records = [];
    let number = firstNumber || 0;
    for (let start = 0; start < items.length; start += HISTORY_PER_RECORD) {
      const chunk = items.slice(start, start + HISTORY_PER_RECORD);
      records.push({ key: 'history:' + pad4(number), value: { $type: 'reminders.history', items: chunk } });
      number += 1;
    }
    return records;
  }

  function unpackHistory(records) {
    const items = [];
    for (const record of records || []) {
      const value = record && record.value;
      if (!value || !Array.isArray(value.items)) {
        continue;
      }
      for (const item of value.items) {
        items.push(item);
      }
    }
    return items;
  }

  function historyNumber(key) {
    const number = Number(idFromKey(key));
    return Number.isFinite(number) ? number : -1;
  }

  /* ---------- Where a reminder shows ---------- */

  function makeEntry(item, moment, pastDue, timeZone) {
    if (moment === null) {
      return { item: item, at: null, pastDue: false, day: null, time: null };
    }
    const wallClock = instantToWallClock(moment, timeZone);
    return { item: item, at: new Date(moment), pastDue: pastDue, day: wallClock.date, time: item.time ? wallClock.time : null };
  }

  // A timed reminder is past due once its moment passes; an all-day one once its day ends
  function placeMoment(placement, item, moment, nowMs, timeZone, todayText) {
    const day = localDateOf(moment, timeZone);
    const pastDue = item.time ? moment <= nowMs : day < todayText;
    const entry = makeEntry(item, moment, pastDue, timeZone);
    if (day === todayText) {
      placement.today = entry;
      if (!pastDue) {
        placement.upcoming = entry;
      }
    } else if (day > todayText) {
      placement.upcoming = entry;
    } else {
      placement.overdue = entry;
    }
  }

  function latestOf(values) {
    let latest = -Infinity;
    for (const value of values) {
      if (!Number.isNaN(value) && value > latest) {
        latest = value;
      }
    }
    return latest;
  }

  // Occurrences up to here are dealt with: done from a notification or this page, or before the reminder existed
  function handledThroughOf(item) {
    return latestOf([instantMs(item.lastDoneAt), instantMs(item.doneThrough), instantMs(item.createdAt) - 1]);
  }

  function placeRepeat(placement, item, nowMs, timeZone, todayText) {
    const handledThrough = handledThroughOf(item);
    const latest = latestOccurrenceAtOrBefore(item, nowMs);
    const missed = latest !== null && latest > handledThrough ? latest : null;
    const snoozedUntil = instantMs(item.snoozedUntil);
    if (missed !== null) {
      const effective = snoozedUntil > missed ? snoozedUntil : missed;
      placeMoment(placement, item, effective, nowMs, timeZone, todayText);
    }
    const next = firstOccurrenceAfter(item, Math.max(nowMs, handledThrough));
    if (next !== null) {
      const nextEntry = makeEntry(item, next, false, timeZone);
      if (!placement.upcoming) {
        placement.upcoming = nextEntry;
      }
      if (!placement.today && nextEntry.day === todayText) {
        placement.today = nextEntry;
      }
    }
    if (missed === null && next === null) {
      // The repeat has ended: nothing more will come
      placement.done = true;
    }
  }

  // Where one item shows at a moment: today, upcoming (Scheduled, All, its list), overdue (Past Due)
  function placeItem(item, now, timeZone) {
    const nowMs = instantMs(now);
    const todayText = localDateOf(nowMs, timeZone);
    const placement = { done: false, undated: null, today: null, upcoming: null, overdue: null };
    if (item.done) {
      placement.done = true;
      return placement;
    }
    if (!item.date) {
      placement.undated = makeEntry(item, null, false, timeZone);
      return placement;
    }
    if (isRepeating(item)) {
      placeRepeat(placement, item, nowMs, timeZone, todayText);
      return placement;
    }
    let moment = wallClockToInstant(item.date, item.time, zoneOfItem(item)).getTime();
    const snoozedUntil = instantMs(item.snoozedUntil);
    if (snoozedUntil > moment) {
      moment = snoozedUntil;
    }
    placeMoment(placement, item, moment, nowMs, timeZone, todayText);
    return placement;
  }

  function createdMs(item) {
    const created = instantMs(item.createdAt);
    return Number.isNaN(created) ? 0 : created;
  }

  function compareIds(first, second) {
    const firstId = String(first.item.id);
    const secondId = String(second.item.id);
    if (firstId === secondId) {
      return 0;
    }
    return firstId < secondId ? -1 : 1;
  }

  function compareByCreated(first, second) {
    const difference = createdMs(first.item) - createdMs(second.item);
    return difference !== 0 ? difference : compareIds(first, second);
  }

  // Same day: all-day first, then by time
  function compareByMoment(first, second) {
    if (first.day !== second.day) {
      return first.day < second.day ? -1 : 1;
    }
    const firstAllDay = first.time === null;
    const secondAllDay = second.time === null;
    if (firstAllDay !== secondAllDay) {
      return firstAllDay ? -1 : 1;
    }
    const difference = first.at.getTime() - second.at.getTime();
    return difference !== 0 ? difference : compareByCreated(first, second);
  }

  function completedMs(item) {
    const candidates = [instantMs(item.completedAt), instantMs(item.lastDoneAt)];
    const latest = latestOf(candidates);
    return latest === -Infinity ? 0 : latest;
  }

  function compareByCompletedDesc(first, second) {
    const difference = completedMs(second.item) - completedMs(first.item);
    return difference !== 0 ? difference : compareIds(first, second);
  }

  function placeAll(items, now, timeZone) {
    const placements = [];
    for (const item of items) {
      placements.push(placeItem(item, now, timeZone));
    }
    return placements;
  }

  function itemsInList(items, listId, now, timeZone) {
    if (listId === 'next7') {
      return itemsInNext7(items, now, timeZone);
    }
    const placements = placeAll(items, now, timeZone);
    const dated = [];
    const byCreation = [];
    for (let index = 0; index < placements.length; index += 1) {
      const placement = placements[index];
      const item = items[index];
      if (listId === 'completed') {
        if (placement.done) {
          dated.push(makeEntry(item, null, false, timeZone));
        }
      } else if (listId === 'today') {
        if (placement.today) {
          dated.push(placement.today);
        }
      } else if (listId === 'pastDue') {
        if (placement.overdue) {
          dated.push(placement.overdue);
        }
      } else if (listId === 'scheduled') {
        if (placement.upcoming) {
          dated.push(placement.upcoming);
        }
      } else if (listId === 'unscheduled') {
        if (placement.undated && !item.list) {
          byCreation.push(placement.undated);
        }
      } else if (listId === 'all') {
        if (placement.upcoming) {
          dated.push(placement.upcoming);
        } else if (placement.undated) {
          byCreation.push(placement.undated);
        }
      } else if (item.list === listId) {
        if (placement.upcoming) {
          byCreation.push(placement.upcoming);
        } else if (placement.undated) {
          byCreation.push(placement.undated);
        }
      }
    }
    if (listId === 'completed') {
      dated.sort(compareByCompletedDesc);
      return dated;
    }
    dated.sort(compareByMoment);
    byCreation.sort(compareByCreated);
    return dated.concat(byCreation);
  }

  /* This Week and This Month: from today (including today's past due) to the week's or month's end.
     The page no longer shows them (Next 7 Days replaced them, 2026-10-11); kept for the existing logic tests. */
  function itemsInScope(items, scope, now, timeZone) {
    const range = scope === 'week' ? weekRange(now, timeZone) : monthRange(now, timeZone);
    const placements = placeAll(items, now, timeZone);
    const entries = [];
    for (const placement of placements) {
      if (placement.today) {
        entries.push(placement.today);
      } else if (placement.upcoming && placement.upcoming.day <= range.end) {
        entries.push(placement.upcoming);
      }
    }
    entries.sort(compareByMoment);
    return entries;
  }

  /* Next 7 Days: tomorrow through a week from today, rolling (not tied to where a week starts) */
  function next7Range(now, timeZone) {
    const today = localDateOf(instantMs(now), timeZone);
    return { start: addDays(today, 1), end: addDays(today, 7) };
  }

  // A repeat shows once, on its first open occurrence from tomorrow on; earlier ones belong to Today and Past Due
  function next7RepeatEntry(item, range, timeZone) {
    const startOfRangeMs = wallClockToInstant(range.start, '00:00', timeZone).getTime();
    const afterMs = Math.max(handledThroughOf(item), startOfRangeMs - 1);
    const next = firstOccurrenceAfter(item, afterMs);
    if (next === null) {
      return null;
    }
    return makeEntry(item, next, false, timeZone);
  }

  function itemsInNext7(items, now, timeZone) {
    const range = next7Range(now, timeZone);
    const nowMs = instantMs(now);
    const entries = [];
    for (const item of items) {
      if (item.done || !item.date) {
        continue;
      }
      let entry = null;
      if (isRepeating(item)) {
        entry = next7RepeatEntry(item, range, timeZone);
      } else {
        const placement = placeItem(item, nowMs, timeZone);
        entry = placement.upcoming;
      }
      if (entry && entry.day >= range.start && entry.day <= range.end) {
        entries.push(entry);
      }
    }
    entries.sort(compareByMoment);
    return entries;
  }

  // A saved sidebar order from before a built-in list existed gets that list in its place; the rest keeps its order
  function orderWithLaterBuiltins(savedOrder) {
    const order = Array.isArray(savedOrder) ? savedOrder.slice() : [];
    if (order.length === 0) {
      return order;
    }
    for (const later of LATER_BUILTINS) {
      if (order.indexOf(later.id) !== -1) {
        continue;
      }
      const afterIndex = order.indexOf(later.after);
      order.splice(afterIndex + 1, 0, later.id);
    }
    return order;
  }

  /* Which colour a reminder's circle takes (founder, 2026-10-11): its own list's colour when it has a list;
     with no list, blue when due today, the Scheduled colour when dated another day, grey when undated */
  function circleKind(item, hasList, now, timeZone) {
    if (hasList) {
      return 'list';
    }
    if (!item.date) {
      return 'unscheduled';
    }
    if (item.done) {
      return 'scheduled';
    }
    const placement = placeItem(item, now, timeZone);
    return placement.today ? 'today' : 'scheduled';
  }

  /* ---------- Apple Reminders export ---------- */

  // FNV-1a, so the same Apple reminder always gets the same id
  function hashText(text, seed) {
    let hash = seed >>> 0;
    for (let index = 0; index < text.length; index += 1) {
      hash ^= text.charCodeAt(index);
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    return hash >>> 0;
  }

  function stableId(prefix, text) {
    const first = hashText(text, 2166136261).toString(36);
    const second = hashText(text, 3735928559).toString(36);
    const padded = ('0000000' + first).slice(-7) + ('0000000' + second).slice(-7);
    return prefix + padded;
  }

  const APPLE_FREQUENCIES = { daily: 'day', weekly: 'week', monthly: 'month', yearly: 'year' };

  function hasEntries(value) {
    return Array.isArray(value) && value.length > 0;
  }

  // Apple's recurrence rule as an engine repeat, or { reason } when the engine cannot do it
  function repeatFromAppleRule(rule, item) {
    const every = APPLE_FREQUENCIES[rule.frequency];
    if (!every) {
      return { reason: 'repeats ' + rule.frequency };
    }
    const interval = Number(rule.interval || 1);
    if (!Number.isInteger(interval) || interval < 1 || interval > 999) {
      return { reason: 'repeats every ' + rule.interval + ' ' + every + 's' };
    }
    const repeat = { every: every };
    if (interval > 1) {
      repeat.interval = interval;
    }
    const start = parseDateText(item.date);
    if (hasEntries(rule.daysOfWeek)) {
      if (every !== 'week') {
        return { reason: 'repeats ' + rule.frequency + ' on a weekday of the month or year' };
      }
      const weekdays = [];
      for (const entry of rule.daysOfWeek) {
        if (entry.weekNumber) {
          return { reason: 'repeats on a numbered weekday' };
        }
        // Apple counts weekdays 1 (Sunday) to 7 (Saturday)
        const weekday = Number(entry.weekday) - 1;
        if (weekdays.indexOf(weekday) === -1) {
          weekdays.push(weekday);
        }
      }
      weekdays.sort(compareNumbers);
      const onlyStartDay = weekdays.length === 1 && weekdays[0] === weekdayOf(item.date);
      if (!onlyStartDay) {
        repeat.weekdays = weekdays;
      }
    }
    if (hasEntries(rule.daysOfMonth)) {
      const sameDay = every === 'month' && rule.daysOfMonth.length === 1 && Number(rule.daysOfMonth[0]) === start.day;
      if (!sameDay) {
        return { reason: 'repeats on chosen days of the month' };
      }
    }
    if (hasEntries(rule.monthsOfYear)) {
      const sameMonth = every === 'year' && rule.monthsOfYear.length === 1 && Number(rule.monthsOfYear[0]) === start.month;
      if (!sameMonth) {
        return { reason: 'repeats in chosen months' };
      }
    }
    if (hasEntries(rule.weeksOfYear) || hasEntries(rule.daysOfYear) || hasEntries(rule.setPositions)) {
      return { reason: 'repeats with week, day-of-year or position rules' };
    }
    if (rule.end && rule.end.date) {
      repeat.until = isoOrNull(rule.end.date);
    } else if (rule.end && rule.end.occurrenceCount) {
      const probe = { date: item.date, time: item.time, timeZone: item.timeZone, repeat: repeat };
      const last = nthOccurrence(probe, Number(rule.end.occurrenceCount));
      if (last === null) {
        return { reason: 'ends after a number of times' };
      }
      repeat.until = new Date(last).toISOString();
    }
    return { repeat: repeat };
  }

  // The moment Apple would alert, or NaN
  function appleAlertMs(reminder) {
    const alarms = Array.isArray(reminder.alarms) ? reminder.alarms : [];
    const due = reminder.due;
    for (const alarm of alarms) {
      const absolute = instantMs(alarm.absoluteDate);
      if (!Number.isNaN(absolute)) {
        return absolute;
      }
      const dueMs = due ? instantMs(due.instant) : NaN;
      if (typeof alarm.relativeOffsetSeconds === 'number' && !Number.isNaN(dueMs)) {
        return dueMs + alarm.relativeOffsetSeconds * 1000;
      }
    }
    return NaN;
  }

  function appleNotes(reminder) {
    const parts = [];
    if (typeof reminder.notes === 'string' && reminder.notes.trim()) {
      parts.push(reminder.notes.trim());
    }
    if (typeof reminder.url === 'string' && reminder.url.trim()) {
      parts.push(reminder.url.trim());
    }
    return parts.join('\n\n');
  }

  function itemFromAppleReminder(reminder, listIds, exportZone, fallbackZone) {
    const due = reminder.due || null;
    const zone = (due && due.timeZone) || exportZone || fallbackZone || deviceTimeZone();
    const externalId = String(reminder.externalId || reminder.id);
    const title = typeof reminder.title === 'string' ? reminder.title.trim() : '';
    const item = {
      id: stableId('a', 'apple:' + externalId),
      title: title || UNTITLED,
      notes: appleNotes(reminder),
      list: listIds[reminder.listId] || null,
      date: null,
      time: null,
      repeat: null,
      timeZone: zone,
      done: reminder.completed === true,
      completedAt: reminder.completed === true ? isoOrNull(reminder.completionDate) : null,
      snoozedUntil: null,
      lastDoneAt: null,
      createdAt: isoOrNull(reminder.creationDate),
      source: { kind: 'apple-reminders', externalId: externalId }
    };
    if (due && due.date) {
      item.date = due.date;
      item.time = due.allDay ? null : (due.time || null);
    }
    // Apple notifies at the alert time; Midas notifies at the reminder's time, so use the alert's
    const alertMs = appleAlertMs(reminder);
    const dueMs = due ? instantMs(due.instant) : NaN;
    if (!Number.isNaN(alertMs) && alertMs !== dueMs) {
      const wallClock = instantToWallClock(alertMs, zone);
      item.date = wallClock.date;
      item.time = wallClock.time;
    }
    let unsupportedReason = null;
    const rules = Array.isArray(reminder.recurrence) ? reminder.recurrence : [];
    if (rules.length > 0) {
      if (!item.date) {
        unsupportedReason = 'repeats without a date';
      } else if (rules.length > 1) {
        unsupportedReason = 'repeats by more than one rule';
      } else {
        const mapped = repeatFromAppleRule(rules[0], item);
        if (mapped.repeat) {
          item.repeat = mapped.repeat;
        } else {
          unsupportedReason = mapped.reason;
        }
      }
    }
    if (unsupportedReason) {
      const note = 'Repeat not imported: ' + unsupportedReason + '.';
      item.notes = item.notes ? item.notes + '\n\n' + note : note;
    }
    return { item: item, unsupportedReason: unsupportedReason };
  }

  function sourceIdOf(entry) {
    return entry && entry.source && entry.source.externalId ? String(entry.source.externalId) : null;
  }

  // What a reminder looks like as far as Apple is concerned; two equal signatures need no update
  function appleSignature(item) {
    const signature = {
      title: item.title || '',
      notes: item.notes || '',
      list: item.list || null,
      date: item.date || null,
      time: item.time || null,
      repeat: item.repeat ? cleanRepeat(item.repeat) : null,
      done: item.done === true,
      completedAt: item.completedAt ? isoOrNull(item.completedAt) : null
    };
    if (item.date) {
      signature.timeZone = item.timeZone || null;
    }
    return JSON.stringify(signature);
  }

  // The existing item with Apple's fields taken from the import; Midas-only fields
  // (snoozedUntil, lastDoneAt, doneThrough) and the id are kept
  function mergeAppleFields(existingItem, imported) {
    const merged = copyJson(existingItem);
    delete merged.recordKey;
    delete merged.historyKey;
    const appleFields = ['title', 'notes', 'list', 'date', 'time', 'repeat', 'timeZone', 'done', 'completedAt', 'source'];
    for (const field of appleFields) {
      merged[field] = imported[field] === undefined ? null : copyJson(imported[field]);
    }
    if (!merged.createdAt) {
      merged.createdAt = imported.createdAt || null;
    }
    return merged;
  }

  // Apple's export as lists and items. Lists and reminders already brought in (same Apple id) are
  // skipped, unless options.updateExisting (the phone's own Reminders: the phone's version wins),
  // when changed ones come back in `updates`. Nothing already here is ever removed.
  function mapAppleExport(exported, existing, timeZone, options) {
    const updateExisting = Boolean(options && options.updateExisting);
    const existingItems = (existing && existing.items) || [];
    const existingLists = (existing && existing.lists) || [];
    const exportZone = exported && exported.timeZone ? exported.timeZone : null;
    const knownItemSources = {};
    const existingBySource = {};
    for (const item of existingItems) {
      const sourceId = sourceIdOf(item);
      if (sourceId) {
        knownItemSources[sourceId] = true;
        existingBySource[sourceId] = item;
      }
    }
    const listIds = {};
    const newLists = [];
    for (const appleList of (exported && exported.lists) || []) {
      const externalId = String(appleList.id);
      const name = typeof appleList.title === 'string' && appleList.title.trim() ? appleList.title.trim() : 'Reminders';
      let match = null;
      for (const list of existingLists.concat(newLists)) {
        const sameSource = sourceIdOf(list) === externalId;
        const sameName = String(list.name || '').toLowerCase() === name.toLowerCase();
        if (sameSource || sameName) {
          match = list;
          break;
        }
      }
      if (match) {
        listIds[externalId] = match.id;
        continue;
      }
      const list = {
        id: stableId('l', 'apple-list:' + externalId), name: name, color: appleList.color || '#007AFF', icon: 'list',
        source: { kind: 'apple-reminders', externalId: externalId }
      };
      listIds[externalId] = list.id;
      newLists.push(list);
    }
    const summary = {
      lists: newLists.length, reminders: 0, active: 0, completed: 0, dated: 0, allDay: 0, repeating: 0,
      unsupportedRepeats: 0, skipped: 0, updated: 0
    };
    const items = [];
    const updates = [];
    const unsupported = [];
    const seenInImport = {};
    for (const reminder of (exported && exported.reminders) || []) {
      const externalId = String(reminder.externalId || reminder.id);
      if (seenInImport[externalId]) {
        summary.skipped += 1;
        continue;
      }
      seenInImport[externalId] = true;
      if (knownItemSources[externalId]) {
        const existingItem = existingBySource[externalId];
        if (updateExisting && existingItem) {
          const imported = itemFromAppleReminder(reminder, listIds, exportZone, timeZone).item;
          if (appleSignature(imported) !== appleSignature(existingItem)) {
            updates.push({ existing: existingItem, item: mergeAppleFields(existingItem, imported) });
            summary.updated += 1;
            continue;
          }
        }
        summary.skipped += 1;
        continue;
      }
      knownItemSources[externalId] = true;
      const mapped = itemFromAppleReminder(reminder, listIds, exportZone, timeZone);
      const item = mapped.item;
      items.push(item);
      summary.reminders += 1;
      if (item.done) {
        summary.completed += 1;
      } else {
        summary.active += 1;
        if (item.date) {
          summary.dated += 1;
          if (!item.time) {
            summary.allDay += 1;
          }
        }
        if (item.repeat) {
          summary.repeating += 1;
        }
      }
      if (mapped.unsupportedReason) {
        summary.unsupportedRepeats += 1;
        unsupported.push({ id: item.id, reason: mapped.unsupportedReason });
      }
    }
    return { lists: newLists, items: items, updates: updates, unsupported: unsupported, summary: summary };
  }

  // The shell hands Apple Reminders over in parts, records import:<id>:<nnnn>; this joins them.
  // Returns null unless every part is there.
  function joinImportParts(records) {
    const parts = [];
    for (const record of records || []) {
      if (record && record.value && typeof record.value === 'object') {
        parts.push(record.value);
      }
    }
    if (parts.length === 0) {
      return null;
    }
    parts.sort(comparePartNumbers);
    const expected = Number(parts[0].parts);
    if (!Number.isInteger(expected) || expected !== parts.length) {
      return null;
    }
    const joined = {
      source: parts[0].source, origin: parts[0].origin || null, exportedAt: parts[0].exportedAt || null,
      timeZone: parts[0].timeZone || null, lists: [], reminders: []
    };
    for (let index = 0; index < parts.length; index += 1) {
      if (Number(parts[index].part) !== index) {
        return null;
      }
      for (const list of parts[index].lists || []) {
        joined.lists.push(list);
      }
      for (const reminder of parts[index].reminders || []) {
        joined.reminders.push(reminder);
      }
    }
    return joined;
  }

  // Done, the same change every writer makes (shell ReminderChange.donePatch; unified data,
  // 2026-10-15): a repeat records this occurrence done (lastDoneAt now, doneThrough the occurrence,
  // never earlier than before) and carries on; a one-time item gets done and completedAt; a snooze
  // is cleared either way.
  function markDoneChange(occurrenceIso, nowIso) {
    return function applyMarkDone(target) {
      target.snoozedUntil = null;
      if (target.date && target.repeat) {
        target.lastDoneAt = nowIso;
        const occurrenceMs = Date.parse(occurrenceIso || '');
        const doneThroughMs = Date.parse(target.doneThrough || '');
        if (!Number.isNaN(occurrenceMs) && (Number.isNaN(doneThroughMs) || occurrenceMs > doneThroughMs)) {
          target.doneThrough = occurrenceIso;
        }
        return;
      }
      target.done = true;
      target.completedAt = nowIso;
    };
  }

  function comparePartNumbers(first, second) {
    return Number(first.part) - Number(second.part);
  }

  return {
    BUILTIN_IDS: BUILTIN_IDS,
    ALL_DAY_TIME: ALL_DAY_TIME,
    formatTime12: formatTime12,
    wallClockToInstant: wallClockToInstant,
    instantToWallClock: instantToWallClock,
    localDateOf: localDateOf,
    instantMs: instantMs,
    addDays: addDays,
    daysBetween: daysBetween,
    weekdayOf: weekdayOf,
    weekRange: weekRange,
    monthRange: monthRange,
    repeatForOption: repeatForOption,
    optionForRepeat: optionForRepeat,
    cleanRepeat: cleanRepeat,
    copyJson: copyJson,
    recordKey: recordKey,
    idFromKey: idFromKey,
    recordFromItem: recordFromItem,
    itemFromRecord: itemFromRecord,
    packHistory: packHistory,
    unpackHistory: unpackHistory,
    historyNumber: historyNumber,
    placeItem: placeItem,
    itemsInList: itemsInList,
    itemsInScope: itemsInScope,
    next7Range: next7Range,
    circleKind: circleKind,
    orderWithLaterBuiltins: orderWithLaterBuiltins,
    mapAppleExport: mapAppleExport,
    joinImportParts: joinImportParts,
    markDoneChange: markDoneChange
  };
})();
  /* copied from index.html: end */

  /* copied from index.html: begin */
  const BUILTIN = {
    today: { name: 'Today', color: 'blue', icon: 'calToday', title: 'blue' },
    next7: { name: 'Next 7 Days', color: 'purple', icon: 'calendar', title: 'purple' },
    scheduled: { name: 'Scheduled', color: 'orange', icon: 'calendar', title: 'orange' },
    unscheduled: { name: 'Unscheduled', color: 'gray', icon: 'tray', title: 'gray' },
    all: { name: 'All', color: 'green', icon: 'trayFill', title: 'green' },
    pastDue: { name: 'Past Due', color: 'red', icon: 'exclaim', title: 'red' },
    completed: { name: 'Completed', color: 'gray', icon: 'check', title: 'gray' }
  };
  /* copied from index.html: end */

  /* copied from index.html: begin */
  const LIST_COLOURS = [
    { name: 'red', hex: '#FF3B30' }, { name: 'orange', hex: '#FF9500' }, { name: 'yellow', hex: '#FFCC00' },
    { name: 'green', hex: '#34C759' }, { name: 'cyan', hex: '#32ADE6' }, { name: 'blue', hex: '#007AFF' },
    { name: 'indigo', hex: '#5856D6' }, { name: 'pink', hex: '#FF2D55' }, { name: 'purple', hex: '#AF52DE' },
    { name: 'brown', hex: '#A2845E' }, { name: 'gray', hex: '#8E8E93' }, { name: 'mint', hex: '#00C7BE' }
  ];
  /* copied from index.html: end */

  /* copied from index.html: begin */
  function colourHex(name) {
    for (const colour of LIST_COLOURS) {
      if (colour.name === name) {
        return colour.hex;
      }
    }
    return '#007AFF';
  }
  /* copied from index.html: end */

  /* copied from index.html: begin */
  function isBuiltin(viewId) {
    return Logic.BUILTIN_IDS.indexOf(viewId) !== -1;
  }
  /* copied from index.html: end */

  /* copied from index.html: begin */
  function compareListsByCreation(first, second) {
    const firstTime = Date.parse(first.createdAt || '') || 0;
    const secondTime = Date.parse(second.createdAt || '') || 0;
    if (firstTime !== secondTime) {
      return firstTime - secondTime;
    }
    return first.name < second.name ? -1 : 1;
  }
  /* copied from index.html: end */

  /* copied from index.html: begin */
  // One order for built-in and own lists; anything the saved order misses goes at the end
  function buildOrder(savedOrder, lists) {
    const order = [];
    const migratedOrder = Logic.orderWithLaterBuiltins(savedOrder);
    for (const id of migratedOrder) {
      const known = isBuiltin(id) || Boolean(lists[id]);
      if (known && order.indexOf(id) === -1) {
        order.push(id);
      }
    }
    for (const id of Logic.BUILTIN_IDS) {
      if (order.indexOf(id) === -1) {
        order.push(id);
      }
    }
    const unplaced = [];
    for (const id of Object.keys(lists)) {
      if (order.indexOf(id) === -1) {
        unplaced.push(lists[id]);
      }
    }
    unplaced.sort(compareListsByCreation);
    for (const list of unplaced) {
      order.push(list.id);
    }
    return order;
  }
  /* copied from index.html: end */

  /* copied from index.html: begin */
  function markNotDoneChange() {
    return function applyMarkNotDone(target) {
      target.done = false;
      target.completedAt = null;
    };
  }
  /* copied from index.html: end */

  const Logic = RemindersLogic;

  function deviceTimeZone() {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  }

  // 12 base36 characters, as the page's newId() makes them; JavaScriptCore has no crypto, so
  // Math.random stands in there
  function newId() {
    const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
    const bytes = new Uint8Array(12);
    const cryptoSource = typeof globalThis.crypto === 'object' ? globalThis.crypto : null;
    if (cryptoSource && typeof cryptoSource.getRandomValues === 'function') {
      cryptoSource.getRandomValues(bytes);
    } else {
      for (let index = 0; index < bytes.length; index += 1) {
        bytes[index] = Math.floor(Math.random() * 256);
      }
    }
    let id = '';
    for (const byte of bytes) {
      id += alphabet[byte % alphabet.length];
    }
    return id;
  }

  /* ======================================================================
     The tools. Each handler is (input, records, now) → { ops, result } or { refused, result }:
     input is the tool's arguments as manifest.json "agent" describes them, with "when" already
     worked out by Midas ({ date, time, allDay, at, repeat, timeZone }, or null); records are this
     Sidekick's records as [{ key, value }]; now is an ISO instant. ops are whole records to set or
     keys to delete; nothing is written by a handler. A refusal changes nothing.
     ====================================================================== */

  const SETTINGS_KEY = 'settings:self';
  const LIST_NAME_LIMIT = 40;
  const CONTEXT_ACTIVE_LIMIT = 150;
  const CONTEXT_DONE_LIMIT = 30;
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

  // Every reminder: the ones in reminder: records, then the completed ones packed in history:
  function entriesOf(records) {
    const entries = [];
    for (const record of records) {
      if (record.key.indexOf('reminder:') !== 0 || !record.value) {
        continue;
      }
      entries.push({ item: Logic.itemFromRecord(record.key, record.value), key: record.key, value: record.value, historyKey: null });
    }
    for (const record of records) {
      if (record.key.indexOf('history:') !== 0 || !record.value || !Array.isArray(record.value.items)) {
        continue;
      }
      for (const storedItem of record.value.items) {
        entries.push({ item: Logic.copyJson(storedItem), key: null, value: null, historyKey: record.key, history: record.value });
      }
    }
    return entries;
  }

  function listsOf(records) {
    const lists = {};
    for (const record of records) {
      if (record.key.indexOf('list:') !== 0 || !record.value) {
        continue;
      }
      const value = record.value;
      const id = Logic.idFromKey(record.key);
      lists[id] = { id: id, name: String(value.name || 'Untitled List'), color: value.color || '#007AFF', icon: value.icon || 'list',
        source: value.source || null, createdAt: value.createdAt || null };
    }
    return lists;
  }

  function listArray(lists) {
    const result = [];
    for (const id of Object.keys(lists)) {
      result.push(lists[id]);
    }
    return result;
  }

  function settingsOf(records) {
    for (const record of records) {
      if (record.key === SETTINGS_KEY) {
        return record.value || null;
      }
    }
    return null;
  }

  function isOpen(entry) {
    return entry.historyKey === null && !entry.item.done;
  }

  function isClosed(entry) {
    return !isOpen(entry);
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

  function isExactName(said, name) {
    const target = normalised(said);
    const normalisedName = normalised(name);
    return target !== '' && (normalisedName === target || normalisedName === withoutLeadingWord(target));
  }

  // One reminder named by what was said. Names are matched over every reminder first, so an
  // exact title wins even when the action cannot apply to it ("Call Mom back" is done: it is not
  // taken as "Call Mom"); then only the reminders the action applies to stay. An open reminder
  // wins over completed ones only when both carry exactly the name said; a part of a name that
  // fits two reminders refuses.
  function findOne(said, entries, applies, notApplicable) {
    const matches = matchByName(said, entries, titleOfEntry);
    if (matches.length === 0) {
      return { problem: refuse('not-found', 'No reminder named ' + cleanText(said)) };
    }
    const applicable = applies ? onlyEntries(matches, applies) : matches;
    if (applicable.length === 0) {
      return { problem: refuse(notApplicable, notApplicableText(notApplicable) + namesOf(matches)) };
    }
    let chosen = applicable;
    const open = onlyEntries(applicable, isOpen);
    const exact = isExactName(said, applicable[0].item.title);
    if (exact && open.length > 0 && open.length < applicable.length) {
      chosen = open;
    }
    if (chosen.length > 1) {
      return { problem: refuse('ambiguous', 'More than one match: ' + namesOf(chosen)) };
    }
    return { entry: chosen[0] };
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

  // A list named by what was said, or null for no list. Unknown or ambiguous names refuse.
  function findList(said, lists) {
    if (said === null || said === undefined || cleanText(said) === '') {
      return { list: null };
    }
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

  // The page's writeRecordChange: the stored record read again, the change applied, written whole
  function changedRecordOp(entry, applyChange) {
    const fresh = Logic.itemFromRecord(entry.key, entry.value);
    applyChange(fresh);
    return { op: setOp(Logic.recordKey(fresh), Logic.recordFromItem(fresh, entry.value)), item: fresh };
  }

  // The page's writeHistoryItems: a history record without items is removed
  function historyItemsOp(historyKey, record, items) {
    if (items.length === 0) {
      return deleteOp(historyKey);
    }
    return setOp(historyKey, Object.assign({}, record || {}, { items: items }));
  }

  function historyWithout(entry) {
    const items = entry.history.items.slice();
    for (let index = 0; index < items.length; index += 1) {
      if (items[index] && items[index].id === entry.item.id) {
        items.splice(index, 1);
        break;
      }
    }
    return items;
  }

  function whenResult(value) {
    if (!value.at) {
      return { at: null, allDay: false };
    }
    return { at: value.at, allDay: value.allDay === true };
  }

  /* ---------- add ---------- */

  function addReminder(input, records, now) {
    const title = cleanText(input.title);
    if (title === '') {
      return refuse('no-title', 'No title');
    }
    const found = findList(input.list, listsOf(records));
    if (found.problem) {
      return found.problem;
    }
    const when = input.when || null;
    const dated = Boolean(when && when.date);
    const item = {
      id: newId(), title: title, notes: cleanText(input.notes), list: found.list ? found.list.id : null,
      date: dated ? when.date : null, time: dated && !when.allDay ? when.time : null,
      repeat: dated && when.repeat ? Logic.cleanRepeat(when.repeat) : null,
      timeZone: when && when.timeZone ? when.timeZone : deviceTimeZone(),
      done: false, completedAt: null, snoozedUntil: null, lastDoneAt: null, doneThrough: null,
      createdAt: now, source: null
    };
    const value = Logic.recordFromItem(item, null);
    return done([setOp(Logic.recordKey(item), value)], 'Added ' + title, whenResult(value));
  }

  /* ---------- edit ---------- */

  // The page's makeUserFieldsChange: a new date or time is meant in the zone it was said in
  function applyFields(fields, timeZone) {
    return function applyEditedFields(target) {
      const timingChanged = (target.date || null) !== fields.date || (target.time || null) !== (fields.date ? fields.time : null);
      target.title = fields.title;
      target.notes = fields.notes;
      target.list = fields.list;
      target.date = fields.date;
      target.time = fields.date ? fields.time : null;
      target.repeat = fields.date && fields.repeat ? Logic.copyJson(fields.repeat) : null;
      if (timingChanged && timeZone) {
        target.timeZone = timeZone;
      }
    };
  }

  function fieldsOf(item) {
    return {
      title: item.title, notes: item.notes || '', list: item.list || null, date: item.date || null,
      time: item.time || null, repeat: Logic.copyJson(item.repeat)
    };
  }

  function editReminder(input, records) {
    const found = findOne(input.item, entriesOf(records), isOpenOrRecord, 'cannot-change');
    if (found.problem) {
      return found.problem;
    }
    const entry = found.entry;
    const fields = fieldsOf(entry.item);
    const before = JSON.stringify(fields);
    const newTitle = cleanText(input.title);
    if (newTitle !== '') {
      fields.title = newTitle;
    }
    if (typeof input.notes === 'string') {
      fields.notes = input.notes.trim();
    }
    const when = input.when || null;
    let timeZone = null;
    if (input.clearDate === true) {
      fields.date = null;
      fields.time = null;
      fields.repeat = null;
    } else if (when && when.date) {
      fields.date = when.date;
      fields.time = when.allDay ? null : when.time;
      fields.repeat = when.repeat ? Logic.cleanRepeat(when.repeat) : null;
      timeZone = when.timeZone;
    }
    if (JSON.stringify(fields) === before) {
      return refuse('nothing-to-change', 'Nothing to change');
    }
    const changed = changedRecordOp(entry, applyFields(fields, timeZone));
    return done([changed.op], 'Changed ' + fields.title, whenResult(changed.op.value));
  }

  function isOpenOrRecord(entry) {
    return entry.historyKey === null;
  }

  /* ---------- move to a list ---------- */

  function moveReminder(input, records) {
    const lists = listsOf(records);
    const foundList = findList(input.list, lists);
    if (foundList.problem) {
      return foundList.problem;
    }
    const found = findOne(input.item, entriesOf(records), isOpenOrRecord, 'cannot-change');
    if (found.problem) {
      return found.problem;
    }
    const entry = found.entry;
    const listId = foundList.list ? foundList.list.id : null;
    if ((entry.item.list || null) === listId) {
      return refuse('nothing-to-change', 'Already there');
    }
    const fields = fieldsOf(entry.item);
    fields.list = listId;
    const changed = changedRecordOp(entry, applyFields(fields, null));
    if (foundList.list === null) {
      return done([changed.op], 'Removed ' + entry.item.title + ' from its list');
    }
    return done([changed.op], 'Moved ' + entry.item.title + ' to ' + foundList.list.name);
  }

  /* ---------- complete and uncomplete ---------- */

  // The occurrence the page shows for a repeat (Past Due first, then Today, then the next one)
  function shownOccurrence(item, now) {
    const placement = Logic.placeItem(item, now, item.timeZone);
    const entry = placement.overdue || placement.today || placement.upcoming || placement.undated;
    if (placement.done && !entry) {
      return null;
    }
    return entry && entry.at ? entry.at.toISOString() : '';
  }

  function completeReminder(input, records, now) {
    const entries = entriesOf(records);
    const found = findOne(input.item, entries, isOpen, 'already-done');
    if (found.problem) {
      return found.problem;
    }
    const entry = found.entry;
    let occurrence = '';
    if (entry.item.date && entry.item.repeat) {
      occurrence = shownOccurrence(entry.item, now);
      if (occurrence === null) {
        return refuse('already-done', 'Already done: ' + entry.item.title);
      }
    }
    const changed = changedRecordOp(entry, Logic.markDoneChange(occurrence, now));
    return done([changed.op], 'Marked done: ' + entry.item.title);
  }

  function uncompleteReminder(input, records) {
    const found = findOne(input.item, entriesOf(records), isClosed, 'not-done');
    if (found.problem) {
      return found.problem;
    }
    const entry = found.entry;
    if (entry.historyKey === null) {
      const changed = changedRecordOp(entry, markNotDoneChange());
      return done([changed.op], 'Marked not done: ' + entry.item.title);
    }
    // The page's writeHistoryChange: the item becomes its own record again, written first
    const fresh = Logic.copyJson(entry.item);
    markNotDoneChange()(fresh);
    const ops = [setOp(Logic.recordKey(fresh), Logic.recordFromItem(fresh, null))];
    ops.push(historyItemsOp(entry.historyKey, entry.history, historyWithout(entry)));
    return done(ops, 'Marked not done: ' + entry.item.title);
  }

  /* ---------- delete ---------- */

  function deleteReminder(input, records) {
    const found = findOne(input.item, entriesOf(records), null, null);
    if (found.problem) {
      return found.problem;
    }
    const entry = found.entry;
    if (entry.historyKey !== null) {
      return done([historyItemsOp(entry.historyKey, entry.history, historyWithout(entry))], 'Deleted ' + entry.item.title);
    }
    return done([deleteOp(entry.key)], 'Deleted ' + entry.item.title);
  }

  /* ---------- snooze (the notification's Snooze: { snoozedUntil }) ---------- */

  function snoozeReminder(input, records, now) {
    const when = input.when || null;
    if (!when || !when.at) {
      return refuse('no-time', 'No snooze time');
    }
    if (Date.parse(when.at) <= Date.parse(now)) {
      return refuse('past', 'Snooze time has passed');
    }
    const found = findOne(input.item, entriesOf(records), isOpen, 'already-done');
    if (found.problem) {
      return found.problem;
    }
    const entry = found.entry;
    if (!entry.item.date) {
      return refuse('not-dated', 'No date on ' + entry.item.title);
    }
    const value = Object.assign({}, entry.value, { snoozedUntil: when.at });
    return done([setOp(entry.key, value)], 'Snoozed ' + entry.item.title, { at: when.at, allDay: false });
  }

  /* ---------- lists ---------- */

  function createList(input, records, now) {
    const name = cleanText(input.name).slice(0, LIST_NAME_LIMIT);
    if (name === '') {
      return refuse('no-name', 'No list name');
    }
    const lists = listsOf(records);
    for (const list of listArray(lists)) {
      if (normalised(list.name) === normalised(name)) {
        return refuse('list-exists', 'Already a list: ' + list.name);
      }
    }
    const list = { id: newId(), name: name, color: colourHex(input.color || 'blue'), icon: input.icon || 'list', source: null, createdAt: now };
    const settings = settingsOf(records);
    const order = buildOrder(settings ? settings.order : null, lists);
    order.push(list.id);
    const listValue = { $type: 'reminders.list', name: list.name, color: list.color, icon: list.icon, createdAt: list.createdAt };
    const settingsValue = Object.assign({}, settings || {}, { $type: 'reminders.settings', order: order });
    return done([setOp('list:' + list.id, listValue), setOp(SETTINGS_KEY, settingsValue)], 'Added list ' + name);
  }

  // Built-in lists can be moved in the sidebar too
  function sidebarEntries(lists) {
    const entries = [];
    for (const id of Logic.BUILTIN_IDS) {
      entries.push({ id: id, name: BUILTIN[id].name });
    }
    for (const list of listArray(lists)) {
      entries.push({ id: list.id, name: list.name });
    }
    return entries;
  }

  function findSidebarEntry(said, lists) {
    const matches = matchByName(said, sidebarEntries(lists), nameOfList);
    if (matches.length === 0) {
      return { problem: refuse('unknown-list', 'No list named ' + cleanText(said)) };
    }
    if (matches.length > 1) {
      const names = [];
      for (const match of matches) {
        names.push(match.name);
      }
      return { problem: refuse('ambiguous', 'More than one list: ' + names.join(', ')) };
    }
    return { entry: matches[0] };
  }

  function moveList(input, records) {
    const lists = listsOf(records);
    const found = findSidebarEntry(input.list, lists);
    if (found.problem) {
      return found.problem;
    }
    const settings = settingsOf(records);
    const order = buildOrder(settings ? settings.order : null, lists);
    const before = order.join(',');
    order.splice(order.indexOf(found.entry.id), 1);
    let target = input.position === 'first' ? 0 : order.length;
    if (input.position === 'before' || input.position === 'after') {
      const other = findSidebarEntry(input.other, lists);
      if (other.problem) {
        return other.problem;
      }
      const otherIndex = order.indexOf(other.entry.id);
      if (otherIndex === -1) {
        return refuse('nothing-to-change', 'Nothing to change');
      }
      target = input.position === 'before' ? otherIndex : otherIndex + 1;
    }
    order.splice(target, 0, found.entry.id);
    if (order.join(',') === before) {
      return refuse('nothing-to-change', 'Already there');
    }
    const settingsValue = Object.assign({}, settings || {}, { $type: 'reminders.settings', order: order });
    return done([setOp(SETTINGS_KEY, settingsValue)], 'Moved ' + found.entry.name);
  }

  /* ---------- What jess is told about this Sidekick's records ---------- */

  function whenTextOf(item) {
    if (!item.date) {
      return null;
    }
    return item.time ? item.date + ' ' + item.time : item.date;
  }

  function contextItem(item, lists) {
    const list = item.list && lists[item.list] ? lists[item.list].name : null;
    return { title: item.title.slice(0, CONTEXT_TITLE_LIMIT), list: list, when: whenTextOf(item), repeats: Boolean(item.date && item.repeat), done: Boolean(item.done) };
  }

  function laterCompletedFirst(first, second) {
    const firstTime = Date.parse(first.completedAt || first.lastDoneAt || '') || 0;
    const secondTime = Date.parse(second.completedAt || second.lastDoneAt || '') || 0;
    return secondTime - firstTime;
  }

  // The user's own lists and reminders, small: open reminders first, then the latest completed
  function buildContext(records) {
    const lists = listsOf(records);
    const listNames = [];
    for (const list of listArray(lists)) {
      listNames.push(list.name);
    }
    const open = [];
    const closed = [];
    for (const entry of entriesOf(records)) {
      if (isOpen(entry)) {
        open.push(entry.item);
      } else {
        closed.push(entry.item);
      }
    }
    closed.sort(laterCompletedFirst);
    const items = [];
    for (const item of open.slice(0, CONTEXT_ACTIVE_LIMIT)) {
      items.push(contextItem(item, lists));
    }
    for (const item of closed.slice(0, CONTEXT_DONE_LIMIT)) {
      items.push(contextItem(item, lists));
    }
    return { lists: listNames, items: items };
  }

  return {
    context: buildContext,
    handlers: {
      add: addReminder,
      edit: editReminder,
      move: moveReminder,
      complete: completeReminder,
      uncomplete: uncompleteReminder,
      delete: deleteReminder,
      snooze: snoozeReminder,
      create_list: createList,
      move_list: moveList
    }
  };
})();

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSidekickTools;
}
