// Record types of the Sidekicks built into the shell (Make, founder 2026-10-24;
// docs/briefs/make-contract.md section 2). Shaped like a manifest's "types" block and checked by
// the same validator (record-schema.js), on the phone and on the server. Keyed by Sidekick id:
// a native Sidekick has no manifest, so its schemas live here.
//
// The person's "make" store:
//   req:<reqId>                       make.request   one thing the person asked for
//   message:<reqId>:<msgId>           make.message   one line in the request's thread
//   card:<reqId>:<cardId>             make.card      a question card (written by the server only)
//   answer:<reqId>:<cardId>           make.answer    the person's pick or own words on a card
//
// The founder's "make-inbox" store holds the same types under keys that start with the person's
// user id (req:<userId>:<reqId>, ...), plus person:<userId>. Every inbox record carries userId.
// Unknown fields are kept.
var MAKE_ID_PATTERN = '^[A-Za-z0-9_-]{8,40}$';
var MAKE_FILE_PATTERN = '^file:[A-Za-z0-9_-]{1,64}$';
var MAKE_USER_ID = { type: 'string', pattern: '^[A-Za-z0-9_-]{1,64}$' };
var MAKE_TIME = { type: 'string', format: 'date-time' };

var MAKE_OPTION_SCHEMA = {
  type: 'object',
  required: ['id'],
  properties: {
    id: { type: 'string', pattern: MAKE_ID_PATTERN },
    label: { type: 'string', minLength: 1, maxLength: 200 },
    image: { type: 'string', pattern: MAKE_FILE_PATTERN },
  },
};

var MAKE_TYPES = {
  'req:': {
    $type: 'make.request',
    schema: {
      type: 'object',
      required: ['title', 'status', 'createdAt', 'updatedAt'],
      properties: {
        $type: { type: 'string' },
        userId: MAKE_USER_ID,
        title: { type: 'string', minLength: 1, maxLength: 200 },
        status: { type: 'string', enum: ['sent', 'figuring_out', 'looking', 'building', 'built'] },
        sidekickId: { type: 'string', pattern: '^[a-z0-9-]{1,40}$' },
        plan: { type: 'string', minLength: 1, maxLength: 200 },
        createdAt: MAKE_TIME,
        updatedAt: MAKE_TIME,
        builtAt: MAKE_TIME,
      },
      // A built request names the Sidekick it became and the one-line plan.
      if: { required: ['status'], properties: { status: { const: 'built' } } },
      then: { required: ['sidekickId', 'plan'] },
    },
  },
  'message:': {
    $type: 'make.message',
    schema: {
      type: 'object',
      required: ['from', 'text', 'sentAt'],
      properties: {
        $type: { type: 'string' },
        userId: MAKE_USER_ID,
        from: { type: 'string', enum: ['person', 'maker'] },
        text: { type: 'string', minLength: 1, maxLength: 4000 },
        sentAt: MAKE_TIME,
      },
    },
  },
  'card:': {
    $type: 'make.card',
    schema: {
      type: 'object',
      required: ['question', 'kind', 'options', 'allowsOwnWords', 'sentAt'],
      properties: {
        $type: { type: 'string' },
        userId: MAKE_USER_ID,
        question: { type: 'string', minLength: 1, maxLength: 300 },
        kind: { type: 'string', enum: ['choice', 'design'] },
        options: { type: 'array', minItems: 1, maxItems: 8, items: MAKE_OPTION_SCHEMA },
        allowsOwnWords: { type: 'boolean' },
        sentAt: MAKE_TIME,
      },
      // Every option of a design card is a picture.
      if: { required: ['kind'], properties: { kind: { const: 'design' } } },
      then: { properties: { options: { items: { required: ['image'] } } } },
    },
  },
  'answer:': {
    $type: 'make.answer',
    schema: {
      type: 'object',
      required: ['cardId', 'sentAt'],
      properties: {
        $type: { type: 'string' },
        userId: MAKE_USER_ID,
        cardId: { type: 'string', pattern: MAKE_ID_PATTERN },
        optionId: { type: 'string', pattern: MAKE_ID_PATTERN },
        text: { type: 'string', minLength: 1, maxLength: 4000 },
        sentAt: MAKE_TIME,
      },
      // Exactly one of a picked option or the person's own words.
      oneOf: [{ required: ['optionId'] }, { required: ['text'] }],
    },
  },
  'person:': {
    $type: 'make.person',
    schema: {
      type: 'object',
      required: ['name', 'firstAt'],
      properties: {
        $type: { type: 'string' },
        userId: MAKE_USER_ID,
        name: { type: 'string', minLength: 1, maxLength: 64 },
        firstAt: MAKE_TIME,
      },
    },
  },
};

var MidasNativeTypes = {
  make: MAKE_TYPES,
  'make-inbox': MAKE_TYPES,
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasNativeTypes;
}
