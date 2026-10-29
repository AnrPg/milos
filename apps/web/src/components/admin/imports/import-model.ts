import type {
  ImportField,
  ImportMappingEntry,
  ImportRow,
  PeopleImport,
} from "@/api/imports";

// ADR-254, mockup s9 option B: the file is read and dry-run at once; the
// owner answers only what needs a person (usually 2–3 cards), and the full
// column mapping stays one expand away.

export type ImportPhase = "review" | "applying" | "done" | "undone";

export function phaseOf(entry: Pick<PeopleImport, "status">): ImportPhase {
  switch (entry.status) {
    case "queued":
    case "applying":
      return "applying";
    case "applied":
    case "failed":
      return "done";
    case "undone":
      return "undone";
    default:
      return "review";
  }
}

export const PACKAGE_FIELDS: ImportField[] = ["package_name", "package_price", "package_starts_on", "package_ends_on"];

/** Mapping entries with a field, one per column, sorted by column. */
export function mappedEntries(mapping: ImportMappingEntry[]): ImportMappingEntry[] {
  return mapping.filter((entry) => entry.field).sort((a, b) => a.column - b.column);
}

export function fieldOfColumn(mapping: ImportMappingEntry[], column: number): ImportField | null {
  return mapping.find((entry) => entry.column === column)?.field ?? null;
}

export function columnOfField(mapping: ImportMappingEntry[], field: ImportField): number | null {
  return mapping.find((entry) => entry.field === field)?.column ?? null;
}

/**
 * Maps `column` to `field` (null = the column stays out). A field fills one
 * column at most, so another column holding it is freed.
 */
export function setColumnField(
  mapping: ImportMappingEntry[],
  column: number,
  field: ImportField | null,
): ImportMappingEntry[] {
  const rest = mapping.filter((entry) => entry.column !== column && (field === null || entry.field !== field));
  return mappedEntries(field ? [...rest, { column, field }] : rest);
}

/** The KPIs of a dry run: new box members, people joined with existing ones, subscription packages. */
export function previewKpis(entry: Pick<PeopleImport, "preview">) {
  const outcomes = entry.preview?.outcomes ?? {};
  const actions = entry.preview?.actions ?? {};
  return {
    created: outcomes.create_person ?? 0,
    matched: outcomes.update_person ?? 0,
    packages: actions.assign_package ?? 0,
    newPackages: actions.create_package ?? 0,
    skipped: (outcomes.invalid ?? 0) + (outcomes.duplicate_row ?? 0) + (outcomes.already_imported ?? 0),
  };
}

/** How many people applying would bring in (new and joined). */
export function peopleToImport(entry: Pick<PeopleImport, "preview">) {
  const kpis = previewKpis(entry);
  return kpis.created + kpis.matched;
}

const PROBLEM_WARNINGS = new Set(["invalid_email", "invalid_phone", "invalid_date", "invalid_amount", "invalid_role", "invalid_status"]);

/** A row with a wrong value (it goes in without it) or without a person (it is skipped). */
export function isProblemRow(row: Pick<ImportRow, "outcome" | "warnings" | "errors">) {
  return row.outcome === "invalid" || row.errors.length > 0 || row.warnings.some((warning) => PROBLEM_WARNINGS.has(warning.code));
}

export type Decision =
  | { kind: "packages"; names: string[]; members: number; count: number }
  | { kind: "rows"; rows: number[]; count: number }
  | { kind: "column"; column: number; header: string; sample: string | null; notesFree: boolean }
  | { kind: "columns"; columns: Array<{ column: number; header: string }> };

export type DecisionKey = "packages" | "rows" | `column-${number}` | "columns";

export function decisionKey(decision: Decision): DecisionKey {
  return decision.kind === "column" ? `column-${decision.column}` : decision.kind;
}

const fold = (value: string) => value.trim().toLocaleLowerCase();

/**
 * The cards that need the owner, worked out once from the first dry run and
 * a sample of rows: subscription packages that do not exist here, rows with a
 * wrong value, and columns with no place. Answering a card never changes
 * which cards there are, so an answer can be taken back.
 */
export function deriveDecisions(entry: PeopleImport, sample: ImportRow[]): Decision[] {
  const decisions: Decision[] = [];
  const kpis = previewKpis(entry);

  const packageColumn = columnOfField(entry.mapping, "package_name");
  if (kpis.newPackages > 0 && packageColumn !== null) {
    const names: string[] = [];
    for (const row of sample) {
      if (!row.warnings.some((warning) => warning.code === "package_created")) continue;
      const name = row.cells[packageColumn]?.trim();
      if (name && !names.some((known) => fold(known) === fold(name))) names.push(name);
    }
    const members = sample.filter((row) => {
      const cell = row.cells[packageColumn];
      return cell !== undefined && names.some((name) => fold(name) === fold(cell));
    }).length;
    decisions.push({ kind: "packages", names, members, count: kpis.newPackages });
  }

  const problemRows = sample.filter(isProblemRow).map((row) => row.row_number);
  const complete = sample.length >= entry.row_count;
  const problemCount = complete
    ? problemRows.length
    : Math.max(
        problemRows.length,
        (entry.preview?.outcomes?.invalid ?? 0) +
          Object.entries(entry.preview?.warnings ?? {})
            .filter(([code]) => PROBLEM_WARNINGS.has(code))
            .reduce((sum, [, count]) => sum + count, 0),
      );
  if (problemCount > 0) decisions.push({ kind: "rows", rows: problemRows, count: problemCount });

  const unmapped = entry.header
    .map((header, column) => ({ column, header }))
    .filter(({ column }) => fieldOfColumn(entry.mapping, column) === null)
    .filter(({ column }) => sample.length === 0 || sample.some((row) => (row.cells[column] ?? "").trim() !== ""));
  if (unmapped.length === 1) {
    const { column, header } = unmapped[0]!;
    const sampleCell = sample.map((row) => row.cells[column]?.trim()).find((cell) => cell);
    decisions.push({
      kind: "column",
      column,
      header,
      sample: sampleCell ?? null,
      notesFree: columnOfField(entry.mapping, "notes") === null,
    });
  } else if (unmapped.length > 1) {
    decisions.push({ kind: "columns", columns: unmapped });
  }

  return decisions;
}

export type Answers = Partial<Record<DecisionKey, string>>;

/**
 * The mapping after answering a card. `original` is the mapping the file
 * came with, so «Νέο πακέτο» after «Να μη μπουν» puts the package columns back.
 */
export function applyAnswer(
  mapping: ImportMappingEntry[],
  original: ImportMappingEntry[],
  decision: Decision,
  answer: string,
): ImportMappingEntry[] {
  if (decision.kind === "packages") {
    const rest = mapping.filter((entry) => !PACKAGE_FIELDS.includes(entry.field as ImportField));
    if (answer === "skip") return mappedEntries(rest);
    const restored = original.filter(
      (entry) =>
        PACKAGE_FIELDS.includes(entry.field as ImportField) && !rest.some((other) => other.column === entry.column),
    );
    return mappedEntries([...rest, ...restored]);
  }
  if (decision.kind === "column") {
    return setColumnField(mapping, decision.column, answer === "notes" ? "notes" : null);
  }
  return mapping;
}

export function sameMapping(a: ImportMappingEntry[], b: ImportMappingEntry[]) {
  const key = (mapping: ImportMappingEntry[]) =>
    mappedEntries(mapping)
      .map((entry) => `${entry.column}:${entry.field}`)
      .join("|");
  return key(a) === key(b);
}

/** Rows applied, skipped or failed so far, out of all rows (0–100). */
export function applyProgress(entry: Pick<PeopleImport, "row_count" | "counts">) {
  const statuses = entry.counts?.statuses ?? {};
  const done = (statuses.applied ?? 0) + (statuses.skipped ?? 0) + (statuses.failed ?? 0);
  if (!entry.row_count) return { done, percent: 0 };
  return { done, percent: Math.min(100, Math.round((done / entry.row_count) * 100)) };
}

type Summary = {
  people_created?: number;
  people_matched?: number;
  subscriptions?: number;
  rows?: Record<string, number>;
};

/** What applying did, from the report. */
export function reportOf(entry: Pick<PeopleImport, "summary" | "counts">) {
  const summary = (entry.summary ?? {}) as Summary;
  const statuses = entry.counts?.statuses ?? summary.rows ?? {};
  return {
    people: (summary.people_created ?? 0) + (summary.people_matched ?? 0),
    packages: summary.subscriptions ?? 0,
    skipped: (statuses.skipped ?? 0) + (statuses.failed ?? 0),
  };
}

export function canUndo(entry: Pick<PeopleImport, "status" | "undo_until">, now: Date) {
  if (entry.status !== "applied" && entry.status !== "failed") return false;
  return Boolean(entry.undo_until && new Date(entry.undo_until).getTime() > now.getTime());
}

function csvCell(value: string) {
  return /[",\n\r;]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
}

/** The skipped rows as a CSV the owner fixes and uploads again: the file's header plus a reason column. */
export function skippedRowsCsv(header: string[], rows: ImportRow[], reason: (row: ImportRow) => string) {
  const lines = [[...header, "reason"].map(csvCell).join(",")];
  for (const row of rows) lines.push([...row.cells, reason(row)].map(csvCell).join(","));
  return `${lines.join("\r\n")}\r\n`;
}
