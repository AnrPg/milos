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
import { useCallback, useEffect, useRef, useState } from "react";

import {
  createDraftWorkout,
  fetchAdminWorkout,
  publishWorkoutDraft,
  updateDraftWorkout,
} from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { sanitizeWorkoutDslPaste } from "@/lib/workout-dsl-editor-data";
import type { WorkoutType } from "@/types/workout";

type Props = {
  draftId: string | null;
  onDraftReady: (id: string) => void;
};

type SaveStatus = "idle" | "saving" | "saved" | "error";

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
  const { tokens } = useSession();
  const accessToken = tokens?.access_token;
  const [title, setTitle] = useState("");
  const [type, setType] = useState<WorkoutType>("crossfit");
  const [body, setBody] = useState("");
  const [saveStatus, setSaveStatus] = useState<SaveStatus>("idle");
  const [publishing, setPublishing] = useState(false);
  const loadedDraftRef = useRef<string | null>(null);

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
      Placeholder.configure({ placeholder: i18n("freeTextEditorPlaceholder") }),
      CharacterCount.configure({ limit: 200_000 }),
    ],
    content: emptyDocument(),
    immediatelyRender: false,
    editorProps: {
      attributes: {
        class:
          "min-h-[26rem] px-6 py-5 outline-none prose prose-sm max-w-none whitespace-pre-wrap",
        spellcheck: "true",
        role: "textbox",
        "aria-label": i18n("freeTextEditorLabel"),
      },
      transformPastedHTML: sanitizeWorkoutDslPaste,
    },
    onUpdate: ({ editor: currentEditor }) => {
      setBody(currentEditor.getText({ blockSeparator: "\n" }));
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

  async function publish() {
    if (!accessToken || !draftId || !editor || !title.trim() || !body.trim()) return;
    setPublishing(true);

    try {
      const payload = buildPayload({ title, type, body, document: editor.getJSON() });
      await updateDraftWorkout(accessToken, draftId, payload);
      await publishWorkoutDraft(accessToken, draftId, payload);
      router.push("/admin/workouts");
    } catch {
      setSaveStatus("error");
    } finally {
      setPublishing(false);
    }
  }

  return (
    <div className="grid min-h-[calc(100dvh-6.5rem)] grid-cols-1 lg:grid-cols-[minmax(0,1fr)_24rem]">
      <section className="flex min-h-0 flex-col border-e" style={{ borderColor: "var(--dim)" }}>
        <header className="border-b px-5 py-4" style={{ borderColor: "var(--dim)" }}>
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

        <div className="grid gap-3 border-b p-4 md:grid-cols-[minmax(0,1fr)_12rem]" style={{ borderColor: "var(--dim)" }}>
          <label className="block">
            <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
              {i18n("titleb78a322")}
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
              {i18n("typea1fa277")}
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

        <FreeTextToolbar editor={editor} />

        <div className="min-h-0 flex-1 overflow-auto">
          <EditorContent editor={editor} />
        </div>

        <footer className="flex flex-wrap items-center justify-between gap-3 border-t px-5 py-3" style={{ borderColor: "var(--dim)" }}>
          <span className="text-xs" style={{ color: "var(--muted)" }}>
            {i18n("quickTextCharacterCount", { count: editor?.storage.characterCount.characters() ?? 0 })}
          </span>
          <button
            type="button"
            disabled={publishing || !title.trim() || !body.trim()}
            onClick={() => void publish()}
            className="rounded-xl px-5 py-2 text-sm font-black disabled:opacity-40"
            style={{ background: "var(--primary)", color: "var(--primary-foreground, white)" }}
          >
            {publishing ? i18n("quickTextPublishing") : i18n("quickTextPublish")}
          </button>
        </footer>
      </section>

      <aside className="min-h-0 overflow-auto p-5" style={{ background: "var(--panel)" }}>
        <h2 className="text-lg font-black" style={{ color: "var(--text)" }}>
          {i18n("quickTextCanonicalPreview")}
        </h2>
        <div className="mt-4 rounded-2xl border p-4" style={{ borderColor: "var(--dim)", background: "var(--card)" }}>
          <div className="text-xl font-black" style={{ color: "var(--text)" }}>
            {title || i18n("untitledWorkout579b8a6")}
          </div>
          <pre className="mt-4 whitespace-pre-wrap font-sans text-sm leading-6" style={{ color: "var(--text)" }}>
            {body || i18n("freeTextPreviewEmpty")}
          </pre>
        </div>
      </aside>
    </div>
  );
}

function FreeTextToolbar({ editor }: { editor: Editor | null }) {
  const i18n = useUiTranslations();
  if (!editor) return null;

  const actions = [
    toolbarButton(i18n("editorBold"), "B", editor.isActive("bold"), () => editor.chain().focus().toggleBold().run()),
    toolbarButton(i18n("editorItalic"), "I", editor.isActive("italic"), () => editor.chain().focus().toggleItalic().run()),
    toolbarButton(i18n("editorUnderline"), "U", editor.isActive("underline"), () => editor.chain().focus().toggleUnderline().run()),
    toolbarButton(i18n("editorStrike"), "S", editor.isActive("strike"), () => editor.chain().focus().toggleStrike().run()),
    toolbarButton(i18n("editorHighlight"), "H", editor.isActive("highlight"), () => editor.chain().focus().toggleHighlight().run()),
    toolbarButton(i18n("editorHeading"), "H2", editor.isActive("heading", { level: 2 }), () => editor.chain().focus().toggleHeading({ level: 2 }).run()),
    toolbarButton(i18n("editorBulletList"), "•", editor.isActive("bulletList"), () => editor.chain().focus().toggleBulletList().run()),
    toolbarButton(i18n("editorOrderedList"), "1.", editor.isActive("orderedList"), () => editor.chain().focus().toggleOrderedList().run()),
    toolbarButton(i18n("editorQuote"), "“”", editor.isActive("blockquote"), () => editor.chain().focus().toggleBlockquote().run()),
    toolbarButton(i18n("editorCode"), "</>", editor.isActive("codeBlock"), () => editor.chain().focus().toggleCodeBlock().run()),
    toolbarButton(i18n("editorAlignLeft"), "L", editor.isActive({ textAlign: "left" }), () => editor.chain().focus().setTextAlign("left").run()),
    toolbarButton(i18n("editorAlignCenter"), "C", editor.isActive({ textAlign: "center" }), () => editor.chain().focus().setTextAlign("center").run()),
    toolbarButton(i18n("editorAlignRight"), "R", editor.isActive({ textAlign: "right" }), () => editor.chain().focus().setTextAlign("right").run()),
    toolbarButton(i18n("editorLink"), "Link", editor.isActive("link"), () => setEditorLink(editor, i18n("editorLinkPrompt"))),
    toolbarButton(i18n("editorUndo"), "Undo", false, () => editor.chain().focus().undo().run()),
    toolbarButton(i18n("editorRedo"), "Redo", false, () => editor.chain().focus().redo().run()),
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
