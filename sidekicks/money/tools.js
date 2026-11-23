// Money tools: every action a person can take in this Sidekick, as functions jess (and later any
// outside agent) can call (jess router, founder 2026-10-21). manifest.json "agent" describes each
// tool; this file does the work. The shell runs it in JavaScriptCore and writes the ops it returns
// through RecordWriter; nothing here touches the store.
//
// The block between "copied from index.html" markers is the page's own code, character for
// character: the deploy gate refuses this file when it no longer appears in index.html, so an
// expense added by voice or from a receipt photo is written exactly as the page writes it.
//
// A receipt photo (founder, 2026-11-08): add_expense's _meta "midas/photo" names the field
// "receipt". The model never sees it; the server stores the photo as the user's file and hands
// "file:<id>" in input.receipt. The expense then keeps it like a receipt added on the page.
//
// A plain script: one global (MidasSidekickTools), a CommonJS export at the end for Node.
var MidasSidekickTools = (function createMoneyTools() {
  'use strict';

  /* copied from index.html: begin */
var MoneyLogic = (function createMoneyLogic() {
  'use strict';

  const PREFIX = 'expense:';
  const CURRENCY = 'USD';
  // The fixed categories (founder, 2026-11-07). A person may add more through Edit: add to this
  // list and to the enums in manifest.json, never remove or rename one.
  const CATEGORIES = ['Groceries', 'Dining', 'Transport', 'Shopping', 'Bills', 'Home', 'Health', 'Fun', 'Travel', 'Other'];
  const FALLBACK_CATEGORY = 'Other';
  const FALLBACK_MERCHANT = 'Expense';
  const MAX_CENTS = 100000000;
  const MAX_LINE_CENTS = 10000000;
  const MAX_ITEMS = 100;
  const MAX_QUANTITY = 999;
  const MAX_TEXT = 120;
  // A date further back than this, or in the future, is taken as a misread and becomes today
  const MAX_DAYS_BACK = 366;
  const RECEIPT_PATTERN = /^file:[A-Za-z0-9_-]{8,64}$/;
  const SOURCES = ['page', 'jess', 'photo'];
  const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const SHORT_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  /* ---------- Amounts: integer cents everywhere ---------- */

  // Dollars as a number (a tool's input) to cents; null when it is not a number
  function centsFromDollars(value) {
    if (typeof value !== 'number' || !isFinite(value)) {
      return null;
    }
    return Math.round(value * 100);
  }

  // Dollars as typed ("12", "12.5", "$1,204.99") to cents; null when it cannot be read
  function parseDollars(text) {
    const cleaned = String(text === null || text === undefined ? '' : text).replace(/[$,\s]/g, '');
    if (!/^\d+(\.\d{0,2})?$/.test(cleaned) && !/^\.\d{1,2}$/.test(cleaned)) {
      return null;
    }
    const parts = cleaned.split('.');
    const whole = parts[0] === '' ? 0 : Number(parts[0]);
    const centsText = ((parts[1] || '') + '00').slice(0, 2);
    return whole * 100 + Number(centsText);
  }

  function isAmountAllowed(cents) {
    return Number.isInteger(cents) && cents >= 1 && cents <= MAX_CENTS;
  }

  function withCommas(wholeText) {
    return wholeText.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  // 120418 -> "$1,204.18"; -150 -> "-$1.50"
  function formatCents(cents) {
    const sign = cents < 0 ? '-' : '';
    const absolute = Math.abs(Math.round(cents));
    const whole = Math.floor(absolute / 100);
    const rest = absolute % 100;
    return sign + '$' + withCommas(String(whole)) + '.' + (rest < 10 ? '0' : '') + rest;
  }

  /* ---------- Days and months, in the phone's own time zone ---------- */

  function pad2(number) {
    return number < 10 ? '0' + number : String(number);
  }

  function dateKeyOf(date) {
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
  }

  function localDateKey(ms) {
    return dateKeyOf(new Date(ms));
  }

  function dateFromKey(dateKey) {
    const parts = dateKey.split('-');
    return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  }

  // A real calendar day written YYYY-MM-DD
  function isDateKey(text) {
    if (typeof text !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(text)) {
      return false;
    }
    return dateKeyOf(dateFromKey(text)) === text;
  }

  function addDaysToKey(dateKey, days) {
    const date = dateFromKey(dateKey);
    return dateKeyOf(new Date(date.getFullYear(), date.getMonth(), date.getDate() + days));
  }

  function monthKeyOf(dateKey) {
    return dateKey.slice(0, 7);
  }

  function shiftMonth(monthKey, delta) {
    const parts = monthKey.split('-');
    const date = new Date(Number(parts[0]), Number(parts[1]) - 1 + delta, 1);
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1);
  }

  function monthKeyFor(ms, monthsAgo) {
    return shiftMonth(monthKeyOf(localDateKey(ms)), -monthsAgo);
  }

  // "November", or "November 2025" when it is not this year
  function monthName(monthKey, nowMs) {
    const parts = monthKey.split('-');
    const name = MONTH_NAMES[Number(parts[1]) - 1];
    const thisYear = localDateKey(nowMs).slice(0, 4);
    return parts[0] === thisYear ? name : name + ' ' + parts[0];
  }

  function monthTitle(monthKey) {
    const parts = monthKey.split('-');
    return MONTH_NAMES[Number(parts[1]) - 1] + ' ' + parts[0];
  }

  // "Today", "Yesterday", else "Thu, Nov 5"
  function dayLabel(dateKey, nowMs) {
    const today = localDateKey(nowMs);
    if (dateKey === today) {
      return 'Today';
    }
    if (dateKey === addDaysToKey(today, -1)) {
      return 'Yesterday';
    }
    const date = dateFromKey(dateKey);
    return DAY_NAMES[date.getDay()] + ', ' + SHORT_MONTHS[date.getMonth()] + ' ' + date.getDate();
  }

  function fullDateLabel(dateKey) {
    const date = dateFromKey(dateKey);
    return DAY_NAMES[date.getDay()] + ', ' + SHORT_MONTHS[date.getMonth()] + ' ' + date.getDate() + ', ' + date.getFullYear();
  }

  // The day an expense is for: a real date said or printed, not in the future and not over a
  // year back; else days ago; else today. A receipt with no printed date gets today.
  function purchaseDate(dateText, daysAgo, nowMs) {
    const today = localDateKey(nowMs);
    const earliest = addDaysToKey(today, -MAX_DAYS_BACK);
    if (isDateKey(dateText) && dateText <= today && dateText >= earliest) {
      return dateText;
    }
    if (Number.isInteger(daysAgo) && daysAgo >= 0 && daysAgo <= MAX_DAYS_BACK) {
      return addDaysToKey(today, -daysAgo);
    }
    return today;
  }

  /* ---------- Words ---------- */

  function cleanText(text) {
    if (typeof text !== 'string') {
      return '';
    }
    return text.replace(/\s+/g, ' ').trim().slice(0, MAX_TEXT);
  }

  function isCategory(category) {
    return CATEGORIES.indexOf(category) !== -1;
  }

  function sameMerchant(first, second) {
    return cleanText(first).toLowerCase() === cleanText(second).toLowerCase();
  }

  /* ---------- Records ---------- */

  function isExpenseValue(value) {
    return value !== null && typeof value === 'object' && Number.isInteger(value.amountCents) && typeof value.date === 'string';
  }

  // [{ key, value }] of this Sidekick's records -> the expenses, as { key, value }
  function expensesFrom(records) {
    const expenses = [];
    for (const record of records) {
      if (record.key.indexOf(PREFIX) === 0 && isExpenseValue(record.value)) {
        expenses.push(record);
      }
    }
    return expenses;
  }

  function compareNewestFirst(first, second) {
    if (first.value.date !== second.value.date) {
      return first.value.date < second.value.date ? 1 : -1;
    }
    const firstCreated = first.value.createdAt || '';
    const secondCreated = second.value.createdAt || '';
    if (firstCreated !== secondCreated) {
      return firstCreated < secondCreated ? 1 : -1;
    }
    return first.key < second.key ? 1 : -1;
  }

  function newestFirst(expenses) {
    const ordered = expenses.slice();
    ordered.sort(compareNewestFirst);
    return ordered;
  }

  // The category this merchant had last time, or null
  function lastCategoryFor(merchant, expenses) {
    for (const expense of newestFirst(expenses)) {
      if (sameMerchant(expense.value.merchant, merchant) && isCategory(expense.value.category)) {
        return expense.value.category;
      }
    }
    return null;
  }

  // Lines as { name, amountCents, quantity } (null when not known) -> the record's items
  function cleanItems(lines) {
    if (!Array.isArray(lines)) {
      return [];
    }
    const items = [];
    for (const line of lines) {
      const name = line && cleanText(line.name);
      if (!name || items.length >= MAX_ITEMS) {
        continue;
      }
      const item = { name: name };
      if (Number.isInteger(line.amountCents) && Math.abs(line.amountCents) <= MAX_LINE_CENTS) {
        item.amountCents = line.amountCents;
      }
      if (Number.isInteger(line.quantity) && line.quantity >= 1 && line.quantity <= MAX_QUANTITY) {
        item.quantity = line.quantity;
      }
      items.push(item);
    }
    return items;
  }

  function newExpenseKey(nowMs, randomFraction) {
    return PREFIX + nowMs.toString(36) + Math.floor(randomFraction * 1e9).toString(36);
  }

  function optionalCents(cents) {
    return Number.isInteger(cents) && cents >= 0 && cents <= MAX_CENTS;
  }

  // One expense record holding everything about it (founder, 2026-11-07). fields: amountCents,
  // merchant, date, category, items, taxCents, tipCents, receipt, source. existing is the record
  // being edited, or null: it keeps its createdAt and source.
  function expenseRecord(fields, existing, nowIso) {
    const value = {
      amountCents: fields.amountCents,
      currency: CURRENCY,
      merchant: cleanText(fields.merchant) || FALLBACK_MERCHANT,
      date: fields.date,
      category: isCategory(fields.category) ? fields.category : FALLBACK_CATEGORY,
      createdAt: existing && existing.createdAt ? existing.createdAt : nowIso
    };
    const items = cleanItems(fields.items);
    if (items.length > 0) {
      value.items = items;
    }
    if (optionalCents(fields.taxCents)) {
      value.taxCents = fields.taxCents;
    }
    if (optionalCents(fields.tipCents)) {
      value.tipCents = fields.tipCents;
    }
    if (typeof fields.receipt === 'string' && RECEIPT_PATTERN.test(fields.receipt)) {
      value.receipt = fields.receipt;
    }
    const source = existing && existing.source ? existing.source : fields.source;
    if (SOURCES.indexOf(source) !== -1) {
      value.source = source;
    }
    if (existing) {
      value.updatedAt = nowIso;
    }
    return value;
  }

  /* ---------- A month ---------- */

  function expensesInMonth(expenses, monthKey) {
    const matching = [];
    for (const expense of expenses) {
      if (monthKeyOf(expense.value.date) === monthKey) {
        matching.push(expense);
      }
    }
    return matching;
  }

  function compareByCentsDescending(first, second) {
    return second.cents - first.cents;
  }

  // { totalCents, count, byCategory: [{ category, cents, percent }] largest first }
  function monthSummary(expenses, monthKey) {
    const inMonth = expensesInMonth(expenses, monthKey);
    const centsByCategory = {};
    let totalCents = 0;
    for (const expense of inMonth) {
      const category = expense.value.category;
      centsByCategory[category] = (centsByCategory[category] || 0) + expense.value.amountCents;
      totalCents += expense.value.amountCents;
    }
    const byCategory = [];
    for (const category of Object.keys(centsByCategory)) {
      const cents = centsByCategory[category];
      const percent = totalCents > 0 ? Math.round((cents / totalCents) * 100) : 0;
      byCategory.push({ category: category, cents: cents, percent: percent });
    }
    byCategory.sort(compareByCentsDescending);
    return { totalCents: totalCents, count: inMonth.length, byCategory: byCategory };
  }

  // The newest expense matching a merchant (null: any) and an amount in cents (null: any)
  function findExpense(expenses, merchant, amountCents) {
    const wanted = cleanText(merchant).toLowerCase();
    for (const expense of newestFirst(expenses)) {
      const name = cleanText(expense.value.merchant).toLowerCase();
      const merchantFits = wanted === '' || name === wanted || name.indexOf(wanted) !== -1;
      const amountFits = amountCents === null || expense.value.amountCents === amountCents;
      if (merchantFits && amountFits) {
        return expense;
      }
    }
    return null;
  }

  return {
    PREFIX: PREFIX,
    CURRENCY: CURRENCY,
    CATEGORIES: CATEGORIES,
    FALLBACK_CATEGORY: FALLBACK_CATEGORY,
    FALLBACK_MERCHANT: FALLBACK_MERCHANT,
    MAX_DAYS_BACK: MAX_DAYS_BACK,
    RECEIPT_PATTERN: RECEIPT_PATTERN,
    centsFromDollars: centsFromDollars,
    parseDollars: parseDollars,
    isAmountAllowed: isAmountAllowed,
    formatCents: formatCents,
    localDateKey: localDateKey,
    isDateKey: isDateKey,
    addDaysToKey: addDaysToKey,
    monthKeyOf: monthKeyOf,
    shiftMonth: shiftMonth,
    monthKeyFor: monthKeyFor,
    monthName: monthName,
    monthTitle: monthTitle,
    dayLabel: dayLabel,
    fullDateLabel: fullDateLabel,
    purchaseDate: purchaseDate,
    cleanText: cleanText,
    isCategory: isCategory,
    expensesFrom: expensesFrom,
    newestFirst: newestFirst,
    lastCategoryFor: lastCategoryFor,
    cleanItems: cleanItems,
    newExpenseKey: newExpenseKey,
    expenseRecord: expenseRecord,
    expensesInMonth: expensesInMonth,
    monthSummary: monthSummary,
    findExpense: findExpense
  };
})();
  /* copied from index.html: end */

  const Logic = MoneyLogic;
  const RECENT_COUNT = 10;
  const MERCHANT_MEMORY = 30;

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

  function categoryIn(input) {
    return Logic.isCategory(input.category) ? input.category : null;
  }

  function atMerchant(merchant) {
    return merchant === Logic.FALLBACK_MERCHANT ? '' : ' at ' + merchant;
  }

  // The tool's lines, dollars -> cents, in the shape the page's lines have
  function linesFrom(items) {
    const lines = [];
    if (!Array.isArray(items)) {
      return lines;
    }
    for (const item of items) {
      if (item && typeof item === 'object') {
        lines.push({ name: item.name, amountCents: Logic.centsFromDollars(item.amount), quantity: item.quantity });
      }
    }
    return lines;
  }

  /* ---------- Handlers ---------- */

  // The page's Add Expense sheet, from words or from a receipt photo
  function addExpense(input, records, now) {
    const nowMs = Date.parse(now);
    const amountCents = Logic.centsFromDollars(input.amount);
    if (!Logic.isAmountAllowed(amountCents)) {
      return refuse('no-amount', 'No amount');
    }
    const expenses = Logic.expensesFrom(records);
    const merchant = Logic.cleanText(input.merchant) || Logic.FALLBACK_MERCHANT;
    const category = categoryIn(input) || Logic.lastCategoryFor(merchant, expenses) || Logic.FALLBACK_CATEGORY;
    const receipt = typeof input.receipt === 'string' && Logic.RECEIPT_PATTERN.test(input.receipt) ? input.receipt : null;
    const fields = {
      amountCents: amountCents,
      merchant: merchant,
      date: Logic.purchaseDate(input.date, input.daysAgo, nowMs),
      category: category,
      items: linesFrom(input.items),
      taxCents: Logic.centsFromDollars(input.tax),
      tipCents: Logic.centsFromDollars(input.tip),
      receipt: receipt,
      source: receipt ? 'photo' : 'jess'
    };
    const value = Logic.expenseRecord(fields, null, new Date(nowMs).toISOString());
    const key = Logic.newExpenseKey(nowMs, Math.random());
    return done([setOp(key, value)], 'Added ' + Logic.formatCents(amountCents) + atMerchant(value.merchant), { key: key, amountCents: amountCents });
  }

  // The page's Edit and Save on one expense
  function editExpense(input, records, now) {
    const nowMs = Date.parse(now);
    const expenses = Logic.expensesFrom(records);
    const target = Logic.findExpense(expenses, input.which, null);
    if (target === null) {
      return refuse('no-expense', 'No such expense');
    }
    const before = target.value;
    const fields = {
      amountCents: before.amountCents,
      merchant: before.merchant,
      date: before.date,
      category: before.category,
      items: before.items,
      taxCents: before.taxCents,
      tipCents: before.tipCents,
      receipt: before.receipt
    };
    if (input.amount !== null && input.amount !== undefined) {
      const amountCents = Logic.centsFromDollars(input.amount);
      if (!Logic.isAmountAllowed(amountCents)) {
        return refuse('no-amount', 'No amount');
      }
      fields.amountCents = amountCents;
    }
    if (Logic.cleanText(input.merchant)) {
      fields.merchant = Logic.cleanText(input.merchant);
    }
    if (typeof input.date === 'string' || Number.isInteger(input.daysAgo)) {
      fields.date = Logic.purchaseDate(input.date, input.daysAgo, nowMs);
    }
    if (categoryIn(input)) {
      fields.category = categoryIn(input);
    }
    const value = Logic.expenseRecord(fields, before, new Date(nowMs).toISOString());
    const unchanged = value.amountCents === before.amountCents && value.merchant === before.merchant && value.date === before.date && value.category === before.category;
    if (unchanged) {
      return refuse('nothing-to-change', 'Nothing to change');
    }
    return done([setOp(target.key, value)], 'Saved ' + Logic.formatCents(value.amountCents) + atMerchant(value.merchant), { key: target.key });
  }

  // The page's Delete Expense
  function deleteExpense(input, records, now) {
    const expenses = Logic.expensesFrom(records);
    const amountCents = input.amount === null || input.amount === undefined ? null : Logic.centsFromDollars(input.amount);
    const target = Logic.findExpense(expenses, input.which, amountCents);
    if (target === null) {
      return refuse('no-expense', 'No such expense');
    }
    return done([deleteOp(target.key)], 'Deleted ' + Logic.formatCents(target.value.amountCents) + atMerchant(target.value.merchant), { key: target.key });
  }

  // The month shown on the page, moved with its arrows
  function monthTotal(input, records, now) {
    const nowMs = Date.parse(now);
    const monthsAgo = Number.isInteger(input.monthsAgo) ? input.monthsAgo : 0;
    if (monthsAgo < 0) {
      return refuse('future-month', 'Only this month or earlier');
    }
    const monthKey = Logic.monthKeyFor(nowMs, monthsAgo);
    const summary = Logic.monthSummary(Logic.expensesFrom(records), monthKey);
    const name = Logic.monthName(monthKey, nowMs);
    const category = categoryIn(input);
    if (category === null) {
      return done([], Logic.formatCents(summary.totalCents) + ' in ' + name, { totalCents: summary.totalCents, month: monthKey });
    }
    let categoryCents = 0;
    for (const entry of summary.byCategory) {
      if (entry.category === category) {
        categoryCents = entry.cents;
      }
    }
    return done([], Logic.formatCents(categoryCents) + ' on ' + category + ' in ' + name, { totalCents: categoryCents, month: monthKey });
  }

  /* ---------- What jess is told about this Sidekick's records ---------- */

  function buildContext(records, now) {
    const nowMs = Date.parse(now);
    const expenses = Logic.newestFirst(Logic.expensesFrom(records));
    const summary = Logic.monthSummary(expenses, Logic.monthKeyFor(nowMs, 0));
    const byCategory = [];
    for (const entry of summary.byCategory) {
      byCategory.push({ category: entry.category, total: Logic.formatCents(entry.cents) });
    }
    const recent = [];
    for (const expense of expenses.slice(0, RECENT_COUNT)) {
      recent.push({ merchant: expense.value.merchant, amount: Logic.formatCents(expense.value.amountCents), date: expense.value.date, category: expense.value.category });
    }
    // The person's own category for each merchant, newest first
    const merchantCategories = {};
    let remembered = 0;
    for (const expense of expenses) {
      const merchant = expense.value.merchant;
      if (remembered >= MERCHANT_MEMORY || merchant === Logic.FALLBACK_MERCHANT || Object.prototype.hasOwnProperty.call(merchantCategories, merchant)) {
        continue;
      }
      merchantCategories[merchant] = expense.value.category;
      remembered += 1;
    }
    return {
      currency: Logic.CURRENCY,
      thisMonth: Logic.formatCents(summary.totalCents),
      byCategory: byCategory,
      recent: recent,
      merchantCategories: merchantCategories,
      categories: Logic.CATEGORIES.slice()
    };
  }

  return {
    context: buildContext,
    handlers: {
      add_expense: addExpense,
      edit_expense: editExpense,
      delete_expense: deleteExpense,
      month_total: monthTotal
    }
  };
})();

// The settings engine (repair lanes W5, founder 2026-11-22), after MoneyLogic so MoneyLogic stays the first copied block
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
var SETTINGS_CATALOGUE = {"entries":[{"key":"page.colour","label":"Background colour","type":"colour","part":"page","selector":":root","css":"--bg","default":"#FFFFFF"},{"key":"text.colour","label":"Text colour","type":"colour","part":"text","selector":":root","css":"--ink","default":"#101210"},{"key":"greyText.colour","label":"Grey text colour (dates, percentages, month)","type":"colour","part":"grey-text","selector":":root","css":"--ink2","default":"#848584"},{"key":"accent.colour","label":"Main colour (Add button and Save)","type":"colour","part":"accent","selector":":root","css":"--accent","default":"#101210"},{"key":"accentText.colour","label":"Text and + on the main buttons colour","type":"colour","part":"accent-text","selector":":root","css":"--accent-ink","default":"#FFFFFF"},{"key":"page.size","label":"Text size (everything on the page)","type":"size","part":"page","selector":".screen","default":"m"},{"key":"page.theme","label":"Appearance (light or dark)","type":"choice","part":"page","values":["auto","light","dark"],"default":"auto"},{"key":"title.colour","label":"Money title colour","type":"colour","part":"title","selector":".top-row .title","css":"color","default":"#101210"},{"key":"title.size","label":"Money title size","type":"size","part":"title","selector":".top-row .title","default":"m"},{"key":"title.show","label":"Money title","type":"show","part":"title","selector":".top-row .title","default":true},{"key":"help.show","label":"Help (?) button","type":"show","part":"help","selector":".help","default":true},{"key":"month.colour","label":"Month name colour","type":"colour","part":"month","selector":".month","css":"color","default":"#848584"},{"key":"month.size","label":"Month name and arrows size","type":"size","part":"month","selector":".month","default":"m"},{"key":"monthArrows.show","label":"Previous and next month arrows","type":"show","part":"month-arrows","selector":".month .arrow","default":true},{"key":"total.colour","label":"Month total colour","type":"colour","part":"total","selector":".total","css":"color","default":"#101210"},{"key":"total.size","label":"Month total size","type":"size","part":"total","selector":".total","default":"m"},{"key":"total.show","label":"Month total","type":"show","part":"total","selector":".total","default":true},{"key":"bar.size","label":"Category bar size","type":"size","part":"bar","selector":".stack","default":"m"},{"key":"bar.show","label":"Category bar","type":"show","part":"bar","selector":".stack","default":true},{"key":"cards.colour","label":"Cards background colour (categories, items)","type":"colour","part":"cards","selector":":root","css":"--card","default":"#F5F6F3"},{"key":"categories.size","label":"Category list size","type":"size","part":"categories","selector":".cat","default":"m"},{"key":"categories.show","label":"Category list","type":"show","part":"categories","selector":".card:has(.cat)","default":true},{"key":"percentages.show","label":"Percentages in the category list","type":"show","part":"percentages","selector":".cat .pct","default":true},{"key":"headings.colour","label":"Headings colour (Expenses, Items)","type":"colour","part":"headings","selector":".lab","css":"color","default":"#101210"},{"key":"headings.size","label":"Headings size (Expenses, Items)","type":"size","part":"headings","selector":".lab","default":"m"},{"key":"rows.size","label":"Expense rows size","type":"size","part":"rows","selector":".row","default":"m"},{"key":"merchants.colour","label":"Expense names colour","type":"colour","part":"merchants","selector":".row .t","css":"color","default":"#101210"},{"key":"rowDetails.colour","label":"Date and category under each expense colour","type":"colour","part":"row-details","selector":".row .d","css":"color","default":"#848584"},{"key":"rowDetails.show","label":"Date and category under each expense","type":"show","part":"row-details","selector":".row .d","default":true},{"key":"amounts.colour","label":"Expense amounts colour","type":"colour","part":"amounts","selector":".row .amt, .cat .amt","css":"color","default":"#101210"},{"key":"icons.size","label":"Category letter tiles size","type":"size","part":"icons","selector":".row .icon","default":"m"},{"key":"icons.show","label":"Category letter tiles","type":"show","part":"icons","selector":".row .icon","default":true},{"key":"clip.show","label":"Receipt clip on an expense","type":"show","part":"clip","selector":".clip","default":true},{"key":"addButton.colour","label":"Round add (+) button colour","type":"colour","part":"add-button","selector":".fab","css":"background-color","default":"#101210"},{"key":"addButton.size","label":"Round add (+) button size","type":"size","part":"add-button","selector":".fab","default":"m"},{"key":"addButton.show","label":"Round add (+) button","type":"show","part":"add-button","selector":".fab","default":true},{"key":"detailAmount.colour","label":"Amount on an expense's page colour","type":"colour","part":"detail-amount","selector":".hero .big","css":"color","default":"#101210"},{"key":"detailAmount.size","label":"Amount on an expense's page size","type":"size","part":"detail-amount","selector":".hero .big","default":"m"},{"key":"detailMerchant.size","label":"Name on an expense's page size","type":"size","part":"detail-merchant","selector":".hero .merchant","default":"m"},{"key":"detailDate.show","label":"Date on an expense's page","type":"show","part":"detail-date","selector":".hero .when","default":true},{"key":"receipt.show","label":"Receipt photo on an expense's page","type":"show","part":"receipt","selector":".receipt","default":true},{"key":"deleteButton.colour","label":"Delete Expense button colour","type":"colour","part":"delete-button","selector":".delete","css":"background-color","default":"#F5F6F3"},{"key":"deleteButton.textColour","label":"Delete Expense button text colour","type":"colour","part":"delete-button","selector":".delete","css":"color","default":"#101210"},{"key":"deleteButton.show","label":"Delete Expense button","type":"show","part":"delete-button","selector":".delete","default":true,"tools":["money.delete_expense"]},{"key":"buttons.colour","label":"Small round buttons colour (arrows, ?, Back, Edit)","type":"colour","part":"buttons","selector":":root","css":"--chip","default":"#F1F2EF"},{"key":"sheet.colour","label":"Add Expense sheet background colour","type":"colour","part":"sheet","selector":":root","css":"--sheet","default":"#FFFFFF"},{"key":"keypad.colour","label":"Keypad keys colour","type":"colour","part":"keypad","selector":":root","css":"--key","default":"#F1F2EF"},{"key":"keypad.size","label":"Keypad size","type":"size","part":"keypad","selector":".keypad","default":"m"},{"key":"toast.colour","label":"Undo message colour","type":"colour","part":"toast","selector":":root","css":"--toast","default":"#101210"},{"key":"dates.format","label":"Date format","type":"dateFormat","part":"dates","default":"auto"}]};
/* copied from index.html: end */

// The settings engine's set_setting, and "turned off" for a hidden feature's tool (repair lanes W5)
MidasSidekickTools = MidasSettings.attachTools(MidasSidekickTools, { sidekickId: "money", catalogue: SETTINGS_CATALOGUE });

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSidekickTools;
}
