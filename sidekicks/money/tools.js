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

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasSidekickTools;
}
