"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { ApiError } from "@/api/client";
import { MY_BILLING_QUERY_KEY, type BillingProvider } from "@/api/my-billing";
import {
  fetchPayment,
  fetchSavedCards,
  removeSavedCard,
  savedCardsKey,
  setCardAutopay,
  withdrawPurchase,
  type OnlinePayment,
  type SavedCard,
} from "@/api/my-payments";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

import { canPayWithAnotherCard, withdrawalDeadline, withdrawalOpen } from "./checkout-flow";
import { InvoicePaySheet } from "./InvoicePaySheet";
import { PayButton, usePayError } from "./PayParts";

/**
 * Εγώ › Πληρωμές `?payment=<id>`: the payment a notification or a receipt
 * link points at. A declined saved-card charge offers «Πληρωμή με άλλη
 * κάρτα» (ADR-260); a package bought online offers «Υπαναχώρηση» while its
 * 14 days last (ADR-248). The link carries no box, so the person's boxes are
 * asked in turn, the one in view first.
 */
export function PaymentFocusCard({ paymentId, providers, preferred }: { paymentId: string; providers: BillingProvider[]; preferred: string | null }) {
  const token = useSession().tokens?.access_token ?? null;
  const slugs = [...new Set([preferred, ...providers.map((provider) => provider.slug)].filter((slug): slug is string => Boolean(slug)))];

  const found = useQuery({
    queryKey: ["me", "payments", "focus", paymentId, slugs.join(",")],
    enabled: Boolean(token) && slugs.length > 0,
    retry: false,
    queryFn: async () => {
      for (const slug of slugs) {
        try {
          const { payment } = await fetchPayment(token!, slug, paymentId);
          return { slug, payment };
        } catch (error) {
          if (!(error instanceof ApiError) || (error.status !== 404 && error.status !== 403)) throw error;
        }
      }
      return null;
    },
  });

  if (!found.data) return null;
  return <PaymentCard slug={found.data.slug} payment={found.data.payment} onChanged={() => void found.refetch()} />;
}

function PaymentCard({ slug, payment, onChanged }: { slug: string; payment: OnlinePayment; onChanged: () => void }) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const [paying, setPaying] = useState(false);
  const [now] = useState(() => new Date());
  const amount = formatMinorUnits(locale, payment.amount_cents, payment.currency);
  const card = payment.card_last4 ? `••${payment.card_last4}` : null;
  const declined = payment.status !== "succeeded" && payment.declines > 0;

  return (
    <HubCard eyebrow={t("paymentTitle")} highlighted>
      <div className="flex min-w-0 flex-col gap-2" data-testid="pay-focus">
        <div className="flex min-w-0 items-baseline justify-between gap-3">
          <p className="min-w-0 break-words text-base font-bold" style={{ color: "var(--text)" }}>{payment.description}</p>
          <p className="shrink-0 text-base font-extrabold tabular-nums" style={{ color: "var(--text)" }}>{amount}</p>
        </div>
        {payment.status === "succeeded" ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {payment.succeeded_at
              ? card
                ? t("paidOnCard", { date: formatDate(locale, payment.succeeded_at.slice(0, 10)), card })
                : t("paidOn", { date: formatDate(locale, payment.succeeded_at.slice(0, 10)) })
              : t("paid")}
          </p>
        ) : declined ? (
          <p className="text-sm" style={{ color: "var(--warning)" }}>
            {card ? t("chargeDeclinedCard", { card }) : t("chargeDeclined")}
            {payment.status !== "failed" && payment.next_attempt_at
              ? ` ${t("nextTry", { date: formatDate(locale, payment.next_attempt_at.slice(0, 10)) })}`
              : ""}
          </p>
        ) : (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`status.${payment.status}`)}</p>
        )}
        {payment.refunded_cents > 0 ? (
          <p className="text-sm" style={{ color: "var(--success)" }}>
            {t("refunded", { amount: formatMinorUnits(locale, payment.refunded_cents, payment.currency) })}
          </p>
        ) : null}

        {canPayWithAnotherCard(payment) ? (
          <PayButton onClick={() => setPaying(true)} testId="pay-other-card">{t("payWithAnotherCard")}</PayButton>
        ) : null}
        {withdrawalOpen(payment, now) ? <WithdrawButton slug={slug} payment={payment} onDone={onChanged} /> : null}
      </div>
      {paying ? (
        <InvoicePaySheet slug={slug} invoiceId={payment.purpose_id} label={payment.description} onClose={() => setPaying(false)} />
      ) : null}
    </HubCard>
  );
}

function WithdrawButton({ slug, payment, onDone }: { slug: string; payment: OnlinePayment; onDone: () => void }) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const payError = usePayError();
  const [open, setOpen] = useState(false);
  const deadline = withdrawalDeadline(payment);

  const withdraw = useMutation({
    mutationFn: () => withdrawPurchase(token!, slug, payment.id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: MY_BILLING_QUERY_KEY });
      onDone();
    },
  });

  return (
    <>
      <PayButton tone="secondary" onClick={() => { withdraw.reset(); setOpen(true); }} testId="pay-withdraw">
        {t("withdraw")}
      </PayButton>
      {deadline ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("withdrawUntil", { date: formatDate(locale, deadline.slice(0, 10)) })}</p>
      ) : null}
      {open ? (
        <Dialog
          onClose={() => setOpen(false)}
          title={t("withdraw")}
          size="sm"
          dismissible={!withdraw.isPending}
          error={withdraw.isError ? payError(withdraw.error) : undefined}
          footer={
            withdraw.isSuccess ? (
              <DialogButton tone="primary" onClick={() => setOpen(false)}>{t("close")}</DialogButton>
            ) : (
              <>
                <DialogButton onClick={() => setOpen(false)}>{t("keepPackage")}</DialogButton>
                <DialogButton tone="danger" disabled={withdraw.isPending} onClick={() => withdraw.mutate()} testId="pay-withdraw-confirm">
                  {t("withdrawConfirm")}
                </DialogButton>
              </>
            )
          }
        >
          {withdraw.isSuccess ? (
            <p className="text-sm" style={{ color: "var(--text)" }} role="status" data-testid="pay-withdrawn">
              {t("withdrawn", { amount: formatMinorUnits(locale, withdraw.data.refunded_cents, payment.currency) })}
            </p>
          ) : (
            <p className="text-sm" style={{ color: "var(--text)" }}>{t("withdrawBody", { name: payment.description })}</p>
          )}
        </Dialog>
      ) : null}
    </>
  );
}

/**
 * The member's saved cards at one box (ADR-247): which one pays what falls
 * due, and removing one (it is never charged again). Hidden without cards.
 */
export function SavedCardsCard({ slug }: { slug: string }) {
  const t = useTranslations("Pay");
  const token = useSession().tokens?.access_token ?? null;
  const cards = useQuery({
    queryKey: savedCardsKey(slug),
    enabled: Boolean(token),
    queryFn: () => fetchSavedCards(token!, slug),
  });

  const active = (cards.data?.payment_methods ?? []).filter((card) => card.status === "active");
  if (active.length === 0) return null;

  return (
    <HubCard eyebrow={t("cardsTitle")}>
      <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }} data-testid="pay-cards">
        {active.map((card) => (
          <CardRow key={card.id} slug={slug} card={card} />
        ))}
      </ul>
    </HubCard>
  );
}

function CardRow({ slug, card }: { slug: string; card: SavedCard }) {
  const t = useTranslations("Pay");
  const token = useSession().tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const payError = usePayError();
  const [confirm, setConfirm] = useState(false);
  const refresh = () => queryClient.invalidateQueries({ queryKey: savedCardsKey(slug) });

  const autopay = useMutation({ mutationFn: (next: boolean) => setCardAutopay(token!, slug, card.id, next), onSuccess: refresh });
  const remove = useMutation({
    mutationFn: () => removeSavedCard(token!, slug, card.id),
    onSuccess: async () => {
      setConfirm(false);
      await refresh();
    },
  });

  const name = `${card.brand ? `${capitalize(card.brand)} ` : ""}••${card.last4 ?? "····"}`;
  const expiry = card.exp_month && card.exp_year ? `${String(card.exp_month).padStart(2, "0")}/${String(card.exp_year).slice(-2)}` : null;

  return (
    <li className="flex min-w-0 flex-col gap-1 py-3 first:pt-0 last:pb-0" style={{ borderColor: "var(--border)" }}>
      <div className="flex min-w-0 items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-bold" style={{ color: "var(--text)" }}>{name}</p>
          {expiry ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("expires", { date: expiry })}</p> : null}
        </div>
        <button
          type="button"
          onClick={() => { remove.reset(); setConfirm(true); }}
          className="min-h-11 shrink-0 px-2 text-sm font-semibold"
          style={{ color: "var(--danger)" }}
          data-testid={`pay-card-remove-${card.id}`}
        >
          {t("removeCard")}
        </button>
      </div>
      <Switch
        checked={card.autopay}
        disabled={autopay.isPending || !token}
        label={t("autopay")}
        hint={card.autopay ? t("autopayOn") : t("autopayOff")}
        onChange={(next) => autopay.mutate(next)}
      />
      {autopay.isError ? <ErrorNotice variant="field">{payError(autopay.error)}</ErrorNotice> : null}
      {confirm ? (
        <Dialog
          onClose={() => setConfirm(false)}
          title={t("removeCardTitle", { card: name })}
          size="sm"
          error={remove.isError ? payError(remove.error) : undefined}
          footer={
            <>
              <DialogButton onClick={() => setConfirm(false)}>{t("keepCard")}</DialogButton>
              <DialogButton tone="danger" disabled={remove.isPending} onClick={() => remove.mutate()} testId="pay-card-remove-confirm">
                {t("removeCard")}
              </DialogButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text)" }}>{t("removeCardBody")}</p>
        </Dialog>
      ) : null}
    </li>
  );
}

function capitalize(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}
