"use client";

import { useState } from "react";

import { ApiError } from "@/api/client";
import { deleteAssignedWorkout, rejectAssignment, sendAssignmentMessage, type AssignedWorkoutRecord } from "@/api/assigned-workouts";
import { WorkoutPreviewDetail, type PreviewSection } from "@/components/workouts/WorkoutPreviewDetail";
import { workoutTypeColor } from "@/lib/workout-colors";

type Props = {
  assignment: AssignedWorkoutRecord;
  isAdmin: boolean;
  accessToken: string;
  onClose: () => void;
  onStartWorkout: (assignment: AssignedWorkoutRecord) => void;
  onRejected?: (assignmentId: string) => void;
  onDeleted?: (assignmentId: string) => void;
  onEditWorkout?: (assignment: AssignedWorkoutRecord) => void;
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
  launching,
}: Props) {
  const [messageText, setMessageText] = useState("");
  const [messageSending, setMessageSending] = useState(false);
  const [messageSent, setMessageSent] = useState(false);
  const [messageError, setMessageError] = useState<string | null>(null);
  const [rejecting, setRejecting] = useState(false);
  const [rejectError, setRejectError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

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

  async function handleSendMessage() {
    if (!messageText.trim()) return;
    setMessageSending(true);
    setMessageError(null);

    try {
      await sendAssignmentMessage(accessToken, assignment.id, messageText.trim());
      setMessageSent(true);
      setMessageText("");
    } catch (err) {
      setMessageError(err instanceof Error ? err.message : "Failed to send message.");
    } finally {
      setMessageSending(false);
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
        className="fixed inset-y-0 right-0 z-50 flex w-full flex-col overflow-hidden md:max-w-[480px]"
        style={{ background: "#0A0A0F", borderLeft: "1px solid #1a1a28" }}
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
            <p
              className="truncate text-xs font-semibold uppercase tracking-[0.2em]"
              style={{ color: workoutTypeColor(assignment.workout.type) }}
            >
              {assignment.workout.type}
            </p>
            <h2
              className="mt-0.5 truncate text-base font-bold"
              style={{ color: "#F0EDF8" }}
            >
              {assignment.workout.title}
            </h2>
          </div>
          <button
            className="shrink-0 rounded-full px-3 py-1 text-xs font-semibold transition-colors"
            style={{ background: "#1a1a28", color: "#8888aa" }}
            onClick={onClose}
            type="button"
          >
            Close ✕
          </button>
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
            <WorkoutPreviewDetail sections={sections} initiallyExpanded />
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

          {/* Message form — non-admin users */}
          {!isAdmin ? (
            <section>
              <p
                className="mb-2 text-xs font-semibold uppercase tracking-[0.2em]"
                style={{ color: "#55556a" }}
              >
                Message your coach
              </p>

              {messageSent ? (
                <p
                  className="rounded-[1.2rem] px-4 py-3 text-sm font-semibold"
                  style={{ background: "rgba(16,185,129,0.1)", border: "1px solid rgba(16,185,129,0.2)", color: "#34d399" }}
                >
                  Message sent to your coach.
                </p>
              ) : (
                <div className="space-y-2">
                  <textarea
                    className="w-full rounded-[1rem] px-4 py-3 text-sm outline-none"
                    style={{
                      background: "#111118",
                      border: "1px solid #1e1e2e",
                      color: "#F0EDF8",
                      minHeight: "6rem",
                      resize: "vertical",
                    }}
                    placeholder="Ask a question or send a note about this workout…"
                    value={messageText}
                    onChange={(e) => setMessageText(e.target.value)}
                    maxLength={1000}
                  />
                  {messageError ? (
                    <p className="text-xs" style={{ color: "#e07a5f" }}>{messageError}</p>
                  ) : null}
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                    style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                    disabled={messageSending || !messageText.trim()}
                    onClick={() => void handleSendMessage()}
                    type="button"
                  >
                    {messageSending ? "Sending…" : "Send message"}
                  </button>
                </div>
              )}
            </section>
          ) : null}

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
        </div>

        {/* Bottom CTA */}
        <div
          className="border-t px-5 py-4"
          style={{ borderColor: "#1a1a28", background: "#0A0A0F" }}
        >
          <button
            className="w-full rounded-full py-3 text-sm font-bold tracking-wide disabled:opacity-50"
            style={{ background: "#d95d39", color: "#fff" }}
            disabled={launching}
            onClick={() => onStartWorkout(assignment)}
            type="button"
          >
            {launching ? "Starting…" : "Start Workout"}
          </button>
        </div>
      </div>
    </>
  );
}
