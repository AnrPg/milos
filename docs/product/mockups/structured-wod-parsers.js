const mmss = s => `${Math.floor(s/60)}:${String(s%60).padStart(2,"0")}`;
const numStr = n => String(Math.round(n * 100) / 100);

// ── time fields ──────────────────────────────────────
// A bare number means minutes ("min") or, with "smart", minutes up to 10 and seconds above ("rest 2" vs "rest 90").
function parseClock(t, dflt = "min") {
  const v = t.trim().toLowerCase(); if (!v) return null;
  let m = /^(\d+):(\d{2})$/.exec(v); if (m) return +m[1]*60 + +m[2];
  m = /^(\d+)\s*(s|sec|″|"|δ)$/.exec(v); if (m) return +m[1];
  m = /^(\d+)\s*(min|'|′|λ|λεπτά)$/.exec(v); if (m) return +m[1]*60;
  m = /^(\d+)$/.exec(v); if (m) return dflt === "min" || +m[1] <= 10 ? +m[1]*60 : +m[1];
  return "bad";
}
// "3-3-3-4", "3'-3'-3'-4'", "90-120″" (two ascending = range)
function parseTimes(t, dflt = "min") {
  let v = t.trim().toLowerCase(); if (!v) return null;
  const um = /\s*(s|sec|″|"|δ|min|'|′|λ)$/.exec(v);
  const parts = v.split(/\s*[-–,]\s*/).map(p => um && /^\d+$/.test(p) ? p + um[1] : p);
  const secs = parts.map(p => parseClock(p, dflt));
  if (secs.some(x => x === "bad" || x === null || x <= 0)) return "bad";
  const range = secs.length === 2 && !v.includes(",") && secs[0] < secs[1];
  return { range, secs };
}
const showTimes = p => !p || p === "bad" ? "" : p.range ? `${clock(p.secs[0])}–${clock(p.secs[1])}` : p.secs.map(clock).join(" · ");

// ── dose notation ────────────────────────────────────
const NUM = "(\\d+(?:\\.\\d+)?(?::\\d{2})?)";
const toNum = t => t.includes(":") ? (() => { const [a, b] = t.split(":"); return +a*60 + +b; })() : +t;
function parseNums(v) {
  let cont = false;
  if (/(…|\.\.\.|\+)$/.test(v)) { cont = true; v = v.replace(/(…|\.\.\.|\+)$/, "").trim(); }
  const words = new RegExp(`^${NUM}\\s*(?:έως|εως|to|~)\\s*${NUM}$`).exec(v);
  if (words) return { entries: [{ min: toNum(words[1]), max: toNum(words[2]) }], cont: false };
  if (v.includes(",")) {
    // "8-10, 6-8, 4-6": commas separate sets, a dash inside a set is a range
    const sets = v.split(/\s*,\s*/).map(p => { const r = new RegExp(`^${NUM}(?:\\s*(?:[-–]|έως|εως|to)\\s*${NUM})?$`).exec(p); return r && { min: toNum(r[1]), max: toNum(r[2] || r[1]) }; });
    if (sets.some(e => !e || e.max < e.min) || (cont && sets.length < 2)) return "bad";
    return { entries: sets, cont };
  }
  const parts = v.split(/\s*[-–,]\s*/);
  if (!parts.every(p => new RegExp(`^${NUM}$`).test(p))) return "bad";
  const nums = parts.map(toNum);
  if (cont && nums.length < 2) return "bad";
  if (nums.length === 2 && !v.includes(",") && nums[0] < nums[1] && !cont) return { entries: [{ min: nums[0], max: nums[1] }], cont };
  return { entries: nums.map(n => ({ min: n, max: n })), cont };
}
const SIDE = /\s*(\/\s*(side|πλευρά|πλευρα|πλ\.?|χέρι|χερι|πόδι|ποδι)|(on\s+)?each(\s+(side|arm|leg))?|for each arm|ανά πλευρά|ανα πλευρα|ανά χέρι|ανα χερι|ανά πόδι|ανα ποδι)$/;
const UNIT = /\s*(reps|r|επ\.?|cal|kcal|θερμ\.?|km|m|sec|s|″|"|δ|min|'|′|λ)$/;
function parseDose(text) {
  let v = text.trim().toLowerCase().replace(/\s+/g, " ");
  if (!v) return null;
  const out = { sets: null, entries: null, unit: "reps", perSide: false, cont: false, max: null };
  const sm = SIDE.exec(v); if (sm) { out.perSide = true; v = v.slice(0, sm.index).trim(); }
  const sx = /^(\d+)(?:\s*-\s*(\d+))?\s*(?:sets?|σετ)?\s*[x×χ]\s*(.*)$/.exec(v);
  if (sx) { out.sets = { min: +sx[1], max: +(sx[2] || sx[1]) }; v = sx[3].trim(); if (!out.sets.min || out.sets.max < out.sets.min) return "bad"; if (!v) return out; }
  const mx = /^(?:(\S+)\s+)?(max|μέγιστ\S*)\s*(reps|cal|m)?$/.exec(v);
  if (mx) { const within = mx[1] ? parseClock(mx[1], "smart") : null; if (within === "bad") return "bad"; out.max = { within }; out.unit = mx[3] === "cal" ? "kcal" : mx[3] === "m" ? "m" : "reps"; return out; }
  const um = UNIT.exec(v);
  let scale = 1;
  if (um) { const u = um[1]; v = v.slice(0, um.index).trim();
    if (["cal", "kcal", "θερμ", "θερμ."].includes(u)) out.unit = "kcal";
    else if (u === "m") out.unit = "m";
    else if (u === "km") { out.unit = "m"; scale = 1000; }
    else if (["sec", "s", "″", '"', "δ"].includes(u)) out.unit = "secs";
    else if (["min", "'", "′", "λ"].includes(u)) { out.unit = "secs"; scale = 60; }
  }
  if (v.includes(":")) out.unit = "secs";
  const p = parseNums(v); if (p === "bad") return "bad";
  out.entries = p.entries.map(e => ({ min: e.min * scale, max: e.max * scale })); out.cont = p.cont;
  if (out.entries.some(e => e.min <= 0)) return "bad";
  if (out.sets && (out.entries.length > 1 || out.cont)) return "bad";
  return out;
}
// Load or intensity never fails: anything unrecognised is kept as the coach's words.
function parseLoad(text) {
  let v = text.trim().toLowerCase().replace(/\s+/g, " ");
  if (!v) return null;
  if (["bw", "σβ", "body", "bodyweight", "σωματικό βάρος"].includes(v)) return { kind: "bw" };
  let m = /^rpe\s*(\d+(?:\.\d)?)(?:\s*-\s*(\d+(?:\.\d)?))?$/.exec(v); if (m) return { kind: "rpe", min: +m[1], max: +(m[2] || m[1]) };
  m = /^(?:z|zone|ζώνη|ζωνη)\s*([1-5])$/.exec(v); if (m) return { kind: "zone", zone: +m[1] };
  m = /^(\d+:\d{2})\s*\/\s*(500m|500|km|100m|mi)$/.exec(v); if (m) return { kind: "pace", per: m[2] === "500" ? "500m" : m[2], secs: toNum(m[1]) };
  let up = false;
  if (/(\+|↑)$/.test(v)) { up = true; v = v.slice(0, -1).trim(); }
  const um = /\s*(kg|κιλά|κιλα|%)$/.exec(v);
  if (um) { const n = parseNums(v.slice(0, um.index).trim().replace(/(\d),(\d)$/, "$1.$2")); if (n !== "bad" && !n.cont) return { kind: um[1] === "%" ? "pct" : "kg", entries: n.entries, up }; }
  return { kind: "text", text: text.trim() };
}
const setCountOf = d => !d || d === "bad" ? 1 : d.sets ? d.sets.max : d.entries ? (d.cont ? d.entries.length : d.entries.length) : 1;
const loadCount = l => l && l.entries ? l.entries.length : 1;
function entryAt(d, i) { if (!d || d === "bad" || !d.entries) return null; const es = d.entries; if (es.length === 1) return es[0]; if (i < es.length) return es[i]; if (d.cont) { const step = es.at(-1).min - es.at(-2).min; const n = es.at(-1).min + step * (i - es.length + 1); return { min: n, max: n }; } return es.at(-1); }
function showOne(n, unit) { return unit === "secs" ? clock(n) : unit === "kcal" ? `${numStr(n)} cal` : unit === "m" ? (n >= 1000 && n % 100 === 0 ? `${numStr(n/1000)} km` : `${numStr(n)} m`) : unit === "kg" ? `${numStr(n)} kg` : unit === "pct" ? `${numStr(n)}%` : numStr(n); }
function showEntry(e, unit) { if (!e) return ""; if (e.min === e.max) return showOne(e.min, unit); return unit === "reps" ? `${numStr(e.min)}–${numStr(e.max)}` : `${showOne(e.min, unit).replace(/ ?(kg|cal|m|km|%|″)$/, "")}–${showOne(e.max, unit)}`; }
function showDoseAt(d, i) {
  if (!d || d === "bad") return "";
  if (d.max) return `max${d.unit === "kcal" ? " cal" : d.unit === "m" ? " m" : ""}${d.max.within ? " σε " + clock(d.max.within) : ""}`;
  const e = entryAt(d, i); return e ? showEntry(e, d.unit) + (d.perSide ? "/πλευρά" : "") : "";
}
function showLoadAt(l, i) {
  if (!l) return "";
  if (l.kind === "bw") return "BW"; if (l.kind === "text") return l.text; if (l.kind === "zone") return `ζώνη ${l.zone}`;
  if (l.kind === "rpe") return l.min === l.max ? `RPE ${l.min}` : `RPE ${l.min}–${l.max}`;
  if (l.kind === "pace") return `${clock(l.secs)}/${l.per}`;
  const e = l.entries.length === 1 ? l.entries[0] : l.entries[i] || l.entries.at(-1);
  return l.up && l.entries.length === 1 && i > 0 ? `↑ από ${showEntry(e, l.kind)}` : showEntry(e, l.kind);
}
function doseCaption(d, word) {
  if (!d) return "";
  if (d === "bad") return "π.χ. 10, 4×10, 12-10-8-8, 8-10, 3-4×12-15, 5-10-15…, 30s, 500m, max";
  const side = d.perSide ? " · ανά πλευρά" : "";
  const sets = d.sets ? `${d.sets.min === d.sets.max ? d.sets.min : d.sets.min + " ή " + d.sets.max} σετ` : "";
  if (d.max) return [sets, `όσες περισσότερες${d.unit === "kcal" ? " θερμίδες" : d.unit === "m" ? " μέτρα" : ""}${d.max.within ? " σε " + clock(d.max.within) : ""}`].filter(Boolean).join(" · ") + side;
  if (!d.entries) return sets;
  if (d.entries.length > 1) {
    const list = d.entries.map(e => showEntry(e, d.unit)).join(" · ");
    const cont = d.cont ? `, μετά ${entryAt(d, d.entries.length).min - d.entries.at(-1).min > 0 ? "+" : ""}${numStr(entryAt(d, d.entries.length).min - d.entries.at(-1).min)} κάθε ${word}` : "";
    return (word === "σετ" && !d.cont ? `${d.entries.length} σετ: ` : `ανά ${word}: `) + list + cont + side;
  }
  const e = d.entries[0];
  const body = e.min !== e.max ? `εύρος ${showEntry(e, d.unit)}, το αποφασίζει ο αθλητής` : showEntry(e, d.unit) + (d.unit === "reps" ? " επαναλήψεις" : "");
  return [sets, body].filter(Boolean).join(" · ") + side;
}
function loadCaption(l) {
  if (!l) return "";
  if (l.kind === "bw") return "σωματικό βάρος"; if (l.kind === "text") return "ως κείμενο για τον αθλητή"; if (l.kind === "zone") return `ζώνη παλμών ${l.zone}`;
  if (l.kind === "rpe") return "πόσο δύσκολο (1–10)"; if (l.kind === "pace") return `ρυθμός ${clock(l.secs)} ανά ${l.per}`;
  const what = l.kind === "pct" ? " του 1RM" : "";
  if (l.entries.length > 1) return `ανά σετ: ${l.entries.map(e => showEntry(e, l.kind)).join(" · ")}${what}`;
  const e = l.entries[0];
  if (l.up) return `ξεκινά από ${showEntry(e, l.kind)}${what} και ανεβαίνει`;
  return e.min !== e.max ? `εύρος ${showEntry(e, l.kind)}${what}, διαλέγει ο αθλητής` : showEntry(e, l.kind) + what;
}

