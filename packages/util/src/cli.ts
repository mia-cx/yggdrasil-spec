#!/usr/bin/env node

import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { convertWikilinksInDirectory } from "./wiki2md/index.js";

const COMMANDS = {
  wiki2md: "Convert wikilinks to markdown links",
  help: "Show help",
} as const;

type Command = keyof typeof COMMANDS;

function printHelp(): void {
  console.log(`
@yggdrasil/util - Utility scripts for the Yggdrasil monorepo

Usage: ygg-util <command> [options]

Commands:
  wiki2md      Convert [[wikilinks]] to [markdown](links.md)
  help         Show this help message

Examples:
  ygg-util wiki2md ./apps/docs/content
  ygg-util wiki2md ./apps/docs/content --dry-run
  ygg-util wiki2md ./apps/docs/content --verbose
`);
}

function printWiki2mdHelp(): void {
  console.log(`
Usage: ygg-util wiki2md <directory> [options]

Convert Obsidian-style [[wikilinks]] to standard [markdown](links.md)

Arguments:
  directory    Directory to search for .md files

Options:
  --dry-run    Show what would be changed without writing
  --verbose    Show each file being processed
  --help       Show this help message

Examples:
  ygg-util wiki2md ./apps/docs/content
  ygg-util wiki2md ./apps/docs/content --dry-run --verbose
`);
}

async function runWiki2md(args: string[]): Promise<void> {
  const { values, positionals } = parseArgs({
    args,
    options: {
      "dry-run": { type: "boolean", default: false },
      verbose: { type: "boolean", short: "v", default: false },
      help: { type: "boolean", short: "h", default: false },
    },
    allowPositionals: true,
  });

  if (values.help) {
    printWiki2mdHelp();
    return;
  }

  const directory = positionals[0];
  if (!directory) {
    console.error("Error: directory argument is required\n");
    printWiki2mdHelp();
    process.exit(1);
  }

  const resolvedDir = resolve(process.cwd(), directory);
  const dryRun = values["dry-run"] ?? false;
  const verbose = values.verbose ?? false;

  console.log(`Converting wikilinks in: ${resolvedDir}`);
  if (dryRun) {
    console.log("(dry run - no files will be modified)\n");
  }

  const results = await convertWikilinksInDirectory({
    directory: resolvedDir,
    dryRun,
    verbose,
  });

  const totalLinks = results.reduce((sum, r) => sum + r.linksConverted, 0);
  const totalUnresolved = results.reduce(
    (sum, r) => sum + r.unresolvedLinks.length,
    0
  );
  const fileCount = results.length;

  if (fileCount === 0) {
    console.log("\nNo wikilinks found.");
  } else {
    console.log(
      `\n${dryRun ? "Would convert" : "Converted"} ${totalLinks} link(s) in ${fileCount} file(s).`
    );
    if (totalUnresolved > 0) {
      console.log(
        `Warning: ${totalUnresolved} link(s) could not be resolved (used fallback paths).`
      );
    }
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const command = args[0] as Command | undefined;

  if (!command || command === "help" || args.includes("--help")) {
    printHelp();
    return;
  }

  switch (command) {
    case "wiki2md":
      await runWiki2md(args.slice(1));
      break;
    default:
      console.error(`Unknown command: ${command}\n`);
      printHelp();
      process.exit(1);
  }
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
