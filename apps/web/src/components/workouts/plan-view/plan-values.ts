import type { PlanCell, PlanRow } from "@/lib/structured-plan";

/** How many columns of a row the coach actually wrote (trailing empty cells inherit). */
export function writtenColumns(row: PlanRow): number {
  const filled = (cell: PlanCell | undefined) => Boolean(cell && Object.values(cell).some((value) => String(value ?? "").trim()));
  return row.cells.reduce((last, cell, index) => (filled(cell) ? index + 1 : last), 0);
}
