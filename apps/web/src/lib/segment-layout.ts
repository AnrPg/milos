// How a set of segment options (user types, list tabs, sources…) is laid out
// so that it never scrolls sideways: one row when every option fits, a grid
// only when the options fill it exactly (4 → 2×2, 6 → 2×3 or 3×2, never
// three chips in a 2×2), otherwise a dropdown.

export type SegmentLayout =
  | { kind: "row" }
  | { kind: "grid"; columns: number; rows: number }
  | { kind: "select" };

/** More rows than this reads as a list, not a segment control: a dropdown is clearer. */
export const MAX_SEGMENT_ROWS = 3;

/**
 * How many equal columns of `chipWidth` fit in `containerWidth` with `gap`
 * between them. Every column is as wide as the widest chip, so a fitting grid
 * never truncates a label.
 */
export function fittingColumns(containerWidth: number, chipWidth: number, gap: number) {
  if (containerWidth <= 0 || chipWidth <= 0) return 0;
  return Math.max(0, Math.floor((containerWidth + gap) / (chipWidth + gap)));
}

/**
 * Whether chips of these natural `widths` fit on one line of `containerWidth`.
 * With `equalShares` every chip gets the same share of the line, so the line
 * fits only when the widest chip fits that share too, otherwise a label would
 * be cut with an ellipsis (ANR 2026-10-25, Μηνύματα «Partn…»). A stretched row
 * that fits only at natural widths keeps them and shares the rest instead.
 */
export function rowFits(widths: readonly number[], containerWidth: number, gap: number, equalShares = false) {
  if (widths.length === 0) return true;
  const gaps = gap * Math.max(0, widths.length - 1);
  const natural = widths.reduce((sum, width) => sum + width, 0) + gaps;
  const widest = Math.max(...widths);
  return natural <= containerWidth && (!equalShares || widest * widths.length + gaps <= containerWidth);
}

/**
 * `rowFits`: the chips at their natural widths fit on one line. `columns`:
 * how many equal columns fit (see `fittingColumns`).
 */
export function chooseSegmentLayout({
  count,
  rowFits,
  columns,
  maxRows = MAX_SEGMENT_ROWS,
}: {
  count: number;
  rowFits: boolean;
  columns: number;
  maxRows?: number;
}): SegmentLayout {
  if (count <= 1 || rowFits) return { kind: "row" };
  // Widest full grid first: fewer rows keep the control short.
  for (let cols = Math.min(columns, count - 1); cols >= 2; cols -= 1) {
    if (count % cols !== 0) continue;
    const rows = count / cols;
    if (rows <= maxRows) return { kind: "grid", columns: cols, rows };
  }
  return { kind: "select" };
}

/**
 * A chip row that must never scroll sideways (Γύρω μου): `null` when the chips
 * fit on one line at their natural widths, otherwise where the second of two
 * order-keeping lines starts, chosen so the wider line is as narrow as
 * possible (balanced lines).
 */
export function balancedLineBreak(widths: readonly number[], containerWidth: number, gap: number): number | null {
  const lineWidth = (from: number, to: number) =>
    widths.slice(from, to).reduce((sum, width) => sum + width, 0) + gap * Math.max(0, to - from - 1);
  if (widths.length <= 1 || containerWidth <= 0 || lineWidth(0, widths.length) <= containerWidth) return null;
  let best = Math.ceil(widths.length / 2);
  let bestWidth = Infinity;
  for (let split = 1; split < widths.length; split += 1) {
    const wider = Math.max(lineWidth(0, split), lineWidth(split, widths.length));
    // Ties go to the fuller first line, like reading order.
    if (wider < bestWidth || (wider === bestWidth && split > best)) {
      best = split;
      bestWidth = wider;
    }
  }
  return best;
}
