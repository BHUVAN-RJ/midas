// Work log entries are links (founder, 2026-10-31; docs/mockups/jess-worklog-links-2026-10-31.html):
// a jess work log card opens its Sidekick at the record it changed. The shell hands the page the
// change once (store.focus(), shell/sdk/midas-store.js) and the SDK marks the element carrying
// that record's key. Each base page must ask for the focus, open the view holding the record, and
// put data-key on its record rows, or the tap lands on the page with nothing marked.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

function page(sidekickId: string): string {
  return readFileSync(new URL(`../../sidekicks/${sidekickId}/index.html`, import.meta.url), "utf8");
}

const storeHelperSource = readFileSync(new URL("../../shell/sdk/midas-store.js", import.meta.url), "utf8");

describe("the store helper", () => {
  it("asks the shell for the focus once and marks the keyed element by itself", () => {
    expect(storeHelperSource).toContain("op: 'focus'");
    expect(storeHelperSource).toContain("focus: readFocus");
    expect(storeHelperSource).toContain("markChange: markChange");
    expect(storeHelperSource).toContain("markFocusWhenDrawn();");
    // The Volt of the mark (docs/DESIGN.md 2.2), never a purple
    expect(storeHelperSource).toContain("#CEFF00");
  });

  it("never scrolls a container the page keeps still (Reminders' own scroller)", () => {
    expect(storeHelperSource).not.toContain("scrollIntoView");
    expect(storeHelperSource).toContain("function scrollingAncestor");
  });
});

describe("Reminders", () => {
  const html = page("reminders");

  it("keys every reminder row and opens the view holding the focused one", () => {
    expect(html).toContain(`data-key="' + escapeHtml(recordKey(item)) + '"`);
    expect(html).toContain("const focus = await store.focus();");
    expect(html).toContain("openViewHolding(focus);");
    expect(html).toContain("scrollToFocus(focus);");
  });
});

describe("Water", () => {
  const html = page("hydration");

  it("keys the drink jess logged with its day's record and opens that day", () => {
    expect(html).toContain("state.focus = await store.focus();");
    expect(html).toContain("openViewHolding(state.focus);");
    expect(html).toContain(`' data-key="' + escapeHtml(Logic.DAY_PREFIX + dateKey) + '"'`);
  });
});

describe("Care Reminders", () => {
  const html = page("care-reminders");

  it("keys every reminder row and opens the list holding the focused one", () => {
    expect(html).toContain(`data-key="' + escapeHtml(itemKey(item.id)) + '"`);
    expect(html).toContain("openListHolding(await store.focus());");
  });
});
