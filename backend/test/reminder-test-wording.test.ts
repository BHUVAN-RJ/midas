import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { describe, expect, it } from "vitest";

// The Reminders page's on-screen words follow docs/WRITING.md: the action, then stop (founder
// approved the wording mockup docs/mockups/wording-2026-10-10.html on 2026-10-10). These fail if
// a removed explaining line or an old phrase comes back.

type AnyRecord = Record<string, any>;

const pagePath = fileURLToPath(new URL("../../sidekicks/reminder-test/index.html", import.meta.url));
const pageText = readFileSync(pagePath, "utf8");

function loadRemindersLogic(): AnyRecord {
  const scriptStart = pageText.indexOf("<script>") + "<script>".length;
  const scriptEnd = pageText.indexOf("</script>", scriptStart);
  const scriptText = pageText.slice(scriptStart, scriptEnd);
  const sandbox: AnyRecord = { window: { location: { origin: "sidekick://reminders" } }, Intl, Date, Math, JSON };
  vm.createContext(sandbox);
  vm.runInContext(scriptText + "\n;globalThis.__logic = RemindersLogic;", sandbox);
  return sandbox.__logic;
}

const removedPhrases = [
  // Empty state explaining line (E2)
  "Bring your lists and reminders over from Apple Reminders",
  // Summary footnote (I9) and old summary rows (I8, I10, I12)
  "Those came in as one-off reminders",
  "Repeats not brought across",
  "Updated from your iPhone",
  "Already here, skipped",
  // Error lines that explained or showed technical words (A2, A4, A5, A6, A7)
  "To allow it, open Settings",
  "Part of your reminders didn’t arrive",
  "The file could not be opened",
  "not valid JSON",
  "does not look like an export",
  "Something went wrong",
  // Interface explanations (D1, D2)
  "then drag it to move it",
  "months without that day are skipped",
  // Old verb (rule 13)
  "Import from Apple Reminders",
  "Importing from Apple Reminders",
  "Couldn’t Import",
];

describe("Reminders page wording (docs/WRITING.md, 2026-10-10)", () => {
  for (const phrase of removedPhrases) {
    it(`never shows "${phrase}"`, () => {
      expect(pageText).not.toContain(phrase);
    });
  }

  it("uses the same import words as the shell's sheet", () => {
    expect(pageText).toContain(">Import Apple Reminders</button>");
    expect(pageText).toContain("showProgress('Importing…'");
    expect(pageText).toContain("showAlert('Import Failed', 'Try again.')");
  });

  it("keeps the empty state to a headline and one button", () => {
    const start = pageText.indexOf("function emptyStateHtml()");
    const end = pageText.indexOf("\n  }\n", start);
    const emptyStateSource = pageText.slice(start, end);

    expect(emptyStateSource).toContain("No Reminders");
    expect(emptyStateSource).not.toContain("empty-text");
  });

  it("notes an unimported repeat in a few words, with the reason", () => {
    const Logic = loadRemindersLogic();
    const zone = "America/Los_Angeles";
    const reminder = {
      id: "device-R1",
      externalId: "R1",
      listId: "phone-list",
      title: "Water plants",
      notes: null,
      url: null,
      completed: false,
      completionDate: null,
      creationDate: "2026-09-01T10:00:00-07:00",
      lastModifiedDate: "2026-09-01T10:00:00-07:00",
      priority: 0,
      due: { allDay: true, date: "2026-10-12", time: null, timeZone: null, instant: null },
      alarms: [],
      recurrence: [
        { frequency: "daily", interval: 1 },
        { frequency: "weekly", interval: 1 },
      ],
    };
    const exported = {
      source: "apple-reminders",
      origin: "iphone",
      exportedAt: "2026-10-10T21:00:00-07:00",
      timeZone: zone,
      lists: [{ id: "phone-list", title: "Reminders", color: "#FF9500" }],
      reminders: [reminder],
    };

    const result = Logic.mapAppleExport(exported, { items: [], lists: [] }, zone, { updateExisting: false });

    expect(result.items).toHaveLength(1);
    expect(result.items[0].notes).toBe("Repeat not imported: repeats by more than one rule.");
  });
});
