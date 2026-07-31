export type WorkoutDslVocabulary = {
  version: number;
  section_formats: string[];
  workout_parameters: string[];
  exercise_parameters: string[];
  header_parameters: string[];
  note_markers: string[];
  section_parameters: Record<string, string[]>;
};

export type WorkoutDslSuggestion = {
  value: string;
  kind: "canonical" | "format" | "exercise" | "word";
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
    return resultFor(
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
  if (!query) return { from: cursor, query: "", items: [] };

  const canonical = unique([
    ...vocabulary.workout_parameters,
    ...vocabulary.exercise_parameters,
    ...vocabulary.header_parameters,
    ...Object.values(vocabulary.section_parameters).flat(),
  ]).map((value) => ({ value, kind: "canonical" as const }));

  const words = commonWords.map((value) => ({ value, kind: "word" as const }));
  return resultFor(cursor, query, [...canonical, ...words]);
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

function rank(kind: WorkoutDslSuggestion["kind"]) {
  switch (kind) {
    case "canonical":
      return 0;
    case "format":
      return 1;
    case "exercise":
      return 2;
    case "word":
      return 3;
  }
}

function unique(values: string[]) {
  return [...new Set(values)];
}
