"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { changeClassState, type ClassAction, type ClassStateResult, type ScheduleSlot, type SeriesEditScope } from "@/api/schedule";
import { classStateBadge } from "@/components/schedule/member-booking";
import { SeriesScopePicker, seriesScopeReady } from "@/components/schedule/SeriesScopePicker";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const TONE = {
  cancelled: "var(--danger)",
  paused: "var(--warning)",
} as const;

/** ADR-200: «Cancelled» or «Booking paused» on a class, wherever it is listed. */
export function ClassStateBadge({ slot }: { slot: ScheduleSlot }) {
  const t = useTranslations("Schedule");
  const state = classStateBadge(slot);
  if (!state) return null;

  return (
    <span
      className="inline-block rounded-full px-2 py-0.5 text-[10px] font-bold"
      data-testid="class-state-badge"
      style={{ background: `color-mix(in srgb, ${TONE[state]} 14%, transparent)`, color: TONE[state] }}
    >
      {state === "cancelled" ? t("classStateCancelled") : t("classStatePaused")}
    </span>
  );
}

/** The class's state in its detail view, with the reason a cancel gave. */
export function ClassStateNotice({ slot, className = "" }: { slot: ScheduleSlot; className?: string }) {
  const t = useTranslations("Schedule");
  const state = classStateBadge(slot);
  if (!state) return null;

  const text =
    state === "paused"
      ? t("classStatePausedNotice")
      : slot.cancel_reason
        ? t("classStateCancelledReason", { reason: slot.cancel_reason })
        : t("classStateCancelledNotice");

  return (
    <p
      role="status"
      data-testid="class-state-notice"
      className={`rounded-2xl px-4 py-3 text-sm font-semibold ${className}`}
      style={{
        background: `color-mix(in srgb, ${TONE[state]} 12%, transparent)`,
        border: `1px solid color-mix(in srgb, ${TONE[state]} 30%, transparent)`,
        color: TONE[state],
      }}
    >
      {text}
    </p>
  );
}

/** The state actions staff can take on an upcoming class. */
export function classActionsFor(slot: ScheduleSlot): ClassAction[] {
  if (slot.cancelled_at) return ["restore", "delete"];
  return [slot.paused_at ? "resume" : "pause", "cancel", "delete"];
}

/** What staff see after an action: how many classes changed and why some didn't. */
export function useClassActionSummary() {
  const t = useTranslations("Schedule");

  return (result: ClassStateResult) =>
    [
      result.changed_count > 1 || result.skipped_count > 0 ? t("classActionDone", { count: result.changed_count }) : null,
      result.released_count > 0 ? t("classActionReleased", { count: result.released_count }) : null,
      result.skipped_with_bookings > 0 ? t("classActionSkippedBookings", { count: result.skipped_with_bookings }) : null,
      result.skipped_count > result.skipped_with_bookings
        ? t("classActionSkipped", { count: result.skipped_count - result.skipped_with_bookings })
        : null,
    ]
      .filter(Boolean)
      .join(" ");
}

/**
 * ADR-200 §2: confirms a pause, resume, cancel, restore or delete. A class of
 * a series offers the same reach as an edit: this class, all upcoming, or a
 * date range, optionally every nth. A cancel asks for a reason members see.
 */
export function ClassActionDialog({
  token,
  slot,
  action,
  classDate,
  onClose,
  onDone,
}: {
  token: string;
  slot: ScheduleSlot;
  action: ClassAction;
  /** The class's date on the gym's clock (YYYY-MM-DD). */
  classDate: string;
  onClose: () => void;
  onDone: (result: ClassStateResult) => void;
}) {
  const t = useTranslations("Schedule");
  const common = useTranslations("Common");
  const i18n = useUiTranslations();
  const [scope, setScope] = useState<SeriesEditScope>({ scope: "this" });
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const danger = action === "cancel" || action === "delete";

  async function confirm() {
    if (busy || !seriesScopeReady(scope)) return;
    setBusy(true);
    setError(null);
    try {
      onDone(await changeClassState(token, slot.id, action, slot.class_series_id ? scope : { scope: "this" }, reason));
    } catch (cause) {
      setError(cause instanceof Error ? localizeError(cause, i18n) : t("classActionFailed"));
      setBusy(false);
    }
  }

  return (
    <Dialog
      onClose={onClose}
      title={t(`classActionTitle_${action}`)}
      size="md"
      footer={
        <div className="flex flex-wrap gap-3">
          <button
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            onClick={onClose}
            type="button"
          >
            {t("classActionKeep")}
          </button>
          <button
            className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
            style={danger ? { background: "var(--danger)", color: "var(--danger-contrast)" } : { background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={busy || !seriesScopeReady(scope)}
            onClick={() => void confirm()}
            type="button"
          >
            {busy ? common("saving") : t(`classActionConfirm_${action}`)}
          </button>
        </div>
      }
    >
      <div className="space-y-4">
        <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
          {t(`classActionBody_${action}`)}
        </p>
        {action === "cancel" ? (
          <label className="block space-y-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
            <span>{t("classCancelReasonLabel")}</span>
            <input
              className="w-full rounded-2xl px-4 py-3 outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              maxLength={280}
              onChange={(event) => setReason(event.target.value)}
              placeholder={t("classCancelReasonPlaceholder")}
              value={reason}
            />
          </label>
        ) : null}
        {slot.class_series_id ? (
          <SeriesScopePicker className="" value={scope} onChange={setScope} classDate={classDate} />
        ) : null}
        {error ? <ErrorNotice>{error}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
