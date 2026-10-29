"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState } from "react";

import { fetchInvoiceTerms, invoiceTermsKey, newIdempotencyKey, payInvoice, termsLanguage } from "@/api/my-payments";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { money, usePayLabel } from "./PackageCheckout";
import { ChoiceLabel, ChoiceRow, PayButton, usePayError, useStartCheckout } from "./PayParts";

/**
 * Paying an open invoice online (ADR-246/247), in the same «Πριν πληρώσεις»
 * sheet as a package: one question, whether the card pays what falls due
 * from now on (the API's consent text) or only this time.
 */
export function InvoicePaySheet({
  slug,
  invoiceId,
  label,
  onClose,
}: {
  slug: string;
  invoiceId: string;
  label: string;
  onClose: () => void;
}) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const language = termsLanguage(locale);
  const token = useSession().tokens?.access_token ?? null;
  const start = useStartCheckout();
  const payLabel = usePayLabel();
  const payError = usePayError();
  const groupId = useId();
  const [autopay, setAutopay] = useState<boolean | null>(null);
  const [key] = useState(newIdempotencyKey);

  const terms = useQuery({
    queryKey: invoiceTermsKey(slug, invoiceId, language),
    enabled: Boolean(token),
    queryFn: () => fetchInvoiceTerms(token!, slug, invoiceId, language),
  });

  const pay = useMutation({
    mutationFn: async () => {
      const save = autopay === true;
      const { payment } = await payInvoice(token!, slug, invoiceId, {
        idempotency_key: key,
        language,
        ...(save ? { save_card: true, consent_accepted: true, autopay: true } : {}),
      });
      await start(payment, { slug, kind: "invoice", itemName: label, origin: "payments", autopay: save });
    },
  });

  const data = terms.data;
  return (
    <Dialog onClose={onClose} title={t("beforePaying")} size="sm" variant="sheet" testId="pay-invoice-sheet">
      {terms.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : terms.isError || !data ? (
        <ErrorNotice>{payError(terms.error)}</ErrorNotice>
      ) : (
        <div className="flex min-w-0 flex-col gap-3">
          <div className="flex min-w-0 items-baseline justify-between gap-3">
            <p className="min-w-0 break-words text-sm font-bold" style={{ color: "var(--text)" }}>{label}</p>
            <p className="shrink-0 text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>
              {money(locale, data.amount_cents, data.currency)}
            </p>
          </div>
          <div role="radiogroup" aria-labelledby={groupId} className="flex flex-col gap-2">
            <ChoiceLabel id={groupId}>{t("yourCard")}</ChoiceLabel>
            <ChoiceRow checked={autopay === true} onSelect={() => setAutopay(true)} title={t("cardPaysNext")} testId="pay-auto-yes">
              {data.consent_text}
            </ChoiceRow>
            <ChoiceRow checked={autopay === false} onSelect={() => setAutopay(false)} title={t("onlyThisTime")} testId="pay-auto-no" />
          </div>
          {!data.available ? <ErrorNotice>{t("errorUnavailable")}</ErrorNotice> : null}
          <PayButton
            disabled={!data.available || autopay === null || pay.isPending}
            onClick={() => pay.mutate()}
            testId="pay-submit"
          >
            {payLabel(data.amount_cents, data.currency, data.provider)}
          </PayButton>
          {pay.isError ? <ErrorNotice variant="field">{payError(pay.error)}</ErrorNotice> : null}
        </div>
      )}
    </Dialog>
  );
}
