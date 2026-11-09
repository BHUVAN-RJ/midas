// The Money Sidekick's tools (jess router, founder 2026-10-21: every action a person can take on
// the page is a tool; Money, founder 2026-11-08). sidekicks/money/tools.js is loaded the way the
// deploy gate and the phone load it; every tool runs on real-shaped records and every record it
// would write is checked against manifest.json, as the shell's write gate checks it. A receipt
// photo reaches add_expense as input.receipt ("file:<id>", filled by Midas, never by the model).
process.env.TZ = "America/Los_Angeles";

import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import { checkBundleFiles } from "../scripts/bundle-tools.mjs";
import { loadToolsScript, sidekickToolsProblems } from "../scripts/sidekick-tools.mjs";

const folder = new URL("../../sidekicks/money/", import.meta.url);
const toolsText = readFileSync(new URL("tools.js", folder), "utf8");
const html = readFileSync(new URL("index.html", folder), "utf8");
const manifestText = readFileSync(new URL("manifest.json", folder), "utf8");
const manifest = JSON.parse(manifestText);

const loaded = loadToolsScript(toolsText);
if (!("tools" in loaded)) {
  throw new Error(loaded.problem);
}
const tools = loaded.tools;

// Saturday Nov 7, 2026, 14:00 in Los Angeles
const NOW = "2026-11-07T22:00:00.000Z";
// Saturday Nov 7, 2026, 23:30 in Los Angeles: already Sunday in UTC
const LATE = "2026-11-08T07:30:00.000Z";
const RECEIPT = "file:3f9a0c1b2d4e5f6071";

type Value = Record<string, unknown>;
type Records = Array<{ key: string; value: Value }>;
type Op = { op: string; key: string; value?: Value };
type Outcome = { ops?: Op[]; refused?: string; result: { text: string; [field: string]: unknown } };

function expense(fields: Value = {}): Value {
  return { $type: "money.expense", amountCents: 1200, currency: "USD", merchant: "Starbucks", date: "2026-11-06", category: "Dining", createdAt: "2026-11-06T16:00:00.000Z", ...fields };
}

function baseRecords(): Records {
  return [
    { key: "expense:a1", value: expense({ merchant: "Corner Market", category: "Groceries", amountCents: 4218, date: "2026-11-02", createdAt: "2026-11-02T20:00:00.000Z" }) },
    { key: "expense:a2", value: expense() },
    { key: "expense:a3", value: expense({ merchant: "City Power", category: "Bills", amountCents: 8620, date: "2026-10-29", createdAt: "2026-10-29T20:00:00.000Z" }) },
  ];
}

function addInput(fields: Value = {}): Value {
  return { amount: null, merchant: null, date: null, daysAgo: null, category: null, items: null, tax: null, tip: null, ...fields };
}

function run(verb: string, input: Value, records: Records = baseRecords(), now = NOW): Outcome {
  return tools.handlers[verb](input, records, now) as Outcome;
}

// Every record an outcome writes must pass the manifest's type, as the shell's write gate checks
function expectWritesFit(outcome: Outcome) {
  for (const op of outcome.ops ?? []) {
    if (op.op === "set") {
      const stamped = MidasRecordSchema.stampType(manifest.types, op.key, op.value);
      expect(MidasRecordSchema.checkRecord(manifest.types, op.key, stamped), op.key).toBeNull();
    }
  }
}

function onlySet(outcome: Outcome): Op {
  expect(outcome.refused).toBeUndefined();
  expect(outcome.ops).toHaveLength(1);
  expect(outcome.ops![0].op).toBe("set");
  expectWritesFit(outcome);
  return outcome.ops![0];
}

describe("money: the bundle and its tools", () => {
  it("passes the deploy gate: page, manifest and tools together", () => {
    expect(checkBundleFiles(html, manifestText, "money", toolsText).problems).toEqual([]);
    expect(sidekickToolsProblems(manifest, toolsText, html, "money")).toEqual([]);
  });

  it("fails the gate when the page's MoneyLogic drifts from the copy in tools.js", () => {
    const drifted = html.replace("const MAX_DAYS_BACK = 366;", "const MAX_DAYS_BACK = 365;");
    expect(drifted).not.toBe(html);
    const problems = sidekickToolsProblems(manifest, toolsText, drifted, "money");
    expect(problems.join("\n")).toContain("no longer matches index.html");
  });

  it("keeps the receipt field out of add_expense's inputSchema, so the model never fills it", () => {
    const addTool = manifest.agent.tools.find((tool: { name: string }) => tool.name === "money.add_expense");
    const photoField = addTool._meta["midas/photo"];
    expect(typeof photoField).toBe("string");
    expect(Object.keys(addTool.inputSchema.properties)).not.toContain(photoField);
  });
});

describe("money.add_expense", () => {
  it("adds a spoken expense in integer cents, today, at the merchant said", () => {
    const outcome = run("add_expense", addInput({ amount: 12, merchant: "Blue Bottle", category: "Dining" }));
    const op = onlySet(outcome);
    expect(op.key).toMatch(/^expense:/);
    expect(op.value).toMatchObject({ amountCents: 1200, currency: "USD", merchant: "Blue Bottle", date: "2026-11-07", category: "Dining", source: "jess" });
    expect(op.value!.receipt).toBeUndefined();
    expect(outcome.result.text).toBe("Added $12.00 at Blue Bottle");
  });

  it("rounds dollars to the cent without float drift", () => {
    expect(onlySet(run("add_expense", addInput({ amount: 19.99 }))).value!.amountCents).toBe(1999);
    expect(onlySet(run("add_expense", addInput({ amount: 0.1 + 0.2 }))).value!.amountCents).toBe(30);
    expect(onlySet(run("add_expense", addInput({ amount: 1204.185 }))).value!.amountCents).toBe(120419);
  });

  it("refuses with nothing written when there is no amount or it is out of range", () => {
    for (const amount of [null, 0, -5, 2_000_000]) {
      const outcome = run("add_expense", addInput({ amount }));
      expect(outcome.refused, String(amount)).toBe("no-amount");
      expect(outcome.ops).toBeUndefined();
    }
  });

  it("keeps the receipt photo Midas handed over, with every line, tax and tip", () => {
    const input = addInput({
      amount: 38.5, merchant: "Noodle Bar", date: "2026-11-05", category: "Dining",
      items: [{ name: "Spicy Ramen", amount: 16, quantity: 1 }, { name: "Gyoza", amount: 8.5, quantity: 2 }], tax: 3.2, tip: 6.8,
      receipt: RECEIPT,
    });
    const op = onlySet(run("add_expense", input));
    expect(op.value).toMatchObject({ amountCents: 3850, receipt: RECEIPT, source: "photo", date: "2026-11-05", taxCents: 320, tipCents: 680 });
    expect(op.value!.items).toEqual([{ name: "Spicy Ramen", amountCents: 1600, quantity: 1 }, { name: "Gyoza", amountCents: 850, quantity: 2 }]);
  });

  it("drops a receipt value that is not a Midas file reference", () => {
    const op = onlySet(run("add_expense", addInput({ amount: 5, receipt: "https://example.com/r.jpg" })));
    expect(op.value!.receipt).toBeUndefined();
    expect(op.value!.source).toBe("jess");
  });

  it("uses today when no date was printed or said, and never a future or year-old date", () => {
    expect(onlySet(run("add_expense", addInput({ amount: 5 }))).value!.date).toBe("2026-11-07");
    expect(onlySet(run("add_expense", addInput({ amount: 5, date: "2026-12-01" }))).value!.date).toBe("2026-11-07");
    expect(onlySet(run("add_expense", addInput({ amount: 5, date: "2024-01-01" }))).value!.date).toBe("2026-11-07");
    expect(onlySet(run("add_expense", addInput({ amount: 5, date: "2026-02-30" }))).value!.date).toBe("2026-11-07");
  });

  it("takes yesterday from daysAgo, in the phone's own day", () => {
    expect(onlySet(run("add_expense", addInput({ amount: 5, daysAgo: 1 }))).value!.date).toBe("2026-11-06");
    // 23:30 Saturday in Los Angeles is Sunday in UTC; yesterday is still Friday
    expect(onlySet(run("add_expense", addInput({ amount: 5, daysAgo: 1 }), baseRecords(), LATE)).value!.date).toBe("2026-11-06");
  });

  it("gives a merchant the person's own last category, else Other", () => {
    expect(onlySet(run("add_expense", addInput({ amount: 9, merchant: "corner market" }))).value!.category).toBe("Groceries");
    expect(onlySet(run("add_expense", addInput({ amount: 9, merchant: "Somewhere New" }))).value!.category).toBe("Other");
  });

  it("names an expense with no merchant Expense", () => {
    const outcome = run("add_expense", addInput({ amount: 45 }));
    expect(onlySet(outcome).value!.merchant).toBe("Expense");
    expect(outcome.result.text).toBe("Added $45.00");
  });
});

describe("money.edit_expense", () => {
  it("changes the latest expense at a merchant and keeps when it was made", () => {
    const outcome = run("edit_expense", { which: "starbucks", amount: 14, merchant: null, date: null, daysAgo: null, category: null });
    const op = onlySet(outcome);
    expect(op.key).toBe("expense:a2");
    expect(op.value).toMatchObject({ amountCents: 1400, merchant: "Starbucks", createdAt: "2026-11-06T16:00:00.000Z" });
    expect(typeof op.value!.updatedAt).toBe("string");
  });

  it("changes the latest expense when none is named", () => {
    const op = onlySet(run("edit_expense", { which: null, amount: null, merchant: null, date: null, daysAgo: null, category: "Fun" }));
    expect(op.key).toBe("expense:a2");
    expect(op.value!.category).toBe("Fun");
  });

  it("refuses an unknown expense and a change that changes nothing", () => {
    expect(run("edit_expense", { which: "Nowhere", amount: 3, merchant: null, date: null, daysAgo: null, category: null }).refused).toBe("no-expense");
    expect(run("edit_expense", { which: "Starbucks", amount: 12, merchant: null, date: null, daysAgo: null, category: null }).refused).toBe("nothing-to-change");
  });
});

describe("money.delete_expense", () => {
  it("deletes the latest expense matching the merchant and amount", () => {
    const outcome = run("delete_expense", { which: "City Power", amount: 86.2 });
    expect(outcome.ops).toEqual([{ op: "delete", key: "expense:a3" }]);
    expect(outcome.result.text).toBe("Deleted $86.20 at City Power");
  });

  it("refuses when nothing matches", () => {
    expect(run("delete_expense", { which: "City Power", amount: 1 }).refused).toBe("no-expense");
  });
});

describe("money.month_total", () => {
  it("adds up this month, and one category, without writing", () => {
    const all = run("month_total", { monthsAgo: null, category: null });
    expect(all.ops).toEqual([]);
    expect(all.result.totalCents).toBe(4218 + 1200);
    expect(all.result.text).toBe("$54.18 in November");
    const groceries = run("month_total", { monthsAgo: 0, category: "Groceries" });
    expect(groceries.result.totalCents).toBe(4218);
  });

  it("adds up last month", () => {
    expect(run("month_total", { monthsAgo: 1, category: null }).result.totalCents).toBe(8620);
  });
});

describe("money: what jess is told", () => {
  it("names this month's total, recent expenses, each merchant's category and the categories", () => {
    const context = tools.context(baseRecords(), NOW) as Value;
    expect(context.currency).toBe("USD");
    expect(context.thisMonth).toBe("$54.18");
    expect((context.recent as Value[])[0]).toMatchObject({ merchant: "Starbucks", amount: "$12.00" });
    expect((context.merchantCategories as Value)["Corner Market"]).toBe("Groceries");
    expect(context.categories).toContain("Groceries");
  });

  it("stays well under the 64 KB context limit with 5,000 expenses", () => {
    const records: Records = [];
    for (let index = 0; index < 5000; index += 1) {
      records.push({ key: "expense:m" + index, value: expense({ merchant: "Shop " + index, amountCents: 100 + index }) });
    }
    const contextText = JSON.stringify(tools.context(records, NOW));
    expect(contextText.length).toBeLessThan(16 * 1024);
  });
});
