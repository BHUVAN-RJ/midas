// Reads a claude stream-json log (agent.mjs runAgent) for check-sandbox.mjs --agent: which tool
// calls the agent made and what came back. A check passes only when the agent tried the call and
// it was refused; a call it never made proves nothing (founder's run, 2026-10-22: the model
// declined every step and the file checks still showed ✓).

// Every tool call in the log, in order: { name, input, isError, resultText }. Lines that are not
// JSON are skipped. A call with no result yet has isError null.
export function toolCallsFromLog(logText) {
  const calls = [];
  const callsById = new Map();
  for (const line of logText.split("\n")) {
    let event = null;
    try {
      event = JSON.parse(line);
    } catch {
      continue;
    }
    const content = event?.message?.content;
    if (!Array.isArray(content)) {
      continue;
    }
    for (const part of content) {
      if (event.type === "assistant" && part.type === "tool_use") {
        const call = { name: part.name, input: part.input ?? {}, isError: null, resultText: "" };
        calls.push(call);
        callsById.set(part.id, call);
      }
      if (event.type === "user" && part.type === "tool_result" && callsById.has(part.tool_use_id)) {
        const call = callsById.get(part.tool_use_id);
        call.isError = part.is_error === true;
        call.resultText = typeof part.content === "string" ? part.content : JSON.stringify(part.content ?? "");
      }
    }
  }
  return calls;
}

// "refused" when the agent called one of toolNames on targetPath and every such call came back an
// error; "allowed" when one of them succeeded; "not tried" when it never made the call.
export function probeVerdict({ calls, toolNames, targetPath }) {
  const attempts = [];
  for (const call of calls) {
    const namesTarget = JSON.stringify(call.input).includes(targetPath);
    if (toolNames.includes(call.name) && namesTarget) {
      attempts.push(call);
    }
  }
  if (attempts.length === 0) {
    return "not tried";
  }
  for (const attempt of attempts) {
    if (attempt.isError !== true) {
      return "allowed";
    }
  }
  return "refused";
}

// True when the API swapped models after its safety filter flagged the prompt (the founder's
// run: "model_refusal_fallback", Opus 5.5 to Opus 4.8).
export function modelWasSwapped(logText) {
  return logText.includes("\"model_refusal_fallback\"");
}
