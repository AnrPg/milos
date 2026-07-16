"use client";






import {useUiTranslations} from "@/i18n/ui";
import React, { useId, useMemo, useState } from "react";

import type { ExerciseNote } from "@/api/executions";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";

type Props = {
  exerciseId: string;
  exerciseName: string;
  selectedText: string;
  selectionStart: number | null;
  selectionEnd: number | null;
  existingNote: ExerciseNote | undefined;
  onSave: (note: ExerciseNote) => Promise<void>;
  onClose: () => void;
};

export function NoteModal({
  exerciseId,
  exerciseName,
  selectedText,
  selectionStart,
  selectionEnd,
  existingNote,
  onSave,
  onClose,
}: Props) {
  const i18n = useUiTranslations();
  const NOTE_TAGS = [
    i18n("easy00f0313"),
    i18n("hard20a8991"),
    i18n("heavy84d7adf"),
    i18n("lighta36ef8a"),
    i18n("pr55af204"),
    i18n("struggled6e26a47"),
    i18n("formBreakc3f3464"),
    i18n("paina036597"),
  ];
  const [selectedTags, setSelectedTags] = useState<string[]>(existingNote?.tags ?? []);
  const [noteText, setNoteText] = useState(existingNote?.note_text ?? "");
  const [isSaving, setIsSaving] = useState(false);
  const dialogRef = useModalFocusTrap<HTMLDivElement>(onClose);
  const titleId = useId();

  const selectionLabel = useMemo(() => selectedText.trim(), [selectedText]);

  function toggleTag(tag: string) {
    setSelectedTags((current) =>
      current.includes(tag) ? current.filter((value) => value !== tag) : [...current, tag],
    );
  }

  async function handleSave() {
    if (selectedTags.length === 0 && !noteText.trim()) {
      onClose();
      return;
    }

    setIsSaving(true);

    try {
      await onSave({
        id: existingNote?.id,
        exercise_id: exerciseId,
        selected_text: selectionLabel,
        selection_start: selectionStart,
        selection_end: selectionEnd,
        tags: selectedTags,
        note_text: noteText.trim() || undefined,
      });
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center p-4 sm:items-center">
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className="absolute inset-0"
        style={{ background: "rgba(0,0,0,0.7)" }}
        onClick={onClose}
      />
      <div
        className="relative z-10 w-full max-w-md rounded-2xl p-6"
        style={{ background: "var(--panel, var(--panel))", border: "1px solid var(--border)" }}
      >
        <div
          className="mb-1 text-xs font-semibold uppercase tracking-widest"
          style={{ color: "var(--muted)" }}
        >
          {i18n("annotationde3b78b")}
        </div>
        <div id={titleId} className="mb-2 text-base font-bold" style={{ color: "var(--text)" }}>
          {exerciseName}
        </div>
        <div
          className="mb-4 rounded-xl px-3 py-2 text-sm"
          style={{ background: "color-mix(in srgb, var(--warning) 12%, transparent)", border: "1px solid color-mix(in srgb, var(--warning) 28%, transparent)", color: "var(--warning)" }}
        >
          “{selectionLabel}”
        </div>

        <div className="mb-3 flex flex-wrap gap-2">
          {NOTE_TAGS.map((tag) => {
            const selected = selectedTags.includes(tag);

            return (
              <button
                key={tag}
                onClick={() => toggleTag(tag)}
                className="rounded-lg px-3 py-1 text-sm font-semibold transition-all"
                style={{
                  background: selected ? "var(--accent, var(--primary))" : "var(--card, var(--panel-muted))",
                  border: "1px solid var(--border)",
                  color: selected ? "var(--text)" : "var(--muted)",
                }}
                type="button"
              >
                {tag}
              </button>
            );
          })}
        </div>

        <textarea
          placeholder={i18n("optionalFreeText398e72d")}
          rows={4}
          value={noteText}
          onChange={(event) => setNoteText(event.target.value)}
          className="w-full resize-none rounded-xl px-4 py-3 text-sm outline-none focus:ring-2"
          style={{
            background: "var(--card, var(--panel-muted))",
            border: "1px solid var(--border)",
            color: "var(--text)",
          }}
        />

        <div className="mt-4 flex gap-3">
          <button
            onClick={onClose}
            disabled={isSaving}
            className="flex-1 rounded-xl py-2.5 text-sm font-semibold"
            style={{
              background: "var(--card, var(--panel-muted))",
              border: "1px solid var(--border)",
              color: "var(--muted)",
            }}
            type="button"
          >
            {i18n("cancel77dfd21")}
          </button>
          <button
            onClick={handleSave}
            disabled={isSaving}
            className="flex-1 rounded-xl py-2.5 text-sm font-semibold"
            style={{ background: "var(--accent, var(--primary))", color: "var(--text)" }}
            type="button"
          >
            {isSaving ? i18n("saving56a2285") : existingNote ? i18n("updatefb91e24") : i18n("saveefc007a")}
          </button>
        </div>
      </div>
    </div>
  );
}
