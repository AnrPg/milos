"use client";

import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useCallback, type ReactNode } from "react";

import type { OnlinePayment } from "@/api/my-payments";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { openCheckout } from "@/lib/platform/checkout";

import { checkoutTarget, payErrorKey, rememberCheckout, type PendingCheckout } from "./checkout-flow";

/**
 * One choice of a sheet (mockup s4 «opt2»): a radio, a bold line, a short
 * explanation and, at the end, a price. Nothing is chosen in advance, so a
 * choice is the member's express answer.
 */
export function ChoiceRow({
  checked,
  onSelect,
  title,
  detail,
  end,
  children,
  testId,
}: {
  checked: boolean;
  onSelect: () => void;
  title: ReactNode;
  detail?: ReactNode;
  end?: ReactNode;
  /** Longer text that belongs to the choice (e.g. the consent the API wrote). */
  children?: ReactNode;
  testId?: string;
}) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={checked}
      onClick={onSelect}
      data-testid={testId}
      className="flex w-full min-w-0 items-start gap-3 rounded-2xl px-3 py-3 text-start"
      style={{
        background: checked ? "color-mix(in srgb, var(--primary) 8%, var(--panel))" : "var(--panel)",
        border: `1px solid ${checked ? "var(--primary)" : "var(--border)"}`,
      }}
    >
      <span
        aria-hidden="true"
        className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full"
        style={{ border: `2px solid ${checked ? "var(--primary)" : "var(--border-strong)"}` }}
      >
        {checked ? <span className="h-2.5 w-2.5 rounded-full" style={{ background: "var(--primary)" }} /> : null}
      </span>
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{title}</span>
        {detail ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{detail}</span> : null}
        {children ? <span className="mt-1 text-xs leading-5" style={{ color: "var(--dim)" }}>{children}</span> : null}
      </span>
      {end ? <span className="shrink-0 text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>{end}</span> : null}
    </button>
  );
}

/** A small uppercase label above a group of choices («Πότε ξεκινά»). */
export function ChoiceLabel({ children, id }: { children: ReactNode; id?: string }) {
  return (
    <p id={id} className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
      {children}
    </p>
  );
}

/** The one button that leaves for the provider's page («Πληρωμή 75,00 € με Viva»). */
export function PayButton({
  children,
  disabled,
  onClick,
  testId,
  tone = "primary",
}: {
  children: ReactNode;
  disabled?: boolean;
  onClick?: () => void;
  testId?: string;
  tone?: "primary" | "secondary";
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      data-testid={testId}
      className="flex min-h-12 w-full items-center justify-center rounded-2xl px-4 text-center text-sm font-bold disabled:opacity-50"
      style={
        tone === "primary"
          ? { background: "var(--primary)", color: "var(--primary-contrast)" }
          : { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }
      }
    >
      {children}
    </button>
  );
}

/**
 * Sends the payer to the provider's page (ADR-256): the in-app browser in
 * the store apps, the same tab on the web, and our own return page for the
 * sandbox provider. Remembers the checkout first, so /pay/return knows the
 * box and where to lead back.
 */
export function useStartCheckout() {
  const router = useRouter();
  return useCallback(
    async (payment: OnlinePayment, pending: Omit<PendingCheckout, "paymentId" | "savedAt">) => {
      if (!payment.redirect_url) throw new Error("unsafe_checkout_url");
      rememberCheckout({ ...pending, paymentId: payment.id });
      const target = checkoutTarget(payment.redirect_url, window.location.origin);
      if (target.kind === "internal") {
        router.push(target.path);
        return;
      }
      await openCheckout(target.url, { paymentId: payment.id, navigate: (path) => router.push(path) });
    },
    [router],
  );
}

/** A payment refusal in plain words (the API's payment codes, then the app's general wording). */
export function usePayError() {
  const t = useTranslations("Pay");
  const ui = useUiTranslations();
  return useCallback(
    (error: unknown) => {
      const key = payErrorKey(error);
      return key ? t(key) : localizeError(error, ui);
    },
    [t, ui],
  );
}
