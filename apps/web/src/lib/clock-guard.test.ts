import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import ts from "typescript";
import { describe, expect, it } from "vitest";

/**
 * Clock guard (product owner, 2026-10-29): Greek is always shown on the
 * 24-hour clock. Intl's Greek data defaults to «π.μ./μ.μ.», so every options
 * object that shows hours (`hour` or `timeStyle`) must go through the clock
 * helper in lib/clock (`withClock`, `clockFormat`, `formatClock`) or a helper
 * that applies it (`formatInZone`, `zonedText`, `readZoned`), and
 * `toLocaleTimeString` is not used at all.
 *
 * An options object that sets `hourCycle` itself (a machine-readable value
 * such as an <input> value) is deliberate and allowed.
 */

const SOURCE_ROOT = join(__dirname, "..");
const SKIPPED_DIRECTORIES = new Set(["api/generated"]);

/** Calls that apply the locale's clock to the options passed to them. */
const CLOCK_AWARE_CALLS = new Set(["withClock", "clockFormat", "formatClock", "formatInZone", "zonedText", "readZoned"]);

/** Files whose hour options are resolved through `withClock` later, with the reason. */
const ALLOWED_FILES: Record<string, string> = {
  "lib/clock.ts": "the helper itself",
  "lib/zoned-time.ts": "named presets, applied through withClock in formatInZone",
};

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    const relativePath = relative(SOURCE_ROOT, path);
    if (statSync(path).isDirectory()) return SKIPPED_DIRECTORIES.has(relativePath) ? [] : sourceFiles(path);
    if (!/\.tsx?$/.test(entry) || entry.includes(".test.") || entry.endsWith(".d.ts")) return [];
    return [path];
  });
}

function propertyName(property: ts.ObjectLiteralElementLike): string | null {
  if (!ts.isPropertyAssignment(property) && !ts.isShorthandPropertyAssignment(property)) return null;
  const name = property.name;
  return ts.isIdentifier(name) || ts.isStringLiteral(name) ? name.text : null;
}

function calleeName(call: ts.CallExpression | ts.NewExpression): string | null {
  const callee = call.expression;
  if (ts.isIdentifier(callee)) return callee.text;
  if (ts.isPropertyAccessExpression(callee)) return callee.name.text;
  return null;
}

/** The call this options object is an argument of, through spreads, conditionals and casts. */
function enclosingCall(node: ts.Node): ts.CallExpression | ts.NewExpression | null {
  let current: ts.Node = node;
  for (;;) {
    const parent: ts.Node | undefined = current.parent;
    if (!parent) return null;
    if ((ts.isCallExpression(parent) || ts.isNewExpression(parent)) && parent.arguments?.includes(current as ts.Expression)) {
      return parent;
    }
    if (
      ts.isParenthesizedExpression(parent) ||
      ts.isAsExpression(parent) ||
      ts.isSatisfiesExpression(parent) ||
      ts.isConditionalExpression(parent) ||
      ts.isBinaryExpression(parent) ||
      ts.isSpreadAssignment(parent) ||
      ts.isObjectLiteralExpression(parent)
    ) {
      current = parent;
      continue;
    }
    return null;
  }
}

function findings(path: string): string[] {
  const relativePath = relative(SOURCE_ROOT, path);
  const source = readFileSync(path, "utf8");
  if (!/\bhour\b|timeStyle|toLocaleTimeString/.test(source)) return [];
  const file = ts.createSourceFile(path, source, ts.ScriptTarget.Latest, true, path.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
  const found: string[] = [];
  const where = (node: ts.Node) => `${relativePath}:${file.getLineAndCharacterOfPosition(node.getStart()).line + 1}`;

  const visit = (node: ts.Node) => {
    if (ts.isPropertyAccessExpression(node) && node.name.text === "toLocaleTimeString") {
      found.push(`${where(node)} toLocaleTimeString (use formatClock from lib/clock)`);
    }
    if (ts.isObjectLiteralExpression(node) && !(relativePath in ALLOWED_FILES)) {
      const names = node.properties.map(propertyName);
      const showsHours = node.properties.some(
        (property) =>
          ts.isPropertyAssignment(property) &&
          ["hour", "timeStyle"].includes(propertyName(property) ?? "") &&
          (ts.isStringLiteral(property.initializer) || ts.isNoSubstitutionTemplateLiteral(property.initializer)),
      );
      if (showsHours && !names.includes("hourCycle")) {
        const call = enclosingCall(node);
        const name = call ? calleeName(call) : null;
        if (!name || !CLOCK_AWARE_CALLS.has(name)) {
          found.push(`${where(node)} hours formatted without the clock helper (wrap the options in withClock(locale, …))`);
        }
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(file);
  return found;
}

describe("clock guard", () => {
  it("formats every hour through the clock helper, so Greek stays on the 24-hour clock", () => {
    expect(sourceFiles(SOURCE_ROOT).flatMap(findings)).toEqual([]);
  }, 60_000);
});
