// Sample inputs for a jess tool, built from its inputSchema (the MCP-style schema in the
// manifest's agent block), so the shield can call every tool the same way before and after a
// repair. Not exhaustive: a few fixed cases per tool, each one deterministic.
//
// Texts come from the person's own records (titles and names), so "item" and "list" inputs name
// things that exist and the handlers do real work instead of refusing. Every case is built twice:
// once with each nullable field null, once with a value in it.

const FALLBACK_TEXT = "Shield sample";
const TEXT_FIELDS = ["title", "name", "label"];
const MAX_RECORD_TEXTS = 2;
const MAX_DEPTH = 8;
const FILL_NULLS = "nulls";
const FILL_VALUES = "values";

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// Up to two distinct titles or names from the records, then the fallback
export function sampleTexts(records) {
  const texts = [];
  for (const record of records) {
    if (texts.length >= MAX_RECORD_TEXTS) {
      break;
    }
    if (!isPlainObject(record.value)) {
      continue;
    }
    for (const fieldName of TEXT_FIELDS) {
      const fieldValue = record.value[fieldName];
      const usable = typeof fieldValue === "string" && fieldValue.trim().length > 0 && !texts.includes(fieldValue);
      if (usable && texts.length < MAX_RECORD_TEXTS) {
        texts.push(fieldValue);
      }
    }
  }
  texts.push(FALLBACK_TEXT);
  return texts;
}

function resolveReference(schema, defs) {
  if (!isPlainObject(schema) || typeof schema.$ref !== "string") {
    return schema;
  }
  const name = schema.$ref.replace("#/$defs/", "");
  return isPlainObject(defs) && isPlainObject(defs[name]) ? defs[name] : {};
}

function allowsNull(schema) {
  if (schema.type === "null") {
    return true;
  }
  if (Array.isArray(schema.type) && schema.type.includes("null")) {
    return true;
  }
  if (Array.isArray(schema.enum) && schema.enum.includes(null)) {
    return true;
  }
  return false;
}

function firstNonNullType(schema) {
  if (Array.isArray(schema.type)) {
    const nonNull = schema.type.filter(function isNotNullType(typeName) {
      return typeName !== "null";
    });
    return nonNull[0] ?? "null";
  }
  return schema.type;
}

// The tools describe dates and times in words ("YYYY-MM-DD", "HH:MM, 24-hour") more often than
// with a format, so both are read
function textFor(schema, text, nowIso) {
  const description = typeof schema.description === "string" ? schema.description : "";
  if (schema.format === "date" || description.includes("YYYY-MM-DD")) {
    return nowIso.slice(0, 10);
  }
  if (description.includes("HH:MM")) {
    return "09:00";
  }
  if (schema.format === "date-time") {
    return nowIso;
  }
  return text;
}

function numberFor(schema) {
  if (typeof schema.minimum === "number" && schema.minimum > 1) {
    return schema.minimum;
  }
  return 1;
}

function objectFor(schema, context, depth) {
  const result = {};
  const properties = isPlainObject(schema.properties) ? schema.properties : {};
  for (const [propertyName, propertySchema] of Object.entries(properties)) {
    result[propertyName] = valueFor(propertySchema, context, depth + 1);
  }
  return result;
}

// One value for one schema node. context: { defs, text, fill, nowIso }
export function valueFor(rawSchema, context, depth = 0) {
  const schema = resolveReference(rawSchema, context.defs);
  if (!isPlainObject(schema) || depth > MAX_DEPTH) {
    return null;
  }
  if (Array.isArray(schema.anyOf) || Array.isArray(schema.oneOf)) {
    const options = schema.anyOf ?? schema.oneOf;
    const resolvedOptions = options.map(function resolveOption(option) {
      return resolveReference(option, context.defs);
    });
    const nullOption = resolvedOptions.find(allowsNull);
    if (context.fill === FILL_NULLS && nullOption !== undefined) {
      return null;
    }
    const valueOption = resolvedOptions.find(function isNotOnlyNull(option) {
      return option.type !== "null";
    });
    return valueFor(valueOption ?? {}, context, depth + 1);
  }
  if (context.fill === FILL_NULLS && allowsNull(schema)) {
    return null;
  }
  if (Array.isArray(schema.enum)) {
    const choices = schema.enum.filter(function isNotNullChoice(choice) {
      return choice !== null;
    });
    return choices.length > 0 ? choices[0] : null;
  }
  const typeName = firstNonNullType(schema);
  if (typeName === "object") {
    return objectFor(schema, context, depth);
  }
  if (typeName === "string") {
    return textFor(schema, context.text, context.nowIso);
  }
  if (typeName === "integer" || typeName === "number") {
    return numberFor(schema);
  }
  if (typeName === "boolean") {
    return context.fill === FILL_VALUES;
  }
  if (typeName === "array") {
    if (context.fill === FILL_NULLS || !isPlainObject(schema.items)) {
      return [];
    }
    return [valueFor(schema.items, context, depth + 1)];
  }
  return null;
}

// The sample inputs for one tool: [{ label, input }]
export function sampleInputs({ tool, records, nowIso }) {
  const inputSchema = isPlainObject(tool.inputSchema) ? tool.inputSchema : { type: "object", properties: {} };
  const defs = isPlainObject(inputSchema.$defs) ? inputSchema.$defs : {};
  const cases = [];
  for (const text of sampleTexts(records)) {
    for (const fill of [FILL_NULLS, FILL_VALUES]) {
      const input = valueFor(inputSchema, { defs, text, fill, nowIso });
      cases.push({ label: `"${text}", ${fill === FILL_NULLS ? "nullable fields null" : "every field filled"}`, input });
    }
  }
  return cases;
}
