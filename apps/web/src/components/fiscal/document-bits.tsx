"use client";

import { useTranslations } from "next-intl";

import type { FiscalDocument } from "@/api/fiscal";

import { transmissionState } from "./documents-model";
import { Icon, Pill } from "./fiscal-ui";

export const FISCAL_DOCUMENTS_KEY = ["admin", "fiscal", "documents"] as const;

const PAYMENTS = ["cash", "card", "bank_transfer", "online", "other"] as const;

export function paymentKey(method: string): (typeof PAYMENTS)[number] {
  return (PAYMENTS as readonly string[]).includes(method) ? (method as (typeof PAYMENTS)[number]) : "other";
}

/** «Εκκρεμεί διαβίβαση», «✓ myDATA» or «Απορρίφθηκε»; nothing where no authority receives documents. */
export function TransmissionPill({ document }: { document: Pick<FiscalDocument, "transmission"> }) {
  const t = useTranslations("FiscalDocuments");
  const state = transmissionState(document.transmission);
  if (state === "none") return null;
  if (state === "accepted") {
    return (
      <Pill tone="ok" testId="fiscal-tx">
        <Icon name="check" size={11} />
        myDATA
      </Pill>
    );
  }
  if (state === "rejected") return <Pill tone="bad" testId="fiscal-tx">{t("txRejected")}</Pill>;
  return <Pill tone="warn" testId="fiscal-tx">{t("txPending")}</Pill>;
}

export function KindPill({ kind }: { kind: FiscalDocument["kind"] }) {
  const t = useTranslations("FiscalDocuments");
  if (kind === "credit_note") return <Pill tone="bad">{t("kind.credit_note")}</Pill>;
  if (kind === "invoice") return <Pill tone="accent">{t("kind.invoice")}</Pill>;
  return <Pill>{t("kind.receipt")}</Pill>;
}
