import type { TaxonomyTree } from "./taxonomy";

/**
 * Reads the `@tree` and `@version` literals of the API's
 * `Palee.Anatomy.Domain.MuscleTaxonomy` module. The tree is a nested
 * literal of strings, lists and tuples, so swapping tuple braces for list
 * brackets turns it into JSON. Used by the test that keeps `taxonomy.ts` in
 * step with the API (the source of truth).
 */
export function parseElixirTaxonomy(source: string): { version: number; tree: TaxonomyTree } {
  const version = Number(/@version\s+(\d+)/.exec(source)?.[1]);
  const start = source.indexOf("@tree [");
  if (start < 0 || !Number.isFinite(version)) throw new Error("no @tree / @version in the taxonomy module");

  let depth = 0;
  let end = -1;
  const open = source.indexOf("[", start);
  for (let i = open; i < source.length; i += 1) {
    const char = source[i];
    if (char === '"') {
      i = source.indexOf('"', i + 1);
      continue;
    }
    if (char === "#") {
      i = source.indexOf("\n", i);
      continue;
    }
    if (char === "[" || char === "{") depth += 1;
    if (char === "]" || char === "}") depth -= 1;
    if (depth === 0) {
      end = i;
      break;
    }
  }
  if (end < 0) throw new Error("unterminated @tree literal");

  const literal = source
    .slice(open, end + 1)
    .replace(/#[^\n"]*$/gm, "")
    .replace(/\{/g, "[")
    .replace(/\}/g, "]");
  return { version, tree: JSON.parse(literal) as TaxonomyTree };
}
