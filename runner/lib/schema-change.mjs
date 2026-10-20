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
//   - a "not" added or widened (it then rejects more), a "contains" added or narrowed
//   - a new key prefix that overlaps an existing one ("reminder:a" next to "reminder:"): keys
//     stored under the old type would be read as the new one
// Key order inside a schema or a "const", and the order of a "type" list, mean nothing and are
// not changes. A new optional field can still clash with a field a stored record already keeps
// (record rule 4: writers keep unknown fields); newFieldClashes below finds those in the user's
// records, which only the runner has.
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
const SUBSCHEMA_KEYWORDS = new Set(["items", "additionalProperties", "propertyNames"]);

const REMOVED_ENTRY_TEXT = "was removed (a rename is a remove; add a new field instead)";

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// The same JSON text for the same value whatever the order of object keys (array order kept).
function canonicalJson(value) {
  if (Array.isArray(value)) {
    const items = value.map(canonicalJson);
    return `[${items.join(",")}]`;
  }
  if (isPlainObject(value)) {
    const names = Object.keys(value).sort();
    const fields = names.map(function canonicalField(name) {
      return `${JSON.stringify(name)}:${canonicalJson(value[name])}`;
    });
    return `{${fields.join(",")}}`;
  }
  return JSON.stringify(value) ?? "undefined";
}

function sameJson(left, right) {
  return canonicalJson(left) === canonicalJson(right);
}

// "type" is a set: "string" and ["string"] are the same, and so are ["string","null"] and
// ["null","string"]. Any other difference (a type added or removed) is a change.
function sameTypeList(left, right) {
  const leftTypes = Array.isArray(left) ? left : [left];
  const rightTypes = Array.isArray(right) ? right : [right];
  const leftSorted = [...new Set(leftTypes.map(canonicalJson))].sort();
  const rightSorted = [...new Set(rightTypes.map(canonicalJson))].sort();
  return leftSorted.join(",") === rightSorted.join(",");
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
      problemAt(problems, entryPath, REMOVED_ENTRY_TEXT);
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

// "not": S rejects what S accepts, so the direction flips: a "not" that is new, or whose S now
// accepts more, rejects values that passed before. Removing a "not" only widens.
function compareNot(oldNot, newNot, path, problems) {
  const keywordPath = `${path}.not`;
  if (newNot === undefined || newNot === false) {
    return;
  }
  if (oldNot === undefined || oldNot === false) {
    problemAt(problems, keywordPath, "was added, so values that passed before may not");
    return;
  }
  // Flipped: what the new "not" accepts that the old one did not. In that direction a "removed"
  // entry is one the new "not" gained, which narrows it (the field accepts more), so those are
  // dropped; an entry the new "not" lost widens it and is found by removedMapEntries.
  const flipped = [];
  compareSchema(newNot, oldNot, keywordPath, flipped);
  const widened = flipped.filter(function isNotGainedEntry(problem) {
    return !problem.endsWith(REMOVED_ENTRY_TEXT);
  });
  removedMapEntries(oldNot, newNot, keywordPath, widened);
  if (widened.length > 0) {
    problemAt(problems, keywordPath, `now matches more values, so the field accepts fewer (${widened.join("; ")})`);
  }
}

// Every properties / $defs / patternProperties entry oldSchema has and newSchema lacks, at any
// depth along the shared parts, as "<path> was removed".
function removedMapEntries(oldSchema, newSchema, path, problems) {
  if (!isPlainObject(oldSchema) || !isPlainObject(newSchema)) {
    return;
  }
  for (const keyword of Object.keys(oldSchema)) {
    const oldValue = oldSchema[keyword];
    const newValue = newSchema[keyword];
    if (SCHEMA_MAP_KEYWORDS.has(keyword) && isPlainObject(oldValue)) {
      const newEntries = isPlainObject(newValue) ? newValue : {};
      for (const name of Object.keys(oldValue)) {
        const entryPath = keyword === "properties" ? `${path}.${name}` : `${path}.${keyword}.${name}`;
        if (!(name in newEntries)) {
          problemAt(problems, entryPath, "was removed");
        } else {
          removedMapEntries(oldValue[name], newEntries[name], entryPath, problems);
        }
      }
    } else if (SUBSCHEMA_KEYWORDS.has(keyword) || keyword === "not" || keyword === "contains") {
      removedMapEntries(oldValue, newValue, `${path}.${keyword}`, problems);
    }
  }
}

// "contains": S needs one array item that passes S, so even "contains": {} refuses an empty
// array. A new one narrows; a shared one narrows when S does.
function compareContains(oldContains, newContains, path, problems) {
  const keywordPath = `${path}.contains`;
  if (newContains === undefined) {
    return;
  }
  if (oldContains === undefined) {
    problemAt(problems, keywordPath, "was added, so values that passed before may not");
    return;
  }
  compareSchema(oldContains, newContains, keywordPath, problems);
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
    } else if (keyword === "not") {
      compareNot(oldValue, newValue, path, problems);
    } else if (keyword === "contains") {
      compareContains(oldValue, newValue, path, problems);
    } else if (keyword === "type" && sameTypeList(oldValue, newValue)) {
      continue;
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
  problems.push(...prefixOverlapProblems(before, after));
  return problems;
}

// A new prefix that starts an existing one, or that an existing one starts, overlaps it: the
// longest prefix wins (record-schema.js typeForKey), so some keys would change type.
function prefixOverlapProblems(before, after) {
  const problems = [];
  const oldPrefixes = Object.keys(before);
  for (const prefix of Object.keys(after)) {
    if (prefix in before) {
      continue;
    }
    for (const oldPrefix of oldPrefixes) {
      if (prefix.startsWith(oldPrefix) || oldPrefix.startsWith(prefix)) {
        problems.push(`types["${prefix}"] is new and overlaps types["${oldPrefix}"]: keys stored under one would be read as the other (use a prefix that shares no start with an existing one)`);
      }
    }
  }
  return problems;
}

// The schema a local "#/..." $ref points at inside rootSchema, or undefined.
function resolveLocalReference(reference, rootSchema) {
  if (typeof reference !== "string" || !reference.startsWith("#/")) {
    return undefined;
  }
  let target = rootSchema;
  for (const part of reference.slice(2).split("/")) {
    if (!isPlainObject(target)) {
      return undefined;
    }
    target = target[part.replace(/~1/g, "/").replace(/~0/g, "~")];
  }
  return target;
}

// Follows $ref until a schema without one (at most a few hops; a loop gives undefined).
function followReferences(schema, rootSchema) {
  let current = schema;
  for (let hop = 0; hop < 8; hop += 1) {
    if (!isPlainObject(current) || current.$ref === undefined) {
      return current;
    }
    current = resolveLocalReference(current.$ref, rootSchema);
  }
  return undefined;
}

function matchesPattern(pattern, fieldName) {
  try {
    return new RegExp(pattern, "u").test(fieldName);
  } catch {
    return false;
  }
}

// Fields a stored value already holds that the new schema names for the first time at that
// place (a new property, or a field matching a new patternProperties entry). Such a field was
// unconstrained before; even when its value fits today, phones that have not synced yet may hold
// another value for it, so a new field name must be one no record uses (founder, 2026-10-19:
// add only). Walks the old and new schemas side by side along the value: properties, items and
// $ref. Returns ["<type>.<path> is new but <key> already holds it"].
export function newFieldClashes({ oldSchema, newSchema, value, typeName, key }) {
  const clashes = [];
  walkForClashes({ oldSchema, newSchema, value, path: typeName, oldRoot: oldSchema, newRoot: newSchema, key, clashes });
  return clashes;
}

function walkForClashes({ oldSchema, newSchema, value, path, oldRoot, newRoot, key, clashes }) {
  const oldNode = followReferences(oldSchema, oldRoot);
  const newNode = followReferences(newSchema, newRoot);
  if (!isPlainObject(oldNode) || !isPlainObject(newNode)) {
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      walkForClashes({ oldSchema: oldNode.items, newSchema: newNode.items, value: item, path: `${path}[]`, oldRoot, newRoot, key, clashes });
    }
    return;
  }
  if (!isPlainObject(value)) {
    return;
  }
  const oldProperties = isPlainObject(oldNode.properties) ? oldNode.properties : {};
  const newProperties = isPlainObject(newNode.properties) ? newNode.properties : {};
  const oldPatterns = isPlainObject(oldNode.patternProperties) ? Object.keys(oldNode.patternProperties) : [];
  const newPatterns = isPlainObject(newNode.patternProperties) ? Object.keys(newNode.patternProperties) : [];
  for (const fieldName of Object.keys(value)) {
    if (fieldName === "$type") {
      continue;
    }
    const fieldPath = `${path}.${fieldName}`;
    if (fieldName in newProperties && !(fieldName in oldProperties)) {
      clashes.push(`${fieldPath} is new but ${key} already holds a ${fieldName} field`);
      continue;
    }
    if (fieldName in newProperties) {
      walkForClashes({ oldSchema: oldProperties[fieldName], newSchema: newProperties[fieldName], value: value[fieldName], path: fieldPath, oldRoot, newRoot, key, clashes });
      continue;
    }
    const newPattern = newPatterns.find(function isNewMatchingPattern(pattern) {
      return !oldPatterns.includes(pattern) && matchesPattern(pattern, fieldName);
    });
    if (newPattern !== undefined) {
      clashes.push(`${path}.patternProperties["${newPattern}"] is new but ${key} already holds a matching ${fieldName} field`);
    }
  }
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
// Reads are left out on purpose: a page's upgrade-on-read code may still read a retired prefix
// to move it forward. Keys built only from variables are not seen.
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
