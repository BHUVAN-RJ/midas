#!/usr/bin/env node
// The repair agent's intel command. Read-only, catalog only.
//   node intel.mjs list
//   node intel.mjs read <name> [--section "<heading text>"]
import { describeCatalog, readIntel } from "../lib/intel.mjs";

const commandArgs = process.argv.slice(2);
const command = commandArgs[0];

function printUsageAndExit() {
  console.error('usage: intel list | intel read <name> [--section "<heading>"]');
  process.exit(2);
}

if (command === "list") {
  console.log(describeCatalog());
  process.exit(0);
}

if (command !== "read" || commandArgs.length < 2) {
  printUsageAndExit();
}

const name = commandArgs[1];
let section = null;
const sectionFlagIndex = commandArgs.indexOf("--section");
if (sectionFlagIndex !== -1) {
  section = commandArgs[sectionFlagIndex + 1] ?? null;
  if (section === null) {
    printUsageAndExit();
  }
}

const result = readIntel({ name, section });
if (result.problem !== undefined) {
  console.error(result.problem);
  process.exit(1);
}
console.log(result.text);
