// The Money Sidekick's record (founder, 2026-11-07/08): one expense:<id> record of type
// money.expense holds everything about an expense: amount in integer cents, USD, merchant, date,
// category, line items, the receipt image as a file reference, and where it came from. Every
// shape the page and the tools write must pass manifest.json the way the shell's write gate checks
// it, and wrong shapes must be refused. Categories may grow through Edit, so these tests check
// that the base ten are offered, never that the list is exactly ten.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { typesBlockProblems, validateManifest } from "../scripts/bundle-tools.mjs";

const manifestText = readFileSync(new URL("../../sidekicks/money/manifest.json", import.meta.url), "utf8");
const manifest = JSON.parse(manifestText);
const BASE_CATEGORIES = ["Groceries", "Dining", "Transport", "Shopping", "Bills", "Home", "Health", "Fun", "Travel", "Other"];

type Value = Record<string, unknown>;

function schemaProblem(key: string, value: Value) {
  const stamped = MidasRecordSchema.stampType(manifest.types, key, value);
  return MidasRecordSchema.checkRecord(manifest.types, key, stamped);
}

function fullExpense(fields: Value = {}): Value {
  return {
    amountCents: 4218, currency: "USD", merchant: "Corner Market", date: "2026-11-07", category: "Groceries",
    items: [{ name: "Bananas", amountCents: 129, quantity: 1 }, { name: "Oat Milk", amountCents: 449 }, { name: "Coupon", amountCents: -100 }],
    taxCents: 493, tipCents: 0, receipt: "file:3f9a0c1b2d4e5f60", source: "photo",
    createdAt: "2026-11-07T22:11:00.000Z", updatedAt: "2026-11-07T22:15:00.000Z", ...fields,
  };
}

describe("money: the manifest", () => {
  it("is Money, with its own id, a tile in light and dark, and expense: in the money namespace", () => {
    expect(validateManifest(manifest, "money")).toEqual([]);
    expect(typesBlockProblems(manifest.types, "money")).toEqual([]);
    expect(manifest.name).toBe("Money");
    expect(manifest.types["expense:"].$type).toBe("money.expense");
    expect(manifest.icon.backgroundDark).toMatch(/^#[0-9A-Fa-f]{6}$/);
  });

  it("offers every base category in the record and in each tool that takes one", () => {
    const recordCategories = manifest.types["expense:"].schema.properties.category.enum;
    for (const category of BASE_CATEGORIES) {
      expect(recordCategories).toContain(category);
    }
    for (const tool of manifest.agent.tools) {
      const property = tool.inputSchema.properties.category;
      if (property !== undefined) {
        for (const category of BASE_CATEGORIES) {
          expect(property.enum, tool.name).toContain(category);
        }
      }
    }
  });
});

describe("money: expense: records", () => {
  it("accepts a full expense with items, tax, tip and a receipt, and a bare one", () => {
    expect(schemaProblem("expense:a1", fullExpense())).toBeNull();
    const bare = { amountCents: 1200, currency: "USD", merchant: "Starbucks", date: "2026-11-07", category: "Dining", createdAt: "2026-11-07T22:11:00.000Z" };
    expect(schemaProblem("expense:a2", bare)).toBeNull();
  });

  it("refuses amounts that are not whole cents from 1 cent to $1,000,000", () => {
    expect(schemaProblem("expense:a1", fullExpense({ amountCents: 0 }))).not.toBeNull();
    expect(schemaProblem("expense:a1", fullExpense({ amountCents: 4.5 }))).not.toBeNull();
    expect(schemaProblem("expense:a1", fullExpense({ amountCents: 100_000_001 }))).not.toBeNull();
    expect(schemaProblem("expense:a1", fullExpense({ amountCents: "12.00" }))).not.toBeNull();
  });

  it("is US dollars only", () => {
    expect(schemaProblem("expense:a1", fullExpense({ currency: "EUR" }))).not.toBeNull();
  });

  it("keeps the receipt only as a Midas file reference, never a URL or the bytes", () => {
    expect(schemaProblem("expense:a1", fullExpense({ receipt: "https://example.com/r.jpg" }))).not.toBeNull();
    expect(schemaProblem("expense:a1", fullExpense({ receipt: "data:image/jpeg;base64,AAAA" }))).not.toBeNull();
  });

  it("refuses a missing or unknown category, a bad date and an unknown source", () => {
    const withoutCategory = fullExpense();
    delete withoutCategory.category;
    expect(schemaProblem("expense:a1", withoutCategory)).not.toBeNull();
    expect(schemaProblem("expense:a1", fullExpense({ category: "Snacks" }))).not.toBeNull();
    expect(schemaProblem("expense:a1", fullExpense({ date: "11/07/2026" }))).not.toBeNull();
    expect(schemaProblem("expense:a1", fullExpense({ source: "bank" }))).not.toBeNull();
  });

  it("refuses more than 100 items and an item without a name", () => {
    const manyItems = [];
    for (let index = 0; index < 101; index += 1) {
      manyItems.push({ name: "Item " + index });
    }
    expect(schemaProblem("expense:a1", fullExpense({ items: manyItems }))).not.toBeNull();
    expect(schemaProblem("expense:a1", fullExpense({ items: [{ amountCents: 100 }] }))).not.toBeNull();
  });
});
