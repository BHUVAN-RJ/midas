// Schema changes a repair may make to a copy's manifest.json "types" (founder, 2026-10-15:
// backward compatible by default; add only). Every record the user already has must still pass,
// and an older phone's writes must too, so a repair may add optional fields and new types but
// never remove, rename or narrow anything:
//   - a key prefix removed, or its "$type" changed
//   - a field (properties / $defs / patternProperties entry) removed: a rename is a remove + add
//   - "type", "format", "pattern", "const", "$ref", "multipleOf" or a combinator changed
//   - a new required field
//   - a limit tightened (max* lower, min* higher, a new limit where there was none)
//   - an enum losing a value (an enum may grow: open value lists, plan section 2)
//   - uniqueItems turned on; additionalProperties / items / propertyNames narrowed
// Whether a breaking change may still be published is decided in one place, breakingChangeVerdict
// below. It refuses every one (founder decision 2026-10-19, docs/PRODUCT.md: repairs make no
// breaking schema change, with or without a migration). Should that decision ever change, only
// that one function changes, not the comparison.

// Words that describe a schema without constraining a value; changing them breaks nothing.
const ANNOTATION_KEYWORDS = new Set(["title", "description", "default", "examples", "$comment", "deprecated", "readOnly", "writeOnly"]);
// A lower value accepts less.
const UPPER_LIMIT_KEYWORDS = new Set(["maxLength", "maxItems", "maxProperties", "maximum", "exclusiveMaximum"]);
// A higher value accepts less.
const LOWER_LIMIT_KEYWORDS = new Set(["minLength", "minItems", "minProperties", "minimum", "exclusiveMinimum"]);
// Maps of named sub-schemas: removing a name breaks, a shared name is compared.
const SCHEMA_MAP_KEYWORDS = new Set(["properties", "$defs", "patternProperties"]);
// One sub-schema each: a new one where there was none narrows, a shared one is compared.
const SUBSCHEMA_KEYWORDS = new Set(["items", "additionalProperties", "propertyNames", "contains", "not"]);

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function problemAt(problems, path, text) {
  problems.push(`${path} ${text}`);
}

// A sub-schema that accepts every value: true, {} or absent.
function acceptsAnything(schema) {
  if (schema === undefined || schema === true) {
    return true;
  }
  return isPlainObject(schema) && Object.keys(schema).length === 0;
}

function compareSchemaMap(keyword, oldMap, newMap, path, problems) {
  if (!isPlainObject(oldMap)) {
    return;
  }
  const newEntries = isPlainObject(newMap) ? newMap : {};
  for (const name of Object.keys(oldMap)) {
    const entryPath = keyword === "properties" ? `${path}.${name}` : `${path}.${keyword}.${name}`;
    if (!(name in newEntries)) {
      problemAt(problems, entryPath, "was removed (a rename is a remove; add a new field instead)");
      continue;
    }
    compareSchema(oldMap[name], newEntries[name], entryPath, problems);
  }
}

function compareSubschema(keyword, oldSchema, newSchema, path, problems) {
  const keywordPath = `${path}.${keyword}`;
  if (acceptsAnything(newSchema)) {
    return;
  }
  if (acceptsAnything(oldSchema)) {
    problemAt(problems, keywordPath, "was added, so values that passed before may not");
    return;
  }
  compareSchema(oldSchema, newSchema, keywordPath, problems);
}

function compareRequired(oldRequired, newRequired, path, problems) {
  const before = Array.isArray(oldRequired) ? oldRequired : [];
  const after = Array.isArray(newRequired) ? newRequired : [];
  for (const fieldName of after) {
    if (!before.includes(fieldName)) {
      problemAt(problems, `${path}.${fieldName}`, "became required (new fields must be optional)");
    }
  }
}

function compareEnum(oldEnum, newEnum, path, problems) {
  if (newEnum === undefined) {
    return;
  }
  if (oldEnum === undefined) {
    problemAt(problems, path, "gained a fixed list of values (enum)");
    return;
  }
  for (const oldValue of oldEnum) {
    const stillAllowed = newEnum.some(function isSameValue(newValue) {
      return sameJson(newValue, oldValue);
    });
    if (!stillAllowed) {
      problemAt(problems, path, `no longer allows ${JSON.stringify(oldValue)}`);
    }
  }
}

function compareLimit(keyword, oldLimit, newLimit, path, problems) {
  if (newLimit === undefined) {
    return;
  }
  if (oldLimit === undefined) {
    problemAt(problems, path, `gained ${keyword} ${newLimit}`);
    return;
  }
  const isUpper = UPPER_LIMIT_KEYWORDS.has(keyword);
  const tightened = isUpper ? newLimit < oldLimit : newLimit > oldLimit;
  if (tightened) {
    problemAt(problems, path, `${keyword} went from ${oldLimit} to ${newLimit}`);
  }
}

// Adds to `problems` every way newSchema accepts less than oldSchema, as "<path> <what>".
export function compareSchema(oldSchema, newSchema, path, problems) {
  if (sameJson(oldSchema, newSchema)) {
    return;
  }
  if (!isPlainObject(oldSchema) || !isPlainObject(newSchema)) {
    if (!acceptsAnything(newSchema)) {
      problemAt(problems, path, "changed");
    }
    return;
  }
  const keywords = new Set([...Object.keys(oldSchema), ...Object.keys(newSchema)]);
  for (const keyword of keywords) {
    const oldValue = oldSchema[keyword];
    const newValue = newSchema[keyword];
    if (ANNOTATION_KEYWORDS.has(keyword) || sameJson(oldValue, newValue)) {
      continue;
    }
    if (SCHEMA_MAP_KEYWORDS.has(keyword)) {
      compareSchemaMap(keyword, oldValue, newValue, path, problems);
    } else if (SUBSCHEMA_KEYWORDS.has(keyword)) {
      compareSubschema(keyword, oldValue, newValue, path, problems);
    } else if (keyword === "required") {
      compareRequired(oldValue, newValue, path, problems);
    } else if (keyword === "enum") {
      compareEnum(oldValue, newValue, path, problems);
    } else if (UPPER_LIMIT_KEYWORDS.has(keyword) || LOWER_LIMIT_KEYWORDS.has(keyword)) {
      compareLimit(keyword, oldValue, newValue, path, problems);
    } else if (keyword === "uniqueItems") {
      if (newValue === true) {
        problemAt(problems, path, "now requires unique items");
      }
    } else {
      // type, format, pattern, const, $ref, multipleOf, allOf, anyOf, oneOf, if/then/else,
      // dependentRequired and anything else: any change counts as a change of meaning.
      problemAt(problems, path, `changed its ${keyword}`);
    }
  }
}

// Every backward-incompatible difference between two manifest "types" blocks, as text. Empty
// when the new block only adds. A manifest without "types" is treated as an empty block.
export function schemaChangeProblems(oldTypes, newTypes) {
  const before = isPlainObject(oldTypes) ? oldTypes : {};
  const after = isPlainObject(newTypes) ? newTypes : {};
  const problems = [];
  for (const prefix of Object.keys(before)) {
    const oldEntry = before[prefix];
    const newEntry = after[prefix];
    if (newEntry === undefined) {
      problems.push(`types["${prefix}"] was removed`);
      continue;
    }
    const typeName = oldEntry?.$type ?? prefix;
    if (oldEntry?.$type !== newEntry?.$type) {
      problems.push(`types["${prefix}"].$type changed from "${oldEntry?.$type}" to "${newEntry?.$type}"`);
      continue;
    }
    compareSchema(oldEntry?.schema, newEntry?.schema, typeName, problems);
  }
  return problems;
}

// The one place that decides whether a schema change may be published. Returns null to allow it,
// or the refusal { reason, detail } for the job. Every breaking change is refused (founder decision
// 2026-10-19, docs/PRODUCT.md), migration or not. This is the final rule; it lives here alone so a
// future change of that decision touches this function only.
export const SCHEMA_REFUSAL_REASON = "schema not backward compatible";

export function breakingChangeVerdict({ problems }) {
  if (problems.length === 0) {
    return null;
  }
  return { reason: SCHEMA_REFUSAL_REASON, detail: problems.join("; ") };
}

// Key prefixes the page writes with a literal key (store.set / store.update('<prefix>...')).
// Reads are left out on purpose: a page may still read a retired prefix to move it forward
// (reminders queries task: once). Keys built only from variables are not seen.
const LITERAL_WRITE_PATTERN = /store\.(?:set|update)\(\s*['"`]([a-z][a-z0-9-]*:)/g;
const SHELL_PREFIXES = ["widget:", "request:"];

export function literalWritePrefixes(html) {
  const prefixes = new Set();
  for (const match of html.matchAll(LITERAL_WRITE_PATTERN)) {
    prefixes.add(match[1]);
  }
  return [...prefixes].sort();
}

// Everything the runner would refuse about a copy's schema, from the manifest and page texts:
// [] when the change only adds and every literal write is declared. Shared by the runner and the
// agent's check tool so both say the same thing.
export function schemaRuleProblems({ manifestBefore, manifestAfter, htmlAfter }) {
  const problems = [];
  const refusal = breakingChangeVerdict({ problems: schemaChangeProblems(manifestBefore?.types, manifestAfter?.types) });
  if (refusal !== null) {
    problems.push(`${refusal.reason}: ${refusal.detail}`);
  }
  const undeclared = undeclaredWritePrefixes(htmlAfter, manifestAfter?.types);
  if (undeclared.length > 0) {
    problems.push(`schema missing: the page writes ${undeclared.join(", ")} but manifest.json types declares no such prefix`);
  }
  return problems;
}

// Prefixes the page writes that the manifest declares no type for. The shell would refuse those
// writes on the phone ("no record type is declared"), so the repair must add the type.
export function undeclaredWritePrefixes(html, types) {
  if (!isPlainObject(types)) {
    return [];
  }
  const written = literalWritePrefixes(html);
  return written.filter(function isUndeclared(prefix) {
    return !SHELL_PREFIXES.includes(prefix) && !(prefix in types);
  });
}
