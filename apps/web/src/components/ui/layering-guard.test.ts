import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { describe, expect, it } from "vitest";

/**
 * Layering guard (ADR-177): every fixed or floating layer takes its z-index
 * from the scale in globals.css (--z-nav, --z-drawer, --z-modal,
 * --z-fullscreen, --z-popover, --z-toast), and dialogs use the shared
 * ui/Dialog shell. A literal z-index (z-[70], z-50, zIndex: 9999) is how a
 * menu ends up behind a card or a sheet behind the nav, so it fails here.
 * z-0 and z-10 stay allowed for stacking inside one component.
 */

const SOURCE_ROOT = join(__dirname, "..", "..");
const SKIPPED_DIRECTORIES = new Set(["api/generated"]);

const RULES: { name: string; pattern: RegExp }[] = [
  { name: "arbitrary z-index class", pattern: /\bz-\[\d+\]/g },
  { name: "high Tailwind z-index class", pattern: /(?<![\w-])z-(?:20|30|40|50)\b/g },
  { name: "numeric zIndex above 10", pattern: /\bzIndex:\s*(?:1[1-9]|[2-9]\d|\d{3,})\b/g },
  { name: "fixed layer without a scale token", pattern: /className=[^\n]*\bfixed\b[^\n]*\binset(?:-[xy])?-0\b(?![^\n]*z-\(--z-)/g },
];

const ALLOWED_FILES = new Set(["components/ui/Dialog.tsx"]);

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    const relativePath = relative(SOURCE_ROOT, path);
    if (statSync(path).isDirectory()) return SKIPPED_DIRECTORIES.has(relativePath) ? [] : sourceFiles(path);
    if (!entry.endsWith(".tsx") && !entry.endsWith(".ts")) return [];
    if (entry.includes(".test.") || ALLOWED_FILES.has(relativePath)) return [];
    return [path];
  });
}

describe("layering guard", () => {
  it("uses the z-index scale tokens for every fixed or floating layer", () => {
    const findings: string[] = [];
    for (const path of sourceFiles(SOURCE_ROOT)) {
      const lines = readFileSync(path, "utf8").split("\n");
      lines.forEach((line, index) => {
        for (const rule of RULES) {
          for (const match of line.matchAll(rule.pattern)) {
            findings.push(`${relative(SOURCE_ROOT, path)}:${index + 1} ${rule.name}: ${match[0].slice(0, 60)}`);
          }
        }
      });
    }
    expect(findings).toEqual([]);
  });
});
