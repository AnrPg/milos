"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState } from "react";

import {
  buyPackage,
  fetchPackageTerms,
  newIdempotencyKey,
  packageTermsKey,
  termsLanguage,
  type PublicPackage,
} from "@/api/my-payments";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

import { isRecurring, providerLabel, type CheckoutOrigin } from "./checkout-flow";
import { ChoiceLabel, ChoiceRow, PayButton, usePayError, useStartCheckout } from "./PayParts";

export type BookingTarget = { id: string; label: string };

/**
 * Buying one package (ADR-248): its terms come from the API in the member's
 * language, the two legal questions (start now within the 14 days; renew
 * with the saved card) are answered with explicit choices, nothing chosen in
 * advance, and the payer then leaves for the provider's page.
 */
export function usePackageCheckout({
  slug,
  pkg,
  booking,
  origin,
}: {
  slug: string;
  pkg: PublicPackage;
  booking?: BookingTarget | null;
  origin: CheckoutOrigin;
}) {
  const locale = useUiLocale();
  const language = termsLanguage(locale);
  const token = useSession().tokens?.access_token ?? null;
  const start = useStartCheckout();
  const [startNow, setStartNow] = useState(false);
  const [autopay, setAutopay] = useState<boolean | null>(null);
  const [key] = useState(newIdempotencyKey);
  const slotId = booking?.id ?? null;

  const terms = useQuery({
    queryKey: packageTermsKey(slug, pkg.id, language, slotId),
    enabled: Boolean(token),
    queryFn: () => fetchPackageTerms(token!, slug, pkg.id, language, slotId),
    staleTime: 60_000,
  });

  const recurring = isRecurring(pkg.billing_period);
  const asksStart = Boolean(terms.data?.withdrawal_days);
  const ready = Boolean(terms.data?.available) && (!asksStart || startNow) && (!recurring || autopay !== null);

  const pay = useMutation({
    mutationFn: async () => {
      const saveCard = recurring && autopay === true;
      const { payment } = await buyPackage(token!, slug, pkg.id, {
        idempotency_key: key,
        language,
        ...(asksStart ? { start_now: true } : {}),
        ...(saveCard ? { save_card: true, consent_accepted: true, autopay: true } : {}),
        ...(slotId ? { book_slot_id: slotId } : {}),
      });
      await start(payment, {
        slug,
        kind: pkg.package_type === "drop_in" || pkg.package_type === "trial" ? "visit" : "package",
        itemName: pkg.name,
        origin,
        autopay: saveCard,
        classLabel: booking?.label ?? null,
      });
    },
  });

  return { terms, recurring, asksStart, startNow, setStartNow, autopay, setAutopay, ready, pay };
}

export function money(locale: string, cents: number, currency: string) {
  return formatMinorUnits(locale, cents, currency);
}

/** «Πληρωμή 75,00 € με Viva» (or without the provider when it is unknown). */
export function usePayLabel() {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  return (cents: number, currency: string, provider: string | null | undefined, andBook = false) => {
    const amount = money(locale, cents, currency);
    const name = providerLabel(provider);
    if (andBook) return t("payAndBook", { amount });
    return name ? t("payWith", { amount, provider: name }) : t("pay", { amount });
  };
}

/**
 * Mockup s4 option B, sheet 2 «Πριν πληρώσεις»: when it starts and, for a
 * package that renews, whether the card pays the next periods.
 */
export function BeforePaying({
  checkout,
  pkg,
  andBook = false,
}: {
  checkout: ReturnType<typeof usePackageCheckout>;
  pkg: PublicPackage;
  andBook?: boolean;
}) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const payLabel = usePayLabel();
  const payError = usePayError();
  const startId = useId();
  const renewId = useId();
  const { terms, recurring, asksStart, startNow, setStartNow, autopay, setAutopay, ready, pay } = checkout;
  const price = money(locale, pkg.base_price_cents, pkg.currency);

  if (terms.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (terms.isError) return <ErrorNotice>{payError(terms.error)}</ErrorNotice>;
  const data = terms.data;

  return (
    <div className="flex min-w-0 flex-col gap-3">
      {asksStart ? (
        <div role="radiogroup" aria-labelledby={startId} className="flex flex-col gap-2">
          <ChoiceLabel id={startId}>{t("whenStarts")}</ChoiceLabel>
          <ChoiceRow
            checked={startNow}
            onSelect={() => setStartNow(true)}
            title={t("startToday")}
            testId="pay-start-now"
          >
            {data.start_now_text}
          </ChoiceRow>
        </div>
      ) : null}

      {recurring ? (
        <div role="radiogroup" aria-labelledby={renewId} className="flex flex-col gap-2">
          <ChoiceLabel id={renewId}>{t(`renewEvery.${periodKey(pkg.billing_period)}`)}</ChoiceLabel>
          <ChoiceRow
            checked={autopay === true}
            onSelect={() => setAutopay(true)}
            title={t("autoRenew")}
            detail={t(`autoRenewDetail.${periodKey(pkg.billing_period)}`, { price })}
            testId="pay-auto-yes"
          >
            {data.consent_text}
          </ChoiceRow>
          <ChoiceRow
            checked={autopay === false}
            onSelect={() => setAutopay(false)}
            title={t("payMyself")}
            detail={t("payMyselfDetail")}
            testId="pay-auto-no"
          />
        </div>
      ) : null}

      {!data.available ? <ErrorNotice>{t("errorUnavailable")}</ErrorNotice> : null}
      <PayButton disabled={!ready || pay.isPending} onClick={() => pay.mutate()} testId="pay-submit">
        {payLabel(pkg.base_price_cents, pkg.currency, data.provider, andBook)}
      </PayButton>
      {pay.isError ? <ErrorNotice variant="field">{payError(pay.error)}</ErrorNotice> : null}
    </div>
  );
}

function periodKey(period: string) {
  return ["monthly", "quarterly", "semiannual", "annual"].includes(period) ? period : "other";
}
