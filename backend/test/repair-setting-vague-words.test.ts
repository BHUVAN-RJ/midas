import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  EMPTY_ONLY_RULE,
  VAGUE_WORDS_RULE,
  buildSettingPrompt,
  buildSettingRequest,
  mapSetting,
} from "../src/repair-setting-model";
import type { SettingRequest } from "../src/repair-setting-model";
import type { SettingsCatalogue } from "../../shell/sdk/midas-settings.js";

// Vague words stay in the setting lane (founder, 2026-11-22; docs/briefs/repair-lanes.md "Change
// 2026-11-22"). Build 42: "Can you change the color to red" on Reminders came back {"changes": []}
// from Haiku and fell to the slow code lane, because the prompt said to answer empty when no setting
// named does it, and people never name the setting. The prompt now tells the model to pick the most
// visible setting of that kind (a colour with no part: the main colour; bigger or smaller: the main
// text size; darker or lighter: the background) and to answer empty only when no setting of that
// kind exists. No network here: the golden set's ideal replies go through the lane's own checks;
// backend/scripts/setting-bench.mjs runs the same set against Haiku by hand.

type GoldenCase = {
  sidekick: string;
  words: string;
  accept: string[];
  reply: { changes: Array<{ key: string; value: unknown }> };
};

type Golden = { cases: GoldenCase[] };

const goldenText = readFileSync(new URL("../scripts/setting-golden.json", import.meta.url), "utf8");
const golden = JSON.parse(goldenText) as Golden;

function catalogueOf(sidekickId: string): SettingsCatalogue {
  const manifestUrl = new URL(`../../sidekicks/${sidekickId}/manifest.json`, import.meta.url);
  const manifestText = readFileSync(manifestUrl, "utf8");
  const manifest = JSON.parse(manifestText) as { settings: SettingsCatalogue };
  return manifest.settings;
}

function requestFor(goldenCase: GoldenCase): SettingRequest {
  return {
    words: goldenCase.words,
    sidekickName: goldenCase.sidekick,
    drawing: "nothing",
    catalogue: catalogueOf(goldenCase.sidekick),
    record: null,
  };
}

function caseName(goldenCase: GoldenCase): string {
  return `${goldenCase.sidekick}: "${goldenCase.words}"`;
}

// OpenRouter as a stub that answers with the case's ideal reply and keeps the prompt it was sent.
function haikuStub(answer: unknown, sentPrompts: string[]) {
  async function fakeFetch(_url: string, init: RequestInit): Promise<Response> {
    const body = JSON.parse(String(init.body)) as { messages: Array<{ content: string }> };
    sentPrompts.push(body.messages[0].content);
    const reply = { choices: [{ message: { content: JSON.stringify(answer) } }], usage: { cost: 0.0001 } };
    return new Response(JSON.stringify(reply), { status: 200, headers: { "content-type": "application/json" } });
  }
  return fakeFetch;
}

const PHRASES = ["Can you change the color to red", "make it darker", "bigger text", "make it pop"];
const CATALOGUES = ["reminders", "care-reminders", "todo"];

describe("the golden set covers the founder's four phrases on three catalogues", () => {
  it("has every phrase for every catalogue", () => {
    const covered = new Set<string>();
    for (const goldenCase of golden.cases) {
      covered.add(`${goldenCase.sidekick}|${goldenCase.words}`);
    }
    for (const sidekick of CATALOGUES) {
      for (const phrase of PHRASES) {
        expect(covered.has(`${sidekick}|${phrase}`), `${sidekick}: ${phrase}`).toBe(true);
      }
    }
  });
});

describe("the setting prompt picks the most visible setting for vague words", () => {
  it("names the rule for each kind: colour, size, darker or lighter, and pop", () => {
    expect(VAGUE_WORDS_RULE).toContain("most visible setting of that kind");
    expect(VAGUE_WORDS_RULE).toContain("a colour with no part named is the main colour");
    expect(VAGUE_WORDS_RULE).toContain("bigger or smaller with no part named is the main text size");
    expect(VAGUE_WORDS_RULE).toContain("darker or lighter with no part named is the background colour");
    expect(VAGUE_WORDS_RULE).toContain('"make it pop"');
    expect(EMPTY_ONLY_RULE).toContain("only when the app has no setting of that kind at all");
  });

  for (const goldenCase of golden.cases) {
    it(`${caseName(goldenCase)}: the prompt carries the words and both rules`, () => {
      const prompt = buildSettingPrompt(requestFor(goldenCase));
      expect(prompt).toContain(`Their words: "${goldenCase.words}"`);
      expect(prompt).toContain(VAGUE_WORDS_RULE);
      expect(prompt).toContain(EMPTY_ONLY_RULE);
      // The line that made build 42 answer empty for "change the color to red"
      expect(prompt).not.toContain("If no setting listed does what they asked");
    });

    it(`${caseName(goldenCase)}: the setting it should pick is in the catalogue the prompt lists`, () => {
      const prompt = buildSettingPrompt(requestFor(goldenCase));
      for (const key of goldenCase.accept) {
        expect(prompt, key).toContain(`- ${key} | `);
      }
    });

    it(`${caseName(goldenCase)}: the ideal answer is accepted and stays in the setting lane`, async () => {
      const sentPrompts: string[] = [];
      const mapping = await mapSetting(requestFor(goldenCase), "test-key", haikuStub(goldenCase.reply, sentPrompts));
      expect(mapping.ok, mapping.ok ? "" : mapping.reason).toBe(true);
      if (!mapping.ok) {
        return;
      }
      const changedKeys = mapping.changes.map(function keyOf(change) {
        return change.key;
      });
      const hitsAnAcceptedKey = changedKeys.some(function isAccepted(key) {
        return goldenCase.accept.includes(key);
      });
      expect(hitsAnAcceptedKey, changedKeys.join(",")).toBe(true);
      expect(sentPrompts).toHaveLength(1);
      expect(sentPrompts[0]).toContain(VAGUE_WORDS_RULE);
    });
  }

  it("an empty answer still goes up to code (the rule only changes what the model is asked)", async () => {
    const reminders = golden.cases[0];
    const mapping = await mapSetting(requestFor(reminders), "test-key", haikuStub({ changes: [] }, []));
    expect(mapping.ok).toBe(false);
    if (!mapping.ok) {
      expect(mapping.reason).toBe("no setting does it");
    }
  });

  it("the request body sends the prompt with the rule to Haiku", () => {
    const body = buildSettingRequest(requestFor(golden.cases[0])) as { messages: Array<{ content: string }> };
    expect(body.messages[0].content).toContain(VAGUE_WORDS_RULE);
  });
});
