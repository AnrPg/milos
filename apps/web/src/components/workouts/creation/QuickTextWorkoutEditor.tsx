"use client";

import { EditorContent, useEditor, type Editor } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { ApiError } from "@/api/client";
import {
  createDraftWorkout,
  fetchAdminWorkout,
  parseWorkoutDsl,
  updateDraftWorkout,
  type WorkoutDslDiagnostic,
  type WorkoutDslPreview,
} from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import {
  COMMON_WORKOUT_WORDS,
  DEFAULT_WORKOUT_DSL_SOURCE,
  EXERCISE_NAMES,
  QUICK_TEXT_EDITOR_CLASS,
} from "@/lib/workout-dsl-editor-data";
import {
  buildWorkoutDslSuggestions,
  type WorkoutDslSuggestion,
  type WorkoutDslVocabulary,
} from "@/lib/workout-dsl-suggestions";

const EMPTY_VOCABULARY: WorkoutDslVocabulary = {
  version: 1,
  section_formats: [],
  workout_parameters: [],
  exercise_parameters: [],
  header_parameters: [],
  note_markers: [],
  section_parameters: {},
};

type Props = {
  draftId: string | null;
  onDraftReady: (id: string) => void;
  onSwitchToStructured: (id: string) => void;
};

type SaveStatus = "idle" | "saving" | "saved" | "error";

export function QuickTextWorkoutEditor({
  draftId,
  onDraftReady,
  onSwitchToStructured,
}: Props) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const [source, setSource] = useState(DEFAULT_WORKOUT_DSL_SOURCE);
  const [preview, setPreview] = useState<WorkoutDslPreview | null>(null);
  const [diagnostics, setDiagnostics] = useState<WorkoutDslDiagnostic[]>([]);
  const [parsing, setParsing] = useState(false);
  const [saveStatus, setSaveStatus] = useState<SaveStatus>("idle");
  const [suggestions, setSuggestions] = useState<WorkoutDslSuggestion[]>([]);
  const loadedDraftRef = useRef<string | null>(null);

  const editor = useEditor({
    extensions: [StarterKit],
    content: sourceToDocument(DEFAULT_WORKOUT_DSL_SOURCE),
    immediatelyRender: false,
    editorProps: {
      attributes: {
        class: QUICK_TEXT_EDITOR_CLASS,
        spellcheck: "true",
        role: "textbox",
        "aria-label": i18n("quickTextEditorLabel"),
      },
    },
    onUpdate: ({ editor: currentEditor }) => {
      setSource(currentEditor.getText({ blockSeparator: "\n" }));
    },
    onSelectionUpdate: ({ editor: currentEditor }) => {
      updateSuggestions(currentEditor);
    },
  });

  const vocabulary = preview?.vocabulary ?? EMPTY_VOCABULARY;

  const updateSuggestions = useCallback(
    (currentEditor = editor) => {
      if (!currentEditor) return;

      const currentSource = currentEditor.state.doc.textBetween(
        0,
        currentEditor.state.selection.from,
        "\n",
      );
      const cursor = currentSource.length;
      const result = buildWorkoutDslSuggestions(
        currentSource,
        cursor,
        vocabulary,
        COMMON_WORKOUT_WORDS,
        EXERCISE_NAMES,
      );
      setSuggestions(result.items);
    },
    [editor, vocabulary],
  );

  useEffect(() => {
    if (!tokens?.access_token || draftId || loadedDraftRef.current === "creating") return;

    loadedDraftRef.current = "creating";
    createDraftWorkout(tokens.access_token)
      .then((draft) => onDraftReady(draft.id))
      .catch(() => {
        loadedDraftRef.current = null;
        setSaveStatus("error");
      });
  }, [draftId, onDraftReady, tokens?.access_token]);

  useEffect(() => {
    if (!tokens?.access_token || !draftId || loadedDraftRef.current === draftId || !editor) return;

    loadedDraftRef.current = draftId;
    fetchAdminWorkout(tokens.access_token, draftId)
      .then((workout) => {
        const draftData =
          workout.draft_data && typeof workout.draft_data === "object"
            ? (workout.draft_data as Record<string, unknown>)
            : null;
        const storedSource = typeof draftData?.dsl_source === "string" ? draftData.dsl_source : null;

        if (storedSource) {
          setSource(storedSource);
          editor.commands.setContent(sourceToDocument(storedSource));
        }
      })
      .catch(() => setSaveStatus("error"));
  }, [draftId, editor, tokens?.access_token]);

  useEffect(() => {
    if (!tokens?.access_token || !source.trim()) return;

    const timer = window.setTimeout(() => {
      setParsing(true);
      parseWorkoutDsl(tokens.access_token, source)
        .then((result) => {
          setPreview(result);
          setDiagnostics([]);
          setParsing(false);
        })
        .catch((error: unknown) => {
          if (error instanceof ApiError && error.status === 422 && error.payload.diagnostics) {
            setDiagnostics(error.payload.diagnostics);
          } else {
            setDiagnostics([]);
          }
          setParsing(false);
        });
    }, 350);

    return () => window.clearTimeout(timer);
  }, [source, tokens?.access_token]);

  useEffect(() => {
    if (!tokens?.access_token || !draftId || loadedDraftRef.current !== draftId) return;

    setSaveStatus("saving");
    const timer = window.setTimeout(() => {
      updateDraftWorkout(tokens.access_token, draftId, {
        authoring_mode: "quick_text",
        dsl_version: 1,
        dsl_source: source,
        dsl_document: editor?.getJSON() ?? null,
      })
        .then(() => setSaveStatus("saved"))
        .catch(() => setSaveStatus("error"));
    }, 1_200);

    return () => window.clearTimeout(timer);
  }, [draftId, editor, source, tokens?.access_token]);

  useEffect(() => {
    updateSuggestions();
  }, [source, updateSuggestions]);

  const statusLabel = useMemo(() => {
    if (parsing) return i18n("quickTextParsing");
    if (diagnostics.length > 0) return i18n("quickTextInvalid");
    if (preview) return i18n("quickTextReady");
    return "";
  }, [diagnostics.length, i18n, parsing, preview]);

  function acceptSuggestion(suggestion: WorkoutDslSuggestion) {
    if (!editor) return;
    const currentSource = editor.state.doc.textBetween(
      0,
      editor.state.selection.from,
      "\n",
    );
    const currentLine = currentSource.slice(currentSource.lastIndexOf("\n") + 1);
    const query =
      currentLine.match(/^\s*\[section:\s*([a-z0-9_-]*)$/i)?.[1] ??
      currentLine.match(/^\s*\[exercise:\s*([^\]]*)$/i)?.[1] ??
      currentLine.match(/^\s*(![a-z-]*)$/i)?.[1] ??
      currentLine.match(/([a-z][a-z0-9-]*)$/i)?.[1] ??
      "";
    const to = editor.state.selection.from;

    editor
      .chain()
      .focus()
      .deleteRange({ from: Math.max(1, to - query.length), to })
      .insertContent(suggestion.value)
      .run();
    setSuggestions([]);
  }

  function beautify() {
    if (!editor || !preview) return;
    setSource(preview.formatted_source.trimEnd());
    editor.commands.setContent(sourceToDocument(preview.formatted_source.trimEnd()));
  }

  async function switchToStructured() {
    if (!tokens?.access_token || !draftId || !preview) return;

    setSaveStatus("saving");

    try {
      await updateDraftWorkout(tokens.access_token, draftId, {
        ...toStructuredDraft(preview.workout),
        authoring_mode: "structured",
        dsl_version: preview.version,
        dsl_source: source,
        dsl_document: editor?.getJSON() ?? null,
      });
      setSaveStatus("saved");
      onSwitchToStructured(draftId);
    } catch {
      setSaveStatus("error");
    }
  }

  return (
    <div className="grid h-full min-h-[calc(100dvh-6.5rem)] grid-cols-1 lg:grid-cols-[minmax(0,1.25fr)_minmax(20rem,0.75fr)]">
      <section className="flex min-h-0 flex-col border-e" style={{ borderColor: "var(--dim)" }}>
        <div className="border-b px-5 py-4" style={{ borderColor: "var(--dim)" }}>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h1 className="text-xl font-black" style={{ color: "var(--text)" }}>
                {i18n("quickTextTitle")}
              </h1>
              <p className="mt-1 max-w-3xl text-sm" style={{ color: "var(--muted)" }}>
                {i18n("quickTextDescription")}
              </p>
            </div>
            <div className="flex items-center gap-2 text-xs font-semibold" style={{ color: "var(--muted)" }}>
              <span>{saveStatusText(saveStatus, i18n)}</span>
              <span aria-live="polite">{statusLabel}</span>
            </div>
          </div>
        </div>

        <EditorToolbar editor={editor} />

        <div className="relative min-h-0 flex-1 overflow-auto">
          <EditorContent editor={editor} />
          {suggestions.length > 0 ? (
            <div
              className="sticky bottom-3 mx-4 max-w-xl overflow-hidden rounded-xl border shadow-xl"
              style={{ background: "var(--panel)", borderColor: "var(--dim)" }}
              role="listbox"
              aria-label={i18n("quickTextSuggestions")}
            >
              {suggestions.map((suggestion) => (
                <button
                  type="button"
                  key={`${suggestion.kind}:${suggestion.value}`}
                  role="option"
                  aria-selected="false"
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => acceptSuggestion(suggestion)}
                  className="flex w-full items-center justify-between px-3 py-2 text-start text-sm hover:opacity-80"
                  style={{ color: "var(--text)" }}
                >
                  <span>{suggestion.value}</span>
                </button>
              ))}
            </div>
          ) : null}
        </div>

        <div
          className="flex flex-wrap items-center justify-between gap-3 border-t px-5 py-3"
          style={{ borderColor: "var(--dim)" }}
        >
          <span className="text-xs" style={{ color: "var(--muted)" }}>
            {i18n("quickTextAutocompleteHint")}
          </span>
          <div className="flex gap-2">
            <button
              type="button"
              disabled={!preview}
              onClick={beautify}
              className="rounded-xl px-4 py-2 text-sm font-bold disabled:opacity-40"
              style={{ background: "var(--card)", color: "var(--text)" }}
            >
              {i18n("quickTextBeautify")}
            </button>
            <button
              type="button"
              disabled={!preview || diagnostics.length > 0}
              onClick={switchToStructured}
              className="rounded-xl px-4 py-2 text-sm font-bold disabled:opacity-40"
              style={{ background: "var(--primary)", color: "var(--primary-foreground, white)" }}
            >
              {i18n("quickTextSwitchStructured")}
            </button>
          </div>
        </div>
      </section>

      <aside className="min-h-0 overflow-auto p-5" style={{ background: "var(--panel)" }}>
        {diagnostics.length > 0 ? (
          <DiagnosticsPanel diagnostics={diagnostics} />
        ) : (
          <CanonicalPreview preview={preview} />
        )}
      </aside>
    </div>
  );
}

function EditorToolbar({ editor }: { editor: Editor | null }) {
  const i18n = useUiTranslations();
  if (!editor) return null;

  const actions = [
    { label: i18n("editorBold"), text: i18n("editorBold"), active: editor.isActive("bold"), run: () => editor.chain().focus().toggleBold().run() },
    { label: i18n("editorItalic"), text: i18n("editorItalic"), active: editor.isActive("italic"), run: () => editor.chain().focus().toggleItalic().run() },
    { label: i18n("editorHeading"), text: i18n("editorHeading"), active: editor.isActive("heading"), run: () => editor.chain().focus().toggleHeading({ level: 2 }).run() },
    { label: i18n("editorBulletList"), text: "•", active: editor.isActive("bulletList"), run: () => editor.chain().focus().toggleBulletList().run() },
    { label: i18n("editorOrderedList"), text: "1.", active: editor.isActive("orderedList"), run: () => editor.chain().focus().toggleOrderedList().run() },
    { label: i18n("editorUndo"), text: "↶", active: false, run: () => editor.chain().focus().undo().run() },
    { label: i18n("editorRedo"), text: "↷", active: false, run: () => editor.chain().focus().redo().run() },
  ];

  return (
    <div className="flex flex-wrap gap-1 border-b px-4 py-2" style={{ borderColor: "var(--dim)" }}>
      {actions.map((action) => (
        <button
          type="button"
          key={action.label}
          aria-label={action.label}
          title={action.label}
          onClick={action.run}
          className="min-w-9 rounded-lg px-2 py-1.5 text-sm font-bold"
          style={{
            background: action.active ? "var(--primary)" : "var(--card)",
            color: action.active ? "var(--primary-foreground, white)" : "var(--text)",
          }}
        >
          {action.text}
        </button>
      ))}
    </div>
  );
}

function DiagnosticsPanel({ diagnostics }: { diagnostics: WorkoutDslDiagnostic[] }) {
  const i18n = useUiTranslations();

  return (
    <div>
      <h2 className="text-lg font-black" style={{ color: "var(--text)" }}>
        {i18n("quickTextDiagnostics")}
      </h2>
      <div className="mt-3 space-y-2">
        {diagnostics.map((diagnostic, index) => (
          <div
            key={`${diagnostic.code}:${diagnostic.line}:${index}`}
            className="rounded-xl border px-3 py-2"
            style={{
              borderColor: "color-mix(in srgb, var(--danger) 45%, transparent)",
              background: "color-mix(in srgb, var(--danger) 8%, transparent)",
            }}
          >
            <div className="text-sm font-bold" style={{ color: "var(--danger)" }}>
              {i18n("quickTextDiagnosticLine", { line: diagnostic.line })}
            </div>
            <div className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
              {i18n("quickTextInvalid")}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function CanonicalPreview({ preview }: { preview: WorkoutDslPreview | null }) {
  const i18n = useUiTranslations();
  const workout = preview?.workout;
  const sections = Array.isArray(workout?.sections) ? workout.sections : [];

  return (
    <div>
      <h2 className="text-lg font-black" style={{ color: "var(--text)" }}>
        {i18n("quickTextCanonicalPreview")}
      </h2>
      {!workout ? (
        <p className="mt-3 text-sm" style={{ color: "var(--muted)" }}>
          {i18n("quickTextPreviewWaiting")}
        </p>
      ) : (
        <div className="mt-4 space-y-4">
          <div>
            <div className="text-xl font-black" style={{ color: "var(--text)" }}>
              {String(workout.title ?? "")}
            </div>
            <div className="text-xs uppercase tracking-wide" style={{ color: "var(--muted)" }}>
              {String(workout.type ?? "")}
            </div>
          </div>
          {sections.map((rawSection, sectionIndex) => {
            const section = rawSection as Record<string, unknown>;
            const exercises = Array.isArray(section.exercises) ? section.exercises : [];

            return (
              <div
                key={`${String(section.name)}:${sectionIndex}`}
                className="rounded-2xl border p-4"
                style={{ borderColor: "var(--dim)", background: "var(--card)" }}
              >
                <div className="font-extrabold" style={{ color: "var(--text)" }}>
                  {String(section.name ?? "")}
                </div>
                <div className="mt-2 space-y-2">
                  {exercises.map((rawExercise, exerciseIndex) => {
                    const exercise = rawExercise as Record<string, unknown>;
                    return (
                      <div key={`${String(exercise.name)}:${exerciseIndex}`} className="text-sm">
                        <span className="font-bold" style={{ color: "var(--text)" }}>
                          {String(exercise.name ?? "")}
                        </span>
                        {exercise.item_type !== "header" ? (
                          <span style={{ color: "var(--muted)" }}>
                            {" "}
                            · {String(exercise.sets ?? 1)} × {String(exercise.prescription_value ?? "")}
                          </span>
                        ) : null}
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function saveStatusText(status: SaveStatus, i18n: ReturnType<typeof useUiTranslations>) {
  switch (status) {
    case "saving":
      return i18n("quickTextSaving");
    case "saved":
      return i18n("quickTextSaved");
    case "error":
      return i18n("quickTextSaveError");
    case "idle":
      return "";
  }
}

function sourceToDocument(source: string) {
  return {
    type: "doc",
    content: source.split("\n").map((line) => ({
      type: "paragraph",
      content: line ? [{ type: "text", text: line }] : undefined,
    })),
  };
}

function toStructuredDraft(workout: Record<string, unknown>) {
  const sections = Array.isArray(workout.sections) ? workout.sections : [];

  return {
    title: workout.title,
    type: workout.type,
    is_team_workout: Boolean(workout.is_team_workout),
    sections: sections.map((rawSection) => {
      const section = rawSection as Record<string, unknown>;
      const exercises = Array.isArray(section.exercises) ? section.exercises : [];

      return {
        name: section.name,
        scoreable: Boolean(section.scoreable),
        score_config: section.score_config ?? null,
        timer_config: section.timer_config ?? { type: "untimed" },
        note: section.note ?? null,
        exercises: exercises.map((rawExercise) => {
          const exercise = rawExercise as Record<string, unknown>;
          return {
            item_type: exercise.item_type ?? "exercise",
            name: exercise.name,
            sets: exercise.sets ?? null,
            set_prescriptions: exercise.set_prescriptions ?? [],
            prescription_value: exercise.prescription_value ?? null,
            prescription_unit: exercise.prescription_unit ?? null,
            load_value: exercise.load_value ?? null,
            load_mode: exercise.load_mode ?? null,
            load_progression: exercise.load_progression ?? null,
            interval_assignment: exercise.interval_assignment ?? null,
            tempo: exercise.tempo ?? null,
            rest_seconds: exercise.rest_seconds ?? null,
            note: exercise.note ?? null,
            variations: [],
          };
        }),
      };
    }),
  };
}
