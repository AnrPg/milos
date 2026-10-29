"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useRef, useState, type FormEvent } from "react";

import {
  CREDIT_REASONS,
  emailFiscalDocument,
  fetchFiscalDocument,
  issueCreditNote,
  retryTransmission,
  type CreditReason,
  type CreditResult,
  type FiscalDocumentDetail,
} from "@/api/fiscal";
import { ApiError } from "@/api/client";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { fieldBorder, formErrorsFrom, invalidFieldProps } from "@/lib/form-errors";

import { DocumentViewDialog } from "./DocumentViewDialog";
import {
  buyerEmail,
  buyerName,
  canCredit,
  canRetry,
  cardLabel,
  creditAmount,
  creditLines,
  providerName,
  ratePercent,
  sellerLine,
  transmissionState,
} from "./documents-model";
import {
  Card,
  Chip,
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
  primaryButtonStyle,
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
  const [emailing, setEmailing] = useState(false);
  const [sentTo, setSentTo] = useState<string | null>(null);
  // What the credit-note panel just did, for the line under the note.
  const [issued, setIssued] = useState<{ id: string; card: string | null } | null>(null);
  const query = useQuery({ queryKey: documentKey(documentId), enabled: Boolean(token), queryFn: () => fetchFiscalDocument(token, documentId) });
  const document = query.data?.document;

  if (viewing && document) {
    return <DocumentViewDialog token={token} document={document} onClose={() => setViewing(false)} />;
  }

  if (mode === "credit" && document) {
    return (
      <CreditPanel
        token={token}
        document={document}
        onBack={() => setMode("detail")}
        onIssued={(result, card) => {
          if (result.document) setIssued({ id: result.document.id, card });
          setMode("detail");
        }}
        onClose={onClose}
      />
    );
  }

  if (emailing && document) {
    return (
      <EmailDialog
        token={token}
        document={document}
        onClose={() => setEmailing(false)}
        onSent={(to) => {
          setSentTo(to);
          setEmailing(false);
        }}
      />
    );
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
              {t("pdf")}
            </button>
            <button type="button" className={ghostButtonClass} style={ghostButtonStyle} onClick={() => setEmailing(true)} data-testid="fiscal-doc-email">
              {t("sendEmail")}
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
        <DocumentDetail token={token} document={document} onOpen={onOpen} sentTo={sentTo} justIssued={issued} />
      )}
    </Dialog>
  );
}

function DocumentDetail({
  token,
  document,
  onOpen,
  sentTo,
  justIssued,
}: {
  token: string;
  document: FiscalDocumentDetail;
  onOpen: (id: string) => void;
  sentTo: string | null;
  justIssued: { id: string; card: string | null } | null;
}) {
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
      {document.credit_reason ? (
        <KeyValue label={t("reason")}>
          <span data-testid="fiscal-doc-reason">{t(`reasons.${document.credit_reason}`)}</span>
        </KeyValue>
      ) : null}
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
              <p className="text-xs" style={hintStyle}>
                {[
                  credit.credit_reason ? t(`reasons.${credit.credit_reason}`) : null,
                  justIssued?.id === credit.id ? (justIssued.card ? t("refundingToCard", { card: justIssued.card }) : t("noRefund")) : null,
                  t("originalUnchanged"),
                ]
                  .filter(Boolean)
                  .join(" · ")}
              </p>
            </div>
          </div>
        </Card>
      ))}

      {sentTo ? (
        <p className="flex items-center gap-1.5 text-xs" style={{ color: "var(--success)" }} role="status" data-testid="fiscal-doc-email-sent">
          <Icon name="check" size={13} />
          {t("emailSent", { to: sentTo })}
        </p>
      ) : null}

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
  onIssued,
  onClose,
}: {
  token: string;
  document: FiscalDocumentDetail;
  onBack: () => void;
  onIssued: (result: CreditResult, card: string | null) => void;
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
  const [reason, setReason] = useState<CreditReason | null>(null);
  const option = document.refund_option ?? null;
  // Mockup s2: the switch starts on; staff turn it off when they gave the money back another way.
  const [refund, setRefund] = useState(Boolean(option));
  const card = option ? cardLabel(option) : null;
  const [error, setError] = useState<string | null>(null);
  // One key per credit note the person means to issue: a retried click is the same request.
  const idempotencyKey = useRef(crypto.randomUUID());
  const amount = creditAmount(lines, full, picked);
  const ready = amount > 0 && reason !== null;

  const issue = useMutation({
    mutationFn: () =>
      issueCreditNote(token, document.id, {
        idempotencyKey: idempotencyKey.current,
        reason: reason!,
        lines: full ? undefined : creditLines(lines, picked),
        refund: Boolean(option) && refund,
      }),
    onSuccess: (result) => {
      void queryClient.invalidateQueries({ queryKey: documentKey(document.id) });
      void queryClient.invalidateQueries({ queryKey: FISCAL_DOCUMENTS_KEY });
      onIssued(result, option && refund ? card : null);
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
  const pickReason = (value: CreditReason) => {
    setReason(value);
    idempotencyKey.current = crypto.randomUUID();
  };
  const toggleRefund = () => {
    setRefund((value) => !value);
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
      footerStart={
        amount <= 0 ? (
          <span className="text-xs" style={hintStyle}>{t("pickLines")}</span>
        ) : reason === null ? (
          <span className="text-xs" style={hintStyle}>{t("pickReason")}</span>
        ) : null
      }
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
        <div className="grid gap-1.5">
          <span id="fiscal-credit-reason-label" className="text-xs font-bold" style={{ color: "var(--text-soft)" }}>
            {t("reason")}
          </span>
          <div role="group" aria-labelledby="fiscal-credit-reason-label" className="flex flex-wrap gap-1.5">
            {CREDIT_REASONS.map((value) => (
              <Chip key={value} on={reason === value} onClick={() => pickReason(value)} testId={`fiscal-credit-reason-${value}`}>
                {t(`reasons.${value}`)}
              </Chip>
            ))}
          </div>
        </div>
        {option && card ? (
          <div className="flex items-center gap-3 rounded-[14px] p-2.5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <span className="min-w-0 flex-1">
              <b id="fiscal-credit-refund-label" className="block" style={{ color: "var(--text)" }}>
                {t("refundToCard", { card })}
              </b>
              <span id="fiscal-credit-refund-hint" className="text-xs" style={hintStyle}>
                {t("refundToCardHint", { provider: providerName(option.provider) })}
              </span>
            </span>
            <button
              type="button"
              role="switch"
              aria-checked={refund}
              aria-labelledby="fiscal-credit-refund-label"
              aria-describedby="fiscal-credit-refund-hint"
              onClick={toggleRefund}
              disabled={issue.isPending}
              data-testid="fiscal-credit-refund"
              className="hit-area relative h-8 w-14 shrink-0 rounded-full disabled:opacity-60"
              style={{ background: refund ? "var(--primary)" : "var(--panel-raised)", border: "1px solid var(--border)" }}
            >
              <span
                aria-hidden="true"
                className="absolute top-1 h-5 w-5 rounded-full transition-all"
                style={{ left: refund ? "1.9rem" : "0.25rem", background: refund ? "var(--bg)" : "var(--text)" }}
              />
            </button>
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

/** «Αποστολή με email» (ADR-265): the PDF to the customer printed on it, or to an address staff type. */
function EmailDialog({
  token,
  document,
  onClose,
  onSent,
}: {
  token: string;
  document: FiscalDocumentDetail;
  onClose: () => void;
  onSent: (to: string) => void;
}) {
  const t = useTranslations("FiscalDocuments");
  const translate = useUiTranslations();
  const [to, setTo] = useState(buyerEmail(document) ?? "");
  const [fieldError, setFieldError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  // One key per address: a retried click sends nothing twice.
  const idempotencyKey = useRef(crypto.randomUUID());

  const send = useMutation({
    mutationFn: () => emailFiscalDocument(token, document.id, idempotencyKey.current, to.trim()),
    onSuccess: (result) => onSent(result.email.to),
    onError: (failure) => {
      const code = failure instanceof ApiError ? failure.payload.code : undefined;
      if (code === "invalid_address" || code === "no_recipient") setFieldError(t(`emailError.${code}`));
      else if (code === "throttled" || code === "suppressed" || code === "business_not_activated") setError(t(`emailError.${code}`));
      else setError(formErrorsFrom(failure, translate, []).message);
    },
  });

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    if (!to.trim()) {
      setFieldError(t("emailError.no_recipient"));
      return;
    }
    setFieldError(null);
    send.mutate();
  }

  return (
    <Dialog
      variant="panel"
      size="md"
      title={t("emailTitle", { number: document.number })}
      onClose={onClose}
      onSubmit={submit}
      dismissible={!send.isPending}
      error={error}
      testId="fiscal-email-dialog"
      footer={
        <>
          <button type="button" className={ghostButtonClass} style={ghostButtonStyle} onClick={onClose} disabled={send.isPending}>
            {t("back")}
          </button>
          <button type="submit" className={ghostButtonClass} style={primaryButtonStyle} disabled={send.isPending} data-testid="fiscal-email-send">
            {send.isPending ? t("emailSending") : t("emailSend")}
          </button>
        </>
      }
    >
      <div className="grid gap-1">
        <label htmlFor="fiscal-email-to" className="text-xs font-bold" style={{ color: "var(--text-soft)" }}>
          {t("emailTo")}
        </label>
        <input
          id="fiscal-email-to"
          data-testid="fiscal-email-to"
          type="email"
          value={to}
          onChange={(event) => {
            setTo(event.target.value);
            setFieldError(null);
            idempotencyKey.current = crypto.randomUUID();
          }}
          autoComplete="off"
          className="min-h-11 w-full rounded-xl px-3 text-sm"
          style={{ background: "var(--bg)", border: fieldBorder(fieldError ?? undefined), color: "var(--text)" }}
          {...invalidFieldProps(fieldError, "fiscal-email-to-error")}
        />
        {fieldError ? (
          <FieldError id="fiscal-email-to-error">{fieldError}</FieldError>
        ) : (
          <span className="text-xs" style={hintStyle}>{t("emailHint")}</span>
        )}
      </div>
    </Dialog>
  );
}
