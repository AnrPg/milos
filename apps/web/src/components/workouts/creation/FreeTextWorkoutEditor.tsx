"use client";

import CharacterCount from "@tiptap/extension-character-count";
import Highlight from "@tiptap/extension-highlight";
import Link from "@tiptap/extension-link";
import Placeholder from "@tiptap/extension-placeholder";
import TextAlign from "@tiptap/extension-text-align";
import Typography from "@tiptap/extension-typography";
import Underline from "@tiptap/extension-underline";
import { Extension, Mark, mergeAttributes } from "@tiptap/core";
import type { ResolvedPos } from "@tiptap/pm/model";
import { Plugin } from "@tiptap/pm/state";
import { EditorContent, useEditor, type Editor, type JSONContent } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { ApiError } from "@/api/client";
import {
  analyzeFreeTextWorkout,
  createDraftWorkout,
  fetchAdminWorkout,
  publishWorkoutDraft,
  updateDraftWorkout,
} from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import {
  acceptIssue,
  addSuggestion,
  blockingProblems,
  createReviewState,
  dismissSuggestion,
  isTextCorrection,
  openIssues,
  publishFields,
  rejectIssue,
  replaceFirst,
  undoIssue,
  type AnalysisIssue,
  type AnalysisSuggestion,
  type ReviewState,
} from "@/lib/free-text-analysis";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { FREE_TEXT_EDITOR_CLASS, sanitizeWorkoutDslPaste } from "@/lib/workout-dsl-editor-data";
import {
  FREE_TEXT_TIMER_METADATA_KEY,
  type FreeTextTimerPreset,
  parseFreeTextTimerPreset,
} from "@/lib/free-text-timer";
import { getFormatLabels, type WorkoutType } from "@/types/workout";

import { WodGoalsEditorPanel } from "@/components/wod-goals/WodGoalsEditorPanel";

import { editorSectionsFrom, SECTIONED_TEXT_MODE, sectionsToFreeText } from "@/lib/text-sections";

import { AssistantSwitch } from "./AssistantSwitch";
import { EditorTabs } from "./EditorTabs";
import { FreeTextTimerFields } from "./FreeTextTimerFields";

import { FreeTextAnalysisPanel, type AnalysisStatus } from "./FreeTextAnalysisPanel";
import { readToken } from "@/lib/theme";

type Props = {
  draftId: string | null;
  folderId?: string | null;
  onDraftReady: (id: string) => void;
  /** ADR-179: switch this workout off the assistant, to text sections (the draft is saved first). */
  onUseSections?: () => void;
};

type SaveStatus = "idle" | "saving" | "saved" | "error";
type AsideTab = "assistant" | "preview";
type EditorTabKey = "details" | "timer" | "goals" | "tools";

const WORKOUT_TYPES: WorkoutType[] = [
  "crossfit",
  "strength",
  "gymnastics",
  "aerobics",
  "flexibility",
  "recovery",
];

export function FreeTextWorkoutEditor({ draftId, folderId = null, onDraftReady, onUseSections }: Props) {
  const i18n = useUiTranslations();
  const assistantT = useTranslations("WorkoutAssistant");
  const goalsT = useTranslations("WodGoals");
  const locale = useUiLocale();
  const router = useRouter();
  const organizationSlug = useOrganizationSlug();
  const { tokens } = useSession();
  const accessToken = tokens?.access_token;
  const [title, setTitle] = useState("");
  const [type, setType] = useState<WorkoutType | "">("");
  const [body, setBody] = useState("");
  const [html, setHtml] = useState("");
  const [saveStatus, setSaveStatus] = useState<SaveStatus>("idle");
  /** Counts draft autosaves; the goals panel re-reads its suggestion on each. */
  const [draftSaves, setDraftSaves] = useState(0);
  const [publishing, setPublishing] = useState(false);
  const [previewOpen, setPreviewOpen] = useState(true);
  const [asideTab, setAsideTab] = useState<AsideTab>("assistant");
  const [review, setReview] = useState<ReviewState | null>(null);
  const [analysisStatus, setAnalysisStatus] = useState<AnalysisStatus>("idle");
  const [analysisError, setAnalysisError] = useState<string | null>(null);
  const [showBlocking, setShowBlocking] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  /** The settings tab that is open over the text (none: all the room for writing). */
  const [openTab, setOpenTab] = useState<EditorTabKey | null>("details");
  /** Optional timer the athlete gets pre-selected; kept in `workout_metadata`. */
  const [timerPreset, setTimerPreset] = useState<FreeTextTimerPreset | null>(null);
  const metadataRef = useRef<Record<string, unknown>>({});
  const formatLabels = useMemo(() => getFormatLabels(i18n), [i18n]);
  const loadedDraftRef = useRef<string | null>(null);
  const revisionRef = useRef<number | null>(null);

  const editor = useEditor({
    extensions: [
      StarterKit.configure({ link: false, underline: false }),
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
      TextColorMark,
      Placeholder.configure({ placeholder: i18n("freeTextEditorPlaceholder") }),
      CharacterCount.configure({ limit: 200_000 }),
      FreeTextEditingAssist,
    ],
    content: emptyDocument(),
    immediatelyRender: false,
    editorProps: {
      attributes: {
        class: FREE_TEXT_EDITOR_CLASS,
        spellcheck: "true",
        role: "textbox",
        "aria-label": i18n("freeTextEditorLabel"),
      },
      transformPastedHTML: sanitizeWorkoutDslPaste,
    },
    onUpdate: ({ editor: currentEditor }) => {
      setBody(currentEditor.getText({ blockSeparator: "\n" }));
      setHtml(currentEditor.getHTML());
    },
  });

  useEffect(() => {
    if (!accessToken || draftId || loadedDraftRef.current === "creating") return;

    loadedDraftRef.current = "creating";
    createDraftWorkout(accessToken, folderId)
      .then((draft) => {
        revisionRef.current = draft.dsl_source_revision ?? 0;
        onDraftReady(draft.id);
      })
      .catch(() => {
        loadedDraftRef.current = null;
        setSaveStatus("error");
      });
  }, [accessToken, draftId, folderId, onDraftReady]);

  useEffect(() => {
    if (!accessToken || !draftId || loadedDraftRef.current === draftId || !editor) return;

    loadedDraftRef.current = draftId;
    fetchAdminWorkout(accessToken, draftId)
      .then((workout) => {
        setTitle(workout.title ?? "");
        if (WORKOUT_TYPES.includes(workout.type as WorkoutType)) {
          setType(workout.type as WorkoutType);
        }
        const storedReview = (workout.draft_data as { free_text_review?: ReviewState } | null)?.free_text_review;
        if (storedReview?.analysis && storedReview.workout) {
          setReview(storedReview);
          setAnalysisStatus("ready");
        }
        metadataRef.current = workout.workout_metadata ?? {};
        setTimerPreset(parseFreeTextTimerPreset(metadataRef.current[FREE_TEXT_TIMER_METADATA_KEY]));
        revisionRef.current = workout.dsl_source_revision ?? 0;
        // ADR-179: a workout written in sections comes back as one text, a
        // heading per titled section; the assistant reads its timers from it.
        const fromSections =
          workout.authoring_mode === SECTIONED_TEXT_MODE ? sectionsToFreeText(editorSectionsFrom(workout, null)) : null;
        const nextBody = fromSections?.body ?? workout.free_text_body ?? "";
        setBody(nextBody);
        editor.commands.setContent(fromSections?.document ?? workout.free_text_document ?? textToDocument(nextBody));
        setHtml(editor.getHTML());
      })
      .catch(() => {
        loadedDraftRef.current = null;
        setSaveStatus("error");
      });
  }, [accessToken, draftId, editor]);

  const saveDraft = useCallback(async () => {
    if (!accessToken || !draftId || !editor) return;
    setSaveStatus("saving");

    try {
      const draft = await updateDraftWorkout(accessToken, draftId, buildPayload({
        title,
        type,
        body,
        document: editor.getJSON(),
        expectedSourceRevision: revisionRef.current,
        review,
        metadata: withTimerPreset(metadataRef.current, timerPreset),
      }));
      revisionRef.current = draft.dsl_source_revision ?? revisionRef.current;
      setSaveStatus("saved");
      setDraftSaves((count) => count + 1);
    } catch {
      setSaveStatus("error");
    }
  }, [accessToken, body, draftId, editor, review, timerPreset, title, type]);

  useEffect(() => {
    if (!draftId || loadedDraftRef.current !== draftId) return;
    const timer = window.setTimeout(() => {
      void saveDraft();
    }, 1_000);
    return () => window.clearTimeout(timer);
  }, [body, draftId, review, saveDraft, timerPreset, title, type]);

  const stale = Boolean(review && review.analyzedText.trim() !== body.trim());
  const blocking = blockingProblems(title, type, review);
  const canPublish = Boolean(accessToken && draftId && editor && body.trim() && !publishing && analysisStatus !== "loading");

  async function analyze(): Promise<ReviewState | null> {
    if (!accessToken || !body.trim()) return null;
    setAnalysisStatus("loading");
    setAnalysisError(null);
    setNotice(null);
    setAsideTab("assistant");
    setPreviewOpen(true);

    try {
      const analyzedText = body.trim();
      const analysis = await analyzeFreeTextWorkout(accessToken, analyzedText, locale);
      const next = createReviewState(analysis, analyzedText);
      const proposed = next.workout;
      // The coach's own title and type win; the assistant only fills blanks.
      if (!title.trim() && proposed.title) setTitle(proposed.title);
      if (!type && proposed.type && WORKOUT_TYPES.includes(proposed.type as WorkoutType)) setType(proposed.type as WorkoutType);
      setReview(next);
      setAnalysisStatus("ready");
      return next;
    } catch (error) {
      setAnalysisStatus("error");
      setAnalysisError(error instanceof ApiError ? error.payload?.code ?? "analyzer_unavailable" : "analyzer_unavailable");
      return null;
    }
  }

  function syncWorkoutField(path: string, value: unknown) {
    if (path === "title") setTitle(typeof value === "string" ? value : "");
    if (path === "type") setType(typeof value === "string" && WORKOUT_TYPES.includes(value as WorkoutType) ? (value as WorkoutType) : "");
  }

  function applyTextEdit(state: ReviewState, find: string, replace: string): ReviewState {
    if (!editor || !replaceInEditor(editor, find, replace)) return state;
    const analyzedText = replaceFirst(state.analyzedText, find, replace) ?? state.analyzedText;
    return { ...state, analyzedText };
  }

  function handleAccept(issue: AnalysisIssue, value?: unknown) {
    if (!review) return;
    const edit = issue.suggestion?.text_edit;
    let next = review;

    if (edit && value === undefined) {
      const edited = applyTextEdit(review, edit.find, edit.replace);
      // The words were already changed by hand or by another fix: say so
      // instead of silently doing nothing. A text-only fix stays open.
      if (edited === review) {
        setNotice(assistantT("editNotApplied", { text: edit.find }));
        if (isTextCorrection(issue) && issue.path === "text") return;
      }
      next = edited;
    }

    next = acceptIssue(next, issue, value);
    syncWorkoutField(issue.path, value !== undefined ? value : issue.suggestion?.value);
    setReview(next);
    setShowBlocking(false);
  }

  function handleReject(issue: AnalysisIssue) {
    if (!review) return;
    setReview(rejectIssue(review, issue));
    // Rejecting a wording suggestion keeps the coach's text and fields.
    if (isTextCorrection(issue)) return;
    syncWorkoutField(issue.path, null);
    if (issue.required) setShowBlocking(true);
  }

  function handleUndo(issue: AnalysisIssue) {
    if (!review) return;
    const next = undoIssue(review, issue);
    setReview(next);
    if (issue.path === "title" || issue.path === "type") syncWorkoutField(issue.path, next.workout[issue.path]);
  }

  function handleAddSuggestion(suggestion: AnalysisSuggestion, value: unknown, alsoInText: boolean) {
    if (!review) return;
    let next = addSuggestion(review, suggestion, value);
    if (alsoInText && suggestion.text_insert && editor) {
      editor.chain().insertContentAt(editor.state.doc.content.size, { type: "paragraph", content: [{ type: "text", text: suggestion.text_insert }] }).run();
      next = { ...next, analyzedText: `${next.analyzedText}\n${suggestion.text_insert}` };
    }
    setReview(next);
  }

  function handleInsertExample() {
    if (!editor) return;
    editor.commands.setContent(textToDocument(assistantT("exampleWorkout")));
    setBody(editor.getText({ blockSeparator: "\n" }));
    setHtml(editor.getHTML());
    editor.commands.focus("end");
  }

  async function publish() {
    if (!accessToken || !draftId || !editor || !body.trim()) return;
    setNotice(null);

    let current = review;
    let freshlyAnalyzed = false;
    if (!current || stale) {
      current = await analyze();
      freshlyAnalyzed = current !== null;
    }

    const effectiveTitle = title.trim() || current?.workout.title || "";
    const proposedType = current?.workout.type ?? "";
    const effectiveType = type || (WORKOUT_TYPES.includes(proposedType as WorkoutType) ? (proposedType as WorkoutType) : "");
    const problems = blockingProblems(effectiveTitle, effectiveType, current);

    if (problems.length > 0) {
      setShowBlocking(true);
      setAsideTab("assistant");
      return;
    }

    // A fresh check that raised notes gets reviewed before anything is created.
    if (freshlyAnalyzed && current && openIssues(current).length > 0) {
      setNotice(assistantT("reviewBeforePublish"));
      return;
    }

    if (current && openIssues(current).some((issue) => issue.severity === "error")) {
      setNotice(assistantT("resolveErrorsFirst"));
      return;
    }

    setPublishing(true);
    try {
      const payload = buildPayload({
        title: effectiveTitle,
        type: effectiveType,
        body,
        document: editor.getJSON(),
        expectedSourceRevision: revisionRef.current,
        review: current,
        metadata: withTimerPreset(metadataRef.current, timerPreset),
      });
      const draft = await updateDraftWorkout(accessToken, draftId, payload);
      revisionRef.current = draft.dsl_source_revision ?? revisionRef.current;
      await publishWorkoutDraft(accessToken, draftId, {
        ...payload,
        expected_source_revision: revisionRef.current,
      });
      router.push(adminHref("/admin/workouts", organizationSlug));
    } catch {
      setSaveStatus("error");
      setNotice(assistantT("publishFailed"));
    } finally {
      setPublishing(false);
    }
  }

  return (
    <div className={previewOpen ? "grid min-h-[calc(100dvh-6.5rem)] min-w-0 grid-cols-1 overflow-x-clip lg:grid-cols-[minmax(0,1fr)_26rem]" : "grid min-h-[calc(100dvh-6.5rem)] min-w-0 grid-cols-1 overflow-x-clip lg:grid-cols-[minmax(0,1fr)_4rem]"}>
      <section className="flex min-h-0 min-w-0 flex-col border-e" style={{ borderColor: "var(--dim)" }}>
        <EditorTabs
          label={i18n("workoutEditorTabsLabel")}
          tabs={[
            { key: "details", icon: "📝", label: i18n("workoutDetails9366821") },
            { key: "timer", icon: "⏱️", label: i18n("freeTextTimerRibbonLabel") },
            { key: "goals", icon: "🎯", label: goalsT("title") },
            { key: "tools", icon: "🔤", label: i18n("editorFormatting") },
          ]}
          active={openTab}
          onSelect={setOpenTab}
          trailing={
            <>
              <span className="hidden text-xs font-semibold sm:inline" role="status" style={{ color: "var(--muted)" }}>
                {saveStatusText(saveStatus, i18n)}
              </span>
              {onUseSections ? (
                <AssistantSwitch
                  enabled
                  available
                  onChange={(enabled) => {
                    if (enabled) return;
                    void saveDraft().then(onUseSections);
                  }}
                />
              ) : null}
            </>
          }
        >
          {openTab === "details" ? (
            <div className="grid gap-3 p-4 md:grid-cols-[minmax(0,1fr)_12rem]">
              <label className="block">
                <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("title768e0c1")}
                </span>
                <input
                  className="mt-1 w-full rounded-xl border px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--card)", borderColor: "var(--dim)", color: "var(--text)" }}
                  value={title}
                  onChange={(event) => setTitle(event.target.value)}
                  maxLength={160}
                  placeholder={assistantT("titlePlaceholder")}
                  aria-invalid={showBlocking && title.trim().length < 3}
                />
              </label>
              <label className="block">
                <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("workoutType34a530c")}
                </span>
                <select
                  className="mt-1 w-full rounded-xl border px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--card)", borderColor: "var(--dim)", color: "var(--text)" }}
                  value={type}
                  onChange={(event) => setType(event.target.value as WorkoutType)}
                  aria-invalid={showBlocking && !type}
                >
                  <option value="" disabled>
                    {assistantT("chooseType")}
                  </option>
                  {WORKOUT_TYPES.map((item) => (
                    <option key={item} value={item}>
                      {item.replaceAll("_", " ")}
                    </option>
                  ))}
                </select>
              </label>
            </div>
          ) : null}
          {openTab === "timer" ? (
            <div className="p-4">
              <label className="flex items-center gap-2 text-sm font-semibold" style={{ color: "var(--text)" }}>
                <input
                  type="checkbox"
                  checked={timerPreset !== null}
                  onChange={(event) =>
                    setTimerPreset(event.target.checked ? { format: "for_time", duration_seconds: 720 } : null)
                  }
                />
                {i18n("attachTimerLabel")}
              </label>
              <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
                {i18n("attachTimerHint")}
              </p>
              {timerPreset ? (
                <FreeTextTimerFields preset={timerPreset} formatLabels={formatLabels} onChange={setTimerPreset} />
              ) : null}
            </div>
          ) : null}
          {openTab === "goals" ? (
            <div className="max-h-[55vh] overflow-y-auto">
              <WodGoalsEditorPanel
                workoutId={draftId}
                refreshKey={draftSaves}
                timeDomainSeconds={timerPreset?.duration_seconds ?? null}
              />
            </div>
          ) : null}
          {openTab === "tools" ? <FreeTextToolbar editor={editor} /> : null}
        </EditorTabs>

        <div className="min-h-0 min-w-0 flex-1 overflow-auto overflow-x-clip">
          <EditorContent editor={editor} />
        </div>

        <footer className="flex flex-wrap items-center justify-between gap-3 border-t px-4 py-3 sm:px-5" style={{ borderColor: "var(--dim)" }}>
          <span className="text-xs" style={{ color: "var(--muted)" }}>
            {i18n("quickTextCharacterCount", { count: editor?.storage.characterCount.characters() ?? 0 })}
          </span>
          <button
            type="button"
            disabled={!canPublish}
            onClick={() => void publish()}
            className="min-w-0 rounded-xl px-5 py-2 text-sm font-black disabled:opacity-40"
            style={{ background: "var(--success, var(--primary))", color: "var(--bg)", boxShadow: "0 10px 24px color-mix(in srgb, var(--primary) 22%, transparent)" }}
          >
            {publishing
              ? i18n("quickTextPublishing")
              : analysisStatus === "loading"
                ? assistantT("analyzing")
                : !review || stale
                  ? assistantT("checkAndPublish")
                  : i18n("quickTextPublish")}
          </button>
        </footer>
      </section>

      <aside className="min-h-0 min-w-0 overflow-auto overflow-x-clip p-4" style={{ background: "var(--panel)" }}>
        <div className="flex items-center justify-between gap-3">
          {previewOpen ? (
            <div className="flex gap-1 rounded-xl p-1" role="tablist" aria-label={assistantT("panelTabs")} style={{ background: "var(--bg)" }}>
              {(["assistant", "preview"] as const).map((tab) => (
                <button
                  key={tab}
                  type="button"
                  role="tab"
                  aria-selected={asideTab === tab}
                  onClick={() => setAsideTab(tab)}
                  className="rounded-lg px-3 py-1.5 text-xs font-black"
                  style={{
                    background: asideTab === tab ? "var(--card)" : "transparent",
                    color: asideTab === tab ? "var(--text)" : "var(--muted)",
                  }}
                >
                  {tab === "assistant" ? assistantT("tabAssistant") : assistantT("tabPreview")}
                  {tab === "assistant" && review && openIssues(review).length > 0 ? (
                    <span className="ms-1 rounded-full px-1.5 text-[10px]" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                      {openIssues(review).length}
                    </span>
                  ) : null}
                </button>
              ))}
            </div>
          ) : null}
          <button
            type="button"
            className="rounded-lg px-3 py-2 text-xs font-bold"
            style={{ background: "var(--card)", color: "var(--text)", border: "1px solid var(--dim)" }}
            onClick={() => setPreviewOpen((open) => !open)}
            aria-expanded={previewOpen}
          >
            {previewOpen ? i18n("hide34d8b60") : i18n("showd97d1ee")}
          </button>
        </div>
        {previewOpen && asideTab === "assistant" ? (
          <div className="mt-4">
            <FreeTextAnalysisPanel
              review={review}
              status={analysisStatus}
              errorCode={analysisError}
              stale={stale}
              hasText={Boolean(body.trim())}
              blocking={blocking}
              showBlocking={showBlocking}
              notice={notice}
              onAnalyze={() => void analyze()}
              onAccept={handleAccept}
              onReject={handleReject}
              onUndo={handleUndo}
              onAddSuggestion={handleAddSuggestion}
              onDismissSuggestion={(suggestion) => review && setReview(dismissSuggestion(review, suggestion))}
              onInsertExample={handleInsertExample}
            />
          </div>
        ) : null}
        {previewOpen && asideTab === "preview" ? (
          <div className="mt-4 rounded-2xl border p-4" style={{ borderColor: "var(--dim)", background: "var(--card)" }}>
            <div className="text-xl font-black" style={{ color: "var(--text)" }}>
              {title || i18n("untitledWorkout579b8a6")}
            </div>
            {body ? (
              <div
                className="free-text-rich-content mt-4 text-sm leading-6"
                style={{ color: "var(--text)" }}
                dangerouslySetInnerHTML={{ __html: html }}
              />
            ) : (
              <p className="mt-4 text-sm" style={{ color: "var(--muted)" }}>
                {i18n("freeTextPreviewEmpty")}
              </p>
            )}
          </div>
        ) : null}
      </aside>
    </div>
  );
}

function FreeTextToolbar({ editor }: { editor: Editor | null }) {
  const i18n = useUiTranslations();
  if (!editor) return null;

  const headingLevels = [1, 2, 3, 4, 5] as const;
  const selectedTextColor = editor.getAttributes("textColor").color as string | undefined;
  const colorPickerValue = /^#[0-9a-f]{6}$/i.test(selectedTextColor ?? "") ? selectedTextColor! : readToken("text");
  const activeHeadingLevel = headingLevels.find((level) => editor.isActive("heading", { level }));
  const textActions = [
    toolbarButton(i18n("editorBold"), i18n("editorBold"), editor.isActive("bold"), () => editor.chain().focus().toggleBold().run()),
    toolbarButton(i18n("editorItalic"), i18n("editorItalic"), editor.isActive("italic"), () => editor.chain().focus().toggleItalic().run()),
    toolbarButton(i18n("editorUnderline"), i18n("editorUnderline"), editor.isActive("underline"), () => editor.chain().focus().toggleUnderline().run()),
    toolbarButton(i18n("editorStrike"), i18n("editorStrike"), editor.isActive("strike"), () => editor.chain().focus().toggleStrike().run()),
    toolbarButton(i18n("editorHighlight"), i18n("editorHighlight"), editor.isActive("highlight"), () => editor.chain().focus().toggleHighlight().run()),
  ];
  const blockActions = [
    toolbarButton(i18n("editorBulletList"), "•", editor.isActive("bulletList"), () => editor.chain().focus().toggleBulletList().run()),
    toolbarButton(i18n("editorOrderedList"), "1.", editor.isActive("orderedList"), () => editor.chain().focus().toggleOrderedList().run()),
    toolbarButton(i18n("editorQuote"), "“”", editor.isActive("blockquote"), () => editor.chain().focus().toggleBlockquote().run()),
    toolbarButton(i18n("editorCode"), "</>", editor.isActive("codeBlock"), () => editor.chain().focus().toggleCodeBlock().run()),
    toolbarButton(i18n("editorLink"), i18n("editorLink"), editor.isActive("link"), () => setEditorLink(editor, i18n("editorLinkPrompt"))),
  ];
  const layoutActions = [
    toolbarButton(i18n("editorAlignLeft"), i18n("editorAlignLeft"), editor.isActive({ textAlign: "left" }), () => editor.chain().focus().setTextAlign("left").run()),
    toolbarButton(i18n("editorAlignCenter"), i18n("editorAlignCenter"), editor.isActive({ textAlign: "center" }), () => editor.chain().focus().setTextAlign("center").run()),
    toolbarButton(i18n("editorAlignRight"), i18n("editorAlignRight"), editor.isActive({ textAlign: "right" }), () => editor.chain().focus().setTextAlign("right").run()),
  ];
  const historyActions = [
    toolbarButton(i18n("editorUndo"), i18n("editorUndo"), false, () => editor.chain().focus().undo().run()),
    toolbarButton(i18n("editorRedo"), i18n("editorRedo"), false, () => editor.chain().focus().redo().run()),
  ];

  return (
    <div className="min-w-0 px-3 py-2 sm:px-4" style={{ background: "color-mix(in srgb, var(--bg) 96%, transparent)" }}>
      <div
        className="flex min-w-0 flex-wrap items-center gap-1.5 rounded-lg border p-1.5"
        style={{ borderColor: "var(--dim)", background: "var(--card)" }}
      >
        <ToolbarGroup actions={textActions} />
        <div className="h-7 w-px" style={{ background: "var(--dim)" }} aria-hidden="true" />
        <label className="sr-only" htmlFor="free-text-heading-select">
          {i18n("editorHeading")}
        </label>
        <select
          id="free-text-heading-select"
          className="h-8 min-w-0 max-w-full flex-1 rounded-md border px-2 text-sm font-bold outline-none sm:min-w-32 sm:flex-none"
          style={{ background: "var(--bg)", borderColor: "var(--dim)", color: "var(--text)" }}
          aria-label={i18n("editorHeading")}
          value={activeHeadingLevel ? `heading-${activeHeadingLevel}` : "paragraph"}
          onChange={(event) => {
            const value = event.target.value;
            if (value === "paragraph") {
              editor.chain().focus().setParagraph().run();
              return;
            }

            const level = Number(value.replace("heading-", "")) as 1 | 2 | 3 | 4 | 5;
            editor.chain().focus().setHeading({ level }).run();
          }}
        >
          <option value="paragraph">{i18n("editorParagraph")}</option>
          {headingLevels.map((level) => (
            <option key={level} value={`heading-${level}`}>
              {i18n("editorHeading")} {level}
            </option>
          ))}
        </select>
        <ToolbarGroup actions={blockActions} />
        <ToolbarGroup actions={layoutActions} />
        <div
          className="flex flex-wrap items-center gap-1 rounded-md px-1"
          role="group"
          aria-label={i18n("editorTextColor")}
        >
          <label
            className="grid h-8 w-8 cursor-pointer place-items-center rounded-md border"
            style={{ background: "var(--bg)", borderColor: selectedTextColor ? "var(--primary)" : "var(--dim)" }}
            title={i18n("editorTextColor")}
            aria-label={i18n("editorTextColor")}
          >
            <input
              type="color"
              value={colorPickerValue}
              onChange={(event) => {
                const nextColor = normalizeEditorColor(event.target.value);
                if (nextColor) {
                  editor.chain().focus().setMark("textColor", { color: nextColor }).run();
                }
              }}
              className="h-5 w-5 cursor-pointer rounded border-0 bg-transparent p-0"
              aria-label={i18n("editorTextColor")}
              title={i18n("editorTextColor")}
            />
          </label>
          <button
            type="button"
            aria-label={i18n("editorClearTextColor")}
            title={i18n("editorClearTextColor")}
            onClick={() => editor.chain().focus().unsetMark("textColor").run()}
            className="h-8 min-w-8 rounded-md px-2 text-sm font-bold"
            style={{
              background: selectedTextColor ? "var(--primary)" : "transparent",
              color: selectedTextColor ? "var(--primary-contrast)" : "var(--text)",
            }}
          >
            ×
          </button>
        </div>
        <div className="flex sm:ms-auto">
          <ToolbarGroup actions={historyActions} />
        </div>
      </div>
    </div>
  );
}

function ToolbarGroup({ actions }: { actions: ReturnType<typeof toolbarButton>[] }) {
  return (
    <div
      className="flex min-w-0 flex-wrap items-center gap-1"
    >
      {actions.map((action) => (
        <button
          type="button"
          key={action.label}
          aria-label={action.label}
          title={action.label}
          onClick={action.run}
          className="h-8 min-w-8 rounded-md px-2 text-sm font-bold"
          style={{
            background: action.active ? "var(--primary)" : "transparent",
            color: action.active ? "var(--primary-contrast)" : "var(--text)",
          }}
        >
          {action.text}
        </button>
      ))}
    </div>
  );
}

const TextColorMark = Mark.create({
  name: "textColor",

  addAttributes() {
    return {
      color: {
        default: null,
        parseHTML: (element) => normalizeEditorColor(element.style.color),
        renderHTML: (attributes) => {
          const color = normalizeEditorColor(attributes.color);
          return color ? { style: `color: ${color}` } : {};
        },
      },
    };
  },

  parseHTML() {
    return [{ tag: "span[style]" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["span", mergeAttributes(HTMLAttributes), 0];
  },
});

const FreeTextEditingAssist = Extension.create({
  name: "freeTextEditingAssist",

  addKeyboardShortcuts() {
    return {
      "Shift-Enter": () => this.editor.commands.setHardBreak(),
    };
  },

  addProseMirrorPlugins() {
    return [
      new Plugin({
        props: {
          handleDOMEvents: {
            mousedown: (view, event) => {
              if (!(event.ctrlKey || event.metaKey) || event.button !== 0) {
                return false;
              }

              const position = view.posAtCoords({
                left: event.clientX,
                top: event.clientY,
              });

              if (!position) return false;

              const wordRange = findWordRangeAt(view.state.doc.resolve(position.pos));
              if (!wordRange) return false;

              event.preventDefault();
              const { state, dispatch } = view;
              const highlight = state.schema.marks.highlight;
              if (!highlight) return false;

              dispatch(
                state.tr
                  .addMark(wordRange.from, wordRange.to, highlight.create({ color: readToken("highlight") }))
                  .setMeta("addToHistory", true),
              );
              return true;
            },
          },
        },
      }),
    ];
  },
});

function findWordRangeAt($pos: ResolvedPos) {
  const parentText = $pos.parent.textContent;
  if (!parentText) return null;

  const offset = Math.min($pos.parentOffset, parentText.length - 1);
  const wordChar = /[\p{L}\p{N}_-]/u;

  let fromOffset = offset;
  while (fromOffset > 0 && wordChar.test(parentText[fromOffset - 1] ?? "")) {
    fromOffset -= 1;
  }

  let toOffset = offset;
  while (toOffset < parentText.length && wordChar.test(parentText[toOffset] ?? "")) {
    toOffset += 1;
  }

  if (fromOffset === toOffset) return null;

  const blockStart = $pos.start();
  return {
    from: blockStart + fromOffset,
    to: blockStart + toOffset,
  };
}

function buildPayload({
  title,
  type,
  body,
  document,
  expectedSourceRevision,
  review,
  metadata,
}: {
  title: string;
  type: WorkoutType | "";
  body: string;
  document: JSONContent;
  expectedSourceRevision?: number | null;
  review: ReviewState | null;
  metadata: Record<string, unknown>;
}) {
  // Canonical fields come from the assistant review the coach accepted; the
  // free text stays the display source of truth (ADR-078, ADR-105).
  const canonical = publishFields(review);
  const workoutType = type || null;
  // The coach's explicit timer preset sits next to the assistant's fresh
  // timer inference (which replaces any inference stored with the draft).
  const workoutMetadata = { ...metadata, ...("workout_metadata" in canonical ? canonical.workout_metadata : {}) };

  return {
    ...canonical,
    title,
    type: workoutType,
    authoring_mode: "free_text",
    free_text_body: body,
    free_text_document: document,
    workout_metadata: workoutMetadata,
    expected_source_revision: expectedSourceRevision,
    draft_data: {
      ...canonical,
      title,
      type: workoutType,
      authoring_mode: "free_text",
      free_text_body: body,
      free_text_document: document,
      workout_metadata: workoutMetadata,
      free_text_review: review,
    },
  };
}

function withTimerPreset(metadata: Record<string, unknown>, preset: FreeTextTimerPreset | null) {
  const rest = { ...metadata };
  delete rest[FREE_TEXT_TIMER_METADATA_KEY];
  return preset ? { ...rest, [FREE_TEXT_TIMER_METADATA_KEY]: preset } : rest;
}

/**
 * Replaces the first verbatim occurrence of `find` inside a single text block,
 * keeping the surrounding formatting. Returns false when the text is absent.
 */
function replaceInEditor(editor: Editor, find: string, replace: string) {
  let range: { from: number; to: number } | null = null;

  editor.state.doc.descendants((node, position) => {
    if (range || !node.isTextblock) return !range;
    let text = "";
    const offsets: number[] = [];
    node.forEach((child, childOffset) => {
      if (!child.isText || !child.text) return;
      for (let index = 0; index < child.text.length; index += 1) {
        offsets.push(position + 1 + childOffset + index);
      }
      text += child.text;
    });
    const index = text.indexOf(find);
    if (index >= 0) {
      range = { from: offsets[index]!, to: offsets[index + find.length - 1]! + 1 };
    }
    return false;
  });

  if (!range) return false;
  editor.chain().focus().insertContentAt(range, replace).run();
  return true;
}

function toolbarButton(label: string, text: string, active: boolean, run: () => unknown) {
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

function normalizeEditorColor(value: unknown) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (/^#[0-9a-f]{6}$/i.test(trimmed)) return trimmed.toLowerCase();

  const rgb = trimmed.match(/^rgb\(\s*(\d{1,3})\s+(\d{1,3})\s+(\d{1,3})\s*\)$/i)
    ?? trimmed.match(/^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$/i);
  if (!rgb) return null;

  const channels = rgb.slice(1).map(Number);
  if (channels.some((channel) => channel < 0 || channel > 255)) return null;
  return `#${channels.map((channel) => channel.toString(16).padStart(2, "0")).join("")}`;
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

function emptyDocument(): JSONContent {
  return { type: "doc", content: [{ type: "paragraph" }] };
}

function textToDocument(source: string): JSONContent {
  return {
    type: "doc",
    content: source.split("\n").map((line) => ({
      type: "paragraph",
      content: line ? [{ type: "text", text: line }] : undefined,
    })),
  };
}
