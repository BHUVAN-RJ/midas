// Injected at document start into every page the shield opens (webkit-page.swift). page-open.mjs
// wraps this file with the record validator (shell/sdk/record-schema.js), the shell's own record
// types (shell/sdk/shell-types.js) and the step's config, then calls shieldPrelude with them.
//
// It stands in for the shell: the page's store calls (POST <origin>/_midas/store, the same
// protocol shell/Midas/SidekickStoreChannel.swift answers) go to an in-memory copy of the
// person's records, every write is stamped and checked against the copy's manifest types as the
// shell does (RecordTypeGate.swift), and nothing reaches the network. It records every console
// error, uncaught error and unhandled rejection, optionally taps one page control, and posts one
// report with the step's nonce.
//
// config: { nonce, sidekickId, records: [{ key, value }], types, action: null | "<data-action>",
//           settleMs, maxSettleMs }
function shieldPrelude(config, recordSchema, shellTypes) {
  'use strict';

  var STORE_PATH = '/_midas/store';
  var FILES_PATH = '/_midas/files';
  var errors = [];
  var writes = [];
  var records = new Map();
  var inFlight = 0;
  var lastActivityAt = Date.now();
  var postReport = window.webkit.messageHandlers.shield.postMessage.bind(window.webkit.messageHandlers.shield);
  var realSetTimeout = window.setTimeout.bind(window);

  /* ---------- Errors ---------- */

  function describe(value) {
    if (value instanceof Error) {
      return value.message;
    }
    if (typeof value === 'string') {
      return value;
    }
    try {
      return JSON.stringify(value);
    } catch (jsonError) {
      return String(value);
    }
  }

  function recordConsoleError() {
    var parts = [];
    for (var index = 0; index < arguments.length; index += 1) {
      parts.push(describe(arguments[index]));
    }
    errors.push('console.error: ' + parts.join(' '));
  }

  // Locked, so a page cannot quietly swap console.error for its own and hide what it logs: a
  // strict-mode assignment then throws, and that throw is caught below.
  Object.defineProperty(console, 'error', { value: recordConsoleError, writable: false, configurable: false });

  function recordUncaught(event) {
    var where = event.lineno ? ' (line ' + event.lineno + ')' : '';
    errors.push('uncaught: ' + (event.message || describe(event.error)) + where);
  }

  function recordRejection(event) {
    errors.push('unhandled rejection: ' + describe(event.reason));
  }

  // Capture phase, added before any page script runs, so the page's own listeners come after
  window.addEventListener('error', recordUncaught, true);
  window.addEventListener('unhandledrejection', recordRejection, true);

  /* ---------- The store ---------- */

  var allTypes = null;
  if (config.types && typeof config.types === 'object') {
    allTypes = Object.assign({}, shellTypes, config.types);
  }

  function loadRecords() {
    for (var index = 0; index < config.records.length; index += 1) {
      var record = config.records[index];
      records.set(record.key, record.value);
    }
  }

  // As the shell: stamp $type from the key, then check the record against its type
  function checkedValue(key, value) {
    if (allTypes === null) {
      return { value: value, problem: null };
    }
    var stamped = recordSchema.stampType(allTypes, key, value);
    var problem = recordSchema.checkRecord(allTypes, key, stamped);
    return { value: stamped, problem: problem };
  }

  function storeWrite(op, key, value) {
    var checked = checkedValue(key, value);
    writes.push({ op: op, key: key, problem: checked.problem });
    if (checked.problem !== null) {
      return { ok: false, error: checked.problem };
    }
    records.set(key, checked.value);
    return { ok: true, value: checked.value };
  }

  function queryRecords(prefix) {
    var keys = Array.from(records.keys());
    var matching = keys.filter(function startsWithPrefix(key) {
      return key.indexOf(prefix) === 0;
    });
    matching.sort();
    return matching.map(function asRecord(key) {
      return { key: key, value: records.get(key) };
    });
  }

  function answerStore(request) {
    var key = typeof request.key === 'string' ? request.key : null;
    if (request.op === 'get') {
      return { ok: true, value: records.has(key) ? records.get(key) : null };
    }
    if (request.op === 'set') {
      return storeWrite('set', key, request.value);
    }
    if (request.op === 'update') {
      var merged = recordSchema.mergePatch(records.has(key) ? records.get(key) : null, request.patch);
      return storeWrite('update', key, merged);
    }
    if (request.op === 'delete') {
      writes.push({ op: 'delete', key: key, problem: null });
      records.delete(key);
      return { ok: true };
    }
    if (request.op === 'query') {
      return { ok: true, records: queryRecords(typeof request.prefix === 'string' ? request.prefix : '') };
    }
    if (request.op === 'shell') {
      return { ok: true, requests: [] };
    }
    if (request.op === 'focus') {
      return { ok: true, focus: null };
    }
    if (request.op === 'widget-placed') {
      return { ok: true, placed: false };
    }
    return { ok: false, error: 'unknown op ' + request.op };
  }

  function jsonResponse(body, status) {
    var options = { status: status, headers: { 'Content-Type': 'application/json' } };
    return new Response(JSON.stringify(body), options);
  }

  function pathOf(url) {
    try {
      return new URL(String(url), window.location.href).pathname;
    } catch (urlError) {
      return '';
    }
  }

  // Every answer is ready at once; the call still counts as activity for settle()
  function markAnswered() {
    inFlight -= 1;
    lastActivityAt = Date.now();
  }

  function shieldFetch(input, options) {
    var url = typeof input === 'string' ? input : (input && input.url) || String(input);
    var path = pathOf(url);
    inFlight += 1;
    lastActivityAt = Date.now();
    if (path === STORE_PATH) {
      var reply;
      try {
        reply = answerStore(JSON.parse(options && options.body ? options.body : '{}'));
      } catch (parseError) {
        reply = { ok: false, error: 'body is not JSON' };
      }
      var storeResponse = jsonResponse(reply, reply.ok ? 200 : 400);
      markAnswered();
      return Promise.resolve(storeResponse);
    }
    if (path === FILES_PATH || path.indexOf(FILES_PATH + '/') === 0) {
      var filesResponse = jsonResponse({ ok: false, error: 'files are not available' }, 404);
      markAnswered();
      return Promise.resolve(filesResponse);
    }
    // A Sidekick has no network on the phone either (CSP): fail as fetch does there
    markAnswered();
    return Promise.reject(new TypeError('Load failed'));
  }

  window.fetch = shieldFetch;
  loadRecords();

  /* ---------- What drew ---------- */

  function isVisible(element) {
    var box = element.getBoundingClientRect();
    if (box.width <= 0 || box.height <= 0) {
      return false;
    }
    var style = window.getComputedStyle(element);
    return style.visibility !== 'hidden' && style.display !== 'none' && style.opacity !== '0';
  }

  function visibleElementCount() {
    if (!document.body) {
      return 0;
    }
    var all = document.body.querySelectorAll('*');
    var count = 0;
    for (var index = 0; index < all.length; index += 1) {
      if (isVisible(all[index])) {
        count += 1;
      }
    }
    return count;
  }

  /* ---------- The step ---------- */

  // Waits until no store call is open and nothing happened for settleMs, or maxSettleMs passed
  function settle(startedAt, done) {
    var now = Date.now();
    var quiet = inFlight === 0 && now - lastActivityAt >= config.settleMs;
    if (quiet || now - startedAt >= config.maxSettleMs) {
      done();
      return;
    }
    realSetTimeout(function settleAgain() {
      settle(startedAt, done);
    }, 50);
  }

  function firstVisibleControl(action) {
    var candidates = document.querySelectorAll('[data-action]');
    for (var index = 0; index < candidates.length; index += 1) {
      var candidate = candidates[index];
      if (candidate.getAttribute('data-action') === action && isVisible(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  function writtenValues() {
    var values = {};
    for (var index = 0; index < writes.length; index += 1) {
      var key = writes[index].key;
      if (records.has(key)) {
        values[key] = records.get(key);
      }
    }
    return values;
  }

  function sendReport(actionResult) {
    var report = {
      nonce: config.nonce,
      errors: errors,
      writes: writes,
      written: writtenValues(),
      visibleElements: visibleElementCount(),
      textLength: document.body ? document.body.innerText.trim().length : 0,
      action: actionResult,
    };
    postReport(JSON.stringify(report));
  }

  function tapControlThenReport() {
    if (config.action === null) {
      sendReport(null);
      return;
    }
    var control = firstVisibleControl(config.action);
    if (control === null) {
      sendReport({ name: config.action, found: false });
      return;
    }
    try {
      control.click();
    } catch (clickError) {
      errors.push('tap ' + config.action + ': ' + describe(clickError));
    }
    lastActivityAt = Date.now();
    settle(Date.now(), function reportAfterTap() {
      sendReport({ name: config.action, found: true });
    });
  }

  function onLoad() {
    settle(Date.now(), tapControlThenReport);
  }

  window.addEventListener('load', onLoad);
}
