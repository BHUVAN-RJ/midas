// Types for record-schema.js, for the Worker and the tests. The script itself is plain JS so the
// shell can load the same file into JavaScriptCore.

export type JsonSchema = Record<string, unknown> | boolean;

export type RecordType = {
  prefix: string;
  $type: string | undefined;
  schema: JsonSchema | undefined;
};

export type TypesBlock = Record<string, { $type?: string; schema?: JsonSchema }>;

export type RecordSchemaModule = {
  TYPE_FIELD: string;
  KNOWN_FORMATS: string[];
  /** The first problem as "<type>.<path> <problem>", or null when the value fits the schema. */
  validate(schema: JsonSchema, value: unknown, typeName?: string, rootSchema?: JsonSchema): string | null;
  /** The type whose prefix starts the key (longest prefix wins), or null. */
  typeForKey(types: unknown, key: string): RecordType | null;
  /** A copy of the value with "$type" set from its key's type. */
  stampType(types: unknown, key: string, value: unknown): unknown;
  /** Why a record cannot be stored under its key, or null. No check when types is not an object. */
  checkRecord(types: unknown, key: string, value: unknown): string | null;
  /** JSON Merge Patch (RFC 7396): a new value, neither argument changed. */
  mergePatch(target: unknown, patch: unknown): unknown;
  isKnownTimeZone(name: string): boolean;
};

declare const MidasRecordSchema: RecordSchemaModule;
export default MidasRecordSchema;
