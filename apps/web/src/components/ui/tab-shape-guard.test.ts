import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

/**
 * Tab shape guard (ANR 2026-10-24/25): the selected tab of every tab bar is a
 * Spark pill. globals.css gives every tab a rounded shape and inline padding
 * in the components layer (so a bar's own rounded-* / px-* utilities win), and
 * the Spark rule only paints colours: it never squares the corners or strips
 * the padding.
 */

const css = readFileSync(join(__dirname, "..", "..", "app", "globals.css"), "utf8");

function block(selectorStart: string): string {
  const start = css.indexOf(selectorStart);
  expect(start, `${selectorStart} rule in globals.css`).toBeGreaterThanOrEqual(0);
  return css.slice(start, css.indexOf("}", css.indexOf("{", start)) + 1);
}

describe("tab shape guard", () => {
  it("gives every tab a rounded, padded default shape in the components layer", () => {
    const layer = block("@layer components {\n  [role=\"tab\"],");
    expect(layer).toContain("[data-tabs] a");
    expect(layer).toMatch(/border-radius:\s*0\.875rem/);
    expect(layer).toMatch(/padding-inline:\s*0\.875rem/);
    expect(layer).not.toContain("!important");
  });

  it("paints the selected tab with theme tokens only and leaves its shape alone", () => {
    const selected = block('[role="tab"][aria-selected="true"],');
    expect(selected).toContain("var(--spark)");
    expect(selected).toContain("var(--spark-contrast)");
    expect(selected).not.toMatch(/border-radius|padding/);
    expect(selected).not.toMatch(/#[0-9a-f]{3,8}\b|rgb\(/i);
  });
});
