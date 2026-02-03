import { readFile, writeFile } from "node:fs/promises";
import { dirname, relative, basename, posix } from "node:path";
import { glob } from "glob";

/**
 * Wikilink pattern matches:
 * - [[target]] -> simple link
 * - [[target|display]] -> link with display text (Obsidian style)
 */
const WIKILINK_PATTERN = /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g;

interface WikilinkMatch {
  full: string;
  target: string;
  display: string | undefined;
  index: number;
}

interface ConversionResult {
  file: string;
  linksConverted: number;
  unresolvedLinks: string[];
  dryRun: boolean;
}

interface ConvertOptions {
  /** Directory to search for markdown files */
  directory: string;
  /** Dry run - don't write changes */
  dryRun?: boolean;
  /** Verbose output */
  verbose?: boolean;
}

/** Map of basename (without .md) -> absolute file path(s) */
type FileIndex = Map<string, string[]>;

/**
 * Build an index of all markdown files by their basename
 */
export async function buildFileIndex(directory: string): Promise<FileIndex> {
  const files = await glob("**/*.md", {
    cwd: directory,
    absolute: true,
    nodir: true,
  });

  const index: FileIndex = new Map();

  for (const file of files) {
    // Get basename without .md extension
    const name = basename(file, ".md").toLowerCase();

    const existing = index.get(name) ?? [];
    existing.push(file);
    index.set(name, existing);
  }

  return index;
}

/**
 * Find all wikilinks in a string
 */
export function findWikilinks(content: string): WikilinkMatch[] {
  const matches: WikilinkMatch[] = [];
  let match: RegExpExecArray | null;

  // Reset regex state
  WIKILINK_PATTERN.lastIndex = 0;

  while ((match = WIKILINK_PATTERN.exec(content)) !== null) {
    matches.push({
      full: match[0],
      target: match[1].trim(),
      display: match[2]?.trim(),
      index: match.index,
    });
  }

  return matches;
}

/**
 * Resolve a wikilink target to an actual file path
 * Returns the relative path from sourceFile to the target, or null if not found
 *
 * Special cases:
 * - [[#heading]] -> #heading (anchor in same page)
 * - [[page#heading]] -> ./page.md#heading (anchor in another page)
 */
export function resolveWikilink(
  target: string,
  sourceFile: string,
  fileIndex: FileIndex,
  baseDirectory: string
): { path: string; isAnchor: boolean } | null {
  // Handle anchor-only links [[#heading]]
  if (target.startsWith("#")) {
    const anchor = target.toLowerCase().replace(/\s+/g, "-");
    return { path: anchor, isAnchor: true };
  }

  // Handle page#heading links
  let anchor = "";
  let pageName = target;
  if (target.includes("#")) {
    const [page, heading] = target.split("#", 2);
    pageName = page;
    anchor = "#" + heading.toLowerCase().replace(/\s+/g, "-");
  }

  // Normalize target - remove .md if present, lowercase for matching
  const normalizedTarget = pageName
    .replace(/\.md$/i, "")
    .toLowerCase()
    .split("/")
    .pop()!; // Handle paths like "folder/page" - just use the filename

  const matches = fileIndex.get(normalizedTarget);

  if (!matches || matches.length === 0) {
    return null;
  }

  // If multiple matches, prefer one in same directory, then shortest path
  let targetFile: string;

  if (matches.length === 1) {
    targetFile = matches[0];
  } else {
    const sourceDir = dirname(sourceFile);

    // First, try to find one in the same directory
    const sameDir = matches.find((f) => dirname(f) === sourceDir);
    if (sameDir) {
      targetFile = sameDir;
    } else {
      // Otherwise, pick the one with shortest relative path
      targetFile = matches.reduce((closest, current) => {
        const closestRel = relative(sourceDir, closest);
        const currentRel = relative(sourceDir, current);
        return currentRel.length < closestRel.length ? current : closest;
      });
    }
  }

  // Compute relative path from source to target
  const sourceDir = dirname(sourceFile);
  let relativePath = relative(sourceDir, targetFile);

  // Use forward slashes for consistency (works on all platforms in URLs/markdown)
  relativePath = relativePath.split("\\").join("/");

  // If the file is in the same directory, ensure it starts with ./
  if (!relativePath.startsWith(".") && !relativePath.startsWith("/")) {
    relativePath = "./" + relativePath;
  }

  return { path: relativePath + anchor, isAnchor: false };
}

/**
 * Convert a wikilink to a markdown link with resolved path
 */
export function wikiLinkToMarkdown(
  target: string,
  display: string | undefined,
  resolved: { path: string; isAnchor: boolean } | null
): string {
  // For anchor-only links, use the heading text (without #) as display if not provided
  const linkText =
    display ?? (target.startsWith("#") ? target.slice(1) : target);

  if (resolved === null) {
    // Fallback: keep original target with .md appended (unresolved)
    const fallbackTarget = target.endsWith(".md") ? target : `${target}.md`;
    return `[${linkText}](${fallbackTarget})`;
  }

  return `[${linkText}](${resolved.path})`;
}

/**
 * Convert all wikilinks in content to markdown links with resolved paths
 */
export function convertWikilinksInContent(
  content: string,
  sourceFile: string,
  fileIndex: FileIndex,
  baseDirectory: string
): {
  content: string;
  count: number;
  unresolved: string[];
} {
  let count = 0;
  const unresolved: string[] = [];

  const converted = content.replace(
    WIKILINK_PATTERN,
    (_match, target: string, display: string | undefined) => {
      count++;
      const trimmedTarget = target.trim();
      const resolved = resolveWikilink(
        trimmedTarget,
        sourceFile,
        fileIndex,
        baseDirectory
      );

      if (resolved === null) {
        unresolved.push(trimmedTarget);
      }

      return wikiLinkToMarkdown(trimmedTarget, display?.trim(), resolved);
    }
  );

  return { content: converted, count, unresolved };
}

/**
 * Convert wikilinks to markdown links in all markdown files in a directory
 */
export async function convertWikilinksInDirectory(
  options: ConvertOptions
): Promise<ConversionResult[]> {
  const { directory, dryRun = false, verbose = false } = options;

  // Build index of all markdown files
  const fileIndex = await buildFileIndex(directory);

  if (verbose) {
    console.log(`Indexed ${fileIndex.size} unique file(s)\n`);

    // Warn about duplicates
    for (const [name, paths] of fileIndex) {
      if (paths.length > 1) {
        console.log(`  Warning: Multiple files named "${name}.md":`);
        for (const p of paths) {
          console.log(`    - ${relative(directory, p)}`);
        }
      }
    }
  }

  const files = await glob("**/*.md", {
    cwd: directory,
    absolute: true,
    nodir: true,
  });

  const results: ConversionResult[] = [];

  for (const file of files) {
    const content = await readFile(file, "utf-8");
    const {
      content: converted,
      count,
      unresolved,
    } = convertWikilinksInContent(content, file, fileIndex, directory);

    if (count > 0) {
      if (verbose) {
        const relPath = relative(directory, file);
        console.log(`  ${relPath}: ${count} link(s)`);
        if (unresolved.length > 0) {
          console.log(`    Unresolved: ${unresolved.join(", ")}`);
        }
      }

      if (!dryRun) {
        await writeFile(file, converted, "utf-8");
      }

      results.push({
        file,
        linksConverted: count,
        unresolvedLinks: unresolved,
        dryRun,
      });
    }
  }

  return results;
}
