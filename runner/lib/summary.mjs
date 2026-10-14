// summary.md: what the founder reads after a job. The request, the transcript, what the agent
// did, the diff, what went live, and the way back.
export function resetToBaseCommand({ sidekickId, userId }) {
  return `node scripts/deploy-sidekick.mjs ${sidekickId} --env live --user ${userId} --from-base`;
}

export function buildSummary({ job, jobFolder, outcome, diff, checkOutput, logFolder, deployedVersion = null }) {
  const lines = [];
  lines.push(`# Repair ${job.id}: ${job.sidekickId}`);
  lines.push("");
  lines.push(`- User: ${job.userId}`);
  lines.push(`- Kind: ${job.kind}`);
  lines.push(`- Bundle the user was on: ${job.bundleVersion ?? "unknown"}`);
  lines.push(`- Device: ${job.device ?? "unknown"}, app ${job.appVersion ?? "unknown"}`);
  lines.push(`- Reported: ${job.createdAt ?? "unknown"}`);
  lines.push(`- Job folder: ${jobFolder}`);
  lines.push(`- Log: ${logFolder}`);
  lines.push("");
  lines.push("## What the user said");
  lines.push("");
  lines.push(job.transcript.trim().length > 0 ? job.transcript.trim() : "(empty)");
  lines.push("");
  lines.push("## What the agent did");
  lines.push("");
  lines.push(`Result: ${outcome.result}`);
  lines.push("");
  lines.push(outcome.summary);
  if (outcome.result === "unsupported") {
    lines.push("");
    lines.push(`Not supported: ${outcome.unsupportedAction}`);
  }
  lines.push("");
  if (outcome.result === "fixed") {
    lines.push("## Live");
    lines.push("");
    if (deployedVersion !== null) {
      lines.push(`Version ${deployedVersion} is live for user ${job.userId} (their copy only; the base is untouched).`);
    } else {
      lines.push("Not deployed.");
    }
    lines.push("");
    lines.push("Way back, from the runner checkout's backend/ folder (puts this user back on the base):");
    lines.push("");
    lines.push("```");
    lines.push(resetToBaseCommand({ sidekickId: job.sidekickId, userId: job.userId }));
    lines.push("```");
    lines.push("");
    lines.push("## Diff");
    lines.push("");
    lines.push("```diff");
    lines.push(diff.trimEnd());
    lines.push("```");
    lines.push("");
  }
  if (checkOutput && checkOutput.trim().length > 0) {
    lines.push("## Check output (tail)");
    lines.push("");
    lines.push("```");
    const outputLines = checkOutput.trimEnd().split("\n");
    lines.push(outputLines.slice(-40).join("\n"));
    lines.push("```");
    lines.push("");
  }
  return lines.join("\n");
}
