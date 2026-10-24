"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { ApiError } from "@/api/client";
import {
  cancelAdminUserFreeze,
  createAdminUserFreeze,
  fetchAdminUserFreezes,
  type MembershipFreeze,
} from "@/api/admin-users";
import {
  freezeDays,
  freezeDaysPerYear,
  freezeDaysUsedInYear,
  freezeState,
  localIsoDate,
  type FreezeState,
} from "@/components/admin/users/membership-freezes";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { DateInput } from "@/components/ui/DateInput";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const STATE_KEYS: Record<FreezeState, string> = {
  upcoming: "admFreezeStateUpcoming",
  active: "admFreezeStateActive",
  ended: "admFreezeStateEnded",
  cancelled: "admFreezeStateCancelled",
};

const fieldStyle = { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" };

/** Package freezes of a member (ADR-097): the package end date moves out by the frozen days. */
export function MembershipFreezes({
  token,
  userId,
  subscriptions,
  onRefresh,
}: {
  token: string;
  userId: string;
  subscriptions: Array<Record<string, unknown>>;
  onRefresh: () => Promise<unknown>;
}) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const today = localIsoDate();
  const year = Number(today.slice(0, 4));
  const [form, setForm] = useState<{ starts_on: string; ends_on: string; reason: string } | null>(null);
  const [cancelTarget, setCancelTarget] = useState<string | null>(null);
  const [cancelReason, setCancelReason] = useState("");

  const queryKey = ["admin", "users", userId, "freezes"];
  const freezesQuery = useQuery({ queryKey, queryFn: () => fetchAdminUserFreezes(token, userId) });
  const freezes = freezesQuery.data ?? [];
  const perYear = freezeDaysPerYear(subscriptions);
  const remaining = Math.max(perYear - freezeDaysUsedInYear(freezes, year), 0);

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey });
    await onRefresh();
  };

  const create = useMutation({
    mutationFn: () => createAdminUserFreeze(token, userId, { ...form!, reason: form!.reason.trim() }),
    onSuccess: async () => {
      setForm(null);
      await refresh();
    },
  });

  const cancel = useMutation({
    mutationFn: (freeze: MembershipFreeze) => cancelAdminUserFreeze(token, userId, freeze.id, cancelReason.trim() || undefined),
    onSuccess: async () => {
      setCancelTarget(null);
      setCancelReason("");
      await refresh();
    },
  });

  // Freeze errors carry no numbers, so the days left are added from the local count.
  const createError = create.error
    ? [
        localizeError(create.error, i18n),
        create.error instanceof ApiError && create.error.payload.code === "freeze_allowance_exceeded"
          ? i18n("admFreezeDaysLeft", { remaining, total: perYear, year: String(year) })
          : null,
      ].filter(Boolean).join(" ")
    : null;

  if (perYear === 0 && freezes.length === 0) {
    return freezesQuery.isSuccess ? <p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("admFreezeNoneInPackage")}</p> : null;
  }

  const requested = form ? freezeDays(form.starts_on, form.ends_on) : 0;

  return (
    <div className="space-y-3 rounded-[1.25rem] p-4" style={{ border: "1px solid var(--border)" }}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="font-semibold" style={{ color: "var(--text)" }}>{i18n("admFreezesTitle")}</p>
          {perYear > 0 ? <p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("admFreezeDaysLeft", { remaining, total: perYear, year: String(year) })}</p> : null}
        </div>
        {!form && perYear > 0 ? (
          <button
            className="rounded-full px-4 py-2 text-xs font-semibold"
            onClick={() => { create.reset(); setForm({ starts_on: today, ends_on: "", reason: "" }); }}
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            type="button"
          >
            {i18n("admFreezeMembership")}
          </button>
        ) : null}
      </div>

      {form ? (
        <form
          className="space-y-3 rounded-2xl p-4"
          onSubmit={(event) => { event.preventDefault(); create.mutate(); }}
          style={{ border: "1px solid var(--border)" }}
        >
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="text-xs font-semibold" style={{ color: "var(--muted)" }}>
              {i18n("admFreezeFrom")}
              <DateInput className="mt-1 w-full rounded-xl px-3 py-2" min={today} onValueChange={(value) => setForm({ ...form, starts_on: value })} required style={fieldStyle} value={form.starts_on} />
            </label>
            <label className="text-xs font-semibold" style={{ color: "var(--muted)" }}>
              {i18n("admFreezeUntil")}
              <DateInput className="mt-1 w-full rounded-xl px-3 py-2" min={form.starts_on || today} onValueChange={(value) => setForm({ ...form, ends_on: value })} required style={fieldStyle} value={form.ends_on} />
            </label>
          </div>
          <input
            aria-label={i18n("admFreezeReason")}
            className="w-full rounded-xl px-3 py-2"
            minLength={3}
            onChange={(event) => setForm({ ...form, reason: event.target.value })}
            placeholder={i18n("admFreezeReason")}
            required
            style={fieldStyle}
            value={form.reason}
          />
          {requested > 0 ? <p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("admFreezeSummary", { days: requested })}</p> : null}
          <div className="flex flex-wrap gap-2">
            <button
              className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50"
              disabled={create.isPending || requested === 0 || form.reason.trim().length < 3}
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              type="submit"
            >
              {i18n("admFreezeConfirm")}
            </button>
            <button className="rounded-full px-4 py-2 text-xs font-semibold" onClick={() => setForm(null)} style={{ background: "var(--border)", color: "var(--text-soft)" }} type="button">
              {i18n("cancel77dfd21")}
            </button>
          </div>
          {createError ? <ErrorNotice variant="field">{createError}</ErrorNotice> : null}
        </form>
      ) : null}

      {freezes.map((freeze) => {
        const state = freezeState(freeze, today);
        const cancellable = state === "upcoming" || state === "active";
        return (
          <div className="rounded-xl p-3" key={freeze.id} style={{ background: "var(--panel-muted)" }}>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <strong style={{ color: state === "cancelled" ? "var(--muted)" : "var(--text)" }}>
                  {freeze.starts_on.slice(0, 10)} → {freeze.ends_on.slice(0, 10)}
                </strong>
                <p className="text-xs" style={{ color: "var(--muted)" }}>
                  {i18n(STATE_KEYS[state])} · {i18n("admFreezeExtension", { days: freeze.extension_days })} · {freeze.reason}
                </p>
                {freeze.cancel_reason ? <p className="text-xs" style={{ color: "var(--muted)" }}>{freeze.cancel_reason}</p> : null}
              </div>
              {cancellable && cancelTarget !== freeze.id ? (
                <button className="text-xs font-semibold" onClick={() => { cancel.reset(); setCancelTarget(freeze.id); }} style={{ color: "var(--danger)" }} type="button">
                  {i18n("admFreezeCancel")}
                </button>
              ) : null}
            </div>
            {cancelTarget === freeze.id ? (
              <div className="mt-3 space-y-2">
                <p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("admFreezeCancelHint")}</p>
                <div className="flex flex-col gap-2 sm:flex-row">
                  <input
                    aria-label={i18n("admFreezeCancelReason")}
                    className="min-w-0 flex-1 rounded-xl px-3 py-2"
                    onChange={(event) => setCancelReason(event.target.value)}
                    placeholder={i18n("admFreezeCancelReason")}
                    style={fieldStyle}
                    value={cancelReason}
                  />
                  <button className="rounded-full px-3 py-2 text-xs font-semibold disabled:opacity-50" disabled={cancel.isPending} onClick={() => cancel.mutate(freeze)} style={{ background: "var(--danger)", color: "var(--danger-contrast)" }} type="button">
                    {i18n("admFreezeCancel")}
                  </button>
                  <button className="rounded-full px-3 py-2 text-xs font-semibold" onClick={() => setCancelTarget(null)} style={{ background: "var(--border)", color: "var(--text-soft)" }} type="button">
                    {i18n("admFreezeKeep")}
                  </button>
                </div>
                {cancel.error ? <ErrorNotice variant="field">{localizeError(cancel.error, i18n)}</ErrorNotice> : null}
              </div>
            ) : null}
          </div>
        );
      })}
    </div>
  );
}
