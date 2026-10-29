import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import el from "../../../messages/el.json";
import en from "../../../messages/en.json";
import { FLOWS, MEASURES, MODS, PRESETS, STRUCTS, type MeasureUnit, type ScoreKey } from "./catalog";
import { PLAN_ERROR_CODES, SHOW_WORD_KEYS } from "./parse";
import { issueKey } from "./validate";

type Tree = { [key: string]: string | Tree };
const lookup = (tree: Tree, key: string): unknown => key.split(".").reduce<unknown>((node, part) => (node && typeof node === "object" ? (node as Tree)[part] : undefined), tree);

/** Every PlanCore key the core can hand to the UI. */
function allKeys(): string[] {
  const keys = new Set<string>();
  for (const f of Object.values(FLOWS)) {
    keys.add(f.labelKey);
    keys.add(f.hintKey);
    f.params.forEach((p) => keys.add(p.labelKey));
    f.scores.forEach((s) => keys.add(`PlanCore.score.${s}`));
  }
  for (const s of Object.values(STRUCTS)) {
    keys.add(s.labelKey);
    keys.add(s.hintKey);
    s.params.forEach((p) => keys.add(p.labelKey));
  }
  for (const m of Object.values(MODS)) {
    keys.add(m.labelKey);
    keys.add(m.hintKey);
    m.params.forEach((p) => keys.add(p.labelKey));
  }
  for (const m of Object.values(MEASURES)) {
    keys.add(m.labelKey);
    if (m.hintKey) keys.add(m.hintKey);
    if (m.unit) keys.add(`PlanCore.unit.${m.unit satisfies MeasureUnit}`);
  }
  for (const p of PRESETS) {
    keys.add(p.labelKey);
    if (p.score) keys.add(`PlanCore.score.${p.score satisfies ScoreKey}`);
  }
  PLAN_ERROR_CODES.forEach((c) => keys.add(issueKey(c)));
  Object.values(SHOW_WORD_KEYS).forEach((k) => keys.add(k));
  ["set", "round", "interval"].forEach((w) => keys.add(`PlanCore.roundWord.${w}`));
  for (const k of ["down", "bottom", "up", "top"]) keys.add(`PlanCore.tempo.${k}`).add(`PlanCore.tempo.${k}Explosive`);
  // literal keys written in the sources
  for (const file of fs.readdirSync(__dirname)) {
    if (!file.endsWith(".ts") || file.endsWith(".test.ts")) continue;
    const text = fs.readFileSync(path.join(__dirname, file), "utf8");
    for (const m of text.matchAll(/"(PlanCore\.[A-Za-z_]+\.[A-Za-z_0-9]+)"/g)) keys.add(m[1]);
  }
  return [...keys];
}

describe("PlanCore messages (ADR-270)", () => {
  it("collects the keys from the catalog and the sources", () => {
    expect(allKeys().length).toBeGreaterThan(170);
    expect(allKeys()).toContain("PlanCore.describe.amrapWindowsRest");
  });

  it.each([
    ["en", en],
    ["el", el],
  ])("has every key the core uses in %s", (_, messages) => {
    const missing = allKeys().filter((k) => typeof lookup(messages as unknown as Tree, k) !== "string");
    expect(missing).toEqual([]);
  });
});
