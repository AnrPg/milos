"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useMemo, useState, type ReactNode } from "react";

import {
  completeSandboxCheckout,
  fetchPayment,
  returnFromCheckout,
  type OnlinePayment,
  type SandboxOutcome,
} from "@/api/my-payments";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { finishCheckout } from "@/lib/platform/checkout";
import { parsePaymentReturn, paymentReturnBody } from "@/lib/platform/deep-links";

import { paymentOutcome, pendingCheckout, type CheckoutOrigin, type PendingCheckout } from "./checkout-flow";
import { PayButton, usePayError } from "./PayParts";

/**
 * `/pay/return` (ADR-246/256; mockup s4 «Επιστροφή»): where the provider
 * sends the payer back. The page always asks the API, which asks the
 * provider (the webhook and polling stay the source of truth), and shows
 * one of three answers: done, waiting for the bank, or not paid. In dev and
 * test the sandbox provider lands here first with `sandbox_checkout=`, and
 * the page plays the provider's page.
 */
export function PaymentReturnPage() {
  const searchParams = useSearchParams();
  const parsed = useMemo(() => parsePaymentReturn(searchParams), [searchParams]);
  const sandboxRef = searchParams.get("sandbox_checkout");
  const pending = useMemo(() => pendingCheckout(parsed.payment_id), [parsed.payment_id]);
  const selectedSlug = useOrganizationSlug();
  const slug = pending?.slug ?? selectedSlug;

  useEffect(() => {
    void finishCheckout();
  }, []);

  if (!slug) return <Shell><Loading /></Shell>;
  if (sandboxRef && parsed.payment_id) {
    return (
      <SandboxCheckout
        slug={slug}
        paymentId={parsed.payment_id}
        providerRef={sandboxRef}
        declineCard={searchParams.get("sandbox_decline") === "1"}
        pending={pending}
      />
    );
  }
  return <ReturnResult slug={slug} parsed={parsed} pending={pending} />;
}

function Shell({ children }: { children: ReactNode }) {
  return <main className="mx-auto flex w-full max-w-md flex-col gap-4 px-4 pb-8 pt-10">{children}</main>;
}

function Loading() {
  const t = useTranslations("Pay");
  return <p className="text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
}

function ReturnResult({
  slug,
  parsed,
  pending,
}: {
  slug: string;
  parsed: ReturnType<typeof parsePaymentReturn>;
  pending: PendingCheckout | null;
}) {
  const t = useTranslations("Pay");
  const token = useSession().tokens?.access_token ?? null;
  const payError = usePayError();
  const body = paymentReturnBody(parsed);

  const check = useQuery({
    queryKey: ["me", "payments", slug, "return", body?.payment_id ?? body?.provider_ref ?? "none"],
    enabled: Boolean(token && body),
    queryFn: () => returnFromCheckout(token!, slug, body!),
    retry: false,
    staleTime: Infinity,
  });

  if (!body) {
    return (
      <Shell>
        <ResultCard tone="bad" title={t("returnUnknownTitle")}>{t("returnUnknown")}</ResultCard>
        <BackLink href="/me/payments">{t("backToPayments")}</BackLink>
      </Shell>
    );
  }
  if (check.isPending) return <Shell><Loading /></Shell>;
  if (check.isError) {
    return (
      <Shell>
        <ErrorNotice>{payError(check.error)}</ErrorNotice>
        <PayButton onClick={() => void check.refetch()}>{t("checkAgain")}</PayButton>
        <BackLink href="/me/payments">{t("backToPayments")}</BackLink>
      </Shell>
    );
  }

  const payment = check.data.payment;
  const outcome = paymentOutcome(payment, parsed.cancelled);
  const origin: CheckoutOrigin = pending?.origin ?? (payment.purpose_type === "finance_invoice" ? "payments" : "box");
  const visit = pending?.kind === "visit";

  if (outcome === "pending") {
    return (
      <Shell>
        <ResultCard tone="wait" title={t("pendingTitle")}>{t("pendingBody")}</ResultCard>
        <PayButton disabled={check.isFetching} onClick={() => void check.refetch()} testId="pay-check-again">
          {t("checkAgain")}
        </PayButton>
      </Shell>
    );
  }

  if (outcome !== "succeeded") {
    return (
      <Shell>
        <ResultCard tone="bad" title={outcome === "cancelled" ? t("cancelledTitle") : t("failedTitle")}>
          {outcome === "cancelled" ? t("cancelledBody") : t("failedBody")}
          {visit ? ` ${t("failedVisit")}` : ""}
        </ResultCard>
        <BackLink href={originPath(origin, slug)} primary testId="pay-try-again">{t("tryAgain")}</BackLink>
        {origin === "box" ? null : <BackLink href="/box">{t("backToBox")}</BackLink>}
      </Shell>
    );
  }

  return (
    <Shell>
      <Succeeded payment={payment} pending={pending} slug={slug} />
      <BackLink href={originPath(origin, slug)} primary testId="pay-back">
        {origin === "schedule" ? t("backToSchedule") : origin === "payments" ? t("backToPayments") : t("backToBox")}
      </BackLink>
    </Shell>
  );
}

function Succeeded({ payment, pending, slug }: { payment: OnlinePayment; pending: PendingCheckout | null; slug: string }) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const amount = formatMinorUnits(locale, payment.amount_cents, payment.currency);
  const name = pending?.itemName ?? (payment.metadata?.package_name as string | undefined) ?? payment.description;
  const kind = pending?.kind ?? (payment.purpose_type === "finance_invoice" ? "invoice" : "package");

  const title = kind === "visit" ? t("visitBookedTitle") : kind === "invoice" ? t("invoicePaidTitle") : t("doneTitle");
  const text =
    kind === "visit"
      ? [pending?.classLabel, t("visitBookedBody")].filter(Boolean).join(" · ")
      : kind === "invoice"
        ? payment.description
        : t("packageStarts", { name });

  return (
    <>
      <ResultCard tone="ok" title={title}>{text}</ResultCard>
      <Link
        href={`/me/payments?box=${encodeURIComponent(slug)}&payment=${encodeURIComponent(payment.id)}`}
        className="flex min-h-12 items-center justify-between gap-3 rounded-2xl px-4 text-sm font-semibold"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        data-testid="pay-receipt"
      >
        <span>{t("receipt", { amount })}</span>
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
      </Link>
      {pending?.autopay && payment.card_last4 ? (
        <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
          {t("nextChargesCard", { last4: payment.card_last4 })}
        </p>
      ) : null}
    </>
  );
}

function ResultCard({ tone, title, children }: { tone: "ok" | "wait" | "bad"; title: string; children: ReactNode }) {
  const color = tone === "ok" ? "var(--success)" : tone === "wait" ? "var(--warning)" : "var(--danger)";
  const icon = tone === "ok" ? "✓" : tone === "wait" ? "…" : "×";
  return (
    <section
      role="status"
      className="flex flex-col items-center gap-3 rounded-3xl p-6 text-center"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid={`pay-result-${tone}`}
    >
      <span
        aria-hidden="true"
        className="flex h-14 w-14 items-center justify-center rounded-full text-2xl font-extrabold"
        style={{ background: `color-mix(in srgb, ${color} 16%, var(--panel))`, color }}
      >
        {icon}
      </span>
      <h1 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{title}</h1>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{children}</p>
    </section>
  );
}

function BackLink({ href, children, primary, testId }: { href: string; children: ReactNode; primary?: boolean; testId?: string }) {
  return (
    <Link
      href={href}
      data-testid={testId}
      className="flex min-h-12 items-center justify-center rounded-2xl px-4 text-center text-sm font-bold"
      style={
        primary
          ? { background: "var(--primary)", color: "var(--primary-contrast)" }
          : { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }
      }
    >
      {children}
    </Link>
  );
}

function originPath(origin: CheckoutOrigin, slug: string) {
  switch (origin) {
    case "schedule":
      return "/box/schedule";
    case "payments":
      return `/me/payments?box=${encodeURIComponent(slug)}`;
    case "public":
    case "box":
    default:
      return "/box";
  }
}

/**
 * The sandbox provider's page (dev and test only, ADR-246): what a real
 * provider would show, with its pay and cancel buttons.
 */
function SandboxCheckout({
  slug,
  paymentId,
  providerRef,
  declineCard,
  pending,
}: {
  slug: string;
  paymentId: string;
  providerRef: string;
  declineCard: boolean;
  pending: PendingCheckout | null;
}) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const router = useRouter();
  const token = useSession().tokens?.access_token ?? null;
  const payError = usePayError();
  const [cancelled, setCancelled] = useState(false);

  const payment = useQuery({
    queryKey: ["me", "payments", slug, "payment", paymentId],
    enabled: Boolean(token),
    queryFn: () => fetchPayment(token!, slug, paymentId),
  });
  const complete = useMutation({
    mutationFn: (outcome: SandboxOutcome) => completeSandboxCheckout(token!, slug, providerRef, outcome, declineCard),
    onSuccess: (_data, outcome) => {
      setCancelled(outcome === "cancelled");
      const query = new URLSearchParams({ payment: paymentId });
      if (outcome === "cancelled") query.set("cancelled", "1");
      router.replace(`/pay/return?${query}`);
    },
  });

  const data = payment.data?.payment;
  return (
    <Shell>
      <section
        className="flex flex-col gap-3 rounded-3xl p-5"
        style={{ background: "var(--paper)", color: "var(--on-paper)", border: "1px solid var(--border)" }}
        data-testid="pay-sandbox"
        aria-label={t("sandboxTitle")}
      >
        <div className="flex items-center justify-between gap-2 text-xs font-bold uppercase tracking-[0.14em]">
          <span>{t("sandboxTitle")}</span>
          <span className="normal-case tracking-normal">{t("sandboxSecure")}</span>
        </div>
        {data ? (
          <div className="flex items-baseline justify-between gap-3">
            <b className="min-w-0 break-words text-sm">{pending?.itemName ?? data.description}</b>
            <b className="shrink-0 text-xl tabular-nums">{formatMinorUnits(locale, data.amount_cents, data.currency)}</b>
          </div>
        ) : payment.isError ? (
          <ErrorNotice>{payError(payment.error)}</ErrorNotice>
        ) : (
          <Loading />
        )}
        <p className="rounded-xl px-3 py-2 text-xs" style={{ border: "1px solid var(--border)" }}>
          {t("sandboxCard")}
          <br />
          <b>4242 •••• •••• 4242</b>
        </p>
        {pending?.autopay ? <p className="text-xs">{t("sandboxSavesCard")}</p> : null}
        <PayButton disabled={!data || complete.isPending || cancelled} onClick={() => complete.mutate("succeeded")} testId="pay-sandbox-pay">
          {data ? t("pay", { amount: formatMinorUnits(locale, data.amount_cents, data.currency) }) : t("loading")}
        </PayButton>
        <button
          type="button"
          disabled={complete.isPending}
          onClick={() => complete.mutate("cancelled")}
          className="min-h-11 text-sm underline"
          data-testid="pay-sandbox-cancel"
        >
          {t("sandboxCancel")}
        </button>
        {complete.isError ? <ErrorNotice variant="field">{payError(complete.error)}</ErrorNotice> : null}
      </section>
    </Shell>
  );
}
