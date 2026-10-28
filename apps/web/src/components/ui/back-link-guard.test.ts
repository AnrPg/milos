import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";

import { describe, expect, it } from "vitest";

/**
 * Back-link guard: ui/BackLink draws the one back arrow. A label that brings
 * its own («← Χρήστες») shows two, so no translation may start with a back
 * arrow and no screen may write one in front of its label.
 */

const SOURCE_ROOT = join(__dirname, "..", "..");
const MESSAGES = resolve(SOURCE_ROOT, "..", "messages");
const BACK_ARROW = /^\s*[←‹⬅◀◁]/;
const ALLOWED = new Set(["components/ui/BackLink.tsx"]);

function strings(node: unknown, path: string): [string, string][] {
  if (typeof node === "string") return [[path, node]];
  if (node && typeof node === "object") return Object.entries(node).flatMap(([key, value]) => strings(value, path ? `${path}.${key}` : key));
  return [];
}

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) return entry === "generated" ? [] : sourceFiles(path);
    return entry.endsWith(".tsx") && !entry.includes(".test.") ? [path] : [];
  });
}

describe("back-link guard", () => {
  it("keeps back arrows out of every translation", () => {
    const locales = readdirSync(MESSAGES).filter((file) => file.endsWith(".json"));
    expect(locales.length).toBeGreaterThanOrEqual(12);
    const findings = locales.flatMap((file) =>
      strings(JSON.parse(readFileSync(join(MESSAGES, file), "utf8")), "")
        .filter(([, text]) => BACK_ARROW.test(text))
        .map(([key, text]) => `${file} ${key}: ${text}`),
    );
    expect(findings).toEqual([]);
  });

  it("draws back links with ui/BackLink instead of an arrow in front of the label", () => {
    const findings: string[] = [];
    for (const path of sourceFiles(SOURCE_ROOT)) {
      const file = relative(SOURCE_ROOT, path);
      if (ALLOWED.has(file)) continue;
      readFileSync(path, "utf8").split("\n").forEach((line, index) => {
        if (/^\s*(\*|\/\/|\/\*)/.test(line)) return;
        if (/(^|>)\s*[←‹]\s*(\{|[\p{L}])/u.test(line)) findings.push(`${file}:${index + 1} ${line.trim().slice(0, 80)}`);
      });
    }
    expect(findings).toEqual([]);
  });
});
