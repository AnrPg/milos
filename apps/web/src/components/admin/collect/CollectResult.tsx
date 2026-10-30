"use client";

import { useMutation } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useRef, useState, type FormEvent } from "react";

import { ApiError } from "@/api/client";
import { emailTerminalReceipt, fetchTerminalPayment, type TerminalPayment, type TerminalReceipt } from "@/api/desk-collect";
import { formatTime } from "@/components/client/format";
import { Card, Chip, Icon, KeyValue, Pill, formatMoney } from "@/components/fiscal/fiscal-ui";
import { QrCode } from "@/components/referrals/QrCode";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { cardTotalCents, looksLikeEmail, newAttemptKey, outcomeOf, tipOwner } from "./collect-flow";
import { BigButton, BigMark, CollectIcon, FieldError, fieldInputClass, fieldInputStyle } from "./collect-ui";

type Props = {
  payment: TerminalPayment;
  /** The member's name; null for a walk-in. */
  payerName: string | null;
  onChange: (payment: TerminalPayment) => void;
  onAgain: () => void;
  onNew: () => void;
  onDone: () => void;
};

/**
 * The «Αποτέλεσμα» of a Tap to Pay payment (mockup pilot-gaps screen 2 A):
 * paid (with the tip and surcharge apart and the receipt), cancelled,
 * declined, unconfirmed («Μην χρεώσεις ξανά»), a mismatched amount, or a
 * payment that did not go through.
 */
export function CollectResult({ payment, payerName, onChange, onAgain, onNew, onDone }: Props) {
  const t = useTranslations("Collect");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const slug = useOrganizationSlug();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const outcome = outcomeOf(payment);
  const check = useMutation({
    mutationFn: () => fetchTerminalPayment(token, payment.id),
    onSuccess: ({ payment: fresh }) => onChange(fresh),
  });
  const amount = formatMoney(locale, payment.amount_cents, payment.currency);

  if (outcome === "cancelled") {
    return (
      <Card className="text-center" testId="collect-result-cancelled">
        <BigMark tone="warn"><CollectIcon name="x" size={26} /></BigMark>
        <b className="text-base" style={{ color: "var(--text)" }}>{t("cancelledTitle")}</b>
        <span className="text-sm" style={{ color: "var(--muted)" }}>{t("cancelledHint")}</span>
        <BigButton onClick={onAgain} testId="collect-retry"><CollectIcon name="nfc" />{t("retry")}</BigButton>
        <BigButton ghost onClick={onDone}>{t("done")}</BigButton>
      </Card>
    );
  }

  if (outcome === "declined") {
    return (
      <Card className="text-center" testId="collect-result-declined">
        <BigMark tone="bad"><CollectIcon name="x" size={26} /></BigMark>
        <b className="text-base" style={{ color: "var(--text)" }}>{t("declinedTitle")}</b>
        <span className="text-sm" style={{ color: "var(--muted)" }}>{t("declinedHint")}</span>
        <BigButton onClick={onAgain} testId="collect-retry"><CollectIcon name="nfc" />{t("retryOtherCard")}</BigButton>
        <Link href={adminHref("/admin/finance?tab=members", slug)} className="text-sm font-bold" style={{ color: "var(--primary-strong)" }}>
          {t("payCash")}
        </Link>
      </Card>
    );
  }

  if (outcome === "unconfirmed" || outcome === "waiting") {
    return (
      <Card className="text-center" testId="collect-result-unconfirmed">
        <BigMark tone="warn"><Icon name="clock" size={26} /></BigMark>
        <b className="text-base" style={{ color: "var(--text)" }}>{t("unconfirmedTitle")}</b>
        <span className="text-sm" style={{ color: "var(--muted)" }}>
          {t.rich("unconfirmedHint", { b: (chunks) => <b style={{ color: "var(--text)" }}>{chunks}</b> })}
        </span>
        <BigButton onClick={onDone}>{t("done")}</BigButton>
        <button type="button" onClick={() => check.mutate()} disabled={check.isPending} className="text-sm font-bold" style={{ color: "var(--primary-strong)" }} data-testid="collect-check-now">
          {t("checkNow")}
        </button>
        {check.isError ? <FieldError id="collect-check-error">{localizeError(check.error, i18n)}</FieldError> : null}
      </Card>
    );
  }

  if (outcome === "mismatch" || outcome === "failed") {
    return (
      <Card className="text-center" testId={`collect-result-${outcome}`}>
        <BigMark tone="bad"><CollectIcon name="alert" size={26} /></BigMark>
        <b className="text-base" style={{ color: "var(--text)" }}>{outcome === "mismatch" ? t("mismatchTitle") : t("failedTitle")}</b>
        <span className="text-sm" style={{ color: "var(--muted)" }}>{outcome === "mismatch" ? t("mismatchHint", { amount }) : t("failedHint")}</span>
        <BigButton onClick={onDone}>{t("done")}</BigButton>
      </Card>
    );
  }

  return <Paid payment={payment} payerName={payerName} onRefresh={() => check.mutate()} refreshing={check.isPending} onNew={onNew} />;
}

function Paid({ payment, payerName, onRefresh, refreshing, onNew }: { payment: TerminalPayment; payerName: string | null; onRefresh: () => void; refreshing: boolean; onNew: () => void }) {
  const t = useTranslations("Collect");
  const locale = useUiLocale();
  const { currentUser } = useSession();
  const money = (cents: number) => formatMoney(locale, cents, payment.currency);
  const tip = payment.tip_cents ?? 0;
  const surcharge = payment.surcharge_cents ?? 0;
  const owner = tipOwner(payment, currentUser?.id);
  const card = [
    payment.card_brand ? `${capitalize(payment.card_brand)}${payment.card_last4 ? ` ••${payment.card_last4}` : ""}` : null,
    capitalize(payment.provider),
    payment.succeeded_at ? formatTime(payment.succeeded_at, locale) : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <>
      <Card className="text-center" testId="collect-result-paid">
        <BigMark tone="ok"><Icon name="check" size={26} /></BigMark>
        <b className="text-lg" style={{ color: "var(--text)" }}>{t("paidTitle", { amount: money(cardTotalCents(payment)) })}</b>
        <span className="text-xs" style={{ color: "var(--muted)" }}>{card}</span>
      </Card>
      {tip > 0 || surcharge > 0 ? (
        <Card testId="collect-breakdown">
          <div className="grid">
            <KeyValue label={payment.description}>{money(payment.amount_cents)}</KeyValue>
            {surcharge > 0 ? <KeyValue label={t("surcharge")}>{money(surcharge)}</KeyValue> : null}
            {tip > 0 ? (
              <KeyValue label={<span data-testid="collect-tip-owner">{owner === "you" ? t("tipYou") : owner === "desk" ? t("tipDesk") : t("tipStaff")}</span>}>
                {money(tip)}
              </KeyValue>
            ) : null}
            <KeyValue label={t("onCard")} total>{money(cardTotalCents(payment))}</KeyValue>
          </div>
        </Card>
      ) : null}
      <ReceiptCard payment={payment} payerName={payerName} onRefresh={onRefresh} refreshing={refreshing} />
      <BigButton onClick={onNew} testId="collect-new">{t("newCollect")}</BigButton>
    </>
  );
}

function capitalize(value: string) {
  return value ? value[0]!.toLocaleUpperCase() + value.slice(1) : value;
}

function TransmissionPill({ status }: { status: TerminalReceipt["transmission_status"] }) {
  const f = useTranslations("FiscalDocuments");
  if (!status) return null;
  if (status === "accepted") {
    return (
      <Pill tone="ok" testId="collect-tx">
        <Icon name="check" size={11} />
        {f("txAccepted")}
      </Pill>
    );
  }
  if (status === "rejected") return <Pill tone="bad" testId="collect-tx">{f("txRejected")}</Pill>;
  return <Pill tone="warn" testId="collect-tx">{f("txPending")}</Pill>;
}

function ReceiptCard({ payment, payerName, onRefresh, refreshing }: { payment: TerminalPayment; payerName: string | null; onRefresh: () => void; refreshing: boolean }) {
  const t = useTranslations("Collect");
  const locale = useUiLocale();
  const document = payment.document;
  const walkIn = !payment.user_id;
  const [qr, setQr] = useState(true);
  const [emailing, setEmailing] = useState(false);
  const [sent, setSent] = useState(false);

  if (!document) {
    return (
      <Card testId="collect-receipt-preparing">
        <div className="flex items-center gap-3">
          <span style={{ color: "var(--muted)" }}><Icon name="receipt" size={20} /></span>
          <span className="flex-1 text-sm" style={{ color: "var(--text-soft)" }}>{t("receiptPreparing")}</span>
          <button type="button" onClick={onRefresh} disabled={refreshing} className="text-sm font-bold" style={{ color: "var(--primary-strong)" }}>
            {t("refresh")}
          </button>
        </div>
      </Card>
    );
  }

  const gross = formatMoney(locale, document.gross_cents, document.currency);
  const pending = document.transmission_status !== null && document.transmission_status !== "accepted" && document.transmission_status !== "rejected";

  return (
    <Card testId="collect-receipt">
      <div className="flex items-start gap-3">
        <span style={{ color: "var(--text-soft)" }}><Icon name="receipt" size={20} /></span>
        <div className="grid min-w-0 flex-1 gap-0.5">
          <b className="text-sm" style={{ color: "var(--text)" }} data-testid="collect-receipt-title">
            {document.kind === "invoice" ? t("invoiceTitle", { number: document.number, amount: gross }) : t("receiptTitle", { number: document.number, amount: gross })}
          </b>
          <span className="text-xs" style={{ color: "var(--muted)" }}>
            {walkIn ? t("retailCustomer") : payerName ?? ""} · {t("paidWith")}
          </span>
        </div>
        <TransmissionPill status={document.transmission_status} />
      </div>
      {pending ? <span className="text-xs" style={{ color: "var(--muted)" }}>{t("receiptPendingHint")}</span> : null}
      <div className="flex flex-wrap gap-1.5">
        {walkIn && document.receipt_url ? (
          <Chip on={qr} onClick={() => setQr(!qr)} testId="collect-show-qr">
            <Icon name="receipt" size={11} />
            {t("showQr")}
          </Chip>
        ) : null}
        {sent ? (
          <Chip on onClick={() => setEmailing(true)} testId="collect-email-sent">
            <Icon name="check" size={11} />
            {t("emailSent")}
          </Chip>
        ) : (
          <Chip on={emailing} onClick={() => setEmailing(!emailing)} testId="collect-send-email">
            {t("sendEmail")}
          </Chip>
        )}
      </div>
      {walkIn && qr && document.receipt_url ? (
        <div className="grid justify-items-center gap-2" data-testid="collect-qr">
          <span className="rounded-2xl p-2" style={{ background: "var(--paper)" }}>
            <QrCode value={document.receipt_url} size={180} label={t("qrLabel")} />
          </span>
          <span className="text-center text-xs" style={{ color: "var(--muted)" }}>{t("qrHint")}</span>
        </div>
      ) : null}
      {emailing && !sent ? (
        <EmailForm
          payment={payment}
          askAddress={walkIn}
          onSent={() => {
            setSent(true);
            setEmailing(false);
          }}
        />
      ) : null}
    </Card>
  );
}

function EmailForm({ payment, askAddress, onSent }: { payment: TerminalPayment; askAddress: boolean; onSent: () => void }) {
  const t = useTranslations("Collect");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const key = useRef(newAttemptKey());
  const [needAddress, setNeedAddress] = useState(askAddress);
  const [to, setTo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const send = useMutation({
    mutationFn: () => emailTerminalReceipt(token, payment.id, key.current, needAddress ? to.trim() : undefined),
    onSuccess: onSent,
    onError: (failure) => {
      const code = failure instanceof ApiError ? failure.payload.code : undefined;
      if (code === "no_recipient") {
        setNeedAddress(true);
        setError(t("noRecipient"));
      } else if (code === "invalid_email" || code === "validation_failed") {
        setError(t("emailInvalid"));
      } else {
        setError(localizeError(failure, i18n));
      }
    },
  });

  function submit(event: FormEvent) {
    event.preventDefault();
    if (needAddress && !looksLikeEmail(to)) {
      setError(t("emailInvalid"));
      return;
    }
    setError(null);
    send.mutate();
  }

  return (
    <form onSubmit={submit} noValidate className="grid gap-2" data-testid="collect-email-form">
      {needAddress ? (
        <label className="grid gap-1">
          <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("emailTo")}</span>
          <input
            type="email"
            inputMode="email"
            autoComplete="off"
            value={to}
            onChange={(event) => setTo(event.target.value)}
            maxLength={254}
            className={fieldInputClass}
            style={fieldInputStyle(Boolean(error))}
            aria-invalid={Boolean(error)}
            aria-describedby={error ? "collect-email-error" : undefined}
            data-testid="collect-email-to"
          />
        </label>
      ) : null}
      {error ? <FieldError id="collect-email-error">{error}</FieldError> : null}
      <BigButton type="submit" ghost disabled={send.isPending} testId="collect-email-send">
        {send.isPending ? t("sending") : t("send")}
      </BigButton>
    </form>
  );
}
