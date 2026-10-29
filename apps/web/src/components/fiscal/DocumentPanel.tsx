"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useRef, useState } from "react";

import { fetchFiscalDocument, issueCreditNote, retryTransmission, type FiscalDocumentDetail } from "@/api/fiscal";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formErrorsFrom } from "@/lib/form-errors";

import { DocumentViewDialog } from "./DocumentViewDialog";
import { buyerName, canCredit, canRetry, creditAmount, creditLines, ratePercent, sellerLine, transmissionState } from "./documents-model";
import {
  Card,
  dangerButtonStyle,
  formatMoney,
  ghostButtonClass,
  ghostButtonStyle,
  hintStyle,
  Icon,
  KeyValue,
  linkButtonClass,
  linkButtonStyle,
  Pill,
} from "./fiscal-ui";
import { FISCAL_DOCUMENTS_KEY, KindPill, paymentKey, TransmissionPill } from "./document-bits";

const documentKey = (id: string) => ["admin", "fiscal", "document", id] as const;

/**
 * The side panel of one document (mockup s2 A): its lines, VAT, payment and
 * report to the tax authority; the credit note opens in the same panel.
 */
export function DocumentPanel({
  token,
  documentId,
  onOpen,
  onClose,
}: {
  token: string;
  documentId: string;
  onOpen: (id: string) => void;
  onClose: () => void;
}) {
  const t = useTranslations("FiscalDocuments");
  const [mode, setMode] = useState<"detail" | "credit">("detail");
  const [viewing, setViewing] = useState(false);
  const query = useQuery({ queryKey: documentKey(documentId), enabled: Boolean(token), queryFn: () => fetchFiscalDocument(token, documentId) });
  const document = query.data?.document;

  if (viewing && document) {
    return <DocumentViewDialog token={token} document={document} onClose={() => setViewing(false)} />;
  }

  if (mode === "credit" && document) {
    return <CreditPanel token={token} document={document} onBack={() => setMode("detail")} onClose={onClose} />;
  }

  return (
    <Dialog
      variant="panel"
      size="lg"
      title={<span className="font-mono">{document?.number ?? ""}</span>}
      ariaLabel={document ? t("documentTitle", { number: document.number }) : t("loading")}
      onClose={onClose}
      testId="fiscal-document-panel"
      footer={
        document ? (
          <>
            <button type="button" className={ghostButtonClass} style={ghostButtonStyle} onClick={() => setViewing(true)} data-testid="fiscal-doc-pdf">
              <Icon name="download" size={15} />
              PDF
            </button>
            {canCredit(document) ? (
              <button type="button" className={ghostButtonClass} style={dangerButtonStyle} onClick={() => setMode("credit")} data-testid="fiscal-doc-credit">
                {t("creditNote")}
              </button>
            ) : null}
          </>
        ) : null
      }
    >
      {query.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : query.isError || !document ? (
        <ErrorNotice>{t("documentLoadFailed")}</ErrorNotice>
      ) : (
        <DocumentDetail token={token} document={document} onOpen={onOpen} />
      )}
    </Dialog>
  );
}

function DocumentDetail({ token, document, onOpen }: { token: string; document: FiscalDocumentDetail; onOpen: (id: string) => void }) {
  const t = useTranslations("FiscalDocuments");
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const money = (cents: number) => formatMoney(locale, cents, document.currency);
  const sign = document.kind === "credit_note" ? -1 : 1;
  const credits = document.credit_notes ?? [];
  const transmission = document.transmission ?? null;
  const state = transmissionState(transmission);
  const issued = new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeStyle: "short" }).format(new Date(document.issued_at));

  const retry = useMutation({
    mutationFn: () => retryTransmission(token, document.id),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: documentKey(document.id) });
      void queryClient.invalidateQueries({ queryKey: FISCAL_DOCUMENTS_KEY });
    },
  });

  return (
    <div className="grid gap-3 text-sm" style={{ color: "var(--text)" }}>
      <div className="flex flex-wrap gap-1.5">
        <KindPill kind={document.kind} />
        <TransmissionPill document={document} />
        {credits.length > 0 ? <Pill tone="bad">{t("hasCreditNote")}</Pill> : null}
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <div className="text-xs" style={hintStyle}>{t("customer")}</div>
          <b>{buyerName(document) ?? t("retailCustomer")}</b>
        </div>
        <div>
          <div className="text-xs" style={hintStyle}>{t("date")}</div>
          <b>{issued}</b>
        </div>
      </div>

      <table className="w-full table-fixed text-[13px]">
        <thead>
          <tr className="text-xs" style={hintStyle}>
            <th className="py-1 text-start font-semibold">{t("line.description")}</th>
            <th className="w-10 py-1 text-end font-semibold">{t("line.quantity")}</th>
            <th className="w-14 py-1 text-end font-semibold">{t("line.vat")}</th>
            <th className="w-24 py-1 text-end font-semibold">{t("line.amount")}</th>
          </tr>
        </thead>
        <tbody>
          {(document.lines ?? []).map((line) => (
            <tr key={line.position} style={{ borderTop: "1px solid var(--border)" }}>
              <td className="truncate py-1.5" title={line.description}>{line.description}</td>
              <td className="py-1.5 text-end font-mono">{line.quantity}</td>
              <td className="py-1.5 text-end font-mono">{ratePercent(line.rate_bp)}%</td>
              <td className="py-1.5 text-end font-mono">{money(sign * line.gross_cents)}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <div>
        {document.tax_breakdown.map((row) => (
          <KeyValue key={`${row.tax_category}-${row.rate_bp}`} label={t("netAndVat", { rate: ratePercent(row.rate_bp), vat: money(sign * row.tax_cents) })}>
            {money(sign * row.net_cents)}
          </KeyValue>
        ))}
        <KeyValue label={t("total")} total>{money(sign * document.gross_cents)}</KeyValue>
      </div>

      {document.payment_method ? <KeyValue label={t("payment.label")}>{t(`payment.${paymentKey(document.payment_method)}`)}</KeyValue> : null}
      {document.corrects_document_id ? (
        <KeyValue label={t("corrects")}>
          <button type="button" className={linkButtonClass} style={linkButtonStyle} onClick={() => onOpen(document.corrects_document_id!)} data-testid="fiscal-doc-corrects">
            {t("openOriginal")}
          </button>
        </KeyValue>
      ) : null}

      {state === "pending" || state === "rejected" ? (
        <Card style={{ borderColor: state === "rejected" ? "var(--danger)" : "var(--warning)" }} className="!px-3 !py-3" testId="fiscal-doc-tx">
          <div className="flex items-start gap-2.5">
            <span style={{ color: state === "rejected" ? "var(--danger)" : "var(--warning)" }}><Icon name="clock" size={18} /></span>
            <div className="min-w-0 flex-1">
              <b>{state === "rejected" ? t("txRejectedTitle") : t("txPendingTitle")}</b>
              <p className="text-xs" style={hintStyle}>
                {state === "rejected"
                  ? [transmission?.last_error_message, t("txRejectedHint")].filter(Boolean).join(" ")
                  : canRetry(transmission)
                    ? t("txFailedHint")
                    : t("txPendingHint")}
              </p>
              {retry.isError ? <p className="text-xs" style={{ color: "var(--danger)" }}>{t("retryFailed")}</p> : null}
            </div>
            {canRetry(transmission) ? (
              <button type="button" className={`${ghostButtonClass} !min-h-8 !px-3 !text-xs`} style={ghostButtonStyle} onClick={() => retry.mutate()} disabled={retry.isPending} data-testid="fiscal-doc-retry">
                {t("retryNow")}
              </button>
            ) : null}
          </div>
        </Card>
      ) : state === "accepted" ? (
        <KeyValue label={t("mark")}>{transmission?.mark ?? "—"}</KeyValue>
      ) : null}

      {credits.map((credit) => (
        <Card key={credit.id} className="!px-3 !py-3" testId="fiscal-doc-credit-note">
          <div className="flex items-start gap-2.5">
            <Icon name="receipt" size={18} />
            <div className="min-w-0 flex-1">
              <button type="button" className={linkButtonClass} style={linkButtonStyle} onClick={() => onOpen(credit.id)}>
                {t("creditNoteLine", { number: credit.number, amount: money(-Math.abs(credit.gross_cents)) })}
              </button>
              <p className="text-xs" style={hintStyle}>{t("originalUnchanged")}</p>
            </div>
          </div>
        </Card>
      ))}

      <details className="text-xs" style={hintStyle}>
        <summary className="cursor-pointer">{t("printedParties")}</summary>
        <p className="mt-1.5">
          {sellerLine(document.seller)}. {t("printedPartiesHint")}
        </p>
      </details>
    </div>
  );
}

function CreditPanel({
  token,
  document,
  onBack,
  onClose,
}: {
  token: string;
  document: FiscalDocumentDetail;
  onBack: () => void;
  onClose: () => void;
}) {
  const t = useTranslations("FiscalDocuments");
  const translate = useUiTranslations();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const money = (cents: number) => formatMoney(locale, cents, document.currency);
  const lines = document.lines ?? [];
  const [full, setFull] = useState(true);
  const [picked, setPicked] = useState<ReadonlySet<number>>(new Set());
  const [error, setError] = useState<string | null>(null);
  // One key per credit note the person means to issue: a retried click is the same request.
  const idempotencyKey = useRef(crypto.randomUUID());
  const amount = creditAmount(lines, full, picked);
  const ready = amount > 0;

  const issue = useMutation({
    mutationFn: () => issueCreditNote(token, document.id, idempotencyKey.current, full ? undefined : creditLines(lines, picked)),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: documentKey(document.id) });
      void queryClient.invalidateQueries({ queryKey: FISCAL_DOCUMENTS_KEY });
      onBack();
    },
    onError: (failure) => setError(formErrorsFrom(failure, translate, []).message),
  });

  const toggle = (position: number) => {
    const next = new Set(picked);
    if (next.has(position)) next.delete(position);
    else next.add(position);
    setPicked(next);
    idempotencyKey.current = crypto.randomUUID();
  };
  const choose = (value: boolean) => {
    setFull(value);
    idempotencyKey.current = crypto.randomUUID();
  };

  return (
    <Dialog
      variant="panel"
      size="lg"
      title={t("creditTitle", { number: document.number })}
      onClose={onClose}
      dismissible={!issue.isPending}
      error={error}
      testId="fiscal-credit-panel"
      footerStart={!ready ? <span className="text-xs" style={hintStyle}>{t("pickLines")}</span> : null}
      footer={
        <>
          <button type="button" className={ghostButtonClass} style={ghostButtonStyle} onClick={onBack} disabled={issue.isPending}>
            {t("back")}
          </button>
          <button type="button" className={ghostButtonClass} style={dangerButtonStyle} onClick={() => issue.mutate()} disabled={!ready || issue.isPending} data-testid="fiscal-credit-issue">
            {issue.isPending ? t("issuing") : t("issueCredit")}
          </button>
        </>
      }
    >
      <div className="grid gap-2.5 text-sm">
        <p className="text-xs" style={hintStyle}>{t("creditHint", { number: document.number })}</p>
        <div role="radiogroup" aria-label={t("creditNote")} className="grid gap-1.5">
          <Option on={full} onClick={() => choose(true)} testId="fiscal-credit-full" title={t("creditFull")} hint={t("creditFullHint", { number: document.number, amount: money(-Math.abs(document.gross_cents)) })} />
          <Option on={!full} onClick={() => choose(false)} testId="fiscal-credit-part" title={t("creditPart")} hint={t("creditPartHint")} />
        </div>
        {!full ? (
          <div className="grid gap-1.5" role="group" aria-label={t("creditPart")}>
            {lines.map((line) => {
              const on = picked.has(line.position);
              return (
                <button
                  key={line.position}
                  type="button"
                  role="checkbox"
                  aria-checked={on}
                  onClick={() => toggle(line.position)}
                  data-testid={`fiscal-credit-line-${line.position}`}
                  className="flex items-center gap-2.5 rounded-[14px] p-2.5 text-start"
                  style={{ background: "var(--panel)", border: `1px solid ${on ? "var(--primary)" : "var(--border)"}` }}
                >
                  <span
                    aria-hidden="true"
                    className="grid h-4 w-4 flex-none place-items-center rounded"
                    style={on ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { border: "2px solid var(--border-strong)" }}
                  >
                    {on ? <Icon name="check" size={11} /> : null}
                  </span>
                  <span className="min-w-0 flex-1">{line.description}</span>
                  <span className="font-mono">{money(line.gross_cents)}</span>
                </button>
              );
            })}
          </div>
        ) : null}
        <KeyValue label={t("creditNote")} total>
          <span data-testid="fiscal-credit-amount">{money(-amount)}</span>
        </KeyValue>
      </div>
    </Dialog>
  );
}

function Option({ on, onClick, title, hint, testId }: { on: boolean; onClick: () => void; title: string; hint: string; testId: string }) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={on}
      onClick={onClick}
      data-testid={testId}
      className="flex items-start gap-2.5 rounded-[14px] p-2.5 text-start"
      style={{ background: "var(--panel)", border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`, boxShadow: on ? "inset 0 0 0 1px var(--primary)" : undefined }}
    >
      <span
        aria-hidden="true"
        className="mt-0.5 h-4 w-4 flex-none rounded-full"
        style={{ border: `2px solid ${on ? "var(--primary)" : "var(--border-strong)"}`, background: on ? "var(--primary)" : "transparent", boxShadow: on ? "inset 0 0 0 3px var(--panel)" : undefined }}
      />
      <span className="min-w-0 flex-1">
        <b className="block" style={{ color: "var(--text)" }}>{title}</b>
        <span className="text-xs" style={hintStyle}>{hint}</span>
      </span>
    </button>
  );
}
