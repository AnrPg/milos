"use client";

import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  actOnFailedCharge,
  declineReason,
  fetchFailedCharges,
  type FailedCharge,
  type FailedChargeAction,
} from "@/api/online-payments";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { addDaysToKey, dateKeyInZone, formatInZone } from "@/lib/zoned-time";

import { paymentErrorText } from "./payment-errors";

export const FAILED_CHARGES_KEY = ["admin", "payments", "attention"] as const;

type Translate = (key: string, values?: Record<string, string | number>) => string;

/** ADR-260: saved-card charges that need a person (Οικονομικά › Ουρές). */
export function useFailedCharges(token: string | null | undefined, enabled: boolean) {
  return useQuery({
    queryKey: FAILED_CHARGES_KEY,
    enabled: Boolean(token) && enabled,
    queryFn: async () => (await fetchFailedCharges(token!)).payments,
  });
}

/**
 * The next step of a failed charge, on the gym's clock: «Νέα προσπάθεια
 * αύριο 06:00 (2 από 3)» while a retry is due, else waiting for the member.
 */
export function nextStepText(
  charge: Pick<FailedCharge, "status" | "next_attempt_at" | "declines" | "retries">,
  t: Translate,
  locale: string,
  zone: string | null,
  now: Date = new Date(),
): string {
  if (charge.status !== "scheduled" || !charge.next_attempt_at) return t("waitingCard");
  const at = charge.next_attempt_at;
  const counts = { attempt: Math.min(Math.max(charge.declines, 1), charge.retries), total: charge.retries };
  const time = formatInZone(at, zone, locale, "time");
  const day = dateKeyInZone(at, zone);
  const today = dateKeyInZone(now, zone);
  if (day <= today) return t("nextToday", { time, ...counts });
  if (day === addDaysToKey(today, 1)) return t("nextTomorrow", { time, ...counts });
  return t("nextOn", { when: formatInZone(at, zone, locale, "day-time"), ...counts });
}

function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");
}

type Done = { text: string; ok: boolean };

/** The «Αποτυχημένες χρεώσεις» group: who, what, why, what happens next, and what staff can do. */
export function FailedChargesList({
  token,
  charges,
  loading,
  canRetry,
}: {
  token: string;
  charges: FailedCharge[];
  loading: boolean;
  canRetry: boolean;
}) {
  const t = useTranslations("OnlinePayments");
  return (
    <div data-testid="failed-charges">
      <p className="border-b px-6 py-4 text-sm" style={{ color: "var(--dim)", borderColor: "var(--border)" }}>{t("queueHint")}</p>
      {loading ? (
        <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{t("queueLoading")}</p>
      ) : charges.length === 0 ? (
        <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{t("queueEmpty")}</p>
      ) : (
        <ul>
          {charges.map((charge, index) => (
            <FailedChargeRow key={charge.id} token={token} charge={charge} last={index === charges.length - 1} canRetry={canRetry} />
          ))}
        </ul>
      )}
    </div>
  );
}

function FailedChargeRow({ token, charge, last, canRetry }: { token: string; charge: FailedCharge; last: boolean; canRetry: boolean }) {
  const t = useTranslations("OnlinePayments");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  const [done, setDone] = useState<Done | null>(null);

  const mutation = useMutation({
    mutationFn: (action: FailedChargeAction) => actOnFailedCharge(token, charge.id, action),
    onSuccess: ({ payment }, action) => {
      if (action === "retry-charge") {
        setDone(payment.status === "succeeded" ? { text: t("doneRetryOk"), ok: true } : { text: t("doneRetryFailed"), ok: false });
      } else if (action === "card-link") {
        setDone({ text: t("doneCardLink"), ok: true });
      } else {
        setDone({ text: t("doneDismiss"), ok: true });
      }
    },
  });

  const name = charge.member_name || t("memberUnknown");
  let amount: string;
  try {
    amount = new Intl.NumberFormat(locale, { style: "currency", currency: charge.currency }).format(charge.amount_cents / 100);
  } catch {
    amount = `${(charge.amount_cents / 100).toFixed(2)} ${charge.currency}`;
  }
  const reason = t(`reason_${declineReason(charge.failure_code)}`);

  return (
    <li
      className="flex flex-col gap-3 px-6 py-4 sm:flex-row sm:items-center"
      style={{ borderBottom: last ? undefined : "1px solid var(--border)" }}
      data-testid="failed-charge"
    >
      <div className="flex min-w-0 flex-1 items-start gap-3">
        <span
          aria-hidden="true"
          className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-xs font-bold"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {initials(name)}
        </span>
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{name}</p>
          <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs" style={{ color: "var(--muted)" }}>
            <span>{charge.description} · {amount}</span>
            {reason ? (
              <span className="rounded-full px-2 py-0.5 font-semibold" style={{ background: "var(--danger-surface)", color: "var(--danger-strong)" }}>
                {reason}
              </span>
            ) : null}
            <span>{done ? done.text : nextStepText(charge, t, locale, zone)}</span>
          </div>
          {mutation.isError ? (
            <ErrorNotice variant="text" className="mt-1 text-xs">{paymentErrorText(mutation.error, t, ui)}</ErrorNotice>
          ) : null}
        </div>
      </div>
      <div className="flex flex-wrap gap-2 sm:justify-end">
        {done?.ok ? (
          <span className="rounded-full px-2.5 py-1 text-xs font-semibold" style={{ background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--text)" }}>
            ✓ {t("doneBadge")}
          </span>
        ) : (
          <>
            {canRetry ? <ActionButton label={t("actionRetry")} busy={mutation.isPending} onClick={() => mutation.mutate("retry-charge")} /> : null}
            <ActionButton label={t("actionCardLink")} busy={mutation.isPending} onClick={() => mutation.mutate("card-link")} />
            <ActionButton label={t("actionDismiss")} busy={mutation.isPending} onClick={() => mutation.mutate("dismiss")} />
          </>
        )}
      </div>
    </li>
  );
}

function ActionButton({ label, busy, onClick }: { label: string; busy: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      disabled={busy}
      onClick={onClick}
      className="rounded-full px-3 py-1.5 text-xs font-semibold disabled:opacity-60"
      style={{ border: "1px solid var(--border)", color: "var(--text)", background: "transparent" }}
    >
      {label}
    </button>
  );
}
