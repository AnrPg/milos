import { FORMAT_FIELD_DEFS, makeDefaultFormatParams, type FormatParams, type SectionFormat } from "@/types/workout";

/**
 * ADR-231: the section format is picked by typing what a coach writes on the
 * whiteboard: "amrap 12", "emom 10", "e2mom 20", "tabata", "for time 15",
 * «για χρόνο 15». The words find the format (its label in the screen's
 * language or a common alias); a number fills the format's main field
 * (minutes for a duration or time cap, otherwise a count of rounds).
 */

export type FormatChoice = { format: SectionFormat; params: FormatParams };

const ALIASES: Record<SectionFormat, string[]> = {
  untimed: ["untimed", "strength", "sets", "no timer", "δύναμη", "χωρίς χρόνο", "χωρίς χρονόμετρο"],
  for_time: ["for time", "ft", "rft", "rounds for time", "για χρόνο", "χρόνος"],
  train_to_exhaustion: ["to failure", "max reps", "failure", "μέχρι αποτυχίας", "αποτυχία"],
  kcal_target: ["calories", "cal", "kcal", "θερμίδες"],
  emom: ["emom", "otm", "every minute", "κάθε λεπτό"],
  complex_emom: ["complex emom", "rotating emom", "σύνθετο emom"],
  even_odd: ["even odd", "odd even", "e/o", "μονά ζυγά", "ζυγά μονά"],
  billat: ["billat", "30/30"],
  amrap: ["amrap", "as many rounds", "όσους γύρους"],
  edt: ["edt", "density"],
  death_by: ["death by", "deathby"],
  tabata: ["tabata"],
  custom_hiit: ["hiit", "intervals", "work rest", "διαστήματα"],
  cluster: ["cluster", "clusters"],
  hrr: ["hrr", "heart rate recovery", "ανάκαμψη παλμών"],
  ladder_ascending: ["ladder", "ladder up", "ascending", "ανεβαίνουσα σκάλα", "σκάλα"],
  ladder_descending: ["ladder down", "descending", "κατεβαίνουσα σκάλα"],
  pyramid: ["pyramid", "πυραμίδα"],
  rest: ["rest", "break", "ξεκούραση", "διάλειμμα"],
};

const DURATION_FIRST: SectionFormat[] = ["amrap", "emom", "complex_emom", "even_odd", "edt", "rest"];
const CAP_FIRST: SectionFormat[] = ["for_time", "kcal_target", "ladder_ascending", "ladder_descending", "pyramid"];
const COUNT_KEY: Partial<Record<SectionFormat, string>> = {
  tabata: "rounds",
  custom_hiit: "rounds",
  billat: "cycles",
  cluster: "sets",
  death_by: "ladder_cap",
};

function normalize(text: string) {
  return text
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/\s+/g, " ");
}

/** Applies the number typed after the words to the format's main field. */
function paramsFor(format: SectionFormat, amount: number | null, intervalMinutes: number | null): FormatParams {
  const params = makeDefaultFormatParams(format);
  if (intervalMinutes && (format === "emom" || format === "complex_emom")) {
    params.interval_seconds = intervalMinutes * 60;
  }
  if (amount === null || amount <= 0) return params;
  if (DURATION_FIRST.includes(format)) params.duration_seconds = amount * 60;
  else if (CAP_FIRST.includes(format)) {
    if (format === "kcal_target") params.kcal_target = amount;
    else params.time_cap_seconds = amount * 60;
  } else if (COUNT_KEY[format]) params[COUNT_KEY[format]!] = amount;
  else if (format === "train_to_exhaustion" || format === "hrr") {
    const first = FORMAT_FIELD_DEFS[format]?.[0];
    if (first) params[first.key] = amount;
  }
  return params;
}

/**
 * The formats matching what the coach typed, best first. An empty query
 * lists every format in `order` (the editor's grouped order).
 */
export function matchFormats(
  query: string,
  labels: Record<SectionFormat, string>,
  order: SectionFormat[],
): FormatChoice[] {
  let text = normalize(query);
  let intervalMinutes: number | null = null;
  const everyN = /^e(\d+)mom\b/.exec(text);
  if (everyN) {
    intervalMinutes = Number(everyN[1]);
    text = text.replace(/^e\d+mom/, "emom");
  }
  const amountMatch = /(\d+)\s*(?:'|′|min|mins|λ|λεπτα)?$/.exec(text);
  const amount = amountMatch && amountMatch.index > 0 ? Number(amountMatch[1]) : null;
  const words = (amount !== null ? text.slice(0, amountMatch!.index) : text).trim();

  if (words === "") {
    return order.map((format) => ({ format, params: paramsFor(format, amount, intervalMinutes) }));
  }

  const scored = order
    .map((format) => {
      const names = [labels[format], ...ALIASES[format]].map(normalize);
      let score = 0;
      for (const name of names) {
        if (name === words) score = Math.max(score, 3);
        else if (name.startsWith(words)) score = Math.max(score, 2);
        else if (name.includes(words) || name.split(" ").some((part) => part.startsWith(words))) score = Math.max(score, 1);
      }
      return { format, score };
    })
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score || order.indexOf(a.format) - order.indexOf(b.format));

  return scored.map(({ format }) => ({ format, params: paramsFor(format, amount, intervalMinutes) }));
}
