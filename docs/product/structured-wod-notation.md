# Structured WOD notation (ADR-270)

What a coach can type in the structured WOD editor, and how Palee reads it. The web parsers
(`apps/web/src/lib/structured-plan/parse.ts`) and the API (`Palee.Workouts.Domain.StructuredPlan`)
follow this document. The shared test corpus is
`apps/web/src/lib/structured-plan/__fixtures__/corpus.json` (an identical copy is in
`apps/api/test/support/fixtures/structured_plan_corpus.json`).

Every value is stored exactly as typed. Reading never changes what the coach wrote.

## 1. Normalisation (applied before every rule)

| Input | Read as |
|---|---|
| Upper / lower case, Greek accents (`ΑΝΆ ΠΛΕΥΡΆ`) | lower case, no accents (`ανα πλευρα`) |
| Runs of spaces, tabs, leading / trailing spaces | one space, trimmed |
| Every dash: `‐ ‒ – — ― − ﹣ －` | `-` |
| Minute marks: `'` `’` `‘` `′` (iOS turns `'` into `’`) | `′` |
| Second marks: `"` `“` `”` `''` `′′` `″` | `″` |
| `...` | `…` |
| `->`, `=>` | `→` |
| Decimal comma: a comma followed by exactly one digit (`22,5`) | `22.5` |

A comma followed by two or more digits separates values (`60,70%` = 60% and 70%).
`m:ss` is a time, and its seconds must be below 60 (`0:90` is refused).

## 2. Unit words

| Unit | English | Greek |
|---|---|---|
| seconds | `s`, `sec`, `secs`, `second(s)`, `″` | `δ`, `δευτ`, `δευτ.`, `δευτερόλεπτο/α` |
| minutes | `min`, `mins`, `minute(s)`, `′` | `λ`, `λ.`, `λεπτ.`, `λεπτό`, `λεπτά` |
| reps | `reps`, `rep`, `r` | `επαναλήψεις`, `επανάληψη`, `επαν.`, `επ.` |
| calories | `cal`, `cals`, `kcal`, `calories` | `θερμίδες`, `θερμ.` |
| metres | `m`, `meters`, `metres` | `μ`, `μ.`, `μέτρα` |
| kilometres | `km` | `χλμ`, `χλμ.` |
| kilograms (load) | `kg`, `kgs`, `kgr` | `κιλά`, `κιλό`, `κ`, `κ.` |
| percent of 1RM (load) | `%`, `70% 1RM`, `70% of 1RM`, `@70%` | `70% του 1RM` |
| per side | `/side`, `/leg`, `/arm`, `each`, `each side`, `on each side`, `per side`, `per leg`, `e/s` | `/πλευρά`, `/πλ.`, `/χέρι`, `/πόδι`, `ανά πλευρά`, `ανά χέρι`, `ανά πόδι` |

A unit may be written once at the end (`30-45s`, `60-70%`) or after every value (`30s-45s`,
`60%-70%`). Mixing units inside one value is refused (`1min-30s`).

## 3. Numbers and lists (reps, loads, measures)

| Typed | Reading |
|---|---|
| `10` | one value |
| `10-12`, `10–12`, `10 έως 12`, `10 to 12`, `10 ως 12` (outside load columns) | **range**: the athlete picks within it |
| `12-10-8-8`, `21-15-9`, `8-8` | **list**: one value per set / round; after the last, the last repeats |
| `10, 12` | list (commas always separate sets) |
| `8-10, 6-8` | list of ranges |
| `5-10-15…`, `5-10-15...`, `5-10-15+` | **ladder**: the last step keeps going (20, 25 …) |

### Ambiguity rules

Where an input can mean two things, the parser returns the reading in the table, plus
`ambiguous: { alt, write, hint }`. The editor shows `hint` in its hint line.

| Typed | Reading | Other reading (`alt`) | Hint (el) |
|---|---|---|---|
| `10-12` (two rising values) | range 10–12 | `list`: two sets, `10, 12` | «εύρος 10–12 · για 2 σετ γράψε 10, 12» |
| `60-70%` | range 60–70% | `list`: `60%, 70%` | «εύρος 60–70% · για 2 σετ γράψε 60%, 70%» |
| `5-10-15` (3+ values rising by one step) | list, then 15 repeats | `ladder`: `5-10-15…` | «5 · 10 · 15, μετά μένει το τελευταίο · για να συνεχίσει να ανεβαίνει γράψε 5-10-15…» |
| AMRAP duration `12-15` | two windows, 12′ and 15′ | `range`: one AMRAP, `12` | «2 παράθυρα AMRAP: 12:00 · 15:00 · για ένα AMRAP γράψε 12:00» |
| a bare time in a rest field (`10`, `90`) | ≤ 10 = minutes, > 10 = seconds | `seconds` / `minutes`: `10″` / `90′` | «διαβάζεται 10:00 · για την άλλη μονάδα γράψε 10″» |

These are not ambiguous:
- falling or equal values (`12-10`, `21-15-9`, `8-8`): always a list;
- a dash after sets (`4x8-10`): always a range;
- `3-4` sets (the sets field): 3 sets, a 4th if they can.

## 4. Reps / quantity (`d`, `dose`)

| Typed | Reading |
|---|---|
| `10`, `10 reps`, `10 επαναλήψεις` | 10 reps |
| `4x10`, `4 x 10`, `4×10`, `4 χ 10`, `4 sets x 10`, `4 σετ x 10` | 4 sets of 10 (the `x` must be followed by a value, so `2 χλμ` stays 2 km) |
| `3-4x12-15` | 3 or 4 sets of 12–15 |
| `30s`, `30″`, `30 δευτ.`, `1:00`, `2′`, `2 λεπτά`, `1.5 min`, `2′30″` | time |
| `500m`, `500 μέτρα`, `2km`, `2 χλμ` | distance in metres (2 km = 2000 m) |
| `15 cal`, `15 θερμίδες` | calories |
| `max`, `max reps`, `AMRAP`, `μέγιστες` | as many as possible |
| `max cal`, `max m` | as many calories / metres as possible |
| `60s max cal`, `max cal σε 1:00`, `max reps in 60″` | as many as possible within a time (one time only) |
| `8-10 each side`, `8/πλευρά`, `8 ανά πόδι` | per side |

Refused (`bad_dose`): `0`, negatives (`-5`), words, emoji, `10-`, `4x0`, two times for max.

## 5. Load (`l`, `load`)

| Typed | Reading |
|---|---|
| `60kg`, `60 κιλά`, `22.5kg`, `22,5 kg` | kilograms (decimals allowed) |
| `70%`, `70% 1RM`, `70% του 1RM`, `@70%` | percent of 1RM |
| `60-70%` | range (see the ambiguity rules) |
| `60%+`, `60%↑` | start at 60% and build up |
| `bw`, `ΣΒ`, `bodyweight`, `σωματικό βάρος` | body weight |
| `rpe 8`, `@8`, `rpe 7-8` | RPE as intensity |
| `z2`, `zone 2`, `ζώνη 2` | heart rate zone 1–5 |
| `2:00/500m`, `2:00/500`, `5:00/km` | pace |
| `βαρύ`, `με βάρος`, `-10kg (λάστιχο)`, anything else | the coach's words, shown as written |
| `60 km`, `20 reps`, `30s`, `15 cal` | **`wrong_unit`**: a number with a unit that is not a load |

Outside the per-set grid, a bare number (`60`, `22,5`) is `missing_unit`.

### Loads per set / round (one row of columns)

- The unit (kg or %) is written **once per row**, in any column. Bare numbers in other columns
  (`70`, `+5`, `60→80`, `65-70`) take that unit.
- Numbers in a row with no unit anywhere → `missing_unit`. kg and % in one row → `mixed_unit`.
- An empty column means the same as the column before.
- `+2.5` / `-5` / `−5` change the column before. Empty columns after a change keep changing by
  the same amount. A change with nothing before it (first column, or after words or a range)
  → `no_base`.
- `60→80`, `60->80`, `60 ως 80`, `60 έως 80` spread evenly from this column to the last.
  (In a single value field, `έως` / `ως` mean a range.) A spread from kg to % → `wrong_unit`.
- `65-70` in a column: a range for that set. It does not progress.
- `60%↑`: starts there, and the columns after it show `↑ 60%` until another value.
- Words (`βαρύ`) pass through and stop the progression.

## 6. Time parameters

| Field | Bare number means | Examples |
|---|---|---|
| Time cap (`cap`), AMRAP duration (`dur`), rest-section duration | minutes | `20`, `20:00`, `20′` |
| Every other time (rest, every, work, off, interrupt every, structure pauses) | ≤ 10 minutes, > 10 seconds | `2` = 2:00, `90` = 90″, `2:30`, `90″` |
| Rest between sets | a range of two rising times is allowed | `90-120″`, `1:30-2:00`, `5-15` = 5″–15″ |
| AMRAP duration | windows split by `-`, `,` or `/` | `3-3-3-4`, `3′-3′-3′-4′`, `3, 3, 3, 4`, `3/3/3/4` |

All bare parts of one field share their unit. If any part is above 10, all are seconds
(`5-15` = 5″–15″, `2-3` = 2′–3′).

Counts (`rounds`, `times`, `hrTarget`, structure counts) are whole numbers above 0. An EMOM with
empty `times` (Death by) runs until the athlete can't finish in time: it is open-ended, like
AMRAP. Sets: `4`, `3-4`, `3–4`, `3 ή 4`, `3 or 4`, `3/4`.

## 7. Measures (per row, Alt+P)

| Measure | Typed | Rules |
|---|---|---|
| Pace (Ρυθμός) | `2:00`, `2:00/500m`, `-0:05`, `2:00→1:50` | progresses in seconds |
| Tempo | `31X1`, `3-1-X-1`, `3.1.x.1`, `31Χ1` (Greek Χ) | 4 marks: seconds down · pause bottom · up (X = explosive) · pause top; only repeats, never progresses; else `bad_tempo` |
| RPE | `8`, `7.5`, `7,5`, `+1`, `7→9`, `7-8` | at most 10 (`rpe_over_max`) |
| RIR, height, distance, hold | `2`, `60`, `60cm`, `400m`, `3`, `0:30` | a number first; in columns also `+x`, `a→b` |
| Heart rate zone | `2`, `z2`, `zone 2` | |
| Per side (Ανά πλευρά) | no value | a tag next to the name and in summaries |

In columns, measures follow the load rules (empty = same, `+x`, `a→b`, `no_base`). A range
(`7-8`) repeats as written.

## 8. Notes

Notes go per exercise, per section, per WOD and per scale level (`levelNotes`, by level key).
Each is optional, up to 2000 characters. Names and values are up to 200 characters.

## 9. Bounds and shape

At most 12 blocks (different rounds), 60 rows per block or interruption, and 30 columns per row.
Counts (rounds, times, sets, structure counts) are at most 999. Every number is at most
1 000 000 000. A larger number does not read: it is `bad_dose` / `bad_param`, and in a load it
counts as the coach's words.
The API refuses JSON in the wrong shape (a number where text belongs, a cell that is not an
object, an unknown cell key) with `bad_shape` at its path. A `null` cell is an empty column.
