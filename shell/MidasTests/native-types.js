// A copy of shell/sdk/native-types.js as docs/briefs/make-contract.md section 2 defines it, for the
// shell tests until the backend builder's file lands (contract section 9). The backend owns the
// real file; once it is in shell/sdk the app ships that one and these tests keep using this copy.
//
// Record types of the Sidekicks built into the shell, shaped like a manifest's "types" block and
// checked by the same validator (record-schema.js), on the phone and on the server.
//
//   make        the person's store: req:<reqId>, message:<reqId>:<msgId>, card:<reqId>:<cardId>,
//               answer:<reqId>:<cardId>
//   make-inbox  the founder's store: person:<userId>, req:<userId>:<reqId>, and the same records
//               with <userId>: in front; every inbox record also carries userId
//
// Unknown fields are kept.
var MAKE_ID_PATTERN = '^[A-Za-z0-9_-]{8,40}$';

var MAKE_TYPES = {
  'req:': {
    $type: 'make.request',
    schema: {
      type: 'object',
      required: ['title', 'status', 'createdAt', 'updatedAt'],
      properties: {
        $type: { type: 'string' },
        title: { type: 'string', minLength: 1, maxLength: 200 },
        status: { enum: ['sent', 'figuring_out', 'looking', 'building', 'built'] },
        createdAt: { type: 'string', format: 'date-time' },
        updatedAt: { type: 'string', format: 'date-time' },
        sidekickId: { type: 'string', pattern: '^[a-z0-9-]{1,40}$' },
        plan: { type: 'string', minLength: 1, maxLength: 200 },
        builtAt: { type: 'string', format: 'date-time' },
        userId: { type: 'string', minLength: 1 },
      },
      if: { properties: { status: { const: 'built' } }, required: ['status'] },
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
        from: { enum: ['person', 'maker'] },
        text: { type: 'string', minLength: 1, maxLength: 4000 },
        sentAt: { type: 'string', format: 'date-time' },
        userId: { type: 'string', minLength: 1 },
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
        question: { type: 'string', minLength: 1, maxLength: 300 },
        kind: { enum: ['choice', 'design'] },
        options: {
          type: 'array',
          minItems: 1,
          maxItems: 8,
          items: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'string', pattern: MAKE_ID_PATTERN },
              label: { type: 'string', minLength: 1, maxLength: 200 },
              image: { type: 'string', pattern: '^file:[A-Za-z0-9_-]{8,64}$' },
            },
          },
        },
        allowsOwnWords: { type: 'boolean' },
        sentAt: { type: 'string', format: 'date-time' },
        userId: { type: 'string', minLength: 1 },
      },
      // Every design option has a picture
      if: { properties: { kind: { const: 'design' } }, required: ['kind'] },
      then: { properties: { options: { items: { required: ['id', 'image'] } } } },
    },
  },
  'answer:': {
    $type: 'make.answer',
    schema: {
      type: 'object',
      required: ['cardId', 'sentAt'],
      properties: {
        $type: { type: 'string' },
        cardId: { type: 'string', pattern: MAKE_ID_PATTERN },
        optionId: { type: 'string', pattern: MAKE_ID_PATTERN },
        text: { type: 'string', minLength: 1, maxLength: 4000 },
        sentAt: { type: 'string', format: 'date-time' },
        userId: { type: 'string', minLength: 1 },
      },
      // Exactly one of a picked option or the person's own words
      oneOf: [
        { required: ['optionId'], not: { required: ['text'] } },
        { required: ['text'], not: { required: ['optionId'] } },
      ],
    },
  },
  'person:': {
    $type: 'make.person',
    schema: {
      type: 'object',
      required: ['name', 'firstAt'],
      properties: {
        $type: { type: 'string' },
        name: { type: 'string' },
        firstAt: { type: 'string', format: 'date-time' },
        userId: { type: 'string', minLength: 1 },
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
