import type { LoadMode, PrescriptionUnit } from "@/types/workout";

/**
 * ADR-270: one text field per quantity in the structured WOD editor. The
 * coach types the amount and its unit together ("10", "30s", "1:30",
 * "15 cal", "70%", "bw") instead of reaching for a stepper and a unit
 * button, so a row is written without the mouse. English and Greek unit
 * words are accepted; values are whole numbers because the API stores them
 * as integers.
 */

export type Prescription = { value: number; unit: PrescriptionUnit };
export type Load = { mode: LoadMode; value: number | null };
export type Parsed<T> = T | null | "invalid";

const REP_WORDS = ["", "r", "rep", "reps", "x", "επ", "επαν", "επανάληψη", "επαναλήψεις", "επαναληψεις", "επαναληψη"];
const SECOND_WORDS = ["s", "sec", "secs", "second", "seconds", "''", "″", "\"", "δ", "δευτ", "δευτερόλεπτο", "δευτερόλεπτα", "δευτερολεπτα"];
const MINUTE_WORDS = ["min", "mins", "minute", "minutes", "'", "′", "λ", "λεπ", "λεπτό", "λεπτά", "λεπτα"];
const CALORIE_WORDS = ["cal", "cals", "kcal", "calories", "θερμ", "θερμίδες", "θερμιδες", "kcals"];
const KILO_WORDS = ["", "kg", "kgs", "κ", "κιλά", "κιλα", "κιλό", "κιλο", "кг", "ק\"ג", "קג", "كجم", "كغ"];
const PERCENT_WORDS = ["%", "% 1rm", "%1rm", "%rm", "% rm"];
const BODYWEIGHT_WORDS = ["bw", "body", "bodyweight", "σβ", "σ.β.", "σωματικό", "σωματικό βάρος", "σωματικο βαρος", "-", "—"];

function normalize(text: string) {
  return text.trim().toLowerCase().replace(/\s+/g, " ");
}

/** "12", "12 cal": the whole number in front and the unit word after it. */
function split(text: string): { amount: number; word: string } | "invalid" {
  const match = /^(\d+)\s*(.*)$/.exec(text);
  if (!match) return "invalid";
  return { amount: Number(match[1]), word: match[2].trim() };
}

export function parsePrescription(text: string): Parsed<Prescription> {
  const value = normalize(text);
  if (value === "") return null;

  const clock = /^(\d+):(\d{2})$/.exec(value);
  if (clock) {
    if (Number(clock[2]) > 59) return "invalid";
    return positive({ value: Number(clock[1]) * 60 + Number(clock[2]), unit: "secs" });
  }

  const parts = split(value);
  if (parts === "invalid") return "invalid";
  const { amount, word } = parts;
  if (REP_WORDS.includes(word)) return positive({ value: amount, unit: "reps" });
  if (SECOND_WORDS.includes(word)) return positive({ value: amount, unit: "secs" });
  if (MINUTE_WORDS.includes(word)) return positive({ value: amount * 60, unit: "secs" });
  if (CALORIE_WORDS.includes(word)) return positive({ value: amount, unit: "kcal" });
  return "invalid";
}

function positive(prescription: Prescription): Parsed<Prescription> {
  return prescription.value > 0 ? prescription : "invalid";
}

/** `bodyweightLabel`: the screen's own word for bodyweight (e.g. «KG» in German), also accepted. */
export function parseLoad(text: string, bodyweightLabel?: string): Parsed<Load> {
  const value = normalize(text);
  if (value === "") return null;
  if (BODYWEIGHT_WORDS.includes(value) || (bodyweightLabel && value === normalize(bodyweightLabel))) {
    return { mode: "bw", value: null };
  }

  const parts = split(value);
  if (parts === "invalid") return "invalid";
  const { amount, word } = parts;
  if (amount <= 0) return "invalid";
  if (KILO_WORDS.includes(word)) return { mode: "absolute", value: amount };
  if (PERCENT_WORDS.includes(word)) return amount <= 200 ? { mode: "pct_1rm", value: amount } : "invalid";
  return "invalid";
}

/** Whole positive number ("5", "5 sets", "5 σετ"), for sets and interval minutes. */
export function parseCount(text: string): Parsed<number> {
  const value = normalize(text);
  if (value === "") return null;
  const match = /^(\d+)\s*(x|sets?|σετ|rounds?|γύροι|γυροι)?$/.exec(value);
  if (!match) return "invalid";
  const amount = Number(match[1]);
  return amount > 0 ? amount : "invalid";
}

export function formatPrescription(value: number | null | undefined, unit: PrescriptionUnit | null | undefined): string {
  if (value == null || value <= 0) return "";
  if (unit === "secs") {
    if (value >= 60) return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, "0")}`;
    return `${value}s`;
  }
  if (unit === "kcal") return `${value} cal`;
  return String(value);
}

export function formatLoad(mode: LoadMode | null | undefined, value: number | null | undefined, bodyweightLabel: string): string {
  if (mode === "bw") return bodyweightLabel;
  if (value == null || value <= 0) return "";
  if (mode === "pct_1rm") return `${value}%`;
  return `${value} kg`;
}
