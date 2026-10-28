"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";

import { ApiError } from "@/api/client";
import {
  fetchFinanceMember,
  getInvoiceUploadUrl,
  receiveFinancePayment,
  type FinanceRecord,
  type ReceivedPayment,
} from "@/api/finance";
import { fetchAdminSettings } from "@/api/settings";
import { ChargeCategorySelect } from "@/components/admin/finance/shared/ChargeCategorySelect";
import { useSession } from "@/components/session-provider";
import { DateInput } from "@/components/ui/DateInput";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";

import { downloadExportDocument, receiptDocument } from "./receipt-pdf";
import {
  PAYMENT_METHODS,
  choosePurpose,
  fieldForErrorCode,
  findPurpose,
  initialForm,
  missingFields,
  outcome,
  paymentPurposes,
  purposeValue,
  receiveBody,
  type PaymentPurpose,
  type ReceivePaymentField,
  type ReceivePaymentForm,
} from "./receive-payment";

const CONTROL: CSSProperties = { background: "var(--panel)", color: "var(--text)" };

function subscriptionName(subscription: FinanceRecord) {
  return String(subscription.package_name ?? subscription.package_code_snapshot ?? subscription.package_family_snapshot ?? "");
}

/**
 * ADR-222: «Καταγραφή πληρωμής». Staff record money a client handed over and
 * get the document the box's billing setup calls for. Opened from the
 * client's ledger row and from their finance panel.
 */
export function ReceivePaymentDialog({ userId, nickname, onClose }: { userId: string; nickname: string; onClose: () => void }) {
  const t = useTranslations("ReceivePayment");
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const ids = useId();

  const profileQuery = useQuery({
    queryKey: ["admin", "finance", "member-profile", userId],
    enabled: Boolean(token && userId),
    queryFn: () => fetchFinanceMember(token, userId),
  });
  const settingsQuery = useQuery({
    queryKey: ["admin", "settings"],
    enabled: Boolean(token),
    queryFn: () => fetchAdminSettings(token),
  });

  const purposes = useMemo(() => paymentPurposes(profileQuery.data, subscriptionName), [profileQuery.data]);
  const [draft, setDraft] = useState<ReceivePaymentForm | null>(null);
  const form = draft ?? initialForm(purposes);
  const purpose = findPurpose(purposes, form.purpose);
  const documentMode = settingsQuery.data?.finance.document_mode;
  // One key per payment being entered: a retry or a double press records it once.
  const [idempotencyKey] = useState(() => crypto.randomUUID());
  const [checked, setChecked] = useState(false);
  const [received, setReceived] = useState<ReceivedPayment | null>(null);

  const money = (cents: number, currency = "EUR") =>
    new Intl.NumberFormat(uiLocale, { style: "currency", currency }).format(cents / 100);

  const mutation = useMutation({
    mutationFn: () => receiveFinancePayment(token, userId, receiveBody(form, purpose, idempotencyKey)),
    onSuccess: async ({ received: result }) => {
      setReceived(result);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["admin", "finance"] }),
        queryClient.invalidateQueries({ queryKey: ["admin", "dashboard"] }),
        queryClient.invalidateQueries({ queryKey: ["admin", "analytics"] }),
        queryClient.invalidateQueries({ queryKey: ["admin", "users", userId, "finance"] }),
      ]);
    },
  });

  const update = (patch: Partial<ReceivePaymentForm>) => setDraft({ ...form, ...patch });

  // ADR-214: the reason sits under the field it belongs to; anything else is
  // one notice inside the dialog.
  const missing = checked ? missingFields(form, purpose) : {};
  const errorCode = mutation.error instanceof ApiError ? mutation.error.payload.code : undefined;
  const serverField = mutation.error ? fieldForErrorCode(errorCode) : null;
  const serverMessage = mutation.error ? localizeError(mutation.error, i18n) : null;
  const fieldMessage = (field: ReceivePaymentField) =>
    (missing[field] ? t(missing[field]!) : null) ?? (serverField === field ? serverMessage : null);
  const formMessage = mutation.error && !serverField ? serverMessage : null;

  function submit() {
    setChecked(true);
    if (Object.keys(missingFields(form, purpose)).length > 0) return;
    mutation.mutate();
  }

  if (received) {
    return <ReceivedView received={received} nickname={nickname} money={money} onClose={onClose} />;
  }

  const purposeLabel = (option: PaymentPurpose) => {
    if (option.kind === "invoice") return t("purposeInvoice", { number: option.number, amount: money(option.amountCents) });
    if (option.kind === "package") return t("purposePackage", { name: option.name || t("packageFallback"), amount: money(option.amountCents) });
    return t("purposeOther");
  };
  const next = outcome(documentMode, purpose);

  return (
    <Dialog
      onClose={onClose}
      title={t("title")}
      description={nickname}
      size="md"
      variant="center"
      dismissible={!mutation.isPending}
      testId="receive-payment"
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
      error={formMessage ? <ErrorNotice variant="field">{formMessage}</ErrorNotice> : null}
      footerStart={
        <p className="text-xs leading-5" style={{ color: "var(--dim)" }} data-testid="receive-payment-outcome">
          {next === "settles_invoice" && purpose.kind === "invoice"
            ? t("outcomeSettlesInvoice", { number: purpose.number })
            : next === "receipt"
              ? t("outcomeReceipt")
              : t("outcomeInvoice")}
        </p>
      }
      footer={
        <DialogButton type="submit" tone="primary" disabled={mutation.isPending || profileQuery.isLoading}>
          {mutation.isPending ? t("saving") : t("save")}
        </DialogButton>
      }
    >
      {profileQuery.isLoading ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
      ) : (
        <div className="space-y-4">
          <FormRow label={t("purpose")} errorId={`${ids}-purpose`} error={fieldMessage("purpose")}>
            <Select
              aria-label={t("purpose")}
              className="w-full rounded-xl px-3 py-2.5 text-sm"
              style={{ ...CONTROL, border: fieldBorder(fieldMessage("purpose")) }}
              value={purposeValue(purpose)}
              onValueChange={(value) => setDraft(choosePurpose(form, purposes, value))}
              {...invalidFieldProps(fieldMessage("purpose"), `${ids}-purpose`)}
            >
              {purposes.map((option) => (
                <option key={purposeValue(option)} value={purposeValue(option)}>
                  {purposeLabel(option)}
                </option>
              ))}
            </Select>
          </FormRow>

          {purpose.kind === "other" ? (
            <>
              <FormRow label={t("description")} errorId={`${ids}-description`} error={fieldMessage("description")}>
                <input
                  aria-label={t("description")}
                  className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
                  style={{ ...CONTROL, border: fieldBorder(fieldMessage("description")) }}
                  value={form.description}
                  maxLength={500}
                  onChange={(event) => update({ description: event.target.value })}
                  {...invalidFieldProps(fieldMessage("description"), `${ids}-description`)}
                />
              </FormRow>
              <FormRow label={i18n("admChargeCategory")}>
                <ChargeCategorySelect
                  className="w-full rounded-xl px-3 py-2.5 text-sm"
                  style={{ ...CONTROL, border: "1px solid var(--border)" }}
                  value={form.chargeCategory}
                  onChange={(chargeCategory) => update({ chargeCategory })}
                />
              </FormRow>
            </>
          ) : null}

          <FormRow label={t("amount")} errorId={`${ids}-amount`} error={fieldMessage("amount_cents")}>
            <input
              aria-label={t("amount")}
              className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
              style={{ ...CONTROL, border: fieldBorder(fieldMessage("amount_cents")) }}
              inputMode="decimal"
              value={form.amount}
              onChange={(event) => update({ amount: event.target.value })}
              {...invalidFieldProps(fieldMessage("amount_cents"), `${ids}-amount`)}
            />
          </FormRow>

          <FormRow label={t("method")} errorId={`${ids}-method`} error={fieldMessage("payment_method")}>
            <div role="radiogroup" aria-label={t("method")} className="flex flex-wrap gap-2">
              {PAYMENT_METHODS.map((method) => {
                const on = form.method === method;
                return (
                  <button
                    key={method}
                    type="button"
                    role="radio"
                    aria-checked={on}
                    onClick={() => update({ method })}
                    className="rounded-full px-3.5 py-2 text-sm font-semibold"
                    style={
                      on
                        ? { background: "var(--primary)", color: "var(--primary-contrast)", border: "1px solid var(--primary)" }
                        : { background: "transparent", color: "var(--text-soft)", border: "1px solid var(--border)" }
                    }
                  >
                    {t(`method_${method}`)}
                  </button>
                );
              })}
            </div>
          </FormRow>

          <FormRow label={t("paidOn")} hint={t("paidOnHint")}>
            <DateInput
              aria-label={t("paidOn")}
              className="w-full rounded-xl px-3 py-2.5 text-sm"
              style={{ ...CONTROL, border: "1px solid var(--border)" }}
              value={form.paidOn}
              onValueChange={(paidOn) => update({ paidOn })}
            />
          </FormRow>

          <FormRow label={t("notes")}>
            <input
              aria-label={t("notes")}
              className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
              style={{ ...CONTROL, border: "1px solid var(--border)" }}
              value={form.notes}
              onChange={(event) => update({ notes: event.target.value })}
            />
          </FormRow>
        </div>
      )}
    </Dialog>
  );
}

function FormRow({
  label,
  hint,
  error,
  errorId,
  children,
}: {
  label: string;
  hint?: string;
  error?: string | null;
  errorId?: string;
  children: ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <p className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{label}</p>
      {children}
      {hint && !error ? <p className="text-xs" style={{ color: "var(--dim)" }}>{hint}</p> : null}
      {errorId ? <FieldError id={errorId}>{error}</FieldError> : null}
    </div>
  );
}

function ReceivedView({
  received,
  nickname,
  money,
  onClose,
}: {
  received: ReceivedPayment;
  nickname: string;
  money: (cents: number, currency?: string) => string;
  onClose: () => void;
}) {
  const t = useTranslations("ReceivePayment");
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const fileRef = useRef<HTMLInputElement>(null);
  const [attach, setAttach] = useState<"idle" | "uploading" | "done" | "failed">("idle");
  const method = String(received.payment.payment_method ?? "other");
  const balance = Number(received.invoice.balance_due_cents ?? 0);

  async function downloadReceipt() {
    await downloadExportDocument(
      receiptDocument(
        received,
        uiLocale,
        {
          receipt: i18n("featureReceipt"),
          documentTitle: i18n("featureReceiptDocumentTitle", { reference: received.reference }),
          paymentReceived: i18n("featurePaymentReceived"),
          reference: i18n("featureReference"),
          date: i18n("featureDate"),
          amountReceived: i18n("featureAmountReceived"),
          package: i18n("package7431e3d"),
          payment: i18n("featurePayment"),
          purpose: i18n("featurePurpose"),
          method: i18n("featureMethod"),
          status: i18n("featureStatus"),
          paid: i18n("featurePaid"),
          footer: i18n("featureReceiptFooter"),
        },
        t(`method_${method}`),
      ),
    );
  }

  async function attachInvoice(file: File) {
    setAttach("uploading");
    try {
      const { upload_url, content_type } = await getInvoiceUploadUrl(
        token,
        String(received.invoice.id),
        file.name,
        file.type || "application/octet-stream",
      );
      const response = await fetch(upload_url, { method: "PUT", headers: { "Content-Type": content_type }, body: file });
      setAttach(response.ok ? "done" : "failed");
    } catch {
      setAttach("failed");
    } finally {
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  const isReceipt = received.document_type === "receipt";

  return (
    <Dialog
      onClose={onClose}
      title={t("doneTitle", { amount: money(received.amount_cents, received.currency) })}
      description={nickname}
      size="md"
      variant="center"
      testId="receive-payment-done"
      footer={
        <DialogButton tone="primary" onClick={onClose}>
          {t("done")}
        </DialogButton>
      }
    >
      <div className="space-y-4">
        {received.replayed ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("alreadyRecorded")}</p>
        ) : null}
        <div className="rounded-2xl p-4 space-y-1" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {isReceipt ? t("doneReceipt", { reference: received.reference }) : t("doneInvoice", { reference: received.reference })}
          </p>
          <p className="text-xs" style={{ color: balance > 0 ? "var(--danger)" : "var(--success)" }}>
            {balance > 0 ? t("stillDue", { amount: money(balance) }) : t("settled")}
          </p>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t(`method_${method}`)}</p>
        </div>
        {isReceipt ? (
          <DialogButton onClick={() => void downloadReceipt()}>{t("downloadReceipt")}</DialogButton>
        ) : (
          <div className="space-y-2">
            <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t("attachHint")}</p>
            <input
              ref={fileRef}
              type="file"
              accept="image/*,.pdf"
              className="sr-only"
              aria-hidden="true"
              tabIndex={-1}
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (file) void attachInvoice(file);
              }}
            />
            <DialogButton disabled={attach === "uploading"} onClick={() => fileRef.current?.click()}>
              {attach === "uploading" ? t("attaching") : attach === "done" ? t("attached") : t("attachInvoice")}
            </DialogButton>
            {attach === "failed" ? <ErrorNotice variant="field">{t("attachFailed")}</ErrorNotice> : null}
          </div>
        )}
      </div>
    </Dialog>
  );
}
