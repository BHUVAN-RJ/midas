// The deploy gate's check of a Sidekick's tools (jess router, founder 2026-10-21): the manifest's
// agent block (MCP-style tools whose inputSchema stays inside every provider's strict-mode
// subset) and tools.js (runs alone, one handler per tool, page code copied character for
// character). A builder that breaks any of these is refused before anything is deployed.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { validateManifest } from "../scripts/bundle-tools.mjs";
import {
  agentBlockProblems,
  copiedBlockProblems,
  inputSchemaProblems,
  loadToolsScript,
  sidekickToolsProblems,
  wireToolName,
} from "../scripts/sidekick-tools.mjs";

function readSidekick(sidekickId: string) {
  const folder = new URL(`../../sidekicks/${sidekickId}/`, import.meta.url);
  return {
    html: readFileSync(new URL("index.html", folder), "utf8"),
    manifest: JSON.parse(readFileSync(new URL("manifest.json", folder), "utf8")),
    toolsText: readFileSync(new URL("tools.js", folder), "utf8"),
  };
}

function strictObject(properties: Record<string, unknown>) {
  return { type: "object", additionalProperties: false, required: Object.keys(properties), properties };
}

function agentWith(tools: unknown[]) {
  return { description: "Test lists.", rules: ["One at a time."], notFor: ["Weather."], examples: ["Add milk"], tools };
}

function simpleTool(name = "demo.add") {
  return { name, description: "Add a thing.", inputSchema: strictObject({ title: { type: "string" } }) };
}

const TOOLS_SOURCE = [
  "var MidasSidekickTools = (function () {",
  "  function add(input, records, now) { return { ops: [], result: { text: 'Added' } }; }",
  "  function context() { return {}; }",
  "  return { context: context, handlers: { add: add } };",
  "})();",
].join("\n");

describe("both live Sidekicks pass", () => {
  for (const sidekickId of ["reminders", "care-reminders"]) {
    it(`${sidekickId}: manifest, agent block and tools.js`, () => {
      const files = readSidekick(sidekickId);
      expect(validateManifest(files.manifest, sidekickId)).toEqual([]);
      expect(sidekickToolsProblems(files.manifest, files.toolsText, files.html, sidekickId)).toEqual([]);
    });
  }

  it("names every tool <sidekickId>.<verb> and fits the wire name rule", () => {
    for (const sidekickId of ["reminders", "care-reminders"]) {
      for (const tool of readSidekick(sidekickId).manifest.agent.tools) {
        expect(tool.name.startsWith(sidekickId + ".")).toBe(true);
        expect(wireToolName(tool.name)).toMatch(/^[a-zA-Z0-9_-]{1,64}$/);
      }
    }
  });
});

describe("inputSchema: the strict-mode subset", () => {
  it("accepts objects with every property required, nullable unions, enums, $defs and $ref", () => {
    const schema = {
      ...strictObject({
        title: { type: "string", description: "What" },
        list: { type: ["string", "null"] },
        when: { anyOf: [{ $ref: "#/$defs/when" }, { type: "null" }] },
        kind: { type: "string", enum: ["a", "b"] },
        tags: { type: "array", items: { type: "string" } },
      }),
      $defs: { when: strictObject({ date: { type: ["string", "null"], format: "date" } }) },
    };
    expect(inputSchemaProblems(schema)).toEqual([]);
  });

  it("refuses an optional property, a missing additionalProperties false and range keywords", () => {
    const optional = { type: "object", additionalProperties: false, required: [], properties: { title: { type: "string" } } };
    expect(inputSchemaProblems(optional).join(" ")).toContain("every property must be required");
    const open = { type: "object", required: ["title"], properties: { title: { type: "string" } } };
    expect(inputSchemaProblems(open).join(" ")).toContain("additionalProperties");
    const ranged = strictObject({ title: { type: "string", minLength: 1 }, count: { type: "integer", maximum: 9 } });
    const problems = inputSchemaProblems(ranged).join(" ");
    expect(problems).toContain('"minLength"');
    expect(problems).toContain('"maximum"');
  });

  it("refuses recursion, a $ref to nothing, a top-level union and an array without items", () => {
    const recursive = { ...strictObject({ node: { $ref: "#/$defs/node" } }), $defs: { node: strictObject({ child: { anyOf: [{ $ref: "#/$defs/node" }, { type: "null" }] } }) } };
    expect(inputSchemaProblems(recursive).join(" ")).toContain("recursive");
    expect(inputSchemaProblems(strictObject({ x: { $ref: "#/$defs/missing" } })).join(" ")).toContain("must name an entry of $defs");
    expect(inputSchemaProblems({ anyOf: [{ type: "object" }, { type: "null" }] })).not.toEqual([]);
    expect(inputSchemaProblems(strictObject({ tags: { type: "array" } })).join(" ")).toContain("needs items");
  });
});

describe("the agent block", () => {
  it("accepts a well-formed block", () => {
    expect(agentBlockProblems(agentWith([simpleTool()]), "demo")).toEqual([]);
  });

  it("refuses a tool outside the Sidekick's namespace, a bad verb and a name used twice", () => {
    expect(agentBlockProblems(agentWith([simpleTool("other.add")]), "demo").join(" ")).toContain('"demo.<verb>"');
    expect(agentBlockProblems(agentWith([simpleTool("demo.Add-Thing")]), "demo").join(" ")).toContain('"demo.<verb>"');
    expect(agentBlockProblems(agentWith([simpleTool(), simpleTool()]), "demo").join(" ")).toContain("used twice");
  });

  it("refuses missing lines, no tools, unknown tool fields and a when marker naming no property", () => {
    expect(agentBlockProblems({ ...agentWith([simpleTool()]), description: "" }, "demo").join(" ")).toContain("agent.description");
    expect(agentBlockProblems({ ...agentWith([simpleTool()]), examples: "Add milk" }, "demo").join(" ")).toContain("agent.examples");
    expect(agentBlockProblems(agentWith([]), "demo").join(" ")).toContain("agent.tools");
    expect(agentBlockProblems(agentWith([{ ...simpleTool(), handler: "x" }]), "demo").join(" ")).toContain('unknown field "handler"');
    expect(agentBlockProblems(agentWith([{ ...simpleTool(), _meta: { "midas/when": "when" } }]), "demo").join(" ")).toContain("midas/when");
  });

  it("is part of the manifest check the deploy and the runner already run", () => {
    const manifest = { id: "demo", name: "Demo", icon: { symbol: "star", background: "#FF9500" }, reads: [], agent: agentWith([simpleTool("demo.Bad")]) };
    expect(validateManifest(manifest, "demo").join(" ")).toContain("agent.tools[0].name");
  });
});

describe("tools.js", () => {
  const manifest = { id: "demo", agent: agentWith([simpleTool()]) };

  it("passes when it sets the global with context and one handler per tool", () => {
    expect(sidekickToolsProblems(manifest, TOOLS_SOURCE, "<html></html>", "demo")).toEqual([]);
    const loaded = loadToolsScript(TOOLS_SOURCE);
    expect("tools" in loaded).toBe(true);
  });

  it("is required by an agent block, and needs an agent block itself", () => {
    expect(sidekickToolsProblems(manifest, null, "<html></html>", "demo").join(" ")).toContain("there is no tools.js");
    expect(sidekickToolsProblems({ id: "demo" }, TOOLS_SOURCE, "<html></html>", "demo").join(" ")).toContain("needs an agent block");
    expect(sidekickToolsProblems({ id: "demo" }, null, "<html></html>", "demo")).toEqual([]);
  });

  it("refuses a tool without a handler and a handler without a tool", () => {
    const twoTools = { id: "demo", agent: agentWith([simpleTool(), simpleTool("demo.delete")]) };
    expect(sidekickToolsProblems(twoTools, TOOLS_SOURCE, "", "demo").join(" ")).toContain("no handler for demo.delete");
    const extraHandler = TOOLS_SOURCE.replace("handlers: { add: add }", "handlers: { add: add, wipe: add }");
    expect(sidekickToolsProblems(manifest, extraHandler, "", "demo").join(" ")).toContain('handler "wipe" has no tool');
  });

  it("refuses network, store, code loading, and a script that throws or sets no global", () => {
    const withFetch = TOOLS_SOURCE.replace("return { ops: []", "fetch('https://x'); return { ops: []");
    expect(sidekickToolsProblems(manifest, withFetch, "", "demo").join(" ")).toContain("may not use fetch");
    const withStore = TOOLS_SOURCE.replace("return { ops: []", "store.set('a:1', {}); return { ops: []");
    expect(sidekickToolsProblems(manifest, withStore, "", "demo").join(" ")).toContain("may not use store");
    expect(sidekickToolsProblems(manifest, "throw new Error('boom');", "", "demo").join(" ")).toContain("does not run: boom");
    expect(sidekickToolsProblems(manifest, "var Other = {};", "", "demo").join(" ")).toContain("must set the global");
  });

  it("refuses a copied block that no longer matches the page", () => {
    const html = "<script>\n  function shared(a) {\n    return a + 1;\n  }\n</script>";
    const copied = "  /* copied from index.html: begin */\n  function shared(a) {\n    return a + 1;\n  }\n  /* copied from index.html: end */\n";
    expect(copiedBlockProblems(copied, html)).toEqual([]);
    const pageChanged = html.replace("a + 1", "a + 2");
    expect(copiedBlockProblems(copied, pageChanged).join(" ")).toContain("no longer matches index.html");
    expect(copiedBlockProblems("  /* copied from index.html: begin */\n  x\n", html).join(" ")).toContain("no end marker");
  });

  it("catches the live Reminders tools.js drifting from its page", () => {
    const files = readSidekick("reminders");
    const drifted = files.html.replace("function markDoneChange(occurrenceIso, nowIso) {", "function markDoneChange(occurrenceIso, nowIso) {\n    // changed");
    expect(drifted).not.toBe(files.html);
    expect(sidekickToolsProblems(files.manifest, files.toolsText, drifted, "reminders").join(" ")).toContain("no longer matches index.html");
  });
});
