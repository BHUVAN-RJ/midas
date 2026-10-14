// The two commands the repair agent may run: check (deploy gate + Sidekick tests, always restoring
// the checkout) and intel (read-only, catalog only).
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { checkSidekick, gateProblems, runCopyTests, sandboxRootFor } from "../../runner/lib/check.mjs";
import { describeCatalog, intelCatalog, markdownSection, readIntel } from "../../runner/lib/intel.mjs";
import { makeScratch, remindersBundle } from "./helpers/runner-fixture";

function makeJobFolder(scratch: string, html: string, manifestText: string): string {
  const jobFolder = join(scratch, "job");
  mkdirSync(join(jobFolder, "sidekick"), { recursive: true });
  writeFileSync(join(jobFolder, "sidekick", "index.html"), html);
  writeFileSync(join(jobFolder, "sidekick", "manifest.json"), manifestText);
  return jobFolder;
}

describe("check", () => {
  it("the gate rejects forbidden primitives and a bad manifest with the deploy script's words", async () => {
    const { checkout } = makeScratch();
    const bundle = remindersBundle();
    const withImport = bundle.html.replace("<script>", "<script>import('x');");
    const problems = await gateProblems({ checkoutRoot: checkout, sidekickId: "reminders", html: withImport, manifestText: bundle.manifestText });
    expect(problems).toEqual(["deploy gate rejected: import"]);

    const wrongId = JSON.stringify({ ...JSON.parse(bundle.manifestText), id: "other" });
    const manifestProblems = await gateProblems({ checkoutRoot: checkout, sidekickId: "reminders", html: bundle.html, manifestText: wrongId });
    expect(manifestProblems).toEqual(['manifest.json: id must be "reminders"']);

    const clean = await gateProblems({ checkoutRoot: checkout, sidekickId: "reminders", html: bundle.html, manifestText: bundle.manifestText });
    expect(clean).toEqual([]);
  });

  it("runs the tests in a sandbox that holds the repaired page, leaves the checkout's page untouched and removes the sandbox, pass, fail or crash", async () => {
    const { scratch, checkout } = makeScratch();
    const bundle = remindersBundle();
    const repaired = bundle.html.replace("<title>Reminders</title>", "<title>Repaired</title>");
    const jobFolder = makeJobFolder(scratch, repaired, bundle.manifestText);
    const checkoutPagePath = join(checkout, "sidekicks", "reminders", "index.html");
    const sandboxRoot = sandboxRootFor(jobFolder);
    const seenDuringTests: string[] = [];
    const sandboxExistedDuringTests: boolean[] = [];

    const passing = await runCopyTests({
      checkoutRoot: checkout,
      sidekickId: "reminders",
      jobFolder,
      runTests: async ({ sandboxBackend }: { sandboxBackend: string }) => {
        // The tests read sidekicks/<id>/index.html relative to the backend folder they run in.
        seenDuringTests.push(readFileSync(join(sandboxBackend, "..", "sidekicks", "reminders", "index.html"), "utf8"));
        sandboxExistedDuringTests.push(existsSync(sandboxRoot));
        return { ok: true, output: "ok" };
      },
    });
    expect(passing.ok).toBe(true);
    expect(sandboxExistedDuringTests).toEqual([true]);
    expect(seenDuringTests[0]).toContain("<title>Repaired</title>");
    expect(readFileSync(checkoutPagePath, "utf8")).toBe(bundle.html);
    expect(existsSync(sandboxRoot)).toBe(false);

    const failing = await runCopyTests({
      checkoutRoot: checkout,
      sidekickId: "reminders",
      jobFolder,
      runTests: async () => ({ ok: false, output: "1 failed" }),
    });
    expect(failing.ok).toBe(false);
    expect(readFileSync(checkoutPagePath, "utf8")).toBe(bundle.html);
    expect(existsSync(sandboxRoot)).toBe(false);

    await expect(runCopyTests({
      checkoutRoot: checkout,
      sidekickId: "reminders",
      jobFolder,
      runTests: async () => {
        throw new Error("vitest crashed");
      },
    })).rejects.toThrow("vitest crashed");
    expect(readFileSync(checkoutPagePath, "utf8")).toBe(bundle.html);
    expect(existsSync(sandboxRoot)).toBe(false);
  });

  it("checkSidekick stops at the gate without running tests, and reports test failures", async () => {
    const { scratch, checkout } = makeScratch();
    const bundle = remindersBundle();
    const jobFolder = makeJobFolder(scratch, bundle.html.replace("<script>", '<script src="x.js"></script><script>'), bundle.manifestText);
    let testsRan = false;
    const gated = await checkSidekick({ checkoutRoot: checkout, sidekickId: "reminders", jobFolder, runTests: async () => { testsRan = true; return { ok: true, output: "" }; } });
    expect(gated.ok).toBe(false);
    expect(gated.problems[0]).toContain("script tag with attributes");
    expect(testsRan).toBe(false);

    const okFolder = makeJobFolder(join(scratch, "two"), bundle.html, bundle.manifestText);
    const failed = await checkSidekick({ checkoutRoot: checkout, sidekickId: "reminders", jobFolder: okFolder, runTests: async () => ({ ok: false, output: "expected 3 to be 4" }) });
    expect(failed.ok).toBe(false);
    expect(failed.problems).toEqual(["Sidekick tests failed"]);
    expect(failed.testOutput).toContain("expected 3 to be 4");
  });
});

describe("intel", () => {
  const scratch = mkdtempSync(join(tmpdir(), "intel-"));
  const docPath = join(scratch, "doc.md");
  writeFileSync(docPath, "# Title\n\nintro\n\n## 4. Using it\n\nfour\n\n### 4.1 Inner\n\ninner\n\n## 5. Next\n\nfive\n");
  const catalog = { doc: { path: docPath, about: "A test doc" }, missing: { path: join(scratch, "nope.md"), about: "Not here" } };

  it("refuses anything not in the catalog, including paths", () => {
    expect(readIntel({ name: "../../etc/passwd", catalog }).problem).toContain("unknown document");
    expect(readIntel({ name: docPath, catalog }).problem).toContain("unknown document");
    expect(readIntel({ name: "missing", catalog }).problem).toContain("not on this machine");
  });

  it("returns a whole document or one section up to the next heading of the same level", () => {
    expect(readIntel({ name: "doc", catalog }).text).toContain("five");
    const section = readIntel({ name: "doc", section: "4. Using", catalog }).text;
    expect(section).toContain("four");
    expect(section).toContain("inner");
    expect(section).not.toContain("five");
    expect(markdownSection("# A\n\n## B\n\nb\n\n## C\n\nc", "C")).toBe("## C\n\nc");
  });

  it("names the headings when a section is not found, and lists the catalog", () => {
    const result = readIntel({ name: "doc", section: "9. Nowhere", catalog });
    expect(result.problem).toContain("## 5. Next");
    const listing = describeCatalog(catalog);
    expect(listing).toContain("doc: A test doc");
    expect(listing).toContain("4. Using it");
    expect(listing).toContain("missing: Not here  (not on this machine)");
  });

  it("the real catalog points only at research, process and the two docs, by name", () => {
    const realCatalog = intelCatalog({ repoRoot: "/repo", intelRoot: "/intel" });
    const paths = Object.values(realCatalog).map((entry) => entry.path);
    for (const path of paths) {
      const inRepoDocs = path.startsWith("/repo/docs/");
      const inIntelResearchOrProcess = path.startsWith("/intel/docs/research/") || path.startsWith("/intel/docs/process/");
      expect(inRepoDocs || inIntelResearchOrProcess).toBe(true);
    }
    expect(Object.keys(realCatalog)).toContain("writing");
    expect(Object.keys(realCatalog)).toContain("reminders-analysis");
    expect(paths.some((path) => path.includes("midas-intel/CLAUDE.md") || path.includes("/intel/intel/"))).toBe(false);
  });
});
