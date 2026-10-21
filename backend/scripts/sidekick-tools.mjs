// A Sidekick's tools (jess router, founder 2026-10-21): the checks live in bundle-tools.mjs, which
// must stay one self-contained file (the runner's tests copy it alone into scratch checkouts).
export {
  TOOLS_FILE,
  TOOLS_GLOBAL,
  WHEN_META_KEY,
  WIRE_NAME_LIMIT,
  COPY_BEGIN,
  COPY_END,
  inputSchemaProblems,
  wireToolName,
  toolVerb,
  agentBlockProblems,
  copiedBlocks,
  copiedBlockProblems,
  loadToolsScript,
  sidekickToolsProblems,
} from "./bundle-tools.mjs";
