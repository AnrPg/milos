import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { describe, expect, it } from "vitest";

/**
 * Native controls guard (ADR-182): the browser draws the popup of a <select>
 * and of date and time inputs itself, off-theme and on phones partly off
 * screen. Screens use ui/Select, ui/DateInput, ui/TimeInput and
 * ui/DateTimeInput instead, which open in a themed ui/Popover.
 */

const SOURCE_ROOT = join(__dirname, "..", "..");
const SKIPPED_DIRECTORIES = new Set(["api/generated"]);

const RULES: { name: string; pattern: RegExp }[] = [
  { name: "native <select> (use ui/Select)", pattern: /<select[\s>]/g },
  {
    name: "native date or time input (use ui/DateInput, TimeInput or DateTimeInput)",
    pattern: /<input\b[^>]*\btype=["{]+"?(?:date|time|datetime-local|month|week)"/g,
  },
];

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    const relativePath = relative(SOURCE_ROOT, path);
    if (statSync(path).isDirectory()) return SKIPPED_DIRECTORIES.has(relativePath) ? [] : sourceFiles(path);
    if (!entry.endsWith(".tsx") || entry.includes(".test.")) return [];
    return [path];
  });
}

describe("native controls guard", () => {
  it("uses the themed pickers instead of native selects and date or time inputs", () => {
    const findings: string[] = [];
    for (const path of sourceFiles(SOURCE_ROOT)) {
      // Multi-line JSX: join each tag onto one line before matching.
      const source = readFileSync(path, "utf8").replace(/<(select|input)\b[^>]*>/g, (tag) => tag.replace(/\s*\n\s*/g, " "));
      const lines = source.split("\n");
      lines.forEach((line, index) => {
        if (/^\s*(\*|\/\/|\/\*)/.test(line)) return;
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
