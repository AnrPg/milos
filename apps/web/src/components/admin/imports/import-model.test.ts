import { describe, expect, it } from "vitest";

import type { ImportRow, PeopleImport } from "@/api/imports";

import {
  applyAnswer,
  applyProgress,
  canUndo,
  decisionKey,
  deriveDecisions,
  phaseOf,
  previewKpis,
  reportOf,
  sameMapping,
  setColumnField,
  skippedRowsCsv,
} from "./import-model";

function importOf(patch: Partial<PeopleImport> = {}): PeopleImport {
  return {
    id: "imp-1",
    status: "draft",
    source: "wodify",
    filename: "wodify-members.csv",
    byte_size: 1200,
    encoding: "utf-8",
    delimiter: ",",
    header: ["First Name", "Email", "Membership", "Coach Notes"],
    row_count: 3,
    mapping: [
      { column: 0, field: "first_name" },
      { column: 1, field: "email" },
      { column: 2, field: "package_name" },
    ],
    date_order: "mdy",
    default_role: "member",
    file_warnings: [],
    preview: {
      rows: 3,
      outcomes: { create_person: 2, invalid: 1 },
      actions: { create_person: 2, assign_package: 2, create_package: 1 },
      warnings: { package_created: 1, invalid_email: 1 },
    },
    ...patch,
  } as PeopleImport;
}

function row(row_number: number, cells: string[], patch: Partial<ImportRow> = {}): ImportRow {
  return { id: `r${row_number}`, row_number, cells, status: "pending", outcome: "create_person", warnings: [], errors: [], result: {}, ...patch } as ImportRow;
}

const sample = [
  row(2, ["Maria", "maria@example.com", "Gold 2024", "Shoulder"], { warnings: [{ code: "package_created", field: "package_name" }] }),
  row(3, ["Nikos", "nikos@", "gold 2024", ""], { warnings: [{ code: "invalid_email", field: "email" }] }),
  row(4, ["", "", "", ""], { outcome: "invalid", errors: [{ code: "missing_person", field: null }] }),
];

describe("import phases", () => {
  it("maps statuses to the screen's phases", () => {
    expect(phaseOf({ status: "draft" })).toBe("review");
    expect(phaseOf({ status: "queued" })).toBe("applying");
    expect(phaseOf({ status: "applying" })).toBe("applying");
    expect(phaseOf({ status: "applied" })).toBe("done");
    expect(phaseOf({ status: "failed" })).toBe("done");
    expect(phaseOf({ status: "undone" })).toBe("undone");
  });
});

describe("dry run decisions", () => {
  it("asks about new packages, problem rows and the one column without a place", () => {
    const decisions = deriveDecisions(importOf(), sample);
    expect(decisions).toEqual([
      { kind: "packages", names: ["Gold 2024"], members: 2, count: 1 },
      { kind: "rows", rows: [3, 4], count: 2 },
      { kind: "column", column: 3, header: "Coach Notes", sample: "Shoulder", notesFree: true },
    ]);
    expect(decisions.map(decisionKey)).toEqual(["packages", "rows", "column-3"]);
  });

  it("groups several columns without a place into one card", () => {
    const entry = importOf({ header: ["First Name", "Email", "Membership", "Coach Notes", "Waiver"] });
    const rows = sample.map((r) => ({ ...r, cells: [...r.cells, "yes"] }));
    const decisions = deriveDecisions(entry, rows);
    expect(decisions.at(-1)).toEqual({
      kind: "columns",
      columns: [
        { column: 3, header: "Coach Notes" },
        { column: 4, header: "Waiver" },
      ],
    });
  });

  it("counts problem rows from the dry run when the sample is only part of the file", () => {
    const decisions = deriveDecisions(importOf({ row_count: 900 }), sample.slice(0, 1));
    expect(decisions.find((d) => d.kind === "rows")).toEqual({ kind: "rows", rows: [], count: 2 });
  });

  it("needs no decision for a clean file", () => {
    const entry = importOf({
      header: ["First Name", "Email"],
      mapping: [
        { column: 0, field: "first_name" },
        { column: 1, field: "email" },
      ],
      preview: { rows: 1, outcomes: { create_person: 1 }, actions: { create_person: 1 }, warnings: {} },
    });
    expect(deriveDecisions(entry, [row(2, ["Maria", "maria@example.com"])])).toEqual([]);
  });
});

describe("answers and the mapping", () => {
  const entry = importOf();
  const [packages, , column] = deriveDecisions(entry, sample);

  it("leaves the package columns out and puts them back", () => {
    const without = applyAnswer(entry.mapping, entry.mapping, packages!, "skip");
    expect(without).toEqual([
      { column: 0, field: "first_name" },
      { column: 1, field: "email" },
    ]);
    expect(applyAnswer(without, entry.mapping, packages!, "create")).toEqual(entry.mapping);
  });

  it("puts a column into the notes or leaves it out", () => {
    const withNotes = applyAnswer(entry.mapping, entry.mapping, column!, "notes");
    expect(withNotes).toContainEqual({ column: 3, field: "notes" });
    expect(applyAnswer(withNotes, entry.mapping, column!, "skip")).toEqual(entry.mapping);
  });

  it("keeps a field on one column only", () => {
    expect(setColumnField(entry.mapping, 3, "email")).toEqual([
      { column: 0, field: "first_name" },
      { column: 2, field: "package_name" },
      { column: 3, field: "email" },
    ]);
    expect(sameMapping(entry.mapping, [...entry.mapping].reverse())).toBe(true);
    expect(sameMapping(entry.mapping, setColumnField(entry.mapping, 0, null))).toBe(false);
  });
});

describe("numbers on screen", () => {
  it("reads the KPIs of a dry run", () => {
    expect(previewKpis(importOf())).toEqual({ created: 2, matched: 0, packages: 2, newPackages: 1, skipped: 1 });
  });

  it("reports progress while applying", () => {
    expect(applyProgress({ row_count: 200, counts: { statuses: { applied: 90, skipped: 10, pending: 100 }, outcomes: {} } })).toEqual({ done: 100, percent: 50 });
    expect(applyProgress({ row_count: 0, counts: null })).toEqual({ done: 0, percent: 0 });
  });

  it("reads the report", () => {
    expect(
      reportOf({
        summary: { people_created: 206, people_matched: 5, subscriptions: 180 },
        counts: { statuses: { applied: 211, skipped: 3 }, outcomes: {} },
      }),
    ).toEqual({ people: 211, packages: 180, skipped: 3 });
  });

  it("allows undo only inside the window", () => {
    const now = new Date("2026-10-29T10:00:00Z");
    expect(canUndo({ status: "applied", undo_until: "2026-11-02T10:00:00Z" }, now)).toBe(true);
    expect(canUndo({ status: "applied", undo_until: "2026-10-28T10:00:00Z" }, now)).toBe(false);
    expect(canUndo({ status: "undone", undo_until: "2026-11-02T10:00:00Z" }, now)).toBe(false);
  });
});

describe("skipped rows file", () => {
  it("writes the header, the cells and the reason, quoting where needed", () => {
    const csv = skippedRowsCsv(["Name", "Email"], [row(4, ["Eleni, K.", "x"])], () => "No name");
    expect(csv).toBe('Name,Email,reason\r\n"Eleni, K.",x,No name\r\n');
  });
});
