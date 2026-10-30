import type { ClassTimerPayload } from "@/api/class-timers";
import type { TimerSegment } from "@/api/executions";
import type { WorkoutBody, WorkoutExerciseRecord } from "@/api/workouts";
import { exerciseInWindow } from "@/components/workouts/execution/progress";
import { buildSequence, type RunStep, type RunWork } from "@/components/workouts/execution/plan/sequence";
import type { ClassTimerPosition } from "@/lib/class-timer";
import { SHOW_WORDS_EN, type ShowWords } from "@/lib/structured-plan/parse";
import type { PlanSection } from "@/lib/structured-plan/types";
import type { IntervalWindow } from "@/lib/timer-engine";

/**
 * What the room does right now, for the class timer's screens (box TV, wall
 * display, coach remote). Pure: the segment the clock is in and its window
 * pick the most detailed answer the WOD allows —
 *
 *   - `step`: this EMOM minute / interval / window (its exercises, set-wise
 *     groups together), or the next one during the rest between intervals;
 *   - `round`: one round of an AMRAP (what repeats until the clock ends);
 *   - `section`: the whole section (For Time, sets, a text section);
 *   - `workout`: the whole WOD, when the clock is not tied to a section
 *     (free text, or a timer the coach picked for the class).
 *
 * Every segment's `section_id` points at a section of `payload.workout.body`
 * (ADR-224), so the same payload answers on every screen.
 */

export type NowScope = "step" | "round" | "section" | "workout";

export type NowLine = {
  key: string;
  name: string;
  /** Reps / quantity as shown ("12", "8–12", "21-15-9", "400 m"); "" when not set. */
  dose: string;
  /** Load as shown ("60 kg", "70%", the coach's words); "" when not set. */
  load: string;
  /** Superset / complex members share `key`; `first` and `last` mark its ends. */
  group: { kind: "superset" | "complex" | "alternating"; key: string; first: boolean; last: boolean } | null;
};

export type NowBlock = {
  key: string;
  /** Section name or text-section title; null when it has none. */
  title: string | null;
  lines: NowLine[];
  /** A text section, or a free-text WOD: shown as written. */
  text: string | null;
  /** The plan of a structured section, for its one-line summary. */
  plan: PlanSection | null;
  /** Interruption rows: done every `everySecs` seconds. */
  everySecs: number | null;
};

export type TimerNow = {
  scope: NowScope;
  /** True in a rest between intervals: the blocks are what comes next. */
  upcoming: boolean;
  blocks: NowBlock[];
};

type BodySection = { id?: string | null };

// ── phases of a window ────────────────────────────────────────────────────

/** The two windows of a plan's intervals (work, then off), when the segment runs both. */
function workOffPattern(segment: TimerSegment): boolean {
  const pattern = segment.timer_config?.interval_pattern_seconds;
  return segment.timer_config?.plan_flow === "intervals" && Array.isArray(pattern) && pattern.length === 2;
}

/**
 * Plan intervals run work and off as windows of one segment: window 2, 4 …
 * is the rest, and round n is windows 2n-1 / 2n. Other segments: the
 * window is the round.
 */
export function windowRound(segment: TimerSegment | null, window: IntervalWindow | null) {
  if (!segment || !window) return null;
  if (!workOffPattern(segment)) return { round: window.index, rounds: window.count, rest: false };
  return {
    round: Math.ceil(window.index / 2),
    rounds: window.count ? Math.ceil(window.count / 2) : null,
    rest: window.index % 2 === 0,
  };
}

// ── values ────────────────────────────────────────────────────────────────

const SIMPLE_NUMBER = /^\d+(?:[.,]\d+)?$/;

/** "12", "12", "12" → "12"; "21", "15", "9" → "21-15-9"; "60 kg", "65 kg" → "60-65 kg"; else joined with " / ". */
export function compressValues(values: string[]): string {
  const list = values.map((value) => value.trim()).filter(Boolean);
  const distinct = list.filter((value, index) => index === 0 || value !== list[index - 1]);
  if (distinct.length <= 1) return distinct[0] ?? "";
  if (distinct.every((value) => SIMPLE_NUMBER.test(value))) return distinct.join("-");
  const withUnit = distinct.map((value) => /^(\d+(?:[.,]\d+)?)\s*(\S+)$/.exec(value));
  const unit = withUnit[0]?.[2];
  if (unit && withUnit.every((match) => match && match[2] === unit)) {
    return `${withUnit.map((match) => match![1]).join("-")} ${unit}`;
  }
  return distinct.join(" / ");
}

function withSide(dose: string, perSide: boolean, words: ShowWords) {
  if (!perSide || !dose || dose.endsWith(words.perSide)) return dose;
  return `${dose}${words.perSide}`;
}

// ── structured plan ──────────────────────────────────────────────────────

function groupOf(work: RunWork): NowLine["group"] {
  return work.group ? { kind: work.group.kind, key: work.group.key, first: false, last: false } : null;
}

/** Marks the ends of each run of lines that share a group. */
function markGroups(lines: NowLine[]): NowLine[] {
  return lines.map((line, index) => {
    if (!line.group) return line;
    const before = lines[index - 1]?.group?.key === line.group.key;
    const after = lines[index + 1]?.group?.key === line.group.key;
    return { ...line, group: { ...line.group, first: !before, last: !after } };
  });
}

const works = (steps: RunStep[]) => steps.filter((step): step is RunWork => step.kind === "work" && step.name.trim() !== "");

/** One line per exercise of a stretch (cluster pieces and drops are one exercise), with the values it shows there. */
function stepLines(steps: RunStep[], words: ShowWords): NowLine[] {
  const seen = new Set<string>();
  const lines: NowLine[] = [];
  for (const work of works(steps)) {
    const key = `${work.rowId}:${work.round}`;
    if (seen.has(key)) continue;
    seen.add(key);
    lines.push({
      key,
      name: work.name,
      dose: withSide(work.values.dose, work.values.perSide, words),
      load: work.values.load,
      group: groupOf(work),
    });
  }
  return markGroups(lines);
}

/** One line per exercise of a whole section, its values across sets / rounds compressed ("21-15-9"). */
function sectionLines(steps: RunStep[], words: ShowWords): NowLine[] {
  const rows = new Map<string, { work: RunWork; doses: string[]; loads: string[]; round: number }>();
  for (const work of works(steps)) {
    const row = rows.get(work.rowId);
    if (!row) {
      rows.set(work.rowId, { work, doses: [work.values.dose], loads: [work.values.load], round: work.round });
    } else if (work.round !== row.round) {
      row.doses.push(work.values.dose);
      row.loads.push(work.values.load);
      row.round = work.round;
    }
  }
  return markGroups(
    [...rows.values()].map(({ work, doses, loads }) => ({
      key: work.rowId,
      name: work.name,
      dose: withSide(compressValues(doses), work.values.perSide, words),
      load: compressValues(loads),
      group: groupOf(work),
    })),
  );
}

function planBlock(section: { id?: string | null; name: string }, plan: PlanSection, lines: NowLine[]): NowBlock {
  return { key: String(section.id ?? section.name), title: section.name || null, lines, text: null, plan, everySecs: null };
}

function interruptBlock(section: { id?: string | null }, plan: PlanSection, words: ShowWords): NowBlock[] {
  const seq = buildSequence(plan, words);
  if (!seq.interrupt) return [];
  const lines = stepLines(seq.interrupt.steps, words);
  if (lines.length === 0) return [];
  return [{ key: `${section.id ?? ""}:interrupt`, title: null, lines, text: null, plan: null, everySecs: seq.interrupt.everySecs }];
}

/** The section's lines for the clock at `window` (EMOM minute, interval, AMRAP round, whole section). */
export function planNow(
  section: { id?: string | null; name: string },
  plan: PlanSection,
  segment: TimerSegment | null,
  window: IntervalWindow | null,
  words: ShowWords = SHOW_WORDS_EN,
): TimerNow | null {
  const seq = buildSequence(plan, words);
  const workPhases = seq.phases.filter((phase) => phase.kind === "work" && phase.steps.length > 0);
  if (workPhases.length === 0) return null;
  const extra = interruptBlock(section, plan, words);

  if (plan.flow === "emom" || plan.flow === "intervals") {
    const at = segment ? windowRound(segment, window) : null;
    const round = at?.round ?? 1;
    const rest = Boolean(at?.rest);
    // Open EMOMs ("until failure") keep cycling their blocks past the generated slots.
    const target = rest ? round + 1 : round;
    const phase =
      workPhases.find((candidate) => candidate.round === target) ??
      (rest ? null : workPhases[(target - 1) % workPhases.length]);
    if (!phase) return null;
    const lines = stepLines(phase.steps, words);
    if (lines.length === 0) return null;
    return { scope: "step", upcoming: rest, blocks: [planBlock(section, plan, lines), ...extra] };
  }

  const steps = workPhases.flatMap((phase) => phase.steps);
  if (plan.flow === "amrap") {
    // One round of each kind (blocks alternate rounds 1, 3, 5 … / 2, 4, 6 …).
    const kinds = Math.max(1, plan.blocks.length);
    const round = steps.filter((step) => step.round <= kinds);
    return { scope: "round", upcoming: false, blocks: [planBlock(section, plan, sectionLines(round, words)), ...extra] };
  }

  const lines = sectionLines(steps, words);
  if (lines.length === 0) return null;
  return { scope: "section", upcoming: false, blocks: [planBlock(section, plan, lines), ...extra] };
}

// ── exercises of a structured (legacy) workout ───────────────────────────

type Exercise = TimerSegment["exercises"][number] | WorkoutExerciseRecord;

const visible = (exercise: Exercise) =>
  !("excluded" in exercise && exercise.excluded) && exercise.item_type !== "header" && Boolean(exercise.name?.trim());

function legacyDose(value: number | string | null | undefined, unit: string | null | undefined) {
  if (value === null || value === undefined || value === "") return "";
  return unit && unit !== "reps" ? `${value} ${unit}` : String(value);
}

/** `LoadMode`: kg, % of 1RM, or bodyweight ("BW", like the plan's loads). */
function legacyLoad(value: number | string | null | undefined, mode: string | null | undefined) {
  if (mode === "bw") return "BW";
  if (value === null || value === undefined || value === "") return "";
  return mode === "pct_1rm" ? `${value}%` : `${value} kg`;
}

function exerciseLines(exercises: Exercise[]): NowLine[] {
  const lines = exercises.filter(visible).map((exercise, index): NowLine => {
    const sets = exercise.set_prescriptions ?? [];
    const dose =
      sets.length > 1
        ? compressValues(sets.map((set) => legacyDose(set.prescription_value ?? exercise.prescription_value, set.prescription_unit ?? exercise.prescription_unit)))
        : legacyDose(exercise.prescription_value, exercise.prescription_unit);
    const load =
      sets.length > 1
        ? compressValues(sets.map((set) => legacyLoad(set.load_value ?? exercise.load_value, set.load_mode ?? exercise.load_mode)))
        : legacyLoad(exercise.load_value, exercise.load_mode);
    const groupKey = exercise.superset_group_id ?? exercise.alternating_group_id ?? null;
    return {
      key: String(exercise.id ?? index),
      name: exercise.name,
      dose,
      load,
      group: groupKey
        ? { kind: exercise.superset_group_id ? "superset" : "alternating", key: groupKey, first: false, last: false }
        : null,
    };
  });
  return markGroups(lines);
}

function segmentNow(segment: TimerSegment, window: IntervalWindow | null): TimerNow | null {
  const all = segment.exercises.filter(visible);
  if (all.length === 0) return null;
  const inWindow = exerciseInWindow(segment, window?.index ?? null);
  const now = all.filter(inWindow);
  const lines = exerciseLines(now);
  // A segment per EMOM minute / interval, or a cycle that rotates its exercises: this window's.
  const scope: NowScope = segment.round != null || now.length < all.length ? "step" : "section";
  return {
    scope,
    upcoming: false,
    blocks: [{ key: segment.section_id, title: segment.section_name || null, lines, text: null, plan: null, everySecs: null }],
  };
}

// ── whole workout ────────────────────────────────────────────────────────

function textBlock(key: string, title: string | null, text: string | null | undefined): NowBlock | null {
  const trimmed = text?.trim();
  return trimmed ? { key, title, lines: [], text: trimmed, plan: null, everySecs: null } : null;
}

function wholeWorkout(body: WorkoutBody, words: ShowWords): NowBlock[] {
  switch (body.kind) {
    case "free_text":
      return [textBlock("workout", null, body.text)].filter((block): block is NowBlock => block !== null);
    case "text_sections":
      return body.sections
        .map((section, index) => textBlock(String(section.id ?? index), section.title, section.text))
        .filter((block): block is NowBlock => block !== null);
    case "structured":
      return body.sections
        .map((section, index): NowBlock => ({
          key: String(section.id ?? index),
          title: section.name || null,
          lines: exerciseLines(section.exercises),
          text: null,
          plan: null,
          everySecs: null,
        }))
        .filter((block) => block.lines.length > 0);
    case "plan":
      return body.sections.flatMap((section) => {
        if (!section.plan) return [];
        const lines = sectionLines(buildSequence(section.plan, words).phases.flatMap((phase) => phase.steps), words);
        return lines.length > 0 ? [planBlock(section, section.plan, lines)] : [];
      });
  }
}

function sectionOf<T extends BodySection>(sections: T[], id: string | undefined): T | null {
  if (!id) return null;
  return sections.find((section) => section.id != null && String(section.id) === id) ?? null;
}

/** The body of the payload's workout; older payloads only carry the free text. */
function bodyOf(workout: ClassTimerPayload["workout"]): WorkoutBody | null {
  if (!workout) return null;
  if (workout.body) return workout.body;
  return workout.free_text_body ? { kind: "free_text", text: workout.free_text_body, document: null, timer: null, structured: false } : null;
}

/** A text WOD or text section as the «Τώρα» panel shows it; null when it is empty. */
export function textNow(scope: "section" | "workout", title: string | null, text: string | null | undefined): TimerNow | null {
  const block = textBlock(scope, title, text);
  return block ? { scope, upcoming: false, blocks: [block] } : null;
}

/** What is done now at `position` of a class timer; null when there is nothing to show. */
export function timerNow(
  payload: Pick<ClassTimerPayload, "workout">,
  position: Pick<ClassTimerPosition, "segment" | "clock"> | null,
  words: ShowWords = SHOW_WORDS_EN,
): TimerNow | null {
  const body = bodyOf(payload.workout);
  const segment = position?.segment ?? null;
  const window = position?.clock?.window ?? null;

  if (segment) {
    if (body?.kind === "plan") {
      const section = sectionOf(body.sections, segment.section_id);
      if (section?.plan) return planNow(section, section.plan, segment, window, words);
    }
    const fromSegment = segmentNow(segment, window);
    if (fromSegment) return fromSegment;
    if (body?.kind === "structured") {
      const section = sectionOf(body.sections, segment.section_id);
      const lines = section ? exerciseLines(section.exercises) : [];
      if (section && lines.length > 0) {
        return { scope: "section", upcoming: false, blocks: [{ key: segment.section_id, title: section.name || null, lines, text: null, plan: null, everySecs: null }] };
      }
    }
    if (body?.kind === "text_sections") {
      const section = sectionOf(body.sections, segment.section_id);
      const block = section ? textBlock(segment.section_id, section.title, section.text) : null;
      if (block) return { scope: "section", upcoming: false, blocks: [block] };
    }
  }

  // Not tied to a section (free text, or the coach's own timer for the class): the whole WOD.
  const blocks = body ? wholeWorkout(body, words) : [];
  return blocks.length > 0 ? { scope: "workout", upcoming: false, blocks } : null;
}
