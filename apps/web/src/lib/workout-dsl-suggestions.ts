export type WorkoutDslVocabulary = {
  version: number;
  section_formats: string[];
  format_aliases?: Record<string, { format: string; composition?: string | null }>;
  format_specs?: Record<
    string,
    { required: string[]; optional: string[]; body: string; score_types: string[] }
  >;
  workout_parameters: string[];
  exercise_parameters: string[];
  group_parameters?: string[];
  scale_parameters?: string[];
  header_parameters: string[];
  note_markers: string[];
  section_parameters: Record<string, string[]>;
  exercise_catalog?: Array<{
    id: string;
    label: string;
    category: string;
    aliases: string[];
    capabilities: string[];
  }>;
};

export type WorkoutDslSuggestion = {
  value: string;
  kind: "canonical" | "format" | "exercise" | "template" | "word";
};

export type WorkoutDslSuggestionResult = {
  from: number;
  query: string;
  items: WorkoutDslSuggestion[];
};

const MAX_SUGGESTIONS = 12;

export function buildWorkoutDslSuggestions(
  source: string,
  cursor: number,
  vocabulary: WorkoutDslVocabulary,
  commonWords: string[],
  exerciseNames: string[] = [],
): WorkoutDslSuggestionResult {
  const beforeCursor = source.slice(0, cursor);
  const currentLine = beforeCursor.slice(beforeCursor.lastIndexOf("\n") + 1);

  const templateMatch = currentLine.match(/^\s*\/([a-z0-9_-]*)$/i);
  if (templateMatch) {
    return resultFor(
      cursor,
      templateMatch[1],
      vocabulary.section_formats.map((value) => ({
        value,
        kind: "template" as const,
      })),
    );
  }

  const sectionMatch = currentLine.match(/^\s*\[section:\s*([a-z0-9_-]*)$/i);
  if (sectionMatch) {
    return resultFor(
      cursor,
      sectionMatch[1],
      vocabulary.section_formats.map((value) => ({ value, kind: "format" as const })),
    );
  }

  const exerciseMatch = currentLine.match(/^\s*\[exercise:\s*([^\]]*)$/i);
  if (exerciseMatch) {
    return fuzzyResultFor(
      cursor,
      exerciseMatch[1],
      exerciseNames.map((value) => ({ value, kind: "exercise" as const })),
    );
  }

  const noteMatch = currentLine.match(/^\s*(![a-z-]*)$/i);
  if (noteMatch) {
    return resultFor(
      cursor,
      noteMatch[1],
      vocabulary.note_markers.map((value) => ({ value, kind: "canonical" as const })),
    );
  }

  const tokenMatch = currentLine.match(/([a-z][a-z0-9-]*)$/i);
  const query = tokenMatch?.[1] ?? "";
  const canonical = contextualParameters(beforeCursor, vocabulary).map((value) => ({
    value,
    kind: "canonical" as const,
  }));

  if (!query && currentLine.trim() !== "") {
    return { from: cursor, query: "", items: [] };
  }

  const words = commonWords.map((value) => ({ value, kind: "word" as const }));
  return resultFor(cursor, query, [...canonical, ...words]);
}

type DslScope = { kind: string; format?: string };

function contextualParameters(
  beforeCursor: string,
  vocabulary: WorkoutDslVocabulary,
): string[] {
  const currentLineStart = beforeCursor.lastIndexOf("\n") + 1;
  const completedSource = beforeCursor.slice(0, currentLineStart);
  const stack: DslScope[] = [];

  for (const rawLine of completedSource.split("\n")) {
    const line = rawLine.trim();
    const close = line.match(/^\[\/(workout|section|group|exercise|header|scale)\]$/i);
    if (close) {
      const index = stack.map((scope) => scope.kind).lastIndexOf(close[1].toLowerCase());
      if (index >= 0) stack.splice(index);
      continue;
    }

    const section = line.match(/^\[section:\s*([^\]]+)\]$/i);
    if (section) {
      stack.push({ kind: "section", format: normalize(section[1]).replaceAll("-", "_") });
      continue;
    }

    const open = line.match(/^\[(workout|header|exercise|scale)(?::[^\]]+)?\]$/i);
    if (open) {
      stack.push({ kind: open[1].toLowerCase() });
      continue;
    }

    const group = line.match(/^\[group:\s*(?:superset|alternating)\]$/i);
    if (group) stack.push({ kind: "group" });
  }

  const scope = stack.at(-1);
  switch (scope?.kind) {
    case "workout":
      return unique(vocabulary.workout_parameters);
    case "section":
      return unique(
        vocabulary.section_parameters[scope.format ?? ""] ??
          Object.values(vocabulary.section_parameters).flat(),
      );
    case "exercise":
      return unique(vocabulary.exercise_parameters);
    case "scale":
      return unique(vocabulary.scale_parameters ?? vocabulary.exercise_parameters);
    case "group":
      return unique(vocabulary.group_parameters ?? []);
    case "header":
      return unique(vocabulary.header_parameters);
    default:
      return unique([
        ...vocabulary.workout_parameters,
        ...vocabulary.exercise_parameters,
        ...(vocabulary.group_parameters ?? []),
        ...(vocabulary.scale_parameters ?? []),
        ...vocabulary.header_parameters,
        ...Object.values(vocabulary.section_parameters).flat(),
      ]);
  }
}

function resultFor(
  cursor: number,
  rawQuery: string,
  candidates: WorkoutDslSuggestion[],
): WorkoutDslSuggestionResult {
  const query = rawQuery.trim();
  const normalizedQuery = query.toLocaleLowerCase();

  const items = candidates
    .filter((candidate) => candidate.value.toLocaleLowerCase().startsWith(normalizedQuery))
    .sort((left, right) => {
      return rank(left.kind) - rank(right.kind);
    })
    .filter(
      (candidate, index, all) =>
        all.findIndex((item) => item.value.toLocaleLowerCase() === candidate.value.toLocaleLowerCase()) ===
        index,
    )
    .slice(0, MAX_SUGGESTIONS);

  return {
    from: cursor - rawQuery.length,
    query,
    items,
  };
}

function fuzzyResultFor(
  cursor: number,
  rawQuery: string,
  candidates: WorkoutDslSuggestion[],
): WorkoutDslSuggestionResult {
  const query = rawQuery.trim();
  const scored = candidates
    .map((candidate, index) => ({ candidate, index, score: fuzzyScore(query, candidate.value) }))
    .filter((entry) => Number.isFinite(entry.score))
    .sort((left, right) => left.score - right.score || left.index - right.index)
    .filter(
      (entry, index, all) =>
        all.findIndex(
          (item) => normalize(item.candidate.value) === normalize(entry.candidate.value),
        ) === index,
    )
    .slice(0, MAX_SUGGESTIONS)
    .map((entry) => entry.candidate);

  return { from: cursor - rawQuery.length, query, items: scored };
}

function fuzzyScore(rawQuery: string, rawCandidate: string) {
  const query = normalize(rawQuery);
  const candidate = normalize(rawCandidate);
  if (!query) return 0;
  if (candidate === query) return 0;
  if (candidate.startsWith(query)) return 1;

  const words = candidate.split(" ");
  const wordPrefix = words.findIndex((word) => word.startsWith(query));
  if (wordPrefix >= 0) return 2 + wordPrefix / 100;
  if (candidate.includes(query)) return 3;

  const queryWords = query.split(" ");
  let total = 0;
  for (const queryWord of queryWords) {
    const scores = words.map((word) => fuzzyWordScore(queryWord, word));
    const best = Math.min(...scores);
    if (!Number.isFinite(best)) return Number.POSITIVE_INFINITY;
    total += best;
  }
  return 4 + total;
}

function fuzzyWordScore(query: string, candidate: string) {
  if (candidate.startsWith(query)) return 0;
  if (isSubsequence(query, candidate)) return 0.5 + (candidate.length - query.length) / 100;

  const distance = levenshtein(query, candidate);
  const tolerance = Math.max(1, Math.floor(Math.max(query.length, candidate.length) * 0.35));
  return distance <= tolerance ? 1 + distance / 10 : Number.POSITIVE_INFINITY;
}

function isSubsequence(query: string, candidate: string) {
  let queryIndex = 0;
  for (const character of candidate) {
    if (character === query[queryIndex]) queryIndex += 1;
    if (queryIndex === query.length) return true;
  }
  return false;
}

function levenshtein(left: string, right: string) {
  const previous = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    const current = [leftIndex];
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      current[rightIndex] = Math.min(
        current[rightIndex - 1] + 1,
        previous[rightIndex] + 1,
        previous[rightIndex - 1] +
          (left[leftIndex - 1] === right[rightIndex - 1] ? 0 : 1),
      );
    }
    previous.splice(0, previous.length, ...current);
  }
  return previous[right.length];
}

function normalize(value: string) {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function rank(kind: WorkoutDslSuggestion["kind"]) {
  switch (kind) {
    case "canonical":
      return 0;
    case "format":
      return 1;
    case "exercise":
      return 2;
    case "template":
      return 0;
    case "word":
      return 3;
  }
}

function unique(values: string[]) {
  return [...new Set(values)];
}
