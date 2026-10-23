// runner/bin/start.sh must find a node installed with nvm, since launchd's PATH does not include
// it (2026-10-21: the runner exited with "command not found: node" on the founder's Mac).
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

const startScript = resolve(__dirname, "../../runner/bin/start.sh");
const systemDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"];

// If a real node sits in one of the fixed PATH folders, start.sh would run it instead of the fake.
function realNodeOnFixedPath(): boolean {
  return systemDirs.some(function hasNode(folder) { return existsSync(join(folder, "node")); });
}

function makeFakeHome(aliasText: string, versionFolder: string): string {
  const home = mkdtempSync(join(tmpdir(), "runner-nvm-"));
  const binFolder = join(home, ".nvm", "versions", "node", versionFolder, "bin");
  mkdirSync(binFolder, { recursive: true });
  mkdirSync(join(home, ".nvm", "alias"), { recursive: true });
  writeFileSync(join(home, ".nvm", "alias", "default"), aliasText);
  const fakeNode = join(binFolder, "node");
  // The fake node prints which script it was asked to run, then stops.
  writeFileSync(fakeNode, "#!/bin/sh\necho \"fake node ran $1\"\n");
  chmodSync(fakeNode, 0o755);
  return home;
}

function runStart(home: string): string {
  return execFileSync("/bin/zsh", [startScript], {
    env: { HOME: home, PATH: "/usr/bin:/bin" },
    encoding: "utf8",
  });
}

describe.skipIf(realNodeOnFixedPath() || !existsSync("/bin/zsh"))("runner start.sh with nvm", () => {
  it("runs the runner with nvm's default node when the alias is an exact version", () => {
    const home = makeFakeHome("v22.18.0\n", "v22.18.0");
    expect(runStart(home)).toContain("fake node ran");
    expect(runStart(home)).toContain("runner/bin/runner.mjs");
  });

  it("takes the newest matching version when the alias is a prefix", () => {
    const home = makeFakeHome("22\n", "v22.9.0");
    expect(runStart(home)).toContain("fake node ran");
  });
});
