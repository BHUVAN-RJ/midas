// Reminders, build 22 (founder, 2026-10-31, docs/briefs/build-22-2026-10-31.md "Water and
// Reminders"): the Alert choice (Normal / Time Sensitive / Alarm) is also in the toolbar on the
// keyboard while typing a reminder, not only in the Details sheet. It shows once the reminder has a
// time (only a timed reminder has a type) and writes item.reminderType as the Details sheet does.
// Checked on the base Reminders page and on Boomi's copy.
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

const PAGES = [
  { name: "Reminders", url: new URL("../../sidekicks/reminders/index.html", import.meta.url) },
  { name: "Boomi's copy", url: new URL("../../copies/reminders/boomi/sidekick/index.html", import.meta.url) },
];

// The text of one page function, from "function <name>(" to its closing brace at two spaces
function functionSource(pageHtml: string, name: string): string {
  const start = pageHtml.indexOf("  function " + name + "(");
  if (start === -1) {
    throw new Error("no function " + name);
  }
  const end = pageHtml.indexOf("\n  }\n", start) + "\n  }\n".length;
  return pageHtml.slice(start, end);
}

function labelsSource(pageHtml: string): string {
  const start = pageHtml.indexOf("  const REMINDER_TYPE_LABELS = ");
  const end = pageHtml.indexOf("\n", start);
  return pageHtml.slice(start, end);
}

type Item = { id: string; date: string | null; time: string | null; reminderType: string | null; repeat: unknown; list: unknown };

// Runs the page's own toolbar functions on a fake editing item
function toolbarFunctions(pageHtml: string, item: Item) {
  const source = [
    labelsSource(pageHtml),
    functionSource(pageHtml, "shownReminderType"),
    functionSource(pageHtml, "reminderTypeOptionsHtml"),
    functionSource(pageHtml, "applyAccessoryChange"),
    functionSource(pageHtml, "accessoryHtml"),
    "globalThis.__toolbar = { applyAccessoryChange, reminderTypeOptionsHtml, accessoryHtml, REMINDER_TYPE_LABELS };",
  ].join("\n");
  const refreshes: number[] = [];
  const sandbox: Record<string, unknown> = {
    Logic: {
      REMINDER_TYPES: ["normal", "timeSensitive", "alarm"],
      reminderTypeOf(value: unknown) {
        return value === "normal" || value === "alarm" ? value : "timeSensitive";
      },
      optionForRepeat() {
        return "none";
      },
    },
    editingItem: () => item,
    refreshEditingRow: () => refreshes.push(1),
    todayText: () => "2026-10-31",
    applyRepeatChoice() {},
    openDetails() {},
    accessoryButtonHtml(kind: string, icon: string, control: string) {
      return "[" + kind + ":" + icon + ":" + control + "]";
    },
  };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return { toolbar: (sandbox as any).__toolbar, refreshes };
}

function newItem(fields: Partial<Item>): Item {
  return { id: "r1", date: null, time: null, reminderType: null, repeat: null, list: null, ...fields };
}

for (const page of PAGES) {
  const pageHtml = readFileSync(page.url, "utf8");

  describe(page.name + ": Alert in the keyboard toolbar", () => {
    it("the toolbar has an Alert button carrying a native menu, after Time", () => {
      const { toolbar } = toolbarFunctions(pageHtml, newItem({}));
      const html: string = toolbar.accessoryHtml();
      expect(html).toContain('[alert:bell:<select class="acc-native" data-native="acc-type" aria-label="Alert"></select>]');
      expect(html.indexOf("[time:")).toBeLessThan(html.indexOf("[alert:"));
      expect(html.indexOf("[alert:")).toBeLessThan(html.indexOf("[repeat:"));
    });

    it("the menu offers Normal, Time Sensitive and Alarm, Time Sensitive when none is chosen", () => {
      const { toolbar } = toolbarFunctions(pageHtml, newItem({}));
      const none: string = toolbar.reminderTypeOptionsHtml(null);
      expect(none).toBe('<option value="normal">Normal</option><option value="timeSensitive" selected>Time Sensitive</option><option value="alarm">Alarm</option>');
      expect(toolbar.reminderTypeOptionsHtml("alarm")).toContain('<option value="alarm" selected>Alarm</option>');
    });

    it("picking Alarm on a timed reminder sets its type and refreshes the row", () => {
      const item = newItem({ date: "2026-10-31", time: "15:00" });
      const { toolbar, refreshes } = toolbarFunctions(pageHtml, item);
      toolbar.applyAccessoryChange("acc-type", { value: "alarm" });
      expect(item.reminderType).toBe("alarm");
      toolbar.applyAccessoryChange("acc-type", { value: "normal" });
      expect(item.reminderType).toBe("normal");
      expect(refreshes.length).toBe(2);
    });

    it("a reminder without a time keeps no type", () => {
      const item = newItem({ date: "2026-10-31" });
      const { toolbar } = toolbarFunctions(pageHtml, item);
      toolbar.applyAccessoryChange("acc-type", { value: "alarm" });
      expect(item.reminderType).toBeNull();
    });

    it("the Alert button is hidden until the reminder has a time, and shows its type's name", () => {
      const update = functionSource(pageHtml, "updateAccessory");
      expect(update).toContain("accessory.querySelector('[data-acc=\"alert\"]').hidden = !item.time;");
      expect(update).toContain("alert: REMINDER_TYPE_LABELS[shownReminderType(item.reminderType)]");
      expect(update).toContain("reminderTypeOptionsHtml(item.reminderType)");
      expect(pageHtml).toContain(".acc-btn[hidden] { display: none; }");
    });

    it("the Details sheet still uses the same menu", () => {
      const details = functionSource(pageHtml, "reminderTypeSelectHtml");
      expect(details).toContain('data-native="det-type" aria-label="Alert">\' + reminderTypeOptionsHtml(reminderType)');
    });
  });
}
