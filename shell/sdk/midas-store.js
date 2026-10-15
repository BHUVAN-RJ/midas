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
//
// Every record has a type: the Sidekick's manifest.json declares one JSON Schema per key prefix
// under "types", and the shell stamps "$type" and checks the value on every set and update. A
// record that does not fit is rejected at write time: the promise rejects with the reason and
// nothing is written. `update` merges a patch into the stored record: a field set to null is
// removed, an object field is merged, every other field is replaced.
var store = (function createMidasStore() {
  var storeURL = window.location.origin + '/_midas/store';

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

  return { set: setRecord, get: getRecord, update: updateRecord, delete: deleteRecord, query: queryRecords };
})();
