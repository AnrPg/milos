"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  leaveProvider,
  MY_BILLING_QUERY_KEY,
  setMyAutoRenew,
  stayWithProvider,
  type BillingProvider,
  type BillingSubscription,
} from "@/api/my-billing";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { canStay, leaveState } from "./billing-model";

/**
 * ADR-220: the member's own «Αυτόματη ανανέωση» for their current package.
 * Off: the package ends with the period they paid for and no new invoice
 * is issued; they can turn it back on until then.
 */
export function RenewalSwitch({ provider, subscription }: { provider: BillingProvider; subscription: BillingSubscription }) {
  const t = useTranslations("Billing");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const change = useMutation({
    mutationFn: (next: boolean) => setMyAutoRenew(token!, provider.slug, subscription.id, next),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: MY_BILLING_QUERY_KEY }),
  });

  const on = subscription.auto_renew === true;
  const hint = on
    ? t("autoRenewHintOn")
    : t("autoRenewHintOff", { date: formatDate(locale, subscription.ends_on) });

  return (
    <div className="mt-3 border-t pt-3" style={{ borderColor: "var(--border)" }} data-testid="billing-auto-renew">
      <Switch
        checked={on}
        disabled={change.isPending || !token}
        label={t("autoRenew")}
        hint={hint}
        onChange={(next) => change.mutate(next)}
      />
      {change.isError ? <ErrorNotice variant="field">{localizeError(change.error, ui)}</ErrorNotice> : null}
    </div>
  );
}

/**
 * ADR-220: leaving the box (or ending with an independent coach). The
 * member keeps what they paid for; only invoices for later periods and for
 * packages that never started are cancelled, and anything already used
 * stays owed. Until the last day passes they can change their mind.
 */
export function LeaveProviderCard({ provider }: { provider: BillingProvider }) {
  const t = useTranslations("Billing");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [today] = useState(() => new Date());
  const kind = provider.kind === "coach" ? "coach" : "gym";

  const refresh = () => queryClient.invalidateQueries({ queryKey: MY_BILLING_QUERY_KEY });
  const leave = useMutation({
    mutationFn: () => leaveProvider(token!, provider.slug, reason.trim() || null),
    onSuccess: async () => {
      setOpen(false);
      setReason("");
      await refresh();
    },
  });
  const stay = useMutation({ mutationFn: () => stayWithProvider(token!, provider.slug), onSuccess: refresh });

  const state = leaveState(provider);
  if (state.kind === "none") return null;

  if (state.kind === "leaving") {
    return (
      <HubCard eyebrow={t("leaveTitle", { kind })}>
        <p className="text-sm" style={{ color: "var(--text)" }} data-testid="billing-leaving">
          {t(state.byStaff ? "leavingByProvider" : "leavingOn", { kind, date: formatDate(locale, state.leavingOn) })}
        </p>
        <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{t("leaveOwedNote")}</p>
        {!state.byStaff && canStay(state.leavingOn, today) ? (
          <button
            className="mt-3 flex min-h-11 w-full items-center justify-center rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
            disabled={stay.isPending || !token}
            onClick={() => stay.mutate()}
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            type="button"
          >
            {t("stay", { kind })}
          </button>
        ) : null}
        {stay.isError ? <ErrorNotice variant="field">{localizeError(stay.error, ui)}</ErrorNotice> : null}
      </HubCard>
    );
  }

  return (
    <>
      <button
        className="flex min-h-11 w-full items-center justify-center rounded-2xl px-4 text-sm font-semibold"
        onClick={() => { leave.reset(); setOpen(true); }}
        style={{ border: "1px solid var(--border)", color: "var(--danger)" }}
        type="button"
        data-testid="billing-leave"
      >
        {t("leaveTitle", { kind })}
      </button>
      {open ? (
        <Dialog
          onClose={() => setOpen(false)}
          title={t("leaveTitle", { kind })}
          size="sm"
          footer={
            <>
              <DialogButton onClick={() => setOpen(false)}>{t("leaveCancel")}</DialogButton>
              <DialogButton tone="danger" disabled={leave.isPending || !token} onClick={() => leave.mutate()} testId="billing-leave-confirm">
                {t("leaveConfirm")}
              </DialogButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text)" }}>
            {t("leaveBody", { date: formatDate(locale, state.previewOn) })}
          </p>
          <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("leaveOwedNote")}</p>
          <label className="mt-4 block text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("leaveReason", { kind })}
            <textarea
              className="mt-1 min-h-20 w-full rounded-xl px-3 py-2 text-sm"
              maxLength={500}
              onChange={(event) => setReason(event.target.value)}
              style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }}
              value={reason}
            />
          </label>
          {leave.isError ? <ErrorNotice variant="field">{localizeError(leave.error, ui)}</ErrorNotice> : null}
        </Dialog>
      ) : null}
    </>
  );
}
