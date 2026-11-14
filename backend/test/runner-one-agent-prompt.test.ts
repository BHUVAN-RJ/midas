// One repair agent for every Sidekick (founder, 2026-11-13, D5; docs/briefs/repair-lanes.md W4).
// These check that runner/agents/repair.md, filled by runner/lib/prompt.mjs, carries what each
// Sidekick is from its own manifest, the primitive it was built from and the person's notes; that
// a Sidekick with no file of its own gets the one agent instead of "no repair agent"; and that the
// per-Sidekick files stay in use until MIDAS_REPAIR_AGENT=shared.
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  buildSharedRepairPrompt,
  buildSystemPrompt,
  fillTemplateOnce,
  primitiveIdFor,
  repairAgentMode,
  settingsText,
  templateNameForSidekick,
  usesSharedAgent,
} from "../../runner/lib/prompt.mjs";
import { NO_NOTES_TEXT } from "../../runner/lib/person-notes.mjs";

const REPO_ROOT = join(__dirname, "..", "..");
const BASE_SIDEKICKS = ["reminders", "care-reminders", "hydration", "todo", "reminder-test", "money"];
const SHARED_HEADING = "# You repair one person's copy of the";

function manifestTextOf(sidekickId: string): string {
  return readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8");
}

function jobFor(sidekickId: string, transcript = "hide the search") {
  return { sidekickId, kind: "change", id: "r-w4", createdAt: "2026-11-13T10:00:00.000Z", transcript };
}

function sharedPromptFor(sidekickId: string, manifestText: string, extra: Record<string, unknown> = {}): string {
  return buildSharedRepairPrompt({
    job: jobFor(sidekickId),
    reportFiles: ["transcript.txt"],
    manifestText,
    checkoutRoot: REPO_ROOT,
    intelToolPath: "/r/intel.mjs",
    checkToolPath: "/r/check.mjs",
    ...extra,
  });
}

function templateText(): string {
  return readFileSync(join(REPO_ROOT, "runner", "agents", "repair.md"), "utf8");
}

describe("the one repair agent's prompt, for every base Sidekick", () => {
  for (const sidekickId of BASE_SIDEKICKS) {
    it(`${sidekickId}: its own manifest fills the prompt, with nothing left unfilled`, () => {
      const manifestText = manifestTextOf(sidekickId);
      const manifest = JSON.parse(manifestText);
      const prompt = sharedPromptFor(sidekickId, manifestText);
      expect(prompt.startsWith(`${SHARED_HEADING} ${manifest.name} Sidekick`)).toBe(true);
      expect(prompt).toContain(`- Id: \`${sidekickId}\``);
      expect(prompt).toContain(manifest.agent.description);
      for (const notForLine of manifest.agent.notFor) {
        expect(prompt).toContain(`- ${notForLine}`);
      }
      for (const tool of manifest.agent.tools) {
        expect(prompt).toContain(`- \`${tool.name}\`: ${tool.description}`);
      }
      for (const typeEntry of Object.values(manifest.types) as Array<{ schema?: { properties?: { $type?: { const?: string } } }; $type?: string }>) {
        const typeName = typeEntry.$type ?? typeEntry.schema?.properties?.$type?.const;
        if (typeof typeName === "string") {
          expect(prompt).toContain(typeName);
        }
      }
      expect(prompt).toContain(`\`${sidekickId}-<topic>.test.ts\``);
      expect(prompt).toContain(`\`../../sidekicks/${sidekickId}/index.html\``);
      expect(prompt).toContain("hide the search");
      expect(prompt).toContain("node /r/check.mjs");
      expect(prompt).toContain("node /r/intel.mjs list");
      expect(prompt).toContain("### 4.2 The `reminder:` record");
      expect(prompt).toContain("## 7. Limits and known issues");
      expect(prompt).toContain("Say the action. Stop.");
      expect(prompt).not.toMatch(/\{\{[A-Z_0-9]+\}\}/);
    });
  }

  it("Money's photo field reaches the agent from its manifest (midas/photo), not from a hand-written file", () => {
    const prompt = sharedPromptFor("money", manifestTextOf("money"));
    expect(prompt).toContain("Photo field: `receipt`.");
  });

  it("To-Do gets the to-do primitive: records, recipe, checklist and every block's table", () => {
    const prompt = sharedPromptFor("todo", manifestTextOf("todo"));
    expect(prompt).toContain("Built from the `todo` primitive");
    expect(prompt).toContain("Not the engine's `repeat`");
    expect(prompt).toContain("Recipe: building a to-do Sidekick");
    expect(prompt).toContain("Completeness checklist: to-do list primitive");
    expect(prompt).toContain("| TD-LOOK-01 | Page style | core |");
    expect(prompt).toContain("| TD-SET-01 |");
    // Only each block's opening: a pattern's full text stays out.
    expect(prompt).not.toContain("### TD-LOOK-01 Page style");
  });

  it("a Sidekick with no primitive says so instead of borrowing another's", () => {
    const prompt = sharedPromptFor("money", manifestTextOf("money"));
    expect(prompt).toContain("This Sidekick was not built from a primitive");
    expect(prompt).not.toContain("TD-LOOK");
  });
});

describe("which agent a job gets", () => {
  it("defaults to the per-Sidekick files until MIDAS_REPAIR_AGENT=shared", () => {
    expect(repairAgentMode({})).toBe("per-sidekick");
    expect(repairAgentMode({ MIDAS_REPAIR_AGENT: "shared" })).toBe("shared");
    expect(repairAgentMode({ MIDAS_REPAIR_AGENT: "Shared " })).toBe("per-sidekick");
    expect(usesSharedAgent("reminders", "per-sidekick")).toBe(false);
    expect(usesSharedAgent("reminders", "shared")).toBe(true);
  });

  it("a Sidekick with its own file gets it by default and the one agent in shared mode", () => {
    const manifestText = manifestTextOf("hydration");
    const job = jobFor("hydration");
    const perSidekick = buildSystemPrompt({ job, reportFiles: [], manifestText, checkoutRoot: REPO_ROOT, agentMode: "per-sidekick" });
    const shared = buildSystemPrompt({ job, reportFiles: [], manifestText, checkoutRoot: REPO_ROOT, agentMode: "shared" });
    expect(perSidekick).toContain("# You repair one user's copy of the hydration Sidekick");
    expect(shared).toContain(`${SHARED_HEADING} Water Sidekick`);
  });

  it("a Sidekick with no file of its own gets the one agent, not 'no repair agent'", () => {
    expect(templateNameForSidekick("split")).toBeNull();
    const manifestText = JSON.stringify({ id: "split", name: "Split", types: {}, agent: { description: "Split a bill.", tools: [] } });
    const prompt = buildSystemPrompt({ job: jobFor("split"), reportFiles: [], manifestText, checkoutRoot: REPO_ROOT, agentMode: "per-sidekick" });
    expect(prompt).toContain(`${SHARED_HEADING} Split Sidekick`);
    expect(prompt).toContain("- What it is: Split a bill.");
    expect(prompt).toContain("- (this copy has no tools yet)");
  });

  it("the one agent still refuses a copy with no usable manifest", () => {
    const job = jobFor("split");
    expect(() => buildSystemPrompt({ job, reportFiles: [], agentMode: "shared" })).toThrow('no repair agent for Sidekick "split"');
    expect(() => buildSystemPrompt({ job, reportFiles: [], manifestText: "not json", agentMode: "shared" })).toThrow("is not JSON");
    expect(() => buildSystemPrompt({ job, reportFiles: [], manifestText: "[]", agentMode: "shared" })).toThrow("is not an object");
  });
});

describe("the primitive comes from the manifest or the Sidekick's id, never from a path", () => {
  it("names the manifest's primitive when that folder exists, else the id's", () => {
    expect(primitiveIdFor({ manifest: { primitive: "todo" }, sidekickId: "chores", checkoutRoot: REPO_ROOT })).toBe("todo");
    expect(primitiveIdFor({ manifest: {}, sidekickId: "todo", checkoutRoot: REPO_ROOT })).toBe("todo");
    expect(primitiveIdFor({ manifest: { primitive: "no-such-primitive" }, sidekickId: "money", checkoutRoot: REPO_ROOT })).toBeNull();
  });

  it("a manifest value that climbs out of docs/primitives is ignored", () => {
    // docs/primitives/../../runner has no README.md, but docs/primitives/../ (docs) would match
    // a README if paths were accepted; both must be refused by the name rule itself.
    const checkoutRoot = mkdtempSync(join(tmpdir(), "w4-primitive-"));
    mkdirSync(join(checkoutRoot, "docs", "primitives"), { recursive: true });
    writeFileSync(join(checkoutRoot, "docs", "README.md"), "# not a primitive");
    expect(primitiveIdFor({ manifest: { primitive: ".." }, sidekickId: "money", checkoutRoot })).toBeNull();
    expect(primitiveIdFor({ manifest: { primitive: "../primitives/../" }, sidekickId: "money", checkoutRoot })).toBeNull();
  });
});

describe("the person's notes and settings in the prompt", () => {
  it("shows the dated lines of the notes it is given, and says when there are none", () => {
    const notesText = "# This person's notes\n\n- 2026-11-07: Search tab hidden. Search stays in the top bar. (repair r-1)\n";
    const withNotes = sharedPromptFor("todo", manifestTextOf("todo"), { personNotesText: notesText });
    expect(withNotes).toContain("- 2026-11-07: Search tab hidden. Search stays in the top bar. (repair r-1)");
    const withoutNotes = sharedPromptFor("todo", manifestTextOf("todo"));
    expect(withoutNotes).toContain(NO_NOTES_TEXT);
  });

  it("reads the notes from the job folder's tests/PERSON_NOTES.md", () => {
    const jobFolder = mkdtempSync(join(tmpdir(), "w4-job-"));
    mkdirSync(join(jobFolder, "tests"), { recursive: true });
    writeFileSync(join(jobFolder, "tests", "PERSON_NOTES.md"), "# This person's notes\n\n- 2026-11-08: Streak hidden. (repair r-2)\n");
    const prompt = sharedPromptFor("hydration", manifestTextOf("hydration"), { jobFolder });
    expect(prompt).toContain("- 2026-11-08: Streak hidden. (repair r-2)");
    expect(prompt).not.toContain(NO_NOTES_TEXT);
  });

  it("shows a settings catalogue when the manifest has one (W5), else points at the settings: type", () => {
    const catalogue = [{ key: "accent", type: "colour", default: "#2F6FEB", part: "header" }];
    expect(settingsText({ settings: catalogue, types: {} })).toContain('"key": "accent"');
    expect(settingsText({ types: { "settings:": {} } })).toContain("declares no `settings` block yet");
    expect(settingsText({ types: {} })).toContain("no `settings:` type yet");
  });
});

describe("filling the template", () => {
  it("fills in one pass: words in the transcript that look like a placeholder stay as said", () => {
    const job = jobFor("todo", "please show {{WRITING}} on the page");
    const prompt = buildSharedRepairPrompt({ job, reportFiles: [], manifestText: manifestTextOf("todo"), checkoutRoot: REPO_ROOT });
    expect(prompt).toContain("please show {{WRITING}} on the page");
    expect(fillTemplateOnce("{{A}} {{B}}", { A: "{{B}}", B: "b" })).toBe("{{B}} b");
  });
});

describe("the shared template's rules", () => {
  const template = templateText();

  it("hands the guardian the check command and the reversal rule, like the per-Sidekick prompts", () => {
    const start = template.indexOf("- When an existing test blocks what the person asked for");
    expect(start).toBeGreaterThan(-1);
    const delegation = template.slice(start, template.indexOf("\n- ", start + 1));
    expect(delegation).toContain("`node {{CHECK_TOOL}}`");
    expect(delegation).toContain("A user reversing an earlier");
  });

  it("tells the agent to run the commands bare", () => {
    expect(template).toContain("Run both commands exactly as written here: `node`, then the path bare (never in quotes),");
    expect(template).toContain("no `2>&1`, `|`, `>` or `;` after them");
  });

  it("carries D1: remove means hide, and the settings engine and set_setting are never removed", () => {
    expect(template).toContain("Remove means hide");
    expect(template).toContain("keep the feature's code and its voice tool");
    expect(template).toContain("never remove `set_setting`");
    expect(template).toContain("the engine, its handling of\n`settings:self` and its tool are never removed");
  });

  it("asks for the notes line in outcome.json and forbids editing the notes file", () => {
    expect(template).toContain('"note": "Search tab hidden. Search stays in the top bar."');
    expect(template).toContain("The log is `tests/PERSON_NOTES.md`. Never edit it");
  });
});
