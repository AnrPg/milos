"use client";

import { useState } from "react";

import { ApiError } from "@/api/client";
import {
  deleteAssignedWorkout,
  rejectAssignment,
  rescheduleAssignment,
  updateAssignedWorkout,
  type AssignedWorkoutRecord,
} from "@/api/assigned-workouts";
import { ChatSection } from "@/components/chat/ChatSection";
import { WorkoutPreviewDetail, type PreviewSection } from "@/components/workouts/WorkoutPreviewDetail";
import { workoutTypeColor } from "@/lib/workout-colors";
import { downloadIcsEvent } from "@/lib/ics";

type Props = {
  assignment: AssignedWorkoutRecord;
  isAdmin: boolean;
  accessToken: string;
  onClose: () => void;
  onStartWorkout: (assignment: AssignedWorkoutRecord) => void;
  onRejected?: (assignmentId: string) => void;
  onDeleted?: (assignmentId: string) => void;
  onEditWorkout?: (assignment: AssignedWorkoutRecord) => void;
  onRescheduled?: (updated: AssignedWorkoutRecord) => void;
  launching?: boolean;
};

export function AssignedWorkoutPanel({
  assignment,
  isAdmin,
  accessToken,
  onClose,
  onStartWorkout,
  onRejected,
  onDeleted,
  onEditWorkout,
  onRescheduled,
  launching,
}: Props) {
  const [chatExpanded, setChatExpanded] = useState(false);
  const [rejecting, setRejecting] = useState(false);
  const [rejectError, setRejectError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [rescheduling, setRescheduling] = useState(false);
  const [rescheduleDate, setRescheduleDate] = useState("");
  const [rescheduleError, setRescheduleError] = useState<string | null>(null);
  const [rescheduleSaving, setRescheduleSaving] = useState(false);
  const todayIso = new Date().toISOString().split("T")[0]!;

  const scaleLevels = (() => {
    const map = new Map<string, { slug: string; label: string; sort_order: number }>();
    for (const section of assignment.workout.sections) {
      for (const exercise of section.exercises) {
        for (const variation of exercise.variations ?? []) {
          const sl = variation.scale_level;
          if (sl?.slug) map.set(sl.slug, { slug: sl.slug, label: sl.label ?? sl.slug, sort_order: sl.sort_order ?? 0 });
        }
      }
    }
    return Array.from(map.values()).sort((a, b) => a.sort_order - b.sort_order || a.label.localeCompare(b.label));
  })();

  const [activeScale, setActiveScale] = useState<string | null>(null);;

  const sections = assignment.workout.sections as PreviewSection[];

  async function handleDelete() {
    if (!window.confirm("Delete this workout assignment? This cannot be undone.")) return;
    setDeleting(true);
    setDeleteError(null);
    try {
      await deleteAssignedWorkout(accessToken, assignment.id);
      onDeleted?.(assignment.id);
      onClose();
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : "Failed to delete assignment.");
    } finally {
      setDeleting(false);
    }
  }

  async function handleReject() {
    if (!window.confirm("Reject this workout? Your coach will be notified.")) return;

    setRejecting(true);
    setRejectError(null);

    try {
      await rejectAssignment(accessToken, assignment.id);
      onRejected?.(assignment.id);
      onClose();
    } catch (err) {
      if (err instanceof ApiError && err.status === 422) {
        setRejectError("This workout is already rejected.");
      } else {
        setRejectError(err instanceof Error ? err.message : "Failed to reject workout.");
      }
    } finally {
      setRejecting(false);
    }
  }

  async function handleReschedule() {
    if (!rescheduleDate) return;
    setRescheduleSaving(true);
    setRescheduleError(null);
    try {
      const updated = isAdmin
        ? await updateAssignedWorkout(accessToken, assignment.id, {
            scheduled_for: rescheduleDate,
            athlete_ids: assignment.athlete_ids ?? [],
            admin_notes: assignment.admin_notes ?? undefined,
          })
        : await rescheduleAssignment(accessToken, assignment.id, rescheduleDate);
      onRescheduled?.(updated);
      onClose();
    } catch (err) {
      setRescheduleError(err instanceof Error ? err.message : "Could not reschedule.");
    } finally {
      setRescheduleSaving(false);
    }
  }

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 z-40"
        style={{ background: "rgba(0,0,0,0.5)" }}
        onClick={onClose}
      />

      {/* Panel */}
      <div
        className="fixed right-0 z-50 flex w-full flex-col overflow-hidden md:max-w-[480px]"
        style={{ background: "#0A0A0F", borderLeft: "1px solid #1a1a28", top: "3.25rem", bottom: 0 }}
      >
        {/* Sticky header */}
        <div
          className="sticky top-0 z-10 flex items-center justify-between gap-4 px-5 py-4"
          style={{
            background: "#0A0A0F",
            borderBottom: "1px solid #1a1a28",
            minHeight: "3.25rem",
          }}
        >
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <p
                className="truncate text-xs font-semibold uppercase tracking-[0.2em]"
                style={{ color: workoutTypeColor(assignment.workout.type) }}
              >
                {assignment.workout.type}
              </p>
              {assignment.workout.is_team_workout ? (
                <span
                  className="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider"
                  style={{ background: "rgba(251,191,36,0.15)", color: "#fbbf24", border: "1px solid rgba(251,191,36,0.35)" }}
                >
                  Team
                </span>
              ) : null}
            </div>
            <h2
              className="mt-0.5 truncate text-base font-bold"
              style={{ color: "#F0EDF8" }}
            >
              {assignment.workout.title}
            </h2>
            {scaleLevels.length > 0 ? (
              <div className="mt-2 flex flex-wrap gap-1.5">
                <button
                  className="rounded-full px-2.5 py-1 text-[10px] font-semibold transition-colors"
                  style={{
                    background: activeScale === null ? "#F0EDF8" : "#1a1a28",
                    color: activeScale === null ? "#0A0A0F" : "#c0c0d8",
                    border: activeScale === null ? "1px solid #F0EDF8" : "1px solid #25253a",
                  }}
                  onClick={() => setActiveScale(null)}
                  type="button"
                >
                  Base
                </button>
                {scaleLevels.map((sl) => (
                  <button
                    key={sl.slug}
                    className="rounded-full px-2.5 py-1 text-[10px] font-semibold transition-colors"
                    style={{
                      background: activeScale === sl.slug ? "rgba(156,121,156,0.22)" : "#1a1a28",
                      color: activeScale === sl.slug ? "#c79ac7" : "#c0c0d8",
                      border: activeScale === sl.slug ? "1px solid rgba(156,121,156,0.5)" : "1px solid #25253a",
                    }}
                    onClick={() => setActiveScale(sl.slug)}
                    type="button"
                  >
                    {sl.label}
                  </button>
                ))}
              </div>
            ) : null}
          </div>
          <div className="flex shrink-0 flex-col items-end gap-2">
            <button
              className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
              style={{ background: "#1a1a28", color: "#8888aa" }}
              onClick={onClose}
              type="button"
            >
              Close ✕
            </button>
            <button
              className="rounded-full px-3 py-1 text-[10px] font-semibold transition-colors"
              style={{ background: "#1a1a28", color: "#55556a", border: "1px solid #1e1e2e" }}
              onClick={() =>
                downloadIcsEvent({
                  title: assignment.workout.title,
                  date: assignment.scheduled_for,
                  description: assignment.admin_notes ?? undefined,
                })
              }
              type="button"
            >
              + Calendar
            </button>
          </div>
        </div>

        {/* Scrollable body */}
        <div className="flex-1 overflow-y-auto px-5 py-5 space-y-6">
          {/* Workout preview */}
          <section>
            <p
              className="mb-3 text-xs font-semibold uppercase tracking-[0.2em]"
              style={{ color: "#55556a" }}
            >
              Workout
            </p>
            <WorkoutPreviewDetail
                sections={sections}
                initiallyExpanded
                activeScaleOverride={scaleLevels.length > 0 ? activeScale : undefined}
                hideScaleChips={scaleLevels.length > 0}
              />
          </section>

          {/* Admin notes */}
          {assignment.admin_notes ? (
            <section
              className="rounded-[1.2rem] px-4 py-3 text-sm"
              style={{ background: "rgba(217,93,57,0.1)", border: "1px solid rgba(217,93,57,0.15)", color: "#e07a5f" }}
            >
              <p className="mb-1 text-[10px] font-bold uppercase tracking-[0.18em]" style={{ color: "#d95d39" }}>
                Coach note
              </p>
              {assignment.admin_notes}
            </section>
          ) : null}

          {/* Admin controls */}
          {isAdmin ? (
            <section className="space-y-3">
              {(assignment.athletes ?? []).length > 0 ? (
                <div>
                  <p className="mb-2 text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "#55556a" }}>
                    Assigned athletes
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {(assignment.athletes ?? []).map((athlete) => (
                      <span
                        key={athlete.id}
                        className="rounded-full px-3 py-1 text-xs font-semibold"
                        style={{ background: "rgba(156,121,156,0.15)", border: "1px solid rgba(156,121,156,0.25)", color: "#9c799c" }}
                      >
                        {athlete.nickname}
                      </span>
                    ))}
                  </div>
                </div>
              ) : null}

              <div>
                <p className="mb-2 text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "#55556a" }}>
                  Scheduled for
                </p>
                <p className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                  {assignment.scheduled_for}
                </p>
              </div>

              <div className="flex flex-wrap gap-2 pt-1">
                {onEditWorkout ? (
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold transition-colors"
                    style={{ background: "rgba(136,136,170,0.1)", border: "1px solid rgba(136,136,170,0.2)", color: "#8888aa" }}
                    onClick={() => onEditWorkout(assignment)}
                    type="button"
                  >
                    Edit workout
                  </button>
                ) : null}
                <button
                  className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50 transition-colors"
                  style={{ background: "rgba(217,93,57,0.1)", border: "1px solid rgba(217,93,57,0.2)", color: "#d95d39" }}
                  disabled={deleting}
                  onClick={() => void handleDelete()}
                  type="button"
                >
                  {deleting ? "Deleting…" : "Delete assignment"}
                </button>
              </div>
              {deleteError ? (
                <p className="text-xs" style={{ color: "#e07a5f" }}>{deleteError}</p>
              ) : null}
            </section>
          ) : null}

          <ChatSection
            contextType="assignment"
            contextId={assignment.id}
            isExpanded={chatExpanded}
            onToggle={() => setChatExpanded((v) => !v)}
            participantNicknames={
              isAdmin
                ? Object.fromEntries(
                    (assignment.athletes ?? []).map((a) => [a.id, a.nickname ?? a.id]),
                  )
                : {}
            }
          />

          {/* Athlete rejection */}
          {!isAdmin ? (
            <section>
              {rejectError ? (
                <p className="mb-2 text-xs" style={{ color: "#e07a5f" }}>{rejectError}</p>
              ) : null}
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                style={{ background: "rgba(217,93,57,0.12)", color: "#d95d39", border: "1px solid rgba(217,93,57,0.2)" }}
                disabled={rejecting}
                onClick={() => void handleReject()}
                type="button"
              >
                {rejecting ? "Rejecting…" : "Reject workout"}
              </button>
            </section>
          ) : null}

          {/* Reschedule */}
          <section className="px-0 pb-4">
            {!rescheduling ? (
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ background: "#1a1a28", color: "#c0c0d8" }}
                onClick={() => {
                  setRescheduleDate(assignment.scheduled_for);
                  setRescheduling(true);
                }}
                type="button"
              >
                Reschedule
              </button>
            ) : (
              <div className="space-y-2">
                <input
                  className="w-full rounded-[1rem] px-4 py-2 text-sm outline-none"
                  style={{ background: "#111118", border: "1px solid #1e1e2e", color: "#F0EDF8" }}
                  type="date"
                  min={todayIso}
                  value={rescheduleDate}
                  onChange={(e) => setRescheduleDate(e.target.value)}
                />
                {rescheduleError ? (
                  <p className="text-xs" style={{ color: "#e07a5f" }}>{rescheduleError}</p>
                ) : null}
                <div className="flex gap-2">
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                    style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                    disabled={rescheduleSaving || !rescheduleDate}
                    onClick={() => void handleReschedule()}
                    type="button"
                  >
                    {rescheduleSaving ? "Saving…" : "Confirm"}
                  </button>
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold"
                    style={{ background: "#1a1a28", color: "#8888aa" }}
                    onClick={() => setRescheduling(false)}
                    type="button"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            )}
          </section>

          {/* Completion scores */}
          {assignment.execution_status === "completed" && (assignment.execution_scores ?? []).length > 0 ? (
            <section>
              <p
                className="mb-3 text-xs font-semibold uppercase tracking-[0.2em]"
                style={{ color: "#55556a" }}
              >
                Your scores
              </p>
              <div className="space-y-2">
                {(assignment.execution_scores ?? []).map((score, index) => (
                  <div
                    key={score.section_id ?? index}
                    className="flex items-center justify-between rounded-[1rem] px-4 py-2.5"
                    style={{ background: "rgba(16,185,129,0.08)", border: "1px solid rgba(16,185,129,0.15)" }}
                  >
                    <span className="text-xs" style={{ color: "#8888aa" }}>
                      {score.section_name ?? score.section_id}
                    </span>
                    <span className="text-sm font-semibold" style={{ color: "#34d399" }}>
                      {score.value}{score.unit ? ` ${score.unit}` : ""}
                    </span>
                  </div>
                ))}
              </div>
            </section>
          ) : null}
        </div>

        {/* Bottom CTA */}
        <div
          className="border-t px-5 py-4"
          style={{ borderColor: "#1a1a28", background: "#0A0A0F" }}
        >
          {assignment.execution_status === "completed" && assignment.scheduled_for <= todayIso ? (
            <button
              className="w-full rounded-full py-3 text-sm font-bold tracking-wide disabled:opacity-50"
              style={{ background: "rgba(16,185,129,0.15)", border: "1px solid rgba(16,185,129,0.3)", color: "#34d399" }}
              disabled={launching}
              onClick={() => onStartWorkout(assignment)}
              type="button"
            >
              {launching ? "Starting…" : "Redo Workout"}
            </button>
          ) : (
            <button
              className="w-full rounded-full py-3 text-sm font-bold tracking-wide disabled:opacity-50"
              style={{ background: "#d95d39", color: "#fff" }}
              disabled={launching}
              onClick={() => onStartWorkout(assignment)}
              type="button"
            >
              {launching ? "Starting…" : "Start Workout"}
            </button>
          )}
        </div>
      </div>
    </>
  );
}
