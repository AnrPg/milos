"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { publishWorkoutDraft, type WorkoutRecord } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { completionSummary, isPublishReady, useWorkoutCreationStore } from "@/stores/workout-creation";
import { FORMAT_EXERCISE_CONTEXT, type WorkoutType } from "@/types/workout";

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
    const ctx = FORMAT_EXERCISE_CONTEXT[section.format];
    const sectionLabel = section.name.trim() || `Section ${sectionIndex + 1}`;
    const needsExercises = section.format !== "rest" && section.format !== "kcal_target";

    if (!section.name.trim()) {
      messages.push(`${sectionLabel}: add a section name`);
    }

    if (needsExercises && section.exercises.length === 0) {
      messages.push(`${sectionLabel}: add at least one exercise`);
    }

    section.exercises.forEach((exercise, exerciseIndex) => {
      const exerciseLabel = exercise.name.trim() || `Exercise ${exerciseIndex + 1}`;

      if (!exercise.name.trim()) {
        messages.push(`${sectionLabel}: ${exerciseLabel} needs a name`);
      }

      if (ctx.showSets && exercise.sets <= 0) {
        messages.push(`${sectionLabel}: ${exerciseLabel} needs sets`);
      }

      if (ctx.showPrescription && !ctx.prescriptionHint && !ctx.ladderPrescription && exercise.prescriptionValue <= 0) {
        messages.push(`${sectionLabel}: ${exerciseLabel} needs a prescription`);
      }
    });
  });

  return messages;
}

type Props = {
  embedded?: boolean;
  onCancel?: () => void;
  onPublished?: (workout: WorkoutRecord) => void;
};

export function CanvasHeader({ embedded = false, onCancel, onPublished }: Props) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { tokens } = useSession();
  const { draftId, title, type, isTeamWorkout, sections, setTitle, setType, setIsTeamWorkout } = useWorkoutCreationStore();
  const toApiPayload = useWorkoutCreationStore((state) => state.toApiPayload);
  const [publishing, setPublishing] = useState(false);
  const [publishError, setPublishError] = useState<string | null>(null);

  const isReopen = searchParams.get("is_reopen") === "true";
  const substituteForAssignment = searchParams.get("substitute_for_assignment");
  const substituteForSlot = searchParams.get("substitute_for_slot");
  const isSubstitute = Boolean(substituteForAssignment ?? substituteForSlot);

  const ready = isPublishReady({ title, type, sections });
  const summary = completionSummary(sections);
  const publishMessages = publishValidationMessages({ title, type, sections });

  const publishLabel = isReopen || isSubstitute ? "Apply changes" : "Publish";

  async function handlePublish() {
    if (!draftId || !tokens?.access_token || !ready) return;

    setPublishing(true);
    setPublishError(null);

    try {
      const payload = toApiPayload() as Record<string, unknown>;

      if (substituteForAssignment) {
        payload.substitute_for = { type: "assignment", id: substituteForAssignment };
      } else if (substituteForSlot) {
        payload.substitute_for = { type: "slot", id: substituteForSlot };
      }

      const workout = await publishWorkoutDraft(tokens.access_token, draftId, payload);

      if (onPublished) {
        onPublished(workout);
      } else {
        router.push("/admin/workouts");
      }
    } catch (error: unknown) {
      setPublishError(error instanceof Error ? error.message : "Publish failed");
      setPublishing(false);
    }
  }

  return (
    <header
      className="flex shrink-0 flex-col border-b"
      style={{ background: "var(--panel)", borderColor: "var(--dim)" }}
    >
      {isReopen && !isSubstitute ? (
        <div className="px-6 py-2 text-xs font-semibold" style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)", borderBottom: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)" }}>
          Editing a live workout — changes will affect all assignments and classes when published
        </div>
      ) : isSubstitute ? (
        <div className="px-6 py-2 text-xs font-semibold" style={{ background: "color-mix(in srgb, var(--success) 8%, transparent)", color: "var(--success)", borderBottom: "1px solid color-mix(in srgb, var(--success) 15%, transparent)" }}>
          {substituteForAssignment
            ? "Publishing will replace the workout for this assignment only"
            : "Publishing will replace the workout for this class slot only"}
        </div>
      ) : null}
      <div className="flex flex-wrap items-center gap-3 px-4 py-3 sm:px-6">
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

      <button
        type="button"
        onClick={() => setIsTeamWorkout(!isTeamWorkout)}
        className="flex items-center gap-1.5 rounded-2xl px-3 py-2 text-xs font-bold transition-colors"
        style={{
          background: isTeamWorkout ? "color-mix(in srgb, var(--warning) 15%, transparent)" : "var(--card)",
          color: isTeamWorkout ? "var(--warning)" : "var(--muted)",
          border: isTeamWorkout ? "1px solid color-mix(in srgb, var(--warning) 40%, transparent)" : "1px solid var(--dim)",
        }}
        title="Team workout (executed in pairs or groups)"
      >
        Team
      </button>

      <div className="flex-1" />

      {embedded && onCancel ? (
        <button
          type="button"
          onClick={onCancel}
          className="rounded-full px-4 py-2 text-xs font-bold"
          style={{ border: "1px solid var(--dim)", color: "var(--muted)" }}
        >
          Keep draft & close
        </button>
      ) : null}

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
            color: ready ? "var(--bg)" : "var(--muted)",
            cursor: ready ? "pointer" : "not-allowed",
          }}
        >
          {publishing ? `${publishLabel}…` : publishLabel}
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
    </div>
    </header>
  );
}
