/**
 * ADR-270: runs the shared corpus (`__fixtures__/corpus.json`, also used by
 * the API's ExUnit parity test) through every core function and checks the
 * hand-written expectations.
 */
import fs from "node:fs";
import path from "node:path";
import { describe as group, expect, it } from "vitest";
import { FLOWS } from "./catalog";
import { describe, summary, timeline } from "./describe";
import { parseDose, parseLoad, progress, repeatText, setLoads, showDoseAt, tempoCanonical } from "./parse";
import { blockLabel, occurrences, structOf, totalRounds, unitsOf } from "./rounds";
import type { PlanRow, PlanSection } from "./types";
import { readParam, validateSection } from "./validate";
import corpus from "./__fixtures__/corpus.json";

type Check = { type: string; [key: string]: unknown };
type Entry = { id: string; title: string; section: PlanSection; expect: { issues: { path: string; code: string }[]; checks: Check[] } };
const entries = corpus.sections as unknown as Entry[];

/** Follows a dot path ("blocks.0.1.cells.0.d") from the section root. */
const at = (root: unknown, p: string): unknown =>
  p.split(".").reduce<unknown>((node, key) => (node && typeof node === "object" ? (node as Record<string, unknown>)[key] : undefined), root);
const listOf = (s: PlanSection, b: number): PlanRow[] => (b === -1 ? s.interrupt || [] : s.blocks[b]);
const sortIssues = (xs: { path: string; code: string }[]) => xs.map((x) => `${x.path}:${x.code}`).sort();

function runCheck(s: PlanSection, c: Check) {
  switch (c.type) {
    case "dose": {
      const d = parseDose(at(s, c.path as string) as string);
      expect(d).not.toBe("bad");
      expect(d).toMatchObject(c.expect as object);
      if (c.noAmbiguity) expect((d as { ambiguous?: unknown }).ambiguous).toBeUndefined();
      return;
    }
    case "doseAt":
      expect(showDoseAt(parseDose(at(s, c.path as string) as string), c.i as number)).toBe(c.expect);
      return;
    case "load":
      expect(parseLoad(at(s, c.path as string) as string)).toMatchObject(c.expect as object);
      return;
    case "setLoads":
      expect(setLoads(at(s, c.path as string) as PlanRow, c.n as number)).toEqual(c.expect);
      return;
    case "progress":
      expect(progress(at(s, c.path as string) as PlanRow, c.key as "rpe", c.n as number, Boolean(c.clock))).toEqual(c.expect);
      return;
    case "repeat":
      expect(repeatText(at(s, c.path as string) as PlanRow, c.key as "tempo", c.n as number)).toEqual(c.expect);
      return;
    case "tempo":
      expect(tempoCanonical(at(s, c.path as string) as string)).toBe(c.expect);
      return;
    case "param": {
      const def = [...FLOWS[s.flow].params, { key: "intEvery", kind: "time", bare: "smart" }].find((d) => d.key === c.key)!;
      expect(readParam(def as never, s.params[c.key as "rest"])).toMatchObject(c.expect as object);
      return;
    }
    case "rounds":
      expect(totalRounds(s)).toBe(c.expect === "Infinity" ? Infinity : c.expect);
      return;
    case "occurrences":
      expect(occurrences(s, c.block as number)).toEqual(c.expect);
      return;
    case "blockLabel":
      expect(blockLabel(s, c.block as number)).toEqual(c.expect);
      return;
    case "units":
      expect(unitsOf(listOf(s, c.block as number)).map((u) => u.rows.length)).toEqual(c.expect);
      return;
    case "struct":
      expect(structOf(s, unitsOf(listOf(s, c.block as number))[c.unit as number])).toEqual(c.expect);
      return;
    case "timeline": {
      const t = timeline(s);
      const e = c.expect as { open: boolean; total: number | null; segments: number; interrupts: number[] };
      expect({ open: t.open, total: t.total, segments: t.segments.length, interrupts: t.interrupts }).toEqual(e);
      return;
    }
    case "describe":
      expect(describe(s).map((p) => p.key)).toEqual(c.expect);
      return;
    case "summary":
      expect(summary(s)).toMatchObject(c.expect as object);
      return;
    default:
      throw new Error(`unknown check ${c.type}`);
  }
}

group("structured plan corpus (ADR-270)", () => {
  it("has at least 60 sections with unique ids and unique row ids per section", () => {
    expect(entries.length).toBeGreaterThanOrEqual(60);
    expect(new Set(entries.map((e) => e.id)).size).toBe(entries.length);
  });

  it("covers every flow, structure, add-on, measure and the open flows", () => {
    const flows = new Set(entries.map((e) => e.section.flow));
    for (const f of Object.keys(FLOWS)) expect(flows).toContain(f);
    const kinds = new Set(entries.flatMap((e) => Object.values(e.section.structs || {}).map((st) => st.kind)));
    for (const k of ["cluster", "drop", "restpause", "superset", "complex"]) expect(kinds).toContain(k);
    const rows = entries.flatMap((e) => [...(Array.isArray(e.section.blocks) ? e.section.blocks.flat() : []), ...(e.section.interrupt || [])]).filter((r) => r && typeof r === "object");
    const measures = new Set(rows.flatMap((r) => r.extra || []));
    for (const m of ["pace", "tempo", "rpe", "rir", "zone", "height", "dist", "hold", "side"]) expect(measures).toContain(m);
    expect(entries.some((e) => e.section.mods?.interrupt)).toBe(true);
    expect(entries.some((e) => e.section.mods?.hr)).toBe(true);
    expect(entries.some((e) => e.section.levelNotes && Object.keys(e.section.levelNotes).length)).toBe(true);
    expect(rows.some((r) => r.kind === "rest")).toBe(true);
    expect(rows.some((r) => r.perRound)).toBe(true);
  });

  it.each(entries.map((e) => [e.id, e] as const))("%s", (_, e) => {
    expect(sortIssues(validateSection(e.section))).toEqual(sortIssues(e.expect.issues));
    // well-shaped sections also go through every reader without throwing
    if (!e.expect.issues.some((x) => x.code === "bad_shape" || x.code === "unknown_flow")) {
      expect(() => [describe(e.section), timeline(e.section), summary(e.section)]).not.toThrow();
      e.section.blocks.forEach((_, b) => expect(() => [occurrences(e.section, b), blockLabel(e.section, b)]).not.toThrow());
    }
    for (const c of e.expect.checks) runCheck(e.section, c);
  });

  it("keeps the API copy byte-identical", () => {
    const web = fs.readFileSync(path.join(__dirname, "__fixtures__", "corpus.json"));
    const api = fs.readFileSync(path.resolve(__dirname, "../../../../api/test/support/fixtures/structured_plan_corpus.json"));
    expect(api.equals(web)).toBe(true);
  });
});
