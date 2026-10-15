// Record types the shell owns, in every Sidekick (unified data plan, section 4, "shell" row).
// Shaped like a manifest's "types" block and checked by the same validator (record-schema.js),
// on the phone and on the server. A Sidekick's manifest may not declare these prefixes.
//
//   widget:<name>          midas.widget   what a Home Screen widget shows (docs/WIDGETS.md); the
//                                         shell's SidekickWidgetDescription checks the pieces
//   request:<id>           midas.request  a Sidekick asks the shell for a native action; the shell
//                                         writes the outcome into the same record
//
// Few required fields and open value lists (rules 3 and 5): a new request kind or status needs no
// new build. Unknown fields are kept.
var MidasShellTypes = {
  'widget:': {
    $type: 'midas.widget',
    schema: {
      type: 'object',
      required: ['name'],
      properties: {
        $type: { type: 'string' },
        version: { type: 'integer', minimum: 1 },
        name: { type: 'string', minLength: 1, maxLength: 40 },
        tint: { type: 'string', maxLength: 40 },
        sources: { type: 'object', maxProperties: 8 },
        small: { type: 'object' },
        medium: { type: 'object' },
        large: { type: 'object' },
      },
    },
  },
  'request:': {
    $type: 'midas.request',
    schema: {
      type: 'object',
      required: ['kind'],
      properties: {
        $type: { type: 'string' },
        kind: { type: 'string', minLength: 1, maxLength: 80 },
        status: { type: 'string', minLength: 1, maxLength: 40 },
        createdAt: { type: 'string', format: 'date-time' },
        finishedAt: { type: 'string', format: 'date-time' },
        error: { type: 'string', maxLength: 500 },
        parts: { type: 'integer', minimum: 0 },
        prefix: { type: 'string', maxLength: 200 },
        lists: { type: 'integer', minimum: 0 },
        reminders: { type: 'integer', minimum: 0 },
      },
    },
  },
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasShellTypes;
}
