"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useState } from "react";

import { fetchFinancePackages } from "@/api/finance";
import {
  addCorporateSeat,
  createCorporateClient,
  endCorporateSeat,
  fetchCorporateClients,
  fetchCorporateInvoices,
  fetchCorporateSeats,
  fetchCorporateInvoiceDocument,
  generateCorporateInvoice,
  recordCorporatePayment,
  reverseCorporatePayment,
  sendCorporateInvoice,
  updateCorporateClient,
  voidCorporateInvoice,
  type CorporateClient,
  type CorporateInvoice,
  type CorporatePaymentMethod,
} from "@/api/payment-models";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";
import { useSession } from "@/components/session-provider";
import {
  centsToInput,
  corporatePackages,
  formatIsoDate,
  localDateKey,
  parseEuroToCents,
  parsePaymentTerms,
  seatUsage,
  staffErrorMessage,
} from "@/components/staff/staff-helpers";
import {
  dangerButtonStyle,
  inputClass,
  inputStyle,
  captionClass,
  captionStyle,
  Pill,
  primaryButtonClass,
  primaryButtonStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
  StaffPanel,
  StatusText,
} from "@/components/staff/staff-ui";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { buildCorporateInvoiceLayout, renderCorporateInvoicePdf } from "@/lib/corporate-invoice-pdf";

const CLIENTS_KEY = ["admin", "finance", "corporate-clients"] as const;

function money(uiLocale: string, cents: number | null | undefined) {
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format((cents ?? 0) / 100);
}

function ClientForm({ client, onDone }: { client: CorporateClient | null; onDone: () => void }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const baseId = useId();
  const [companyName, setCompanyName] = useState(client?.company_name ?? "");
  const [contactName, setContactName] = useState(client?.contact_name ?? "");
  const [billingEmail, setBillingEmail] = useState(client?.billing_email ?? "");
  const [packageId, setPackageId] = useState(client?.membership_package_id ?? "");
  const [terms, setTerms] = useState(String(client?.payment_terms_days ?? 14));
  const [autoInvoice, setAutoInvoice] = useState(client?.auto_invoice ?? true);

  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled: Boolean(token) && !client,
    queryFn: () => fetchFinancePackages(token),
  });
  const packages = corporatePackages(packagesQuery.data?.packages ?? []);
  const termsValue = parsePaymentTerms(terms);
  const valid = companyName.trim().length >= 2 && Boolean(client || packageId) && termsValue !== null;

  const mutation = useMutation({
    mutationFn: () => {
      const details = {
        company_name: companyName.trim(),
        contact_name: contactName.trim() || null,
        billing_email: billingEmail.trim() || null,
        payment_terms_days: termsValue ?? 14,
        auto_invoice: autoInvoice,
      };
      return client
        ? updateCorporateClient(token, client.id, details)
        : createCorporateClient(token, { ...details, membership_package_id: packageId });
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: CLIENTS_KEY });
      onDone();
    },
  });

  return (
    <form
      className="grid gap-3 sm:grid-cols-2"
      onSubmit={(event) => {
        event.preventDefault();
        if (valid) mutation.mutate();
      }}
    >
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-company`} style={captionStyle}>
          {i18n("stfCompanyName")}
        </label>
        <input
          id={`${baseId}-company`}
          className={inputClass}
          maxLength={120}
          onChange={(event) => setCompanyName(event.target.value)}
          required
          style={inputStyle}
          value={companyName}
        />
      </div>
      {client ? null : (
        <div className="space-y-1">
          <label className={captionClass} htmlFor={`${baseId}-package`} style={captionStyle}>
            {i18n("stfCorporatePackage")}
          </label>
          <select
            id={`${baseId}-package`}
            className={inputClass}
            onChange={(event) => setPackageId(event.target.value)}
            required
            style={inputStyle}
            value={packageId}
          >
            <option value="">{i18n("selectPackage02bf832")}</option>
            {packages.map((pkg) => (
              <option key={String(pkg.id)} value={String(pkg.id)}>
                {String(pkg.name ?? pkg.code ?? pkg.id)}
              </option>
            ))}
          </select>
          {packagesQuery.isSuccess && packages.length === 0 ? (
            <p className="text-xs" style={{ color: "var(--dim)" }}>
              {i18n("stfNoCorporatePackages")}
            </p>
          ) : null}
        </div>
      )}
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-contact`} style={captionStyle}>
          {i18n("stfContactName")}
        </label>
        <input
          id={`${baseId}-contact`}
          className={inputClass}
          maxLength={120}
          onChange={(event) => setContactName(event.target.value)}
          style={inputStyle}
          value={contactName}
        />
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-email`} style={captionStyle}>
          {i18n("stfBillingEmail")}
        </label>
        <input
          id={`${baseId}-email`}
          className={inputClass}
          maxLength={200}
          onChange={(event) => setBillingEmail(event.target.value)}
          style={inputStyle}
          type="email"
          value={billingEmail}
        />
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-terms`} style={captionStyle}>
          {i18n("stfPaymentTermsDays")}
        </label>
        <input
          id={`${baseId}-terms`}
          aria-invalid={termsValue === null}
          className={inputClass}
          inputMode="numeric"
          max={120}
          min={0}
          onChange={(event) => setTerms(event.target.value)}
          required
          style={inputStyle}
          type="number"
          value={terms}
        />
      </div>
      <div className="space-y-1">
        <label className="flex items-center gap-2 text-sm" htmlFor={`${baseId}-auto`} style={{ color: "var(--text)" }}>
          <input
            id={`${baseId}-auto`}
            aria-describedby={`${baseId}-auto-hint`}
            checked={autoInvoice}
            onChange={(event) => setAutoInvoice(event.target.checked)}
            type="checkbox"
          />
          {i18n("stfAutoInvoice")}
        </label>
        <p id={`${baseId}-auto-hint`} className="text-xs" style={{ color: "var(--dim)" }}>
          {i18n("stfAutoInvoiceHint")}
        </p>
      </div>
      <div className="flex flex-wrap items-center gap-3 sm:col-span-2">
        <button className={primaryButtonClass} disabled={!valid || mutation.isPending} style={primaryButtonStyle} type="submit">
          {mutation.isPending ? i18n("stfSaving") : client ? i18n("saveChanges179359b") : i18n("stfAddCorporateClient")}
        </button>
        <button className={secondaryButtonClass} onClick={onDone} style={secondaryButtonStyle} type="button">
          {i18n("cancel77dfd21")}
        </button>
        {mutation.isError ? <StatusText tone="error">{staffErrorMessage(mutation.error, i18n)}</StatusText> : null}
      </div>
    </form>
  );
}

function SeatsSection({ client }: { client: CorporateClient }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const [userId, setUserId] = useState("");
  const seatsKey = [...CLIENTS_KEY, client.id, "seats"];

  const seatsQuery = useQuery({
    queryKey: seatsKey,
    enabled: Boolean(token),
    queryFn: () => fetchCorporateSeats(token, client.id),
  });
  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: seatsKey });
    await queryClient.invalidateQueries({ queryKey: CLIENTS_KEY, exact: true });
  };
  const add = useMutation({
    mutationFn: () => addCorporateSeat(token, client.id, userId),
    onSuccess: async () => {
      setUserId("");
      await refresh();
    },
  });
  const end = useMutation({ mutationFn: (seatId: string) => endCorporateSeat(token, client.id, seatId), onSuccess: refresh });
  const seats = seatsQuery.data ?? [];

  return (
    <div className="space-y-3">
      <h4 className="text-xs font-bold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
        {i18n("stfSeats")} ({seatUsage(client.active_seats, client.seats)})
      </h4>
      {client.status === "active" && token ? (
        <div className="flex flex-wrap items-end gap-3">
          <div className="min-w-60 flex-1">
            <UserSearchField label={i18n("stfEnrollMember")} onChange={(id) => setUserId(id)} token={token} value={userId} />
          </div>
          <button
            className={primaryButtonClass}
            disabled={!userId || add.isPending}
            onClick={() => add.mutate()}
            style={primaryButtonStyle}
            type="button"
          >
            {i18n("stfEnroll")}
          </button>
        </div>
      ) : null}
      {add.isError ? <StatusText tone="error">{staffErrorMessage(add.error, i18n)}</StatusText> : null}
      {end.isError ? <StatusText tone="error">{staffErrorMessage(end.error, i18n)}</StatusText> : null}
      {seatsQuery.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : seats.length === 0 ? (
        <StatusText tone="muted">{i18n("stfNoSeats")}</StatusText>
      ) : (
        <ul className="space-y-1.5">
          {seats.map((seat) => (
            <li
              key={seat.id}
              className="flex flex-wrap items-center justify-between gap-2 rounded-[1rem] px-3 py-2"
              style={{ background: "var(--panel)" }}
            >
              <span className="text-sm" style={{ color: "var(--text)" }}>
                {seat.nickname ?? i18n("stfUnknownMember")}
                <span className="ms-2 text-xs" style={{ color: "var(--dim)" }}>
                  {[seat.starts_on, seat.ends_on].filter(Boolean).join(" → ")}
                </span>
              </span>
              <span className="flex items-center gap-2">
                <Pill tone={seatTone(seat.status)}>
                  {seat.status === "active" ? i18n("stfSeatActive") : i18n("stfSeatEnded")}
                </Pill>
                {seat.status === "active" ? (
                  <button
                    className={secondaryButtonClass}
                    disabled={end.isPending}
                    onClick={() => {
                      if (window.confirm(i18n("stfEndSeatConfirm"))) end.mutate(seat.id);
                    }}
                    style={dangerButtonStyle}
                    type="button"
                  >
                    {i18n("stfEndSeat")}
                  </button>
                ) : null}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function seatTone(status: string) {
  return status === "active" ? ("success" as const) : ("neutral" as const);
}

function invoiceTone(status: CorporateInvoice["status"]) {
  if (status === "paid") return "success" as const;
  if (status === "void") return "neutral" as const;
  if (status === "overdue") return "warning" as const;
  return "primary" as const;
}

const PAYMENT_METHODS: CorporatePaymentMethod[] = ["bank_transfer", "cash", "card_manual", "other"];

function usePaymentMethodLabels(): Record<CorporatePaymentMethod, string> {
  const i18n = useUiTranslations();
  return {
    bank_transfer: i18n("stfMethodBankTransfer"),
    cash: i18n("stfMethodCash"),
    card_manual: i18n("stfMethodCard"),
    other: i18n("stfMethodOther"),
  };
}

function useInvoiceStatusLabels(): Record<CorporateInvoice["status"], string> {
  const i18n = useUiTranslations();
  return {
    issued: i18n("stfInvoiceIssued"),
    overdue: i18n("stfInvoiceOverdue"),
    paid: i18n("stfInvoicePaid"),
    void: i18n("stfInvoiceVoid"),
  };
}

function downloadFile(file: File) {
  const url = URL.createObjectURL(file);
  const link = document.createElement("a");
  link.href = url;
  link.download = file.name;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function PaymentForm({ invoice, clientId, onDone }: { invoice: CorporateInvoice; clientId: string; onDone: () => void }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const baseId = useId();
  const methodLabels = usePaymentMethodLabels();
  const [amount, setAmount] = useState(() => centsToInput(invoice.balance_cents));
  const [method, setMethod] = useState<CorporatePaymentMethod>("bank_transfer");
  const [paidOn, setPaidOn] = useState(() => localDateKey(new Date()));
  const [reference, setReference] = useState("");
  const cents = parseEuroToCents(amount);
  const valid = cents !== null && cents <= invoice.balance_cents;

  const mutation = useMutation({
    mutationFn: () =>
      recordCorporatePayment(tokens!.access_token, invoice.id, {
        amount_cents: cents!,
        payment_method: method,
        paid_on: paidOn || null,
        reference: reference.trim() || null,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: [...CLIENTS_KEY, clientId, "invoices"] });
      onDone();
    },
  });

  return (
    <form
      className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
      onSubmit={(event) => {
        event.preventDefault();
        if (valid) mutation.mutate();
      }}
    >
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-amount`} style={captionStyle}>
          {i18n("stfAmountEuro")}
        </label>
        <input
          id={`${baseId}-amount`}
          aria-invalid={!valid}
          className={inputClass}
          inputMode="decimal"
          onChange={(event) => setAmount(event.target.value)}
          required
          style={inputStyle}
          value={amount}
        />
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-method`} style={captionStyle}>
          {i18n("stfPaymentMethod")}
        </label>
        <select
          id={`${baseId}-method`}
          className={inputClass}
          onChange={(event) => setMethod(event.target.value as CorporatePaymentMethod)}
          style={inputStyle}
          value={method}
        >
          {PAYMENT_METHODS.map((option) => (
            <option key={option} value={option}>
              {methodLabels[option]}
            </option>
          ))}
        </select>
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-date`} style={captionStyle}>
          {i18n("stfPaidOn")}
        </label>
        <input
          id={`${baseId}-date`}
          className={inputClass}
          onChange={(event) => setPaidOn(event.target.value)}
          style={inputStyle}
          type="date"
          value={paidOn}
        />
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-reference`} style={captionStyle}>
          {i18n("stfPaymentReference")}
        </label>
        <input
          id={`${baseId}-reference`}
          className={inputClass}
          maxLength={120}
          onChange={(event) => setReference(event.target.value)}
          style={inputStyle}
          value={reference}
        />
      </div>
      <div className="flex flex-wrap items-center gap-3 sm:col-span-2 lg:col-span-4">
        <button className={primaryButtonClass} disabled={!valid || mutation.isPending} style={primaryButtonStyle} type="submit">
          {mutation.isPending ? i18n("stfSaving") : i18n("stfRecordPayment")}
        </button>
        <button className={secondaryButtonClass} onClick={onDone} style={secondaryButtonStyle} type="button">
          {i18n("cancel77dfd21")}
        </button>
        {!valid ? <StatusText tone="error">{i18n("stfPaymentAmountHint")}</StatusText> : null}
        {mutation.isError ? <StatusText tone="error">{staffErrorMessage(mutation.error, i18n)}</StatusText> : null}
      </div>
    </form>
  );
}

function InvoiceRow({ invoice, clientId }: { invoice: CorporateInvoice; clientId: string }) {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const methodLabels = usePaymentMethodLabels();
  const statusLabels = useInvoiceStatusLabels();
  const [paying, setPaying] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const refresh = () => queryClient.invalidateQueries({ queryKey: [...CLIENTS_KEY, clientId, "invoices"] });
  const open = invoice.status === "issued" || invoice.status === "overdue";

  const voidInvoice = useMutation({ mutationFn: () => voidCorporateInvoice(token, invoice.id), onSuccess: refresh });
  const send = useMutation({
    mutationFn: () => sendCorporateInvoice(token, invoice.id),
    onSuccess: async () => {
      setNotice(i18n("stfInvoiceSent"));
      await refresh();
    },
  });
  const reverse = useMutation({
    mutationFn: ({ paymentId, reason }: { paymentId: string; reason?: string }) =>
      reverseCorporatePayment(token, invoice.id, paymentId, reason),
    onSuccess: refresh,
  });
  const pdf = useMutation({
    mutationFn: async () => {
      const document = await fetchCorporateInvoiceDocument(token, invoice.id);
      const layout = buildCorporateInvoiceLayout(
        document,
        {
          invoice: i18n("stfPdfInvoice"),
          billTo: i18n("stfPdfBillTo"),
          contact: i18n("stfContactName"),
          email: i18n("stfBillingEmail"),
          issuedOn: i18n("stfIssuedOn"),
          dueOn: i18n("stfDueOn"),
          period: i18n("stfPdfPeriod"),
          status: i18n("statusbae7d5b"),
          description: i18n("description55f8ebc"),
          quantity: i18n("stfSeats"),
          unitPrice: i18n("stfPdfUnitPrice"),
          amount: i18n("stfPdfAmount"),
          seatLine: i18n("stfPdfSeatLine"),
          total: i18n("stfPdfTotal"),
          paid: i18n("stfPaidAmount"),
          balanceDue: i18n("stfBalanceDue"),
          payments: i18n("stfPayments"),
          reference: i18n("stfPaymentReference"),
          footer: i18n("stfPdfFooter", { issuer: document.issuer.name }),
          statuses: statusLabels,
          methods: methodLabels,
        },
        uiLocale,
      );
      downloadFile(await renderCorporateInvoicePdf(layout));
    },
  });
  const error = voidInvoice.error ?? send.error ?? reverse.error ?? pdf.error;
  const date = (iso: string | null | undefined) => formatIsoDate(uiLocale, iso);

  return (
    <li className="rounded-[1rem] px-3 py-3" style={{ background: "var(--panel)" }}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {invoice.invoice_number ?? "—"}
            <span className="ms-2 text-xs font-normal" style={{ color: "var(--dim)" }}>
              {invoice.period_start} → {invoice.period_end}
            </span>
          </p>
          <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
            {[
              `${i18n("stfIssuedOn")} ${date(invoice.issued_on)}`,
              `${i18n("stfDueOn")} ${date(invoice.due_on)}`,
              i18n("stfSeatsBilled", { count: invoice.seats_billed }),
              invoice.reminder_count ? i18n("stfRemindersSent", { count: invoice.reminder_count }) : null,
            ]
              .filter(Boolean)
              .join(" · ")}
          </p>
          <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>
            {money(uiLocale, invoice.total_cents)} · {i18n("stfPaidAmount")} {money(uiLocale, invoice.paid_cents)} ·{" "}
            <strong style={{ color: invoice.status === "overdue" ? "var(--warning)" : "var(--text)" }}>
              {i18n("stfBalanceDue")} {money(uiLocale, invoice.balance_cents)}
            </strong>
          </p>
        </div>
        <Pill tone={invoiceTone(invoice.status)}>{statusLabels[invoice.status]}</Pill>
      </div>

      <div className="mt-2 flex flex-wrap gap-1.5">
        {open && invoice.balance_cents > 0 && !paying ? (
          <button className={secondaryButtonClass} onClick={() => setPaying(true)} style={secondaryButtonStyle} type="button">
            {i18n("stfRecordPayment")}
          </button>
        ) : null}
        {invoice.status !== "void" ? (
          <button className={secondaryButtonClass} disabled={send.isPending} onClick={() => send.mutate()} style={secondaryButtonStyle} type="button">
            {send.isPending ? i18n("stfSending") : i18n("stfSendToCompany")}
          </button>
        ) : null}
        <button className={secondaryButtonClass} disabled={pdf.isPending} onClick={() => pdf.mutate()} style={secondaryButtonStyle} type="button">
          {pdf.isPending ? i18n("stfPreparingPdf") : i18n("stfDownloadPdf")}
        </button>
        {open && invoice.paid_cents === 0 ? (
          <button
            className={secondaryButtonClass}
            disabled={voidInvoice.isPending}
            onClick={() => {
              if (window.confirm(i18n("voidThisInvoiceThisCannotBeUndone571b60e"))) voidInvoice.mutate();
            }}
            style={dangerButtonStyle}
            type="button"
          >
            {i18n("stfVoid")}
          </button>
        ) : null}
      </div>
      {paying ? <PaymentForm clientId={clientId} invoice={invoice} onDone={() => setPaying(false)} /> : null}
      {notice && !send.isPending ? (
        <div className="mt-2">
          <StatusText tone="success">{notice}</StatusText>
        </div>
      ) : null}
      {error ? (
        <div className="mt-2">
          <StatusText tone="error">{staffErrorMessage(error, i18n)}</StatusText>
        </div>
      ) : null}

      {invoice.payments.length > 0 ? (
        <ul className="mt-3 space-y-1" aria-label={i18n("stfPayments")}>
          {invoice.payments.map((payment) => (
            <li
              key={payment.id}
              className="flex flex-wrap items-center justify-between gap-2 text-xs"
              style={{ color: payment.reversed_at ? "var(--dim)" : "var(--text-soft)" }}
            >
              <span style={payment.reversed_at ? { textDecoration: "line-through" } : undefined}>
                {[date(payment.paid_on), methodLabels[payment.payment_method], money(uiLocale, payment.amount_cents), payment.reference]
                  .filter(Boolean)
                  .join(" · ")}
              </span>
              {payment.reversed_at ? (
                <span>
                  {i18n("stfPaymentReversed")}
                  {payment.reversal_reason ? `: ${payment.reversal_reason}` : ""}
                </span>
              ) : invoice.status !== "void" ? (
                <button
                  className={secondaryButtonClass}
                  disabled={reverse.isPending}
                  onClick={() => {
                    const reason = window.prompt(i18n("stfReversePaymentPrompt"));
                    if (reason === null) return;
                    reverse.mutate({ paymentId: payment.id, reason: reason.trim() || undefined });
                  }}
                  style={dangerButtonStyle}
                  type="button"
                >
                  {i18n("stfReversePayment")}
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      ) : null}
    </li>
  );
}

function InvoicesSection({ client }: { client: CorporateClient }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const dateId = useId();
  const [on, setOn] = useState(() => localDateKey(new Date()));
  const invoicesKey = [...CLIENTS_KEY, client.id, "invoices"];

  const invoicesQuery = useQuery({
    queryKey: invoicesKey,
    enabled: Boolean(token),
    queryFn: () => fetchCorporateInvoices(token, client.id),
  });
  const generate = useMutation({
    mutationFn: () => generateCorporateInvoice(token, client.id, on || undefined),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: invoicesKey }),
  });
  const invoices = invoicesQuery.data ?? [];

  return (
    <div className="space-y-3">
      <h4 className="text-xs font-bold uppercase tracking-[0.2em]" style={{ color: "var(--dim)" }}>
        {i18n("stfCorporateInvoices")}
      </h4>
      <form
        className="flex flex-wrap items-end gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          generate.mutate();
        }}
      >
        <div className="space-y-1">
          <label className={captionClass} htmlFor={dateId} style={captionStyle}>
            {i18n("stfInvoicePeriodContaining")}
          </label>
          <input id={dateId} className={inputClass} onChange={(event) => setOn(event.target.value)} style={inputStyle} type="date" value={on} />
        </div>
        <button className={primaryButtonClass} disabled={generate.isPending} style={primaryButtonStyle} type="submit">
          {generate.isPending ? i18n("stfGenerating") : i18n("stfGenerateInvoice")}
        </button>
      </form>
      {generate.isError ? <StatusText tone="error">{staffErrorMessage(generate.error, i18n)}</StatusText> : null}
      {invoicesQuery.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : invoices.length === 0 ? (
        <StatusText tone="muted">{i18n("stfNoCorporateInvoices")}</StatusText>
      ) : (
        <ul className="space-y-2">
          {invoices.map((invoice) => (
            <InvoiceRow key={invoice.id} clientId={client.id} invoice={invoice} />
          ))}
        </ul>
      )}
    </div>
  );
}

function ClientCard({ client }: { client: CorporateClient }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState(false);
  const refresh = () => queryClient.invalidateQueries({ queryKey: CLIENTS_KEY, exact: true });
  const update = useMutation({
    mutationFn: (body: { regenerate_code?: boolean; status?: "active" | "archived" }) => updateCorporateClient(token, client.id, body),
    onSuccess: refresh,
  });
  const detailsId = `corporate-client-${client.id}`;

  return (
    <li className="rounded-[1.4rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {client.company_name}
          </p>
          <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
            {[
              client.package_name,
              i18n("stfSeatsUsed", { usage: seatUsage(client.active_seats, client.seats) }),
              client.seat_billing === "used" ? i18n("stfSeatBillingUsed") : client.seat_billing === "agreed" ? i18n("stfSeatBillingAgreed") : null,
              typeof client.payment_terms_days === "number" ? i18n("stfPaymentTermsShort", { days: client.payment_terms_days }) : null,
              client.auto_invoice === false ? i18n("stfManualInvoicing") : null,
              client.contact_name,
              client.billing_email,
            ]
              .filter(Boolean)
              .join(" · ")}
          </p>
          <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
            {client.enrollment === "email_domain" && client.enrollment_domain
              ? i18n("stfEnrollmentDomain", { domain: client.enrollment_domain })
              : null}
            {client.enrollment === "email_domain" && client.enrollment_domain ? " · " : null}
            {i18n("stfEnrollmentCode")}{" "}
            <code className="rounded px-1.5 py-0.5 font-mono text-xs" style={{ background: "var(--panel)", color: "var(--text)" }}>
              {client.enrollment_code}
            </code>
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {client.status === "archived" ? <Pill tone="neutral">{i18n("stfArchived")}</Pill> : null}
          <button
            aria-controls={detailsId}
            aria-expanded={open}
            className={secondaryButtonClass}
            onClick={() => setOpen((value) => !value)}
            style={secondaryButtonStyle}
            type="button"
          >
            {open ? i18n("stfHideDetails") : i18n("stfManage")}
          </button>
        </div>
      </div>
      {open ? (
        <div id={detailsId} className="mt-4 space-y-5">
          <div className="flex flex-wrap gap-2">
            <button className={secondaryButtonClass} onClick={() => setEditing((value) => !value)} style={secondaryButtonStyle} type="button">
              {editing ? i18n("cancel77dfd21") : i18n("edit5301648")}
            </button>
            <button
              className={secondaryButtonClass}
              disabled={update.isPending}
              onClick={() => {
                if (window.confirm(i18n("stfRegenerateCodeConfirm"))) update.mutate({ regenerate_code: true });
              }}
              style={secondaryButtonStyle}
              type="button"
            >
              {i18n("stfRegenerateCode")}
            </button>
            <button
              className={secondaryButtonClass}
              disabled={update.isPending}
              onClick={() => update.mutate({ status: client.status === "active" ? "archived" : "active" })}
              style={client.status === "active" ? dangerButtonStyle : secondaryButtonStyle}
              type="button"
            >
              {client.status === "active" ? i18n("stfArchive") : i18n("stfReactivate")}
            </button>
          </div>
          {update.isError ? <StatusText tone="error">{staffErrorMessage(update.error, i18n)}</StatusText> : null}
          {editing ? <ClientForm client={client} onDone={() => setEditing(false)} /> : null}
          <SeatsSection client={client} />
          <InvoicesSection client={client} />
        </div>
      ) : null}
    </li>
  );
}

export function CorporateTab() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const [creating, setCreating] = useState(false);

  const clientsQuery = useQuery({
    queryKey: CLIENTS_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchCorporateClients(tokens!.access_token),
  });
  const clients = clientsQuery.data ?? [];

  return (
    <div className="space-y-6">
      {creating ? (
        <StaffPanel labelledBy="corporate-new-client" title={i18n("stfAddCorporateClient")}>
          <ClientForm client={null} onDone={() => setCreating(false)} />
        </StaffPanel>
      ) : null}
      <StaffPanel
        eyebrow={i18n("stfCorporateEyebrow")}
        labelledBy="corporate-clients"
        title={i18n("stfCorporateClients")}
        actions={
          creating ? null : (
            <button className={primaryButtonClass} onClick={() => setCreating(true)} style={primaryButtonStyle} type="button">
              {i18n("stfAddCorporateClient")}
            </button>
          )
        }
      >
        {clientsQuery.isPending ? (
          <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
        ) : clientsQuery.isError ? (
          <StatusText tone="error">{staffErrorMessage(clientsQuery.error, i18n)}</StatusText>
        ) : clients.length === 0 ? (
          <StatusText tone="muted">{i18n("stfNoCorporateClients")}</StatusText>
        ) : (
          <ul className="space-y-3">
            {clients.map((client) => (
              <ClientCard key={client.id} client={client} />
            ))}
          </ul>
        )}
      </StaffPanel>
    </div>
  );
}
