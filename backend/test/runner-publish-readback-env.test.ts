// When the read-back cannot be read, the deploy script's closing line counts as the publish only
// if it names the job's own environment (runner serves live and staging, founder 2026-10-21; a
// published repair is always marked done, founder 2026-10-21): a line for the other environment
// is never this job's publish.
import { describe, expect, it } from "vitest";
import { publishedVersionFromOutput } from "../../runner/lib/deploy.mjs";

const STAGING_LINE = "deployed reminders 20261020T055239856Z-b44ec144 for user 9-GAkqjLqjvn6Hyr9-AbTg to staging with 1 script hash(es) and 9 test file(s); base untouched";

describe("publishedVersionFromOutput and the job's environment", () => {
  it("takes the line only when it names the job's environment", () => {
    expect(publishedVersionFromOutput({ output: STAGING_LINE, sidekickId: "reminders", userId: "9-GAkqjLqjvn6Hyr9-AbTg", environmentName: "staging" })).toBe("20261020T055239856Z-b44ec144");
    expect(publishedVersionFromOutput({ output: STAGING_LINE, sidekickId: "reminders", userId: "9-GAkqjLqjvn6Hyr9-AbTg", environmentName: "live" })).toBeNull();
  });
});
