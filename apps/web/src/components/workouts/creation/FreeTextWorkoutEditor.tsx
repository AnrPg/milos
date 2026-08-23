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
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";

import {
  createDraftWorkout,
  fetchAdminWorkout,
  publishWorkoutDraft,
  updateDraftWorkout,
} from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { FREE_TEXT_EDITOR_CLASS, sanitizeWorkoutDslPaste } from "@/lib/workout-dsl-editor-data";
import type { WorkoutType } from "@/types/workout";

type Props = {
  draftId: string | null;
  onDraftReady: (id: string) => void;
};

type SaveStatus = "idle" | "saving" | "saved" | "error";
type RibbonKey = "overview" | "details" | "tools";

const WORKOUT_TYPES: WorkoutType[] = [
  "crossfit",
  "strength",
  "gymnastics",
  "aerobics",
  "flexibility",
  "recovery",
];

export function FreeTextWorkoutEditor({ draftId, onDraftReady }: Props) {
  const i18n = useUiTranslations();
  const router = useRouter();
  const organizationSlug = useOrganizationSlug();
  const { tokens } = useSession();
  const accessToken = tokens?.access_token;
  const [title, setTitle] = useState("");
  const [type, setType] = useState<WorkoutType>("crossfit");
  const [body, setBody] = useState("");
  const [html, setHtml] = useState("");
  const [saveStatus, setSaveStatus] = useState<SaveStatus>("idle");
  const [publishing, setPublishing] = useState(false);
  const [previewOpen, setPreviewOpen] = useState(true);
  const [collapsedRibbons, setCollapsedRibbons] = useState<Record<RibbonKey, boolean>>({
    overview: false,
    details: false,
    tools: false,
  });
  const loadedDraftRef = useRef<string | null>(null);

  function toggleRibbon(key: RibbonKey) {
    setCollapsedRibbons((current) => ({ ...current, [key]: !current[key] }));
  }

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
    createDraftWorkout(accessToken)
      .then((draft) => onDraftReady(draft.id))
      .catch(() => {
        loadedDraftRef.current = null;
        setSaveStatus("error");
      });
  }, [accessToken, draftId, onDraftReady]);

  useEffect(() => {
    if (!accessToken || !draftId || loadedDraftRef.current === draftId || !editor) return;

    loadedDraftRef.current = draftId;
    fetchAdminWorkout(accessToken, draftId)
      .then((workout) => {
        setTitle(workout.title ?? "");
        if (WORKOUT_TYPES.includes(workout.type as WorkoutType)) {
          setType(workout.type as WorkoutType);
        }
        const nextBody = workout.free_text_body ?? "";
        setBody(nextBody);
        editor.commands.setContent(workout.free_text_document ?? textToDocument(nextBody));
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
      await updateDraftWorkout(accessToken, draftId, buildPayload({
        title,
        type,
        body,
        document: editor.getJSON(),
      }));
      setSaveStatus("saved");
    } catch {
      setSaveStatus("error");
    }
  }, [accessToken, body, draftId, editor, title, type]);

  useEffect(() => {
    if (!draftId || loadedDraftRef.current !== draftId) return;
    const timer = window.setTimeout(() => {
      void saveDraft();
    }, 1_000);
    return () => window.clearTimeout(timer);
  }, [body, draftId, saveDraft, title, type]);

  const canPublish = Boolean(accessToken && draftId && editor && title.trim() && body.trim() && !publishing);

  async function publish() {
    if (!accessToken || !draftId || !editor || !title.trim() || !body.trim()) return;
    setPublishing(true);

    try {
      const payload = buildPayload({ title, type, body, document: editor.getJSON() });
      await updateDraftWorkout(accessToken, draftId, payload);
      await publishWorkoutDraft(accessToken, draftId, payload);
      router.push(adminHref("/admin/workouts", organizationSlug));
    } catch {
      setSaveStatus("error");
    } finally {
      setPublishing(false);
    }
  }

  return (
    <div className={previewOpen ? "grid min-h-[calc(100dvh-6.5rem)] min-w-0 grid-cols-1 overflow-x-clip lg:grid-cols-[minmax(0,1fr)_24rem]" : "grid min-h-[calc(100dvh-6.5rem)] min-w-0 grid-cols-1 overflow-x-clip lg:grid-cols-[minmax(0,1fr)_4rem]"}>
      <section className="flex min-h-0 min-w-0 flex-col border-e" style={{ borderColor: "var(--dim)" }}>
        <CollapsibleRibbon
          label={i18n("freeTextTitle")}
          collapsed={collapsedRibbons.overview}
          onToggle={() => toggleRibbon("overview")}
        >
          <header className="px-5 py-4">
            <div className="flex flex-wrap items-start justify-between gap-4">
              <div>
                <h1 className="text-xl font-black" style={{ color: "var(--text)" }}>
                  {i18n("freeTextTitle")}
                </h1>
                <p className="mt-1 max-w-2xl text-sm" style={{ color: "var(--muted)" }}>
                  {i18n("freeTextDescription")}
                </p>
              </div>
              <div className="text-end text-xs font-semibold" style={{ color: "var(--muted)" }}>
                {saveStatusText(saveStatus, i18n)}
              </div>
            </div>
          </header>
        </CollapsibleRibbon>

        <CollapsibleRibbon
          label={i18n("workoutDetails9366821")}
          collapsed={collapsedRibbons.details}
          onToggle={() => toggleRibbon("details")}
        >
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
              >
                {WORKOUT_TYPES.map((item) => (
                  <option key={item} value={item}>
                    {item.replaceAll("_", " ")}
                  </option>
                ))}
              </select>
            </label>
          </div>
        </CollapsibleRibbon>

        <CollapsibleRibbon
          label={i18n("editorFormatting")}
          collapsed={collapsedRibbons.tools}
          onToggle={() => toggleRibbon("tools")}
        >
          <FreeTextToolbar editor={editor} />
        </CollapsibleRibbon>

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
            {publishing ? i18n("quickTextPublishing") : i18n("quickTextPublish")}
          </button>
        </footer>
      </section>

      <aside className="min-h-0 min-w-0 overflow-auto overflow-x-clip p-4" style={{ background: "var(--panel)" }}>
        <div className="flex items-center justify-between gap-3">
          {previewOpen ? (
            <h2 className="text-lg font-black" style={{ color: "var(--text)" }}>
              {i18n("quickTextCanonicalPreview")}
            </h2>
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
        {previewOpen ? (
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

function CollapsibleRibbon({
  label,
  collapsed,
  onToggle,
  children,
}: {
  label: string;
  collapsed: boolean;
  onToggle: () => void;
  children: ReactNode;
}) {
  return (
    <section className="min-w-0 border-b" style={{ borderColor: "var(--dim)" }}>
      <button
        type="button"
        className="flex w-full min-w-0 items-center justify-between gap-3 px-4 py-2 text-start text-xs font-black uppercase tracking-[0.18em]"
        style={{ background: "var(--bg)", color: "var(--muted)" }}
        aria-expanded={!collapsed}
        onClick={onToggle}
      >
        <span className="min-w-0 truncate">{label}</span>
        <span aria-hidden="true" className="text-base leading-none" style={{ color: "var(--primary)" }}>
          {collapsed ? "+" : "−"}
        </span>
      </button>
      {collapsed ? null : (
        <div className="min-w-0 border-t overflow-x-clip" style={{ borderColor: "color-mix(in srgb, var(--dim) 70%, transparent)" }}>
          {children}
        </div>
      )}
    </section>
  );
}

function FreeTextToolbar({ editor }: { editor: Editor | null }) {
  const i18n = useUiTranslations();
  if (!editor) return null;

  const headingLevels = [1, 2, 3, 4, 5] as const;
  const selectedTextColor = editor.getAttributes("textColor").color as string | undefined;
  const colorPickerValue = /^#[0-9a-f]{6}$/i.test(selectedTextColor ?? "") ? selectedTextColor! : "#f4efe8";
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
              color: selectedTextColor ? "var(--primary-foreground, white)" : "var(--text)",
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
            color: action.active ? "var(--primary-foreground, white)" : "var(--text)",
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
                  .addMark(wordRange.from, wordRange.to, highlight.create({ color: "#fde68a" }))
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
}: {
  title: string;
  type: WorkoutType;
  body: string;
  document: JSONContent;
}) {
  return {
    title,
    type,
    authoring_mode: "free_text",
    free_text_body: body,
    free_text_document: document,
    draft_data: {
      title,
      type,
      authoring_mode: "free_text",
      free_text_body: body,
      free_text_document: document,
      sections: [],
    },
    sections: [],
  };
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
