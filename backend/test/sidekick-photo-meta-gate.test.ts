// The deploy gate's rule for _meta["midas/photo"] (founder, 2026-11-08): a tool may name one input
// field the server fills with the jess request's photo ("file:<id>"). The field must be a plain
// name and must not be in inputSchema, so the model never sees or fills it. The repair runner
// runs the same gate on every user copy.
import { describe, expect, it } from "vitest";
import { agentBlockProblems } from "../scripts/bundle-tools.mjs";

function agentWithMeta(meta: Record<string, unknown>, extraProperties: Record<string, unknown> = {}) {
  return {
    description: "Things.",
    rules: [],
    notFor: [],
    examples: ["add a thing"],
    tools: [
      {
        name: "things.add",
        description: "Add a thing.",
        _meta: { "midas/page-actions": ["add"], ...meta },
        inputSchema: {
          type: "object",
          additionalProperties: false,
          required: ["title", ...Object.keys(extraProperties)],
          properties: { title: { type: ["string", "null"] }, ...extraProperties },
        },
      },
    ],
  };
}

describe("midas/photo in a tool's _meta", () => {
  it("is accepted when it names a field outside inputSchema", () => {
    expect(agentBlockProblems(agentWithMeta({ "midas/photo": "picture" }), "things")).toEqual([]);
  });

  it("is refused when the model could fill the field (it is in inputSchema)", () => {
    const problems = agentBlockProblems(agentWithMeta({ "midas/photo": "picture" }, { picture: { type: ["string", "null"] } }), "things");
    expect(problems.join("\n")).toContain('names "picture", which is in inputSchema');
  });

  it("is refused when it is not a plain field name", () => {
    for (const value of [42, "", "a.b", "../x"]) {
      const problems = agentBlockProblems(agentWithMeta({ "midas/photo": value }), "things");
      expect(problems.join("\n"), String(value)).toContain('_meta["midas/photo"] must name the input field');
    }
  });
});
