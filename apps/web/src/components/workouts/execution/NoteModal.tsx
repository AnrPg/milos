"use client";

import React, { useMemo, useState } from "react";

import type { ExerciseNote } from "@/api/executions";

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

const NOTE_TAGS = [
  "Easy",
  "Hard",
  "Heavy",
  "Light",
  "PR",
  "Struggled",
  "Form break",
  "Pain",
];

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
  const [selectedTags, setSelectedTags] = useState<string[]>(existingNote?.tags ?? []);
  const [noteText, setNoteText] = useState(existingNote?.note_text ?? "");
  const [isSaving, setIsSaving] = useState(false);

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
          Annotation
        </div>
        <div className="mb-2 text-base font-bold" style={{ color: "var(--text)" }}>
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
          placeholder="Optional free text…"
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
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={isSaving}
            className="flex-1 rounded-xl py-2.5 text-sm font-semibold"
            style={{ background: "var(--accent, var(--primary))", color: "var(--text)" }}
            type="button"
          >
            {isSaving ? "Saving…" : existingNote ? "Update" : "Save"}
          </button>
        </div>
      </div>
    </div>
  );
}
