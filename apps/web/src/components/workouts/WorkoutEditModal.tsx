"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import { duplicateWorkout, reopenWorkout } from "@/api/workouts";

type GlobalContext = {
  kind: "global";
};

type ContextualContext = {
  kind: "assignment" | "slot";
  sourceId: string;
  sourceLabel: string;
};

export type WorkoutEditContext = GlobalContext | ContextualContext;

type Props = {
  workoutId: string;
  workoutTitle: string;
  accessToken: string;
  context: WorkoutEditContext;
  onClose: () => void;
};

export function WorkoutEditModal({
  workoutId,
  workoutTitle,
  accessToken,
  context,
  onClose,
}: Props) {
  const router = useRouter();
  const [busy, setBusy] = useState<"reopen" | "duplicate" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const firstButtonRef = useRef<HTMLButtonElement>(null);
  const headingId = `workout-edit-modal-${workoutId}`;

  useEffect(() => {
    firstButtonRef.current?.focus();
  }, []);

  async function handleReopen() {
    setBusy("reopen");
    setError(null);
    try {
      await reopenWorkout(accessToken, workoutId);
      router.push(`/admin/workouts/new?draft=${workoutId}&is_reopen=true`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to reopen workout.");
      setBusy(null);
    }
  }

  async function handleDuplicate() {
    setBusy("duplicate");
    setError(null);
    try {
      const dupeContext =
        context.kind === "assignment"
          ? { assignment_id: context.sourceId }
          : context.kind === "slot"
            ? { slot_id: context.sourceId }
            : undefined;
      const draft = await duplicateWorkout(accessToken, workoutId, dupeContext);
      const substituteParam =
        context.kind === "assignment"
          ? `&substitute_for_assignment=${context.sourceId}`
          : context.kind === "slot"
            ? `&substitute_for_slot=${context.sourceId}`
            : "";
      router.push(`/admin/workouts/new?draft=${draft.id}${substituteParam}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to duplicate workout.");
      setBusy(null);
    }
  }

  const isContextual = context.kind === "assignment" || context.kind === "slot";
  const sourceLabel =
    context.kind === "assignment"
      ? "this assignment only"
      : context.kind === "slot"
        ? "this class only"
        : null;

  return (
    <>
      <div
        className="fixed inset-0 z-50 flex items-center justify-center p-4"
        style={{ background: "rgba(0,0,0,0.65)" }}
        onClick={onClose}
        role="presentation"
      >
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby={headingId}
          className="w-full max-w-md rounded-[2rem] p-6"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
          onClick={(e) => e.stopPropagation()}
        >
          <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
            {isContextual ? "Edit published workout" : "Editing live workout"}
          </p>

          <h2 id={headingId} className="mt-2 text-xl font-bold" style={{ color: "var(--text)" }}>
            {workoutTitle}
          </h2>

          <p className="mt-3 text-sm leading-6" style={{ color: "var(--muted)" }}>
            {isContextual
              ? "This workout is published and may be assigned to other athletes or scheduled in other class slots. Choose how to proceed:"
              : "This workout is live. Editing and re-publishing will immediately update all athlete assignments and scheduled classes that reference it. Affected users will be notified."}
          </p>

          {error ? (
            <p className="mt-3 text-xs" style={{ color: "var(--primary-strong)" }}>{error}</p>
          ) : null}

          <div className="mt-6 flex flex-col gap-3">
            {isContextual ? (
              <>
                <button
                  ref={firstButtonRef}
                  className="rounded-full px-4 py-3 text-sm font-semibold disabled:opacity-50"
                  style={{ background: "var(--text)", color: "var(--bg)" }}
                  disabled={busy !== null}
                  onClick={() => void handleDuplicate()}
                  type="button"
                >
                  {busy === "duplicate"
                    ? "Duplicating…"
                    : `Duplicate and edit for ${sourceLabel}`}
                </button>

                <button
                  className="rounded-full px-4 py-3 text-sm font-semibold disabled:opacity-50"
                  style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
                  disabled={busy !== null}
                  onClick={() => void handleReopen()}
                  type="button"
                >
                  {busy === "reopen" ? "Opening…" : "Proceed to edit globally"}
                </button>
              </>
            ) : (
              <button
                ref={firstButtonRef}
                className="rounded-full px-4 py-3 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                disabled={busy !== null}
                onClick={() => void handleReopen()}
                type="button"
              >
                {busy === "reopen" ? "Opening…" : "Edit globally"}
              </button>
            )}

            <button
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--border)", color: "var(--muted)" }}
              disabled={busy !== null}
              onClick={onClose}
              type="button"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </>
  );
}
