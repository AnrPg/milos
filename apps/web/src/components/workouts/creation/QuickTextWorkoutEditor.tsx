"use client";

import CharacterCount from "@tiptap/extension-character-count";
import Highlight from "@tiptap/extension-highlight";
import Link from "@tiptap/extension-link";
import Placeholder from "@tiptap/extension-placeholder";
import TextAlign from "@tiptap/extension-text-align";
import Typography from "@tiptap/extension-typography";
import Underline from "@tiptap/extension-underline";
import { EditorContent, useEditor, type Editor, type JSONContent } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { ApiError } from "@/api/client";
import {
  createDraftWorkout,
  fetchWorkoutDslAuthoring,
  fetchWorkoutDslManual,
  parseWorkoutDsl,
  publishWorkoutDsl,
  updateDraftWorkout,
  type WorkoutDslDiagnostic,
  type WorkoutDslManual,
  type WorkoutDslPreview,
} from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import {
  COMMON_WORKOUT_WORDS,
  DEFAULT_WORKOUT_DSL_SOURCE,
  QUICK_TEXT_EDITOR_CLASS,
  sanitizeWorkoutDslPaste,
} from "@/lib/workout-dsl-editor-data";
import {
  buildWorkoutDslSuggestions,
  type WorkoutDslSuggestion,
  type WorkoutDslVocabulary,
} from "@/lib/workout-dsl-suggestions";

const EMPTY_VOCABULARY: WorkoutDslVocabulary = {
  version: 1,
  section_formats: [],
  format_aliases: {},
  format_specs: {},
  workout_parameters: [],
  exercise_parameters: [],
  group_parameters: [],
  scale_parameters: [],
  header_parameters: [],
  note_markers: [],
  section_parameters: {},
  exercise_catalog: [],
};

type Props = {
  draftId: string | null;
  onDraftReady: (id: string) => void;
  onSwitchToStructured: (id: string) => void;
};

type SaveStatus = "idle" | "saving" | "saved" | "error" | "conflict";

export function QuickTextWorkoutEditor({
  draftId,
  onDraftReady,
  onSwitchToStructured,
}: Props) {
  const i18n = useUiTranslations();
  const router = useRouter();
  const { tokens } = useSession();
  const accessToken = tokens?.access_token;
  const [source, setSource] = useState(DEFAULT_WORKOUT_DSL_SOURCE);
  const [preview, setPreview] = useState<WorkoutDslPreview | null>(null);
  const [diagnostics, setDiagnostics] = useState<WorkoutDslDiagnostic[]>([]);
  const [manual, setManual] = useState<WorkoutDslManual | null>(null);
  const [manualOpen, setManualOpen] = useState(false);
  const [parsing, setParsing] = useState(false);
  const [publishing, setPublishing] = useState(false);
  const [warningsAcknowledged, setWarningsAcknowledged] = useState(false);
  const [saveStatus, setSaveStatus] = useState<SaveStatus>("idle");
  const [sourceRevision, setSourceRevision] = useState(0);
  const [suggestions, setSuggestions] = useState<WorkoutDslSuggestion[]>([]);
  const [authoringReady, setAuthoringReady] = useState(false);
  const loadedDraftRef = useRef<string | null>(null);
  const parseRequestRef = useRef(0);
  const sourceRef = useRef(source);
  const revisionRef = useRef(sourceRevision);

  const editor = useEditor({
    extensions: [
      StarterKit.configure({
        link: false,
        underline: false,
      }),
      Underline,
      Highlight.configure({ multicolor: true }),
      Link.configure({
        openOnClick: false,
        autolink: true,
        linkOnPaste: true,
        protocols: ["https", "mailto"],
      }),
      TextAlign.configure({ types: ["heading", "paragraph"] }),
      Typography,
      Placeholder.configure({ placeholder: i18n("quickTextEditorPlaceholder") }),
      CharacterCount.configure({ limit: 200_000 }),
    ],
    content: sourceToDocument(DEFAULT_WORKOUT_DSL_SOURCE),
    editable: false,
    immediatelyRender: false,
    editorProps: {
      attributes: {
        class: QUICK_TEXT_EDITOR_CLASS,
        spellcheck: "true",
        role: "textbox",
        "aria-label": i18n("quickTextEditorLabel"),
      },
      transformPastedHTML: sanitizeWorkoutDslPaste,
    },
    onUpdate: ({ editor: currentEditor }) => {
      const nextSource = currentEditor.getText({ blockSeparator: "\n" });
      sourceRef.current = nextSource;
      setSource(nextSource);
      setWarningsAcknowledged(false);
    },
    onSelectionUpdate: ({ editor: currentEditor }) => {
      updateSuggestions(currentEditor);
    },
  });

  const vocabulary = preview?.vocabulary ?? manual?.vocabulary ?? EMPTY_VOCABULARY;
  const exerciseNames = useMemo(
    () =>
      (vocabulary.exercise_catalog ?? []).flatMap((exercise) => [
        exercise.label,
        ...exercise.aliases,
      ]),
    [vocabulary.exercise_catalog],
  );
  const errors = diagnostics.filter((diagnostic) => diagnostic.severity === "error");
  const warnings = diagnostics.filter((diagnostic) => diagnostic.severity === "warning");

  useEffect(() => {
    editor?.setEditable(authoringReady);
  }, [authoringReady, editor]);

  const updateSuggestions = useCallback(
    (currentEditor = editor) => {
      if (!currentEditor) return;

      const currentSource = currentEditor.state.doc.textBetween(
        0,
        currentEditor.state.selection.from,
        "\n",
      );
      const result = buildWorkoutDslSuggestions(
        currentSource,
        currentSource.length,
        vocabulary,
        COMMON_WORKOUT_WORDS,
        exerciseNames,
      );
      setSuggestions(result.items);
    },
    [editor, exerciseNames, vocabulary],
  );

  useEffect(() => {
    sourceRef.current = source;
  }, [source]);

  useEffect(() => {
    revisionRef.current = sourceRevision;
  }, [sourceRevision]);

  useEffect(() => {
    if (!tokens?.access_token || manual) return;
    fetchWorkoutDslManual(tokens.access_token)
      .then(setManual)
      .catch(() => undefined);
  }, [manual, tokens?.access_token]);

  useEffect(() => {
    if (!tokens?.access_token || draftId || loadedDraftRef.current === "creating") return;

    loadedDraftRef.current = "creating";
    createDraftWorkout(tokens.access_token)
      .then((draft) => {
        const revision = draft.dsl_source_revision ?? 0;
        revisionRef.current = revision;
        setSourceRevision(revision);
        onDraftReady(draft.id);
      })
      .catch(() => {
        loadedDraftRef.current = null;
        setSaveStatus("error");
      });
  }, [draftId, onDraftReady, tokens?.access_token]);

  useEffect(() => {
    if (!tokens?.access_token || !draftId || loadedDraftRef.current === draftId || !editor) return;

    setAuthoringReady(false);
    loadedDraftRef.current = draftId;
    fetchWorkoutDslAuthoring(tokens.access_token, draftId)
      .then((authoring) => {
        const nextSource = authoring.source || DEFAULT_WORKOUT_DSL_SOURCE;
        const nextRevision = authoring.source_revision ?? 0;
        sourceRef.current = nextSource;
        revisionRef.current = nextRevision;
        setSource(nextSource);
        setSourceRevision(nextRevision);
        setDiagnostics(authoring.diagnostics ?? []);
        editor.commands.setContent(authoring.document ?? sourceToDocument(nextSource));
        setAuthoringReady(true);
      })
      .catch(() => {
        loadedDraftRef.current = null;
        setAuthoringReady(false);
        setSaveStatus("error");
      });
  }, [draftId, editor, tokens?.access_token]);

  useEffect(() => {
    if (!tokens?.access_token || !source.trim()) return;

    const requestId = ++parseRequestRef.current;
    const timer = window.setTimeout(() => {
      setParsing(true);
      parseWorkoutDsl(tokens.access_token, source)
        .then((result) => {
          if (requestId !== parseRequestRef.current) return;
          setPreview(result);
          setDiagnostics(result.diagnostics ?? []);
          setParsing(false);
        })
        .catch((error: unknown) => {
          if (requestId !== parseRequestRef.current) return;
          setPreview(null);
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

  const saveDraftSnapshot = useCallback(
    async (snapshot: string, document: JSONContent | null, expectedRevision: number) => {
      if (!accessToken || !draftId) throw new Error();
      setSaveStatus("saving");

      try {
        const draft = await updateDraftWorkout(accessToken, draftId, {
          draft_data: {
            authoring_mode: "quick_text",
            dsl_version: 1,
            dsl_source: snapshot,
            dsl_document: document,
          },
          authoring_mode: "quick_text",
          dsl_version: 1,
          dsl_source: snapshot,
          dsl_document: document,
          last_dsl_diagnostics: diagnostics,
          expected_source_revision: expectedRevision,
        });
        const nextRevision = draft.dsl_source_revision ?? expectedRevision + 1;
        revisionRef.current = nextRevision;
        setSourceRevision(nextRevision);
        setSaveStatus("saved");
        return nextRevision;
      } catch (error) {
        if (error instanceof ApiError && error.payload.code === "stale_dsl_revision") {
          setSaveStatus("conflict");
        } else {
          setSaveStatus("error");
        }
        throw error;
      }
    },
    [accessToken, diagnostics, draftId],
  );

  useEffect(() => {
    if (!draftId || loadedDraftRef.current !== draftId || !editor) return;

    const snapshot = source;
    const document = editor.getJSON();
    const expectedRevision = revisionRef.current;
    const timer = window.setTimeout(() => {
      void saveDraftSnapshot(snapshot, document, expectedRevision).catch(() => undefined);
    }, 1_200);

    return () => window.clearTimeout(timer);
  }, [draftId, editor, saveDraftSnapshot, source]);

  useEffect(() => {
    updateSuggestions();
  }, [source, updateSuggestions]);

  const statusLabel = useMemo(() => {
    if (parsing) return i18n("quickTextParsing");
    if (errors.length > 0) return i18n("quickTextInvalid");
    if (warnings.length > 0) return i18n("quickTextWarnings");
    if (preview) return i18n("quickTextReady");
    return "";
  }, [errors.length, i18n, parsing, preview, warnings.length]);

  function acceptSuggestion(suggestion: WorkoutDslSuggestion) {
    if (!editor) return;
    const beforeCursor = editor.state.doc.textBetween(0, editor.state.selection.from, "\n");
    const currentLine = beforeCursor.slice(beforeCursor.lastIndexOf("\n") + 1);
    const slashQuery = currentLine.match(/^\s*\/([a-z0-9_-]*)$/i)?.[1];
    const query =
      slashQuery ??
      currentLine.match(/^\s*\[section:\s*([a-z0-9_-]*)$/i)?.[1] ??
      currentLine.match(/^\s*\[exercise:\s*([^\]]*)$/i)?.[1] ??
      currentLine.match(/^\s*(![a-z-]*)$/i)?.[1] ??
      currentLine.match(/([a-z][a-z0-9-]*)$/i)?.[1] ??
      "";
    const to = editor.state.selection.from;
    const slashOffset = slashQuery === undefined ? 0 : 1;
    const replacement =
      suggestion.kind === "template"
        ? manual?.templates?.sections?.[suggestion.value] ?? suggestion.value
        : suggestion.value;

    editor
      .chain()
      .focus()
      .deleteRange({ from: Math.max(1, to - query.length - slashOffset), to })
      .insertContent(replacement)
      .run();
    setSuggestions([]);
  }

  function insertTemplate(template: string) {
    if (!editor || !template) return;
    editor.chain().focus().insertContent(`${template.trim()}\n`).run();
  }

  function beautify() {
    if (!editor || !preview || errors.length > 0) return;
    const formatted = preview.formatted_source.trimEnd();
    sourceRef.current = formatted;
    setSource(formatted);
    editor.commands.setContent(sourceToDocument(formatted));
  }

  async function switchToStructured() {
    if (!tokens?.access_token || !draftId || !preview || errors.length > 0) return;

    try {
      const snapshot = sourceRef.current;
      await updateDraftWorkout(tokens.access_token, draftId, {
        ...preview.workout,
        authoring_mode: "structured",
        dsl_version: preview.version,
        dsl_source: snapshot,
        dsl_document: editor?.getJSON() ?? null,
        expected_source_revision: revisionRef.current,
      });
      setSaveStatus("saved");
      onSwitchToStructured(draftId);
    } catch (error) {
      setSaveStatus(
        error instanceof ApiError && error.payload.code === "stale_dsl_revision"
          ? "conflict"
          : "error",
      );
    }
  }

  async function publish() {
    if (
      !tokens?.access_token ||
      !draftId ||
      !editor ||
      !preview ||
      errors.length > 0 ||
      (warnings.length > 0 && !warningsAcknowledged)
    ) {
      return;
    }

    const snapshot = sourceRef.current;
    const document = editor.getJSON();
    setPublishing(true);

    try {
      const revision = await saveDraftSnapshot(snapshot, document, revisionRef.current);
      if (sourceRef.current !== snapshot) {
        setSaveStatus("error");
        return;
      }

      await publishWorkoutDsl(tokens.access_token, draftId, {
        source: snapshot,
        document,
        expected_source_revision: revision,
        acknowledge_warnings: warningsAcknowledged,
      });
      router.push("/admin/workouts");
    } catch (error) {
      if (
        error instanceof ApiError &&
        error.payload.code === "dsl_warnings_require_acknowledgement"
      ) {
        setDiagnostics(error.payload.diagnostics ?? []);
        setWarningsAcknowledged(false);
      }
    } finally {
      setPublishing(false);
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
            <div className="text-end text-xs font-semibold" style={{ color: "var(--muted)" }}>
              <div>{saveStatusText(saveStatus, i18n)}</div>
              <div aria-live="polite">{statusLabel}</div>
              <div>{i18n("quickTextRevision", { revision: sourceRevision })}</div>
            </div>
          </div>
        </div>

        <EditorToolbar editor={editor} />
        <div
          className="flex flex-wrap items-center gap-2 border-b px-4 py-2"
          style={{ borderColor: "var(--dim)" }}
        >
          <select
            aria-label={i18n("quickTextTemplate")}
            defaultValue=""
            onChange={(event) => {
              insertTemplate(
                event.target.value === "workout"
                  ? manual?.templates?.workout ?? ""
                  : manual?.templates?.sections?.[event.target.value] ?? "",
              );
              event.currentTarget.value = "";
            }}
            className="rounded-lg border px-3 py-2 text-sm"
            style={{ background: "var(--card)", borderColor: "var(--dim)", color: "var(--text)" }}
          >
            <option value="">{i18n("quickTextInsertTemplate")}</option>
            <option value="workout">{i18n("quickTextFullWorkoutTemplate")}</option>
            {Object.keys(manual?.templates?.sections ?? {}).map((format) => (
              <option key={format} value={format}>
                {format.replaceAll("_", " ")}
              </option>
            ))}
          </select>
          <button
            type="button"
            onClick={() => setManualOpen(true)}
            className="rounded-lg px-3 py-2 text-sm font-bold"
            style={{ background: "var(--card)", color: "var(--text)" }}
          >
            {i18n("quickTextManual")}
          </button>
          <span className="text-xs" style={{ color: "var(--muted)" }}>
            {i18n("quickTextSlashHint")}
          </span>
        </div>

        <div className="relative min-h-0 flex-1 overflow-auto">
          <EditorContent editor={editor} />
          {suggestions.length > 0 ? (
            <SuggestionMenu suggestions={suggestions} onAccept={acceptSuggestion} />
          ) : null}
        </div>

        <div
          className="flex flex-wrap items-center justify-between gap-3 border-t px-5 py-3"
          style={{ borderColor: "var(--dim)" }}
        >
          <span className="text-xs" style={{ color: "var(--muted)" }}>
            {i18n("quickTextCharacterCount", {
              count: editor?.storage.characterCount.characters() ?? 0,
            })}
          </span>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={!preview || errors.length > 0}
              onClick={beautify}
              className="rounded-xl px-4 py-2 text-sm font-bold disabled:opacity-40"
              style={{ background: "var(--card)", color: "var(--text)" }}
            >
              {i18n("quickTextBeautify")}
            </button>
            <button
              type="button"
              disabled={!preview || errors.length > 0}
              onClick={switchToStructured}
              className="rounded-xl px-4 py-2 text-sm font-bold disabled:opacity-40"
              style={{ background: "var(--card)", color: "var(--text)" }}
            >
              {i18n("quickTextSwitchStructured")}
            </button>
            <button
              type="button"
              disabled={
                publishing ||
                !preview ||
                errors.length > 0 ||
                saveStatus === "conflict" ||
                (warnings.length > 0 && !warningsAcknowledged)
              }
              onClick={publish}
              className="rounded-xl px-5 py-2 text-sm font-black disabled:opacity-40"
              style={{ background: "var(--primary)", color: "var(--primary-foreground, white)" }}
            >
              {publishing ? i18n("quickTextPublishing") : i18n("quickTextPublish")}
            </button>
          </div>
        </div>
      </section>

      <aside className="min-h-0 overflow-auto p-5" style={{ background: "var(--panel)" }}>
        {diagnostics.length > 0 ? (
          <>
            <DiagnosticsPanel diagnostics={diagnostics} />
            {warnings.length > 0 && errors.length === 0 ? (
              <label className="mt-4 flex items-start gap-2 text-sm" style={{ color: "var(--text)" }}>
                <input
                  type="checkbox"
                  checked={warningsAcknowledged}
                  onChange={(event) => setWarningsAcknowledged(event.target.checked)}
                />
                {i18n("quickTextAcknowledgeWarnings")}
              </label>
            ) : null}
          </>
        ) : (
          <CanonicalPreview preview={preview} />
        )}
      </aside>

      {manualOpen && manual ? (
        <ManualDialog markdown={manual.markdown} onClose={() => setManualOpen(false)} />
      ) : null}
    </div>
  );
}

function EditorToolbar({ editor }: { editor: Editor | null }) {
  const i18n = useUiTranslations();
  if (!editor) return null;

  const actions = [
    button(i18n("editorBold"), i18n("editorBold"), editor.isActive("bold"), () => editor.chain().focus().toggleBold().run()),
    button(i18n("editorItalic"), i18n("editorItalic"), editor.isActive("italic"), () => editor.chain().focus().toggleItalic().run()),
    button(i18n("editorUnderline"), i18n("editorUnderline"), editor.isActive("underline"), () => editor.chain().focus().toggleUnderline().run()),
    button(i18n("editorStrike"), i18n("editorStrike"), editor.isActive("strike"), () => editor.chain().focus().toggleStrike().run()),
    button(i18n("editorHighlight"), "▰", editor.isActive("highlight"), () => editor.chain().focus().toggleHighlight().run()),
    button(i18n("editorHeading"), i18n("editorHeading"), editor.isActive("heading", { level: 2 }), () => editor.chain().focus().toggleHeading({ level: 2 }).run()),
    button(i18n("editorBulletList"), "•", editor.isActive("bulletList"), () => editor.chain().focus().toggleBulletList().run()),
    button(i18n("editorOrderedList"), "1.", editor.isActive("orderedList"), () => editor.chain().focus().toggleOrderedList().run()),
    button(i18n("editorQuote"), "❝", editor.isActive("blockquote"), () => editor.chain().focus().toggleBlockquote().run()),
    button(i18n("editorCode"), "</>", editor.isActive("codeBlock"), () => editor.chain().focus().toggleCodeBlock().run()),
    button(i18n("editorAlignLeft"), "⇤", editor.isActive({ textAlign: "left" }), () => editor.chain().focus().setTextAlign("left").run()),
    button(i18n("editorAlignCenter"), "↔", editor.isActive({ textAlign: "center" }), () => editor.chain().focus().setTextAlign("center").run()),
    button(i18n("editorAlignRight"), "⇥", editor.isActive({ textAlign: "right" }), () => editor.chain().focus().setTextAlign("right").run()),
    button(i18n("editorLink"), "🔗", editor.isActive("link"), () => setEditorLink(editor, i18n("editorLinkPrompt"))),
    button(i18n("editorUndo"), "↶", false, () => editor.chain().focus().undo().run()),
    button(i18n("editorRedo"), "↷", false, () => editor.chain().focus().redo().run()),
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

function SuggestionMenu({
  suggestions,
  onAccept,
}: {
  suggestions: WorkoutDslSuggestion[];
  onAccept: (suggestion: WorkoutDslSuggestion) => void;
}) {
  const i18n = useUiTranslations();

  return (
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
          onClick={() => onAccept(suggestion)}
          className="flex w-full items-center justify-between px-3 py-2 text-start text-sm hover:opacity-80"
          style={{ color: "var(--text)" }}
        >
          <span>{suggestion.value}</span>
          <span className="text-[10px] uppercase" style={{ color: "var(--muted)" }}>
            {suggestion.kind}
          </span>
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
        {diagnostics.map((diagnostic, index) => {
          const danger = diagnostic.severity === "error";
          const color = danger ? "var(--danger)" : "var(--warning, #b7791f)";

          return (
            <div
              key={`${diagnostic.code}:${diagnostic.line}:${index}`}
              className="rounded-xl border px-3 py-2"
              style={{ borderColor: color }}
            >
              <div className="text-sm font-bold" style={{ color }}>
                {i18n("quickTextDiagnosticPosition", {
                  line: diagnostic.line,
                  column: diagnostic.column,
                })}
              </div>
              <div className="mt-1 font-mono text-xs" style={{ color: "var(--text)" }}>
                {diagnostic.code}
              </div>
              {Object.keys(diagnostic.params).length > 0 ? (
                <div className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
                  {formatDiagnosticParams(diagnostic.params)}
                </div>
              ) : null}
            </div>
          );
        })}
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
                            · {String(exercise.sets ?? 1)} ×{" "}
                            {String(exercise.prescription_value ?? "")}
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

function ManualDialog({ markdown, onClose }: { markdown: string; onClose: () => void }) {
  const i18n = useUiTranslations();

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/55 p-4" role="presentation">
      <section
        role="dialog"
        aria-modal="true"
        aria-label={i18n("quickTextManual")}
        className="flex max-h-[90dvh] w-full max-w-4xl flex-col rounded-2xl shadow-2xl"
        style={{ background: "var(--panel)" }}
      >
        <header className="flex items-center justify-between border-b p-4" style={{ borderColor: "var(--dim)" }}>
          <h2 className="text-lg font-black" style={{ color: "var(--text)" }}>
            {i18n("quickTextManual")}
          </h2>
          <button type="button" onClick={onClose} className="rounded-lg px-3 py-2" style={{ color: "var(--text)" }}>
            {i18n("quickTextCloseManual")}
          </button>
        </header>
        <pre
          className="min-h-0 flex-1 overflow-auto whitespace-pre-wrap p-5 font-sans text-sm leading-6"
          style={{ color: "var(--text)" }}
        >
          {markdown}
        </pre>
      </section>
    </div>
  );
}

function button(label: string, text: string, active: boolean, run: () => unknown) {
  return { label, text, active, run };
}

function setEditorLink(editor: Editor, promptLabel: string) {
  const previous = editor.getAttributes("link").href as string | undefined;
  const url = window.prompt(promptLabel, previous ?? "");
  if (url === null) return;
  if (url.trim() === "") {
    editor.chain().focus().extendMarkRange("link").unsetLink().run();
    return;
  }
  if (!/^(https?:|mailto:)/i.test(url.trim())) return;
  editor.chain().focus().extendMarkRange("link").setLink({ href: url.trim() }).run();
}

function saveStatusText(status: SaveStatus, i18n: ReturnType<typeof useUiTranslations>) {
  switch (status) {
    case "saving":
      return i18n("quickTextSaving");
    case "saved":
      return i18n("quickTextSaved");
    case "error":
      return i18n("quickTextSaveError");
    case "conflict":
      return i18n("quickTextRevisionConflict");
    case "idle":
      return "";
  }
}

function sourceToDocument(source: string): JSONContent {
  return {
    type: "doc",
    content: source.split("\n").map((line) => ({
      type: "paragraph",
      content: line ? [{ type: "text", text: line }] : undefined,
    })),
  };
}

function formatDiagnosticParams(params: Record<string, unknown>) {
  return Object.entries(params)
    .map(([key, value]) => `${key}: ${Array.isArray(value) ? value.join(", ") : String(value)}`)
    .join(" · ");
}
