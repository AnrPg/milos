"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { publishWorkout } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { completionSummary, isPublishReady, useWorkoutCreationStore } from "@/stores/workout-creation";
import type { WorkoutType } from "@/types/workout";

const WORKOUT_TYPES: WorkoutType[] = [
  "crossfit",
  "strength",
  "gymnastics",
  "aerobics",
  "flexibility",
  "recovery",
];

const TYPE_LABELS: Record<WorkoutType, string> = {
  crossfit: "CrossFit",
  strength: "Strength",
  gymnastics: "Gymnastics",
  aerobics: "Aerobics",
  flexibility: "Flexibility",
  recovery: "Recovery",
};

function SaveStatusIndicator() {
  const status = useWorkoutCreationStore((state) => state.saveStatus);

  if (status === "idle") return null;

  const map = {
    saving: { icon: "↻", text: "Saving…", color: "var(--muted)" },
    saved: { icon: "✓", text: "Draft saved", color: "var(--lime)" },
    error: { icon: "⚠", text: "Draft not saved", color: "var(--amber)" },
  } as const;

  const { icon, text, color } = map[status];

  return (
    <span className="text-sm font-medium" style={{ color }}>
      {icon} {text}
    </span>
  );
}

function publishValidationMessages({
  title,
  type,
  sections,
}: Pick<ReturnType<typeof useWorkoutCreationStore.getState>, "title" | "type" | "sections">) {
  const messages: string[] = [];

  if (!title.trim()) messages.push("Missing workout title");
  if (!type) messages.push("Missing workout type");
  if (sections.length === 0) messages.push("Add at least one section");

  sections.forEach((section, sectionIndex) => {
    const sectionLabel = section.name.trim() || `Section ${sectionIndex + 1}`;

    if (!section.name.trim()) {
      messages.push(`${sectionLabel}: add a section name`);
    }

    if (section.exercises.length === 0) {
      messages.push(`${sectionLabel}: add at least one exercise`);
    }

    section.exercises.forEach((exercise, exerciseIndex) => {
      const exerciseLabel = exercise.name.trim() || `Exercise ${exerciseIndex + 1}`;

      if (!exercise.name.trim()) {
        messages.push(`${sectionLabel}: ${exerciseLabel} needs a name`);
      }

      if (exercise.sets <= 0) {
        messages.push(`${sectionLabel}: ${exerciseLabel} needs sets`);
      }

      if (exercise.prescriptionValue <= 0) {
        messages.push(`${sectionLabel}: ${exerciseLabel} needs a prescription`);
      }
    });
  });

  return messages;
}

export function CanvasHeader() {
  const router = useRouter();
  const { tokens } = useSession();
  const { draftId, title, type, sections, setTitle, setType } = useWorkoutCreationStore();
  const [publishing, setPublishing] = useState(false);
  const [publishError, setPublishError] = useState<string | null>(null);

  const ready = isPublishReady({ title, type, sections });
  const summary = completionSummary(sections);
  const publishMessages = publishValidationMessages({ title, type, sections });

  async function handlePublish() {
    if (!draftId || !tokens?.access_token || !ready) return;

    setPublishing(true);
    setPublishError(null);

    try {
      await publishWorkout(tokens.access_token, draftId);
      router.push("/admin/workouts");
    } catch (error: unknown) {
      setPublishError(error instanceof Error ? error.message : "Publish failed");
      setPublishing(false);
    }
  }

  return (
    <header
      className="flex shrink-0 items-center gap-4 border-b px-6 py-3"
      style={{
        background: "var(--panel)",
        borderColor: "var(--dim)",
      }}
    >
      <span className="text-xl font-black" style={{ color: "var(--accent)" }}>
        ✦
      </span>

      <input
        type="text"
        value={title}
        onChange={(event) => setTitle(event.target.value)}
        placeholder="Workout title"
        className="min-w-0 flex-1 border-b border-transparent bg-transparent text-lg font-extrabold outline-none transition-colors focus:border-current"
        style={{ color: "var(--text)", maxWidth: 320 }}
      />

      <select
        value={type ?? ""}
        onChange={(event) => setType(event.target.value as WorkoutType)}
        className="cursor-pointer rounded-2xl px-4 py-2 text-sm font-semibold outline-none"
        style={{
          background: "var(--card)",
          color: type ? "var(--text)" : "var(--muted)",
          border: "1px solid var(--dim)",
        }}
      >
        <option value="" disabled>
          Type
        </option>
        {WORKOUT_TYPES.map((workoutType) => (
          <option key={workoutType} value={workoutType}>
            {TYPE_LABELS[workoutType]}
          </option>
        ))}
      </select>

      <div className="flex-1" />

      {sections.length > 0 ? (
        <span className="text-sm" style={{ color: "var(--muted)" }}>
          {summary}
        </span>
      ) : null}

      <SaveStatusIndicator />

      <div className="group relative">
        <button
          onClick={handlePublish}
          disabled={!ready || publishing}
          className="rounded-3xl px-6 py-2 text-sm font-bold transition-opacity"
          style={{
            background: ready ? "var(--lime)" : "var(--dim)",
            color: ready ? "#0A0A0F" : "var(--muted)",
            cursor: ready ? "pointer" : "not-allowed",
          }}
        >
          {publishing ? "Publishing..." : "Publish"}
        </button>

        {!ready ? (
          <div
            className="pointer-events-none absolute right-0 top-full z-50 mt-2 rounded-xl p-3 text-xs opacity-0 transition-opacity group-hover:opacity-100"
            style={{ background: "var(--card)", border: "1px solid var(--dim)", color: "var(--muted)" }}
          >
            {publishMessages.map((message) => (
              <div key={message}>- {message}</div>
            ))}
          </div>
        ) : null}
      </div>

      {publishError ? (
        <span className="text-xs" style={{ color: "var(--red)" }}>
          {publishError}
        </span>
      ) : null}
    </header>
  );
}
