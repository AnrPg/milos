import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { describe, expect, it } from "vitest";

import { APP_THEMES, cssVariablesForTheme } from "./theme";

/**
 * Every colour comes from the theme (src/lib/theme.ts → CSS variables).
 * This guard fails on any colour literal anywhere else in the web sources,
 * so no picker, scrollbar or badge drifts off-theme (docs/brand/THEME.md).
 */

const SOURCE_ROOT = join(__dirname, "..");
const THEME_SOURCE = "lib/theme.ts";
const SKIPPED_DIRECTORIES = new Set(["api/generated"]);
const CHECKED_EXTENSIONS = [".ts", ".tsx", ".css"];

const NAMED_COLOURS =
  "white|black|red|green|blue|yellow|orange|purple|pink|gray|grey|silver|maroon|navy|teal|olive|lime|aqua|fuchsia|gold|crimson";
const TAILWIND_PALETTE =
  "white|black|slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose";

const RULES: { name: string; pattern: RegExp }[] = [
  { name: "hex colour", pattern: /(?<![\w&])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![\w-])/g },
  { name: "rgb/hsl colour", pattern: /\b(?:rgba?|hsla?|hwb|lab|lch|oklch|oklab)\(\s*[\d.]/g },
  { name: "RGB channels", pattern: /\bset(?:Text|Fill|Draw)Color\(\s*\d|\bcolor:\s*\[\s*\d{1,3},/g },
  { name: "named colour", pattern: new RegExp(`(?:["'\`:]\\s*|\\s)(?:${NAMED_COLOURS})(?=["'\`;,)\\s])`, "g") },
  {
    name: "Tailwind palette class",
    pattern: new RegExp(
      `\\b(?:bg|text|border|from|to|via|ring|fill|stroke|shadow|outline|decoration|divide|caret|accent|placeholder)-(?:${TAILWIND_PALETTE})(?:-\\d{2,3})?(?:\\/\\d+)?\\b`,
      "g",
    ),
  },
];

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    const relativePath = relative(SOURCE_ROOT, path);
    if (statSync(path).isDirectory()) return SKIPPED_DIRECTORIES.has(relativePath) ? [] : sourceFiles(path);
    if (!CHECKED_EXTENSIONS.some((extension) => entry.endsWith(extension))) return [];
    if (entry.includes(".test.") || relativePath === THEME_SOURCE) return [];
    return [path];
  });
}

// Comments may name colours ("the green flash"); only code counts.
function withoutComments(source: string) {
  return source.replace(/\/\*[\s\S]*?\*\//g, (comment) => comment.replace(/[^\n]/g, "")).replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
}

// Words that only look like named colours: i18n keys, ids, enum values.
function isNamedColourFalsePositive(line: string, match: string) {
  const word = match.replace(/^["'`:\s]+/, "");
  return !new RegExp(`(?:color|background|fill|stroke|border|outline|shadow)[\\w-]*["']?\\s*[:=][^;]*\\b${word}\\b`, "i").test(line);
}

describe("theme guard", () => {
  it("finds no colour literal outside src/lib/theme.ts", () => {
    const offences: string[] = [];
    for (const file of sourceFiles(SOURCE_ROOT)) {
      const lines = withoutComments(readFileSync(file, "utf8")).split("\n");
      lines.forEach((line, index) => {
        for (const rule of RULES) {
          for (const match of line.matchAll(rule.pattern)) {
            if (rule.name === "named colour" && isNamedColourFalsePositive(line, match[0])) continue;
            offences.push(`${relative(SOURCE_ROOT, file)}:${index + 1} ${rule.name} ${match[0].trim()}`);
          }
        }
      });
    }
    expect(offences).toEqual([]);
  });

  it("uses only CSS variables the theme or a stylesheet defines", () => {
    const themeVariables = new Set(Object.keys(cssVariablesForTheme(APP_THEMES.frost)));
    const files = sourceFiles(SOURCE_ROOT).map((file) => ({ file, source: readFileSync(file, "utf8") }));
    const declared = new Set(files.flatMap(({ source }) => [...source.matchAll(/["']?(--[\w-]+)["']?\s*:/g)].map((match) => match[1]!)));
    const unknown: string[] = [];
    for (const { file, source } of files) {
      for (const match of source.matchAll(/var\((--[\w-]+[\w])(?=[,)])/g)) {
        const name = match[1]!;
        if (!themeVariables.has(name) && !declared.has(name)) unknown.push(`${relative(SOURCE_ROOT, file)} ${name}`);
      }
    }
    expect(unknown).toEqual([]);
  });
});
