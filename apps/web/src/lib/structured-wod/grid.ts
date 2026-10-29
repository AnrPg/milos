/**
 * ADR-270: ↑ and ↓ move between the rows of the structured editor the way
 * they do in a spreadsheet: same column in the row above or below, across
 * section boundaries (a section's own row counts as a row). A row without
 * that column gets the nearest one by position, so the caret never jumps to
 * the far side of the screen.
 */

export type GridRow = { key: string; cols: string[] };
export type GridCell = { rowKey: string; col: string };

export function neighbourCell(rows: GridRow[], from: GridCell, delta: -1 | 1): GridCell | null {
  const index = rows.findIndex((row) => row.key === from.rowKey);
  if (index === -1) return null;
  const target = rows[index + delta];
  if (!target || target.cols.length === 0) return null;
  if (target.cols.includes(from.col)) return { rowKey: target.key, col: from.col };

  const position = Math.max(0, rows[index].cols.indexOf(from.col));
  const ratio = rows[index].cols.length > 1 ? position / (rows[index].cols.length - 1) : 0;
  const nearest = Math.round(ratio * (target.cols.length - 1));
  return { rowKey: target.key, col: target.cols[nearest] };
}

const CELL_SELECTOR = "[data-sw-cell]";

export function cellAttributes(rowKey: string, col: string) {
  return { "data-sw-cell": `${rowKey}::${col}` };
}

export function readCell(element: Element | null): GridCell | null {
  const cell = element?.closest<HTMLElement>(CELL_SELECTOR);
  const value = cell?.dataset.swCell;
  if (!value) return null;
  const [rowKey, col] = value.split("::");
  return rowKey && col ? { rowKey, col } : null;
}

/** The editor's rows in screen order, read from the cells it rendered. */
export function readRows(root: HTMLElement): GridRow[] {
  const rows: GridRow[] = [];
  for (const element of root.querySelectorAll<HTMLElement>(CELL_SELECTOR)) {
    const cell = readCell(element);
    if (!cell) continue;
    const last = rows[rows.length - 1];
    if (last?.key === cell.rowKey) last.cols.push(cell.col);
    else rows.push({ key: cell.rowKey, cols: [cell.col] });
  }
  return rows;
}

export function focusCell(root: HTMLElement, cell: GridCell): boolean {
  const element = root.querySelector<HTMLElement>(`[data-sw-cell="${CSS.escape(`${cell.rowKey}::${cell.col}`)}"]`);
  if (!element) return false;
  element.focus();
  if (element instanceof HTMLInputElement && element.type === "text") element.select();
  return true;
}

export type RowRef =
  | { kind: "workout" }
  | { kind: "section"; sectionId: string }
  | { kind: "exercise"; sectionId: string; exerciseId: string };

export function rowKey(ref: RowRef): string {
  if (ref.kind === "workout") return "w";
  if (ref.kind === "section") return `s:${ref.sectionId}`;
  return `e:${ref.sectionId}:${ref.exerciseId}`;
}

export function parseRowKey(key: string): RowRef | null {
  if (key === "w") return { kind: "workout" };
  const [kind, sectionId, exerciseId] = key.split(":");
  if (kind === "s" && sectionId) return { kind: "section", sectionId };
  if (kind === "e" && sectionId && exerciseId) return { kind: "exercise", sectionId, exerciseId };
  return null;
}
