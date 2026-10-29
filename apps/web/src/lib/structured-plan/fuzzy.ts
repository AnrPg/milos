/**
 * ADR-270: Meilisearch-like matching for every free-text pick in the
 * structured WOD editor (flows and presets, measures, structures, menu
 * actions, exercise names). Every query word must match some word of the
 * text: as a prefix (best), inside a word, or with one typo (two from seven
 * letters). Case and Greek accents are ignored ("αμραπ" finds "ΑΜΡΑΠ",
 * "ξεκουραση" finds "Ξεκούραση").
 */

/** Lower case, accents removed (NFD, combining marks dropped), trimmed. Keeps the length of plain text. */
export const fold = (s: string): string => foldRaw(s).trim();

/** `fold` without trimming: one folded string per input character run, same indexes for plain text. */
const foldRaw = (s: string): string =>
  s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/ς/g, "σ");

/** Damerau–Levenshtein distance (with adjacent transpositions). */
export function editDistance(a: string, b: string): number {
  const d: number[][] = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array<number>(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
    }
  }
  return d[a.length][b.length];
}

/** Matched ranges `[start, end)` in the original text, for highlighting. */
export type FuzzyMatch = { score: number; marks: [number, number][] };

/**
 * Matches `query` against `text`. Scores per query word: prefix 10 (+3 for
 * the whole word), inside a word 6, a typo 4 − distance; summed. `null` when
 * any query word matches nothing. An empty query matches with score 0.
 */
export function fuzzy(query: string, text: string): FuzzyMatch | null {
  const q = fold(query).split(/[\s\-/]+/).filter(Boolean);
  if (!q.length) return { score: 0, marks: [] };
  // fold the text without trimming, so indexes stay those of `text` (NFD of Greek/Latin letters keeps one base letter each)
  const t = foldRaw(text);
  const offsets = foldOffsets(text);
  const words: { w: string; at: number }[] = [];
  for (const m of t.matchAll(/[^\s\-/(),·]+/g)) words.push({ w: m[0], at: m.index ?? 0 });
  let score = 0;
  const marks: [number, number][] = [];
  for (const qw of q) {
    let best: { s: number; m: [number, number] } | null = null;
    for (const { w, at } of words) {
      let s: number | null = null;
      let m: [number, number] | null = null;
      if (w.startsWith(qw)) {
        s = 10 + (w === qw ? 3 : 0);
        m = [at, at + qw.length];
      } else if (qw.length > 1 && w.includes(qw)) {
        s = 6;
        const i = w.indexOf(qw);
        m = [at + i, at + i + qw.length];
      } else if (qw.length >= 3) {
        const allow = qw.length >= 7 ? 2 : 1;
        const dist = Math.min(editDistance(qw, w.slice(0, qw.length)), editDistance(qw, w));
        if (dist <= allow) {
          s = 4 - dist;
          m = [at, at + Math.min(w.length, qw.length)];
        }
      }
      if (s != null && m && (!best || s > best.s)) best = { s, m };
    }
    if (!best) return null;
    score += best.s;
    marks.push([offsets[best.m[0]], offsets[best.m[1]]]);
  }
  return { score, marks };
}

/** Maps an index in the folded text back to the original text (accents fold away). */
function foldOffsets(text: string): number[] {
  const out: number[] = [];
  let i = 0;
  for (const ch of text) {
    const folded = foldRaw(ch);
    for (let k = 0; k < folded.length; k++) out.push(i);
    i += ch.length;
  }
  out.push(i);
  return out;
}

/** What `rankItems` matches for one item: its (translated) label, other words, and a bonus. */
export type RankText = { label: string; alt?: string; bonus?: number };
export type Ranked<T> = { item: T; score: number; marks: [number, number][]; onLabel: boolean };

/**
 * Ranks items for a query, best first (stable for ties). A match on the
 * label wins over one on `alt` (aliases, hint), which scores one less;
 * `bonus` lifts a kind of item (flows over presets). Empty query: every
 * item, in order, score 0.
 */
export function rankItems<T>(query: string, items: T[], text: (item: T) => RankText): Ranked<T>[] {
  if (!fold(query)) return items.map((item) => ({ item, score: 0, marks: [], onLabel: true }));
  const out: Ranked<T>[] = [];
  for (const item of items) {
    const { label, alt, bonus = 0 } = text(item);
    const a = fuzzy(query, label);
    const b = alt ? fuzzy(query, alt) : null;
    if (a && (!b || a.score >= b.score)) out.push({ item, score: a.score + bonus, marks: a.marks, onLabel: true });
    else if (b) out.push({ item, score: b.score - 1 + bonus, marks: [], onLabel: false });
  }
  return out.map((r, i) => ({ r, i })).sort((x, y) => y.r.score - x.r.score || x.i - y.i).map(({ r }) => r);
}
