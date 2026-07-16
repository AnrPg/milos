"use client";





import {useUiTranslations} from "@/i18n/ui";
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
  const i18n = useUiTranslations();
  const [activeSection, setActiveSection] = useState<"details" | "conversation">("details");
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
    if (!window.confirm(i18n("deleteThisWorkoutAssignmentThisCannotBeUndone9bbe00a"))) return;
    setDeleting(true);
    setDeleteError(null);
    try {
      await deleteAssignedWorkout(accessToken, assignment.id);
      onDeleted?.(assignment.id);
      onClose();
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : i18n("failedToDeleteAssignmentde15c58"));
    } finally {
      setDeleting(false);
    }
  }

  async function handleReject() {
    if (!window.confirm(i18n("rejectThisWorkoutYourCoachWillBeNotifiedc5e945d"))) return;

    setRejecting(true);
    setRejectError(null);

    try {
      await rejectAssignment(accessToken, assignment.id);
      onRejected?.(assignment.id);
      onClose();
    } catch (err) {
      if (err instanceof ApiError && err.status === 422) {
        setRejectError(i18n("thisWorkoutIsAlreadyRejected9605eb6"));
      } else {
        setRejectError(err instanceof Error ? err.message : i18n("failedToRejectWorkout6939c34"));
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
      setRescheduleError(err instanceof Error ? err.message : i18n("couldNotReschedulefaa6dd2"));
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
        className="fixed end-0 z-50 flex w-full flex-col overflow-hidden md:max-w-[480px]"
        style={{ background: "var(--bg)", borderInlineStart: "1px solid var(--border)", top: "3.25rem", bottom: 0 }}
      >
        {/* Sticky header */}
        <div
          className="sticky top-0 z-10 flex items-center justify-between gap-4 px-5 py-4"
          style={{
            background: "var(--bg)",
            borderBottom: "1px solid var(--border)",
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
                  style={{ background: "color-mix(in srgb, var(--warning) 15%, transparent)", color: "var(--warning)", border: "1px solid color-mix(in srgb, var(--warning) 35%, transparent)" }}
                >
                  {i18n("team2188872")}
                </span>
              ) : null}
            </div>
            <h2
              className="mt-0.5 truncate text-base font-bold"
              style={{ color: "var(--text)" }}
            >
              {assignment.workout.title}
            </h2>
            {scaleLevels.length > 0 ? (
              <div className="mt-2 flex flex-wrap gap-1.5">
                <button
                  className="rounded-full px-2.5 py-1 text-[10px] font-semibold transition-colors"
                  style={{
                    background: activeScale === null ? "var(--text)" : "var(--border)",
                    color: activeScale === null ? "var(--bg)" : "var(--text-soft)",
                    border: activeScale === null ? "1px solid var(--text)" : "1px solid var(--border-strong)",
                  }}
                  onClick={() => setActiveScale(null)}
                  type="button"
                >
                  {i18n("base077fe9c")}
                </button>
                {scaleLevels.map((sl) => (
                  <button
                    key={sl.slug}
                    className="rounded-full px-2.5 py-1 text-[10px] font-semibold transition-colors"
                    style={{
                      background: activeScale === sl.slug ? "color-mix(in srgb, var(--primary) 22%, transparent)" : "var(--border)",
                      color: activeScale === sl.slug ? "var(--primary-strong)" : "var(--text-soft)",
                      border: activeScale === sl.slug ? "1px solid color-mix(in srgb, var(--primary) 50%, transparent)" : "1px solid var(--border-strong)",
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
              style={{ background: "var(--border)", color: "var(--muted)" }}
              onClick={onClose}
              type="button"
            >
              {i18n("closefeb3e25")}
            </button>
            <button
              className="rounded-full px-3 py-1 text-[10px] font-semibold transition-colors"
              style={{ background: "var(--border)", color: "var(--dim)", border: "1px solid var(--border)" }}
              onClick={() =>
                downloadIcsEvent({
                  title: assignment.workout.title,
                  date: assignment.scheduled_for,
                  description: assignment.admin_notes ?? undefined,
                })
              }
              type="button"
            >
              {i18n("calendar4e44752")}
            </button>
          </div>
        </div>

        {/* Scrollable body */}
        <div className="flex-1 overflow-y-auto px-5 py-5 space-y-3">
          <section className="overflow-hidden rounded-[1.2rem]" style={{ border: "1px solid var(--border)" }}>
            <button
              className="flex w-full items-center justify-between gap-3 px-4 py-3 text-start"
              style={{ background: "var(--panel-muted)" }}
              onClick={() => setActiveSection("details")}
              type="button"
            >
              <span className="text-sm font-medium" style={{ color: "var(--text)" }}>
                {i18n("workoutDetails9366821")}
              </span>
              <span style={{ color: "var(--dim)" }}>{activeSection === "details" ? "▲" : "▼"}</span>
            </button>

            {activeSection === "details" ? (
              <div className="space-y-6 px-4 py-4">
                {/* Workout preview */}
                <section>
                  <p
                    className="mb-3 text-xs font-semibold uppercase tracking-[0.2em]"
                    style={{ color: "var(--dim)" }}
                  >
                    {i18n("workout39463a5")}
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
                    style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 15%, transparent)", color: "var(--primary-strong)" }}
                  >
                    <p className="mb-1 text-[10px] font-bold uppercase tracking-[0.18em]" style={{ color: "var(--primary)" }}>
                      {i18n("coachNotee98376b")}
                    </p>
                    {assignment.admin_notes}
                  </section>
                ) : null}

                {/* Admin controls */}
                {isAdmin ? (
                  <section className="space-y-3">
              {(assignment.athletes ?? []).length > 0 ? (
                <div>
                  <p className="mb-2 text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
                    {i18n("assignedAthletes3f6c5e6")}
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {(assignment.athletes ?? []).map((athlete) => (
                      <span
                        key={athlete.id}
                        className="rounded-full px-3 py-1 text-xs font-semibold"
                        style={{ background: "color-mix(in srgb, var(--primary) 15%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 25%, transparent)", color: "var(--primary)" }}
                      >
                        {athlete.nickname}
                      </span>
                    ))}
                  </div>
                </div>
              ) : null}

              <div>
                <p className="mb-2 text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
                  {i18n("scheduledFor4cbbcd5")}
                </p>
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {assignment.scheduled_for}
                </p>
              </div>

              <div className="flex flex-wrap gap-2 pt-1">
                {onEditWorkout ? (
                  <button
                    className="rounded-full px-4 py-2 text-xs font-semibold transition-colors"
                    style={{ background: "color-mix(in srgb, var(--muted) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--muted) 20%, transparent)", color: "var(--muted)" }}
                    onClick={() => onEditWorkout(assignment)}
                    type="button"
                  >
                    {i18n("editWorkoutd299ce5")}
                  </button>
                ) : null}
                <button
                  className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50 transition-colors"
                  style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
                  disabled={deleting}
                  onClick={() => void handleDelete()}
                  type="button"
                >
                  {deleting ? i18n("deletingc7ac551") : i18n("deleteAssignmentd46dbbc")}
                </button>
              </div>
              {deleteError ? (
                <p className="text-xs" style={{ color: "var(--primary-strong)" }}>{deleteError}</p>
              ) : null}
                  </section>
                ) : null}

                {/* Athlete actions: Reject + Reschedule side-by-side */}
                {!isAdmin ? (
                  <section className="pb-4">
                    {rejectError ? (
                      <p className="mb-2 text-xs" style={{ color: "var(--primary-strong)" }}>{rejectError}</p>
                    ) : null}
                    {!rescheduling ? (
                      <div className="flex gap-2">
                        <button
                          className="flex-1 rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                          style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)" }}
                          disabled={rejecting}
                          onClick={() => void handleReject()}
                          type="button"
                        >
                          {rejecting ? i18n("rejecting812b8d2") : i18n("rejectWorkouta584840")}
                        </button>
                        <button
                          className="flex-1 rounded-full px-4 py-2 text-sm font-semibold"
                          style={{ background: "var(--border)", color: "var(--text-soft)" }}
                          onClick={() => {
                            setRescheduleDate(assignment.scheduled_for);
                            setRescheduling(true);
                          }}
                          type="button"
                        >
                          {i18n("reschedule34b2dc9")}
                        </button>
                      </div>
                    ) : (
                      <div className="space-y-2">
                        <input
                          className="w-full rounded-[1rem] px-4 py-2 text-sm outline-none"
                          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                          type="date"
                          min={todayIso}
                          value={rescheduleDate}
                          onChange={(e) => setRescheduleDate(e.target.value)}
                        />
                        {rescheduleError ? (
                          <p className="text-xs" style={{ color: "var(--primary-strong)" }}>{rescheduleError}</p>
                        ) : null}
                        <div className="flex gap-2">
                          <button
                            className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                            style={{ background: "var(--text)", color: "var(--bg)" }}
                            disabled={rescheduleSaving || !rescheduleDate}
                            onClick={() => void handleReschedule()}
                            type="button"
                          >
                            {rescheduleSaving ? i18n("saving56a2285") : i18n("confirm04a2122")}
                          </button>
                          <button
                            className="rounded-full px-4 py-2 text-sm font-semibold"
                            style={{ background: "var(--border)", color: "var(--muted)" }}
                            onClick={() => setRescheduling(false)}
                            type="button"
                          >
                            {i18n("cancel77dfd21")}
                          </button>
                        </div>
                      </div>
                    )}
                  </section>
                ) : null}

                {/* Completion scores */}
                {assignment.execution_status === "completed" && (assignment.execution_scores ?? []).length > 0 ? (
                  <section>
                    <p
                      className="mb-3 text-xs font-semibold uppercase tracking-[0.2em]"
                      style={{ color: "var(--dim)" }}
                    >
                      {i18n("yourScores842c2ab")}
                    </p>
                    <div className="space-y-2">
                      {(assignment.execution_scores ?? []).map((score, index) => (
                        <div
                          key={score.section_id ?? index}
                          className="flex items-center justify-between rounded-[1rem] px-4 py-2.5"
                          style={{ background: "color-mix(in srgb, var(--success) 8%, transparent)", border: "1px solid color-mix(in srgb, var(--success) 15%, transparent)" }}
                        >
                          <span className="text-xs" style={{ color: "var(--muted)" }}>
                            {score.section_name ?? score.section_id}
                          </span>
                          <span className="text-sm font-semibold" style={{ color: "var(--success)" }}>
                            {score.value}{score.unit ? (score.unit) : ""}
                          </span>
                        </div>
                      ))}
                    </div>
                  </section>
                ) : null}
              </div>
            ) : null}
          </section>

          <ChatSection
            contextType="assignment"
            contextId={assignment.id}
            isExpanded={activeSection === "conversation"}
            onToggle={() => setActiveSection("conversation")}
            participantNicknames={
              isAdmin
                ? Object.fromEntries(
                    (assignment.athletes ?? []).map((a) => [a.id, a.nickname ?? a.id]),
                  )
                : {}
            }
          />

        </div>

        {/* Bottom CTA */}
        {activeSection === "details" ? (
          <div
            className="border-t px-5 py-4"
            style={{ borderColor: "var(--border)", background: "var(--bg)" }}
          >
          {assignment.execution_status === "completed" && assignment.scheduled_for <= todayIso ? (
            <button
              className="w-full rounded-full py-3 text-sm font-bold tracking-wide disabled:opacity-50"
              style={{ background: "color-mix(in srgb, var(--success) 15%, transparent)", border: "1px solid color-mix(in srgb, var(--success) 30%, transparent)", color: "var(--success)" }}
              disabled={launching}
              onClick={() => onStartWorkout(assignment)}
              type="button"
            >
              {launching ? i18n("startinge5f5809") : i18n("redoWorkout0f2cad2")}
            </button>
          ) : (
            <button
              className="w-full rounded-full py-3 text-sm font-bold tracking-wide disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              disabled={launching}
              onClick={() => onStartWorkout(assignment)}
              type="button"
            >
              {launching ? i18n("startinge5f5809") : i18n("startWorkoutd1072dd")}
            </button>
          )}
          </div>
        ) : null}
      </div>
    </>
  );
}
