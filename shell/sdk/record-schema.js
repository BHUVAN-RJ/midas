// The one record validator in Midas (unified data, founder decisions 2026-10-13 and 2026-10-15):
// JSON records, one JSON Schema per record type, the schemas inside each Sidekick's
// manifest.json under "types". This file runs unchanged in three places so every writer checks
// the same thing the same way:
//
//   - the Worker (backend/src/record-types.ts imports it) checks every op pushed to /sync/push;
//   - the shell loads it into JavaScriptCore (shell/Midas/RecordSchemaEngine.swift) and checks
//     every write a page or a native writer makes;
//   - tests run it under Node.
//
// It is a plain script: no imports, one global, a CommonJS export at the end for Node and the
// Worker bundler. It covers the JSON Schema (draft 2020-12) keywords Midas schemas use; a keyword
// it does not know is ignored, as the specification allows.
//
// A manifest's "types" block maps a key prefix to its type:
//
//   "types": { "reminder:": { "$type": "reminders.item", "schema": { "type": "object", ... } } }
//
// Every record carries "$type" (<sidekickId>.<name>). Fields starting with "$" are reserved.
var MidasRecordSchema = (function createMidasRecordSchema() {
  var TYPE_FIELD = '$type';
  // 2026-10-15T09:30:00.000Z or 2026-10-15T09:30:00+02:00 (ISO 8601 with an offset, rule 5).
  var DATE_TIME_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})$/;
  var DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
  // A time of day as the pages store it, "HH:MM".
  var WALL_TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;
  var KNOWN_FORMATS = ['date-time', 'date', 'wall-time', 'time-zone'];

  /* ---------- JSON helpers ---------- */

  function isObject(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
  }

  function jsonTypeOf(value) {
    if (value === null) {
      return 'null';
    }
    if (Array.isArray(value)) {
      return 'array';
    }
    if (typeof value === 'number') {
      return Number.isInteger(value) ? 'integer' : 'number';
    }
    return typeof value;
  }

  function deepEqual(first, second) {
    return JSON.stringify(sortedCopy(first)) === JSON.stringify(sortedCopy(second));
  }

  // Object keys in a fixed order so two equal objects stringify the same.
  function sortedCopy(value) {
    if (Array.isArray(value)) {
      var items = [];
      for (var index = 0; index < value.length; index += 1) {
        items.push(sortedCopy(value[index]));
      }
      return items;
    }
    if (!isObject(value)) {
      return value;
    }
    var copy = {};
    var fieldNames = Object.keys(value).sort();
    for (var nameIndex = 0; nameIndex < fieldNames.length; nameIndex += 1) {
      var fieldName = fieldNames[nameIndex];
      copy[fieldName] = sortedCopy(value[fieldName]);
    }
    return copy;
  }

  function describePath(typeName, path) {
    return path.length === 0 ? typeName : typeName + '.' + path.join('.');
  }

  function describeValue(value) {
    var kind = jsonTypeOf(value);
    if (kind === 'string') {
      return 'a string';
    }
    if (kind === 'integer' || kind === 'number') {
      return 'a number';
    }
    if (kind === 'boolean') {
      return 'true or false';
    }
    if (kind === 'array') {
      return 'a list';
    }
    if (kind === 'object') {
      return 'an object';
    }
    return 'null';
  }

  /* ---------- Formats ---------- */

  function isKnownTimeZone(name) {
    try {
      new Intl.DateTimeFormat('en-US', { timeZone: name });
      return true;
    } catch (error) {
      return false;
    }
  }

  // Returns the problem with a formatted string, or null. Unknown formats are not checked.
  function formatProblem(format, text) {
    if (format === 'date-time') {
      var isDateTime = DATE_TIME_PATTERN.test(text) && !Number.isNaN(Date.parse(text));
      return isDateTime ? null : 'must be an ISO 8601 date and time with an offset, like 2026-10-15T09:30:00.000Z';
    }
    if (format === 'date') {
      return DATE_PATTERN.test(text) ? null : 'must be a date like 2026-10-15';
    }
    if (format === 'wall-time') {
      return WALL_TIME_PATTERN.test(text) ? null : 'must be a time like 09:30';
    }
    if (format === 'time-zone') {
      return isKnownTimeZone(text) ? null : 'is not a known time zone';
    }
    return null;
  }

  /* ---------- $ref ---------- */

  // Only references into the same schema document are supported: "#/$defs/<name>" and
  // "#/definitions/<name>", possibly deeper ("#/$defs/rule/properties/kind").
  function resolveReference(reference, rootSchema) {
    if (typeof reference !== 'string' || reference.indexOf('#/') !== 0) {
      return undefined;
    }
    var segments = reference.slice(2).split('/');
    var current = rootSchema;
    for (var index = 0; index < segments.length; index += 1) {
      var segment = segments[index].replace(/~1/g, '/').replace(/~0/g, '~');
      if (!isObject(current) || !(segment in current)) {
        return undefined;
      }
      current = current[segment];
    }
    return current;
  }

  /* ---------- Validation ---------- */

  // Returns the first problem as "<type>.<path> <problem>", or null when the value fits. The
  // path names the field so a page or a person can see what to fix.
  function validate(schema, value, typeName, rootSchema) {
    var context = { typeName: typeName || 'record', root: rootSchema || schema };
    return checkValue(schema, value, [], context);
  }

  function checkValue(schema, value, path, context) {
    if (schema === true || schema === undefined) {
      return null;
    }
    if (schema === false) {
      return describePath(context.typeName, path) + ' is not allowed';
    }
    if (!isObject(schema)) {
      return null;
    }
    if (schema.$ref !== undefined) {
      var referenced = resolveReference(schema.$ref, context.root);
      if (referenced === undefined) {
        return describePath(context.typeName, path) + ' uses an unknown schema reference ' + schema.$ref;
      }
      var referenceProblem = checkValue(referenced, value, path, context);
      if (referenceProblem !== null) {
        return referenceProblem;
      }
    }
    var checks = [checkType, checkEnum, checkConst, checkString, checkNumber, checkArray, checkObject, checkCombinations];
    for (var index = 0; index < checks.length; index += 1) {
      var problem = checks[index](schema, value, path, context);
      if (problem !== null) {
        return problem;
      }
    }
    return null;
  }

  function typeMatches(expected, value) {
    var actual = jsonTypeOf(value);
    if (expected === 'number') {
      return actual === 'number' || actual === 'integer';
    }
    return expected === actual;
  }

  function checkType(schema, value, path, context) {
    if (schema.type === undefined) {
      return null;
    }
    var allowedTypes = Array.isArray(schema.type) ? schema.type : [schema.type];
    for (var index = 0; index < allowedTypes.length; index += 1) {
      if (typeMatches(allowedTypes[index], value)) {
        return null;
      }
    }
    return describePath(context.typeName, path) + ' must be ' + describeTypes(allowedTypes) + ', not ' + describeValue(value);
  }

  function describeTypes(types) {
    var words = [];
    for (var index = 0; index < types.length; index += 1) {
      words.push(describeType(types[index]));
    }
    return words.join(' or ');
  }

  function describeType(type) {
    if (type === 'string') {
      return 'a string';
    }
    if (type === 'integer') {
      return 'a whole number';
    }
    if (type === 'number') {
      return 'a number';
    }
    if (type === 'boolean') {
      return 'true or false';
    }
    if (type === 'array') {
      return 'a list';
    }
    if (type === 'object') {
      return 'an object';
    }
    return type;
  }

  function checkEnum(schema, value, path, context) {
    if (!Array.isArray(schema.enum)) {
      return null;
    }
    for (var index = 0; index < schema.enum.length; index += 1) {
      if (deepEqual(schema.enum[index], value)) {
        return null;
      }
    }
    return describePath(context.typeName, path) + ' must be one of ' + JSON.stringify(schema.enum);
  }

  function checkConst(schema, value, path, context) {
    if (!('const' in schema)) {
      return null;
    }
    return deepEqual(schema.const, value) ? null : describePath(context.typeName, path) + ' must be ' + JSON.stringify(schema.const);
  }

  function checkString(schema, value, path, context) {
    if (typeof value !== 'string') {
      return null;
    }
    var where = describePath(context.typeName, path);
    // Lengths count code points, so an emoji is one character, as a person would count.
    var length = Array.from(value).length;
    if (typeof schema.minLength === 'number' && length < schema.minLength) {
      return schema.minLength === 1 ? where + ' must not be empty' : where + ' must be at least ' + schema.minLength + ' characters';
    }
    if (typeof schema.maxLength === 'number' && length > schema.maxLength) {
      return where + ' must be at most ' + schema.maxLength + ' characters';
    }
    if (typeof schema.pattern === 'string' && !new RegExp(schema.pattern, 'u').test(value)) {
      return where + ' must match ' + schema.pattern;
    }
    if (typeof schema.format === 'string') {
      var problem = formatProblem(schema.format, value);
      if (problem !== null) {
        return where + ' ' + problem;
      }
    }
    return null;
  }

  function checkNumber(schema, value, path, context) {
    if (typeof value !== 'number') {
      return null;
    }
    var where = describePath(context.typeName, path);
    if (typeof schema.minimum === 'number' && value < schema.minimum) {
      return where + ' must be at least ' + schema.minimum;
    }
    if (typeof schema.maximum === 'number' && value > schema.maximum) {
      return where + ' must be at most ' + schema.maximum;
    }
    if (typeof schema.exclusiveMinimum === 'number' && value <= schema.exclusiveMinimum) {
      return where + ' must be more than ' + schema.exclusiveMinimum;
    }
    if (typeof schema.exclusiveMaximum === 'number' && value >= schema.exclusiveMaximum) {
      return where + ' must be less than ' + schema.exclusiveMaximum;
    }
    if (typeof schema.multipleOf === 'number' && schema.multipleOf > 0) {
      var quotient = value / schema.multipleOf;
      if (Math.abs(quotient - Math.round(quotient)) > 1e-9) {
        return where + ' must be a multiple of ' + schema.multipleOf;
      }
    }
    return null;
  }

  function checkArray(schema, value, path, context) {
    if (!Array.isArray(value)) {
      return null;
    }
    var where = describePath(context.typeName, path);
    if (typeof schema.minItems === 'number' && value.length < schema.minItems) {
      return schema.minItems === 1 ? where + ' must not be empty' : where + ' must have at least ' + schema.minItems + ' items';
    }
    if (typeof schema.maxItems === 'number' && value.length > schema.maxItems) {
      return where + ' must have at most ' + schema.maxItems + ' items';
    }
    if (schema.uniqueItems === true && hasDuplicates(value)) {
      return where + ' must not repeat an item';
    }
    if (schema.items !== undefined) {
      for (var index = 0; index < value.length; index += 1) {
        var itemProblem = checkValue(schema.items, value[index], path.concat([String(index)]), context);
        if (itemProblem !== null) {
          return itemProblem;
        }
      }
    }
    return null;
  }

  function hasDuplicates(items) {
    var seen = [];
    for (var index = 0; index < items.length; index += 1) {
      var text = JSON.stringify(sortedCopy(items[index]));
      if (seen.indexOf(text) !== -1) {
        return true;
      }
      seen.push(text);
    }
    return false;
  }

  function checkObject(schema, value, path, context) {
    if (!isObject(value)) {
      return null;
    }
    var where = describePath(context.typeName, path);
    var fieldNames = Object.keys(value);
    if (Array.isArray(schema.required)) {
      for (var requiredIndex = 0; requiredIndex < schema.required.length; requiredIndex += 1) {
        var requiredName = schema.required[requiredIndex];
        if (!(requiredName in value)) {
          return describePath(context.typeName, path.concat([requiredName])) + ' is required';
        }
      }
    }
    if (typeof schema.minProperties === 'number' && fieldNames.length < schema.minProperties) {
      return where + ' must have at least ' + schema.minProperties + ' fields';
    }
    if (typeof schema.maxProperties === 'number' && fieldNames.length > schema.maxProperties) {
      return where + ' must have at most ' + schema.maxProperties + ' fields';
    }
    if (isObject(schema.dependentRequired)) {
      var dependentProblem = checkDependentRequired(schema.dependentRequired, value, path, context);
      if (dependentProblem !== null) {
        return dependentProblem;
      }
    }
    var properties = isObject(schema.properties) ? schema.properties : {};
    for (var fieldIndex = 0; fieldIndex < fieldNames.length; fieldIndex += 1) {
      var fieldName = fieldNames[fieldIndex];
      var fieldPath = path.concat([fieldName]);
      var fieldValue = value[fieldName];
      if (schema.propertyNames !== undefined) {
        var nameProblem = checkValue(schema.propertyNames, fieldName, fieldPath, context);
        if (nameProblem !== null) {
          return nameProblem;
        }
      }
      if (fieldName in properties) {
        var propertyProblem = checkValue(properties[fieldName], fieldValue, fieldPath, context);
        if (propertyProblem !== null) {
          return propertyProblem;
        }
        continue;
      }
      var patternSchema = matchingPatternProperty(schema.patternProperties, fieldName);
      if (patternSchema !== undefined) {
        var patternProblem = checkValue(patternSchema, fieldValue, fieldPath, context);
        if (patternProblem !== null) {
          return patternProblem;
        }
        continue;
      }
      // Unknown fields are kept by every writer (rule 4); a schema may still forbid them.
      if (schema.additionalProperties === false) {
        return describePath(context.typeName, fieldPath) + ' is not a field of this type';
      }
      if (isObject(schema.additionalProperties)) {
        var additionalProblem = checkValue(schema.additionalProperties, fieldValue, fieldPath, context);
        if (additionalProblem !== null) {
          return additionalProblem;
        }
      }
    }
    return null;
  }

  function matchingPatternProperty(patternProperties, fieldName) {
    if (!isObject(patternProperties)) {
      return undefined;
    }
    var patterns = Object.keys(patternProperties);
    for (var index = 0; index < patterns.length; index += 1) {
      if (new RegExp(patterns[index], 'u').test(fieldName)) {
        return patternProperties[patterns[index]];
      }
    }
    return undefined;
  }

  function checkDependentRequired(dependentRequired, value, path, context) {
    var triggerNames = Object.keys(dependentRequired);
    for (var index = 0; index < triggerNames.length; index += 1) {
      var triggerName = triggerNames[index];
      if (!(triggerName in value)) {
        continue;
      }
      var needed = dependentRequired[triggerName];
      for (var neededIndex = 0; neededIndex < needed.length; neededIndex += 1) {
        if (!(needed[neededIndex] in value)) {
          return describePath(context.typeName, path.concat([needed[neededIndex]])) + ' is required with ' + triggerName;
        }
      }
    }
    return null;
  }

  function checkCombinations(schema, value, path, context) {
    var where = describePath(context.typeName, path);
    if (Array.isArray(schema.allOf)) {
      for (var allIndex = 0; allIndex < schema.allOf.length; allIndex += 1) {
        var allProblem = checkValue(schema.allOf[allIndex], value, path, context);
        if (allProblem !== null) {
          return allProblem;
        }
      }
    }
    if (Array.isArray(schema.anyOf)) {
      var anyProblems = problemsOfEach(schema.anyOf, value, path, context);
      if (anyProblems.passing === 0) {
        return anyProblems.firstProblem || where + ' fits none of its allowed forms';
      }
    }
    if (Array.isArray(schema.oneOf)) {
      var oneProblems = problemsOfEach(schema.oneOf, value, path, context);
      if (oneProblems.passing === 0) {
        return oneProblems.firstProblem || where + ' fits none of its allowed forms';
      }
      if (oneProblems.passing > 1) {
        return where + ' fits more than one of its allowed forms';
      }
    }
    if (schema.not !== undefined && checkValue(schema.not, value, path, context) === null) {
      return where + ' is not allowed';
    }
    if (schema.if !== undefined) {
      var conditionHolds = checkValue(schema.if, value, path, context) === null;
      var branch = conditionHolds ? schema.then : schema.else;
      if (branch !== undefined) {
        return checkValue(branch, value, path, context);
      }
    }
    return null;
  }

  function problemsOfEach(schemas, value, path, context) {
    var passing = 0;
    var firstProblem = null;
    for (var index = 0; index < schemas.length; index += 1) {
      var problem = checkValue(schemas[index], value, path, context);
      if (problem === null) {
        passing += 1;
      } else if (firstProblem === null) {
        firstProblem = problem;
      }
    }
    return { passing: passing, firstProblem: firstProblem };
  }

  /* ---------- Types by key prefix ---------- */

  // The type whose prefix starts the key; the longest prefix wins when one is a prefix of
  // another. Returns { prefix, $type, schema } or null.
  function typeForKey(types, key) {
    if (!isObject(types) || typeof key !== 'string') {
      return null;
    }
    var bestPrefix = null;
    var prefixes = Object.keys(types);
    for (var index = 0; index < prefixes.length; index += 1) {
      var prefix = prefixes[index];
      var isLonger = bestPrefix === null || prefix.length > bestPrefix.length;
      if (key.indexOf(prefix) === 0 && isLonger) {
        bestPrefix = prefix;
      }
    }
    if (bestPrefix === null) {
      return null;
    }
    var entry = types[bestPrefix];
    if (!isObject(entry)) {
      return null;
    }
    return { prefix: bestPrefix, $type: entry.$type, schema: entry.schema };
  }

  // A copy of the value with "$type" set from its key's type. A non-object value or a key with
  // no type comes back as it was.
  function stampType(types, key, value) {
    var type = typeForKey(types, key);
    if (type === null || !isObject(value) || typeof type.$type !== 'string') {
      return value;
    }
    var stamped = {};
    stamped[TYPE_FIELD] = type.$type;
    var fieldNames = Object.keys(value);
    for (var index = 0; index < fieldNames.length; index += 1) {
      var fieldName = fieldNames[index];
      if (fieldName !== TYPE_FIELD) {
        stamped[fieldName] = value[fieldName];
      }
    }
    return stamped;
  }

  // Why a record cannot be stored under its key, or null. Checks the key has a type, the
  // record carries that type, and the record fits the type's schema. A `types` block that is
  // missing means the Sidekick has no schemas yet; then nothing is checked.
  function checkRecord(types, key, value) {
    if (!isObject(types)) {
      return null;
    }
    var type = typeForKey(types, key);
    if (type === null) {
      return 'no record type is declared for ' + key;
    }
    if (!isObject(value)) {
      return type.$type + ' must be an object, not ' + describeValue(value);
    }
    if (value[TYPE_FIELD] !== type.$type) {
      return type.$type + '.$type must be "' + type.$type + '"';
    }
    return validate(type.schema, value, type.$type, type.schema);
  }

  /* ---------- JSON Merge Patch (RFC 7396) ---------- */

  // store.update(key, patch): a field set to null is removed, an object field is merged, every
  // other field is replaced. Returns a new value; neither argument is changed.
  function mergePatch(target, patch) {
    if (!isObject(patch)) {
      return patch;
    }
    var result = {};
    if (isObject(target)) {
      var existingNames = Object.keys(target);
      for (var existingIndex = 0; existingIndex < existingNames.length; existingIndex += 1) {
        result[existingNames[existingIndex]] = target[existingNames[existingIndex]];
      }
    }
    var patchNames = Object.keys(patch);
    for (var patchIndex = 0; patchIndex < patchNames.length; patchIndex += 1) {
      var fieldName = patchNames[patchIndex];
      var patchValue = patch[fieldName];
      if (patchValue === null) {
        delete result[fieldName];
      } else {
        result[fieldName] = mergePatch(result[fieldName], patchValue);
      }
    }
    return result;
  }

  return {
    TYPE_FIELD: TYPE_FIELD,
    KNOWN_FORMATS: KNOWN_FORMATS,
    validate: validate,
    typeForKey: typeForKey,
    stampType: stampType,
    checkRecord: checkRecord,
    mergePatch: mergePatch,
    isKnownTimeZone: isKnownTimeZone,
  };
})();

if (typeof module !== 'undefined' && module.exports) {
  module.exports = MidasRecordSchema;
}
