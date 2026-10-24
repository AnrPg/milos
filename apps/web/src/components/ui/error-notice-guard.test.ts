import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { describe, expect, it } from "vitest";

/**
 * Error notice guard (ADR-195): errors shown to the person render through
 * ui/ErrorNotice, so every one is the same red, prominent notice. A
 * hand-made role="alert" element is only allowed for warnings (amber, a
 * --warning style on the same tag); anything else is an error built by hand.
 */

const SOURCE_ROOT = join(__dirname, "..", "..");
const SKIPPED_DIRECTORIES = new Set(["api/generated"]);
const ERROR_NOTICE = join("components", "ui", "ErrorNotice.tsx");

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    const relativePath = relative(SOURCE_ROOT, path);
    if (statSync(path).isDirectory()) return SKIPPED_DIRECTORIES.has(relativePath) ? [] : sourceFiles(path);
    if (!entry.endsWith(".tsx") || entry.includes(".test.") || relativePath === ERROR_NOTICE) return [];
    return [path];
  });
}

describe("error notice guard", () => {
  it("renders errors through ui/ErrorNotice instead of hand-made alerts", () => {
    const findings: string[] = [];
    for (const path of sourceFiles(SOURCE_ROOT)) {
      const source = readFileSync(path, "utf8");
      // An opening tag carrying role="alert", across lines.
      for (const match of source.matchAll(/<[a-zA-Z][\w.]*\b[^<>]*?role=["{]+"?alert"[^<>]*?>/g)) {
        if (match[0].includes("var(--warning)")) continue;
        const line = source.slice(0, match.index).split("\n").length;
        findings.push(`${relative(SOURCE_ROOT, path)}:${line} ${match[0].replace(/\s+/g, " ").slice(0, 80)}`);
      }
    }
    expect(findings).toEqual([]);
  });
});
