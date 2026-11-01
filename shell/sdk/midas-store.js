// Midas local store for Sidekicks. Paste this into the Sidekick bundle's inline script (its
// hash goes into the deploy like any other script). It talks to the Midas shell on the phone
// through plain fetch to the Sidekick's own origin: no bridge, works without a connection.
//
//   await store.set('reminder:42', { at: new Date(2026, 9, 9, 9, 0).toISOString(),
//                                    title: 'Call mom', repeat: { every: 'week' },
//                                    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone });
//   const reminder = await store.get('reminder:42');     // null if absent
//   const all = await store.query('reminder:');          // [{ key, value }], sorted by key
//   await store.update('reminder:42', { done: true, snoozedUntil: null });  // merge, RFC 7396
//   await store.delete('reminder:42');
//   var ref = await store.putFile(blob);                 // "file:<id>", put it in a record
//   img.src = await store.fileUrl(ref);                  // a blob: URL for the file's bytes
//
// Every record has a type: the Sidekick's manifest.json declares one JSON Schema per key prefix
// under "types", and the shell stamps "$type" and checks the value on every set and update. A
// record that does not fit is rejected at write time: the promise rejects with the reason and
// nothing is written. `update` merges a patch into the stored record: a field set to null is
// removed, an object field is merged, every other field is replaced.
//
// A record holds at most 64 KB. Images and other files go through `putFile` (up to 20 MB): the
// shell keeps the file, sends it to the server before the record that points to it, and gives it
// back with `fileUrl`. A record over the limit because of a `data:` URL is fixed the same way.
//
// Opened from a jess work log card (founder, 2026-10-31), the page is told which record jess
// changed: give every record's element `data-key="<its key>"` and the change is found, centred
// and marked in Volt by itself. A page that shows records in lists, months or days also opens the
// one holding the key, and a page with its own scroller scrolls to it itself (the SDK only scrolls
// a container that really scrolls); an edit's old value and a deleted record's row (with Undo)
// are the page's:
//
//   var focus = await store.focus();   // { key, op: 'new'|'edit'|'delete', before } or null
//   store.markChange(element);         // centre and mark an element again (after a re-render)
var store = (function createMidasStore() {
  var storeURL = window.location.origin + '/_midas/store';
  var filesURL = window.location.origin + '/_midas/files';

  async function sendToShell(request) {
    var requestOptions = {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(request),
    };
    var response = await fetch(storeURL, requestOptions);
    var reply = await response.json();
    if (!reply.ok) {
      throw new Error(reply.error);
    }
    return reply;
  }

  async function setRecord(key, value) {
    await sendToShell({ op: 'set', key: key, value: value });
  }

  async function getRecord(key) {
    var reply = await sendToShell({ op: 'get', key: key });
    return reply.value;
  }

  async function updateRecord(key, patch) {
    var reply = await sendToShell({ op: 'update', key: key, patch: patch });
    return reply.value;
  }

  async function deleteRecord(key) {
    await sendToShell({ op: 'delete', key: key });
  }

  async function queryRecords(prefix) {
    var reply = await sendToShell({ op: 'query', prefix: prefix || '' });
    return reply.records;
  }

  async function putFile(blob) {
    // The bytes themselves, not the Blob: the shell's scheme handler gets a plain body that way.
    var bytes = await new Response(blob).arrayBuffer();
    var requestOptions = {
      method: 'POST',
      headers: { 'Content-Type': blob.type || 'application/octet-stream' },
      body: bytes,
    };
    var response = await fetch(filesURL, requestOptions);
    var reply = await response.json();
    if (!reply.ok) {
      throw new Error(reply.error);
    }
    return reply.ref;
  }

  async function fileUrl(reference) {
    var fileId = String(reference).replace(/^file:/, '');
    var response = await fetch(filesURL + '/' + encodeURIComponent(fileId));
    if (!response.ok) {
      throw new Error('no such file');
    }
    var blob = await response.blob();
    return URL.createObjectURL(blob);
  }

  // The change a jess card opened this page at; asked once, kept for the page's later calls
  var focusRequest = null;

  async function askFocus() {
    try {
      var reply = await sendToShell({ op: 'focus' });
      return reply.focus || null;
    } catch (error) {
      // An older shell does not know the op: the page opens as usual
      return null;
    }
  }

  function readFocus() {
    if (!focusRequest) {
      focusRequest = askFocus();
    }
    return focusRequest;
  }

  // The mark (docs/mockups/jess-worklog-links-2026-10-31.html): Volt in 180 ms, held 1.2 s,
  // faded over 1.2 s, with a 3 pt ink edge on the left (Volt alone is 1.2:1 on white)
  var markInMs = 180;
  var markHoldMs = 1200;
  var markFadeMs = 1200;

  // The nearest container that really scrolls; null when the page scrolls itself (a custom
  // scroller), so the SDK never moves a container the page keeps still
  function scrollingAncestor(element) {
    var current = element.parentElement;
    while (current && current !== document.body && current !== document.documentElement) {
      var overflowY = window.getComputedStyle(current).overflowY;
      if ((overflowY === 'auto' || overflowY === 'scroll') && current.scrollHeight > current.clientHeight) {
        return current;
      }
      current = current.parentElement;
    }
    var page = document.scrollingElement || document.documentElement;
    var pageOverflow = window.getComputedStyle(document.body).overflowY;
    if (pageOverflow !== 'hidden' && page.scrollHeight > window.innerHeight) {
      return page;
    }
    return null;
  }

  function centre(element) {
    var container = scrollingAncestor(element);
    if (!container) {
      return;
    }
    var box = element.getBoundingClientRect();
    var isPage = container === document.scrollingElement || container === document.documentElement;
    var containerTop = isPage ? 0 : container.getBoundingClientRect().top;
    var visibleHeight = isPage ? window.innerHeight : container.clientHeight;
    var target = container.scrollTop + (box.top - containerTop) - (visibleHeight - box.height) / 2;
    container.scrollTop = Math.max(0, target);
  }

  function markChange(element) {
    if (!element) {
      return;
    }
    centre(element);
    var ownBackground = window.getComputedStyle(element).backgroundColor;
    var total = markInMs + markHoldMs + markFadeMs;
    var lit = { backgroundColor: '#CEFF00', boxShadow: 'inset 3px 0 0 #111111' };
    var keyframes = [
      { backgroundColor: ownBackground, boxShadow: 'inset 3px 0 0 rgba(17, 17, 17, 0)', offset: 0 },
      { backgroundColor: lit.backgroundColor, boxShadow: lit.boxShadow, offset: markInMs / total },
      { backgroundColor: lit.backgroundColor, boxShadow: lit.boxShadow, offset: (markInMs + markHoldMs) / total },
      { backgroundColor: ownBackground, boxShadow: 'inset 3px 0 0 rgba(17, 17, 17, 0)', offset: 1 },
    ];
    element.animate(keyframes, { duration: total, easing: 'ease-out' });
  }

  function elementForKey(key) {
    var all = document.querySelectorAll('[data-key]');
    for (var index = 0; index < all.length; index += 1) {
      if (all[index].getAttribute('data-key') === key) {
        return all[index];
      }
    }
    return null;
  }

  // Waits up to 3 s for the page to draw the record, then marks it once
  var markWaitMs = 3000;

  async function markFocusWhenDrawn() {
    var focus = await readFocus();
    if (!focus) {
      return;
    }
    var found = elementForKey(focus.key);
    if (found) {
      markChange(found);
      return;
    }
    var observer = new MutationObserver(checkForElement);
    function checkForElement() {
      var drawn = elementForKey(focus.key);
      if (!drawn) {
        return;
      }
      observer.disconnect();
      markChange(drawn);
    }
    function stopWaiting() {
      observer.disconnect();
    }
    observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-key'] });
    window.setTimeout(stopWaiting, markWaitMs);
  }

  markFocusWhenDrawn();

  return { set: setRecord, get: getRecord, update: updateRecord, delete: deleteRecord, query: queryRecords, putFile: putFile, fileUrl: fileUrl, focus: readFocus, markChange: markChange };
})();
