"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";

import {
  fetchAccountingExportDownload,
  fetchReconciliationCandidates,
  fetchRefundReceiptDocument,
  listAccountingExports,
  listReconciliationRecords,
  listRefundReceipts,
  matchReconciliationRecord,
  recordReconciliationLine,
  requestAccountingExport,
  unmatchReconciliationRecord,
  type ReconciliationRecord,
} from "@/api/finance-accounting";
import { RefundReceiptDocumentDialog } from "@/components/finance/RefundReceiptDocumentDialog";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";
import {
  accountingErrorKey,
  buildReconciliationLine,
  discrepancyMessageKey,
  exportRunsInBackground,
  formatMinorUnits,
  shiftIsoDate,
  todayIso,
  validateExportRange,
  type ReconciliationForm,
} from "@/lib/finance-accounting";
import { Select } from "@/components/ui/Select";
import { DateInput } from "@/components/ui/DateInput";

// ADR-126: refund receipts, manual provider reconciliation and accounting exports.

const panelStyle = { background: "var(--panel)", border: "1px solid var(--border)" };
const inputClass = "w-full rounded-xl px-3 py-2 text-sm";
const inputStyle = { background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" };
const primaryButton = { background: "var(--text)", color: "var(--bg)" };
const secondaryButton = { background: "var(--border)", color: "var(--text-soft)" };

function Section({ title, intro, children }: { title: string; intro: string; children: ReactNode }) {
  return (
    <section className="space-y-4 rounded-[2rem] p-6" style={panelStyle}>
      <div>
        <h2 className="text-xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{title}</h2>
        <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{intro}</p>
      </div>
      {children}
    </section>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
      {label}
      {children}
    </label>
  );
}

function Notice({ tone, children }: { tone: "error" | "info"; children: ReactNode }) {
  return (
    <p className="text-sm" role={tone === "error" ? "alert" : "status"} style={{ color: tone === "error" ? "var(--danger)" : "var(--success)" }}>
      {children}
    </p>
  );
}

export function AccountingTab() {
  return (
    <div className="space-y-6">
      <RefundReceiptsSection />
      <ReconciliationSection />
      <ExportsSection />
    </div>
  );
}

function RefundReceiptsSection() {
  const t = useTranslations("FinanceAccounting");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [search, setSearch] = useState("");
  const [document, setDocument] = useState<{ html: string; number: string } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const receiptsQuery = useQuery({
    queryKey: ["admin", "finance", "refund-receipts", search],
    enabled: Boolean(token),
    queryFn: () => listRefundReceipts(token!, { q: search.trim() || undefined }),
  });

  const openDocument = async (id: string, number: string) => {
    setError(null);
    try {
      const html = await fetchRefundReceiptDocument(token!, id, locale);
      setDocument({ html, number });
    } catch (cause) {
      setError(t(accountingErrorKey(cause)));
    }
  };

  const receipts = receiptsQuery.data?.refund_receipts ?? [];

  return (
    <Section intro={t("receiptsIntro")} title={t("receiptsTitle")}>
      <input
        aria-label={t("searchReceipts")}
        className={inputClass}
        onChange={(event) => setSearch(event.target.value)}
        placeholder={t("searchReceipts")}
        style={inputStyle}
        value={search}
      />
      {error ? <Notice tone="error">{error}</Notice> : null}
      {receiptsQuery.isLoading ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : receipts.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noReceipts")}</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ color: "var(--dim)" }}>
                <th className="py-2 text-start">{t("receiptNumber")}</th>
                <th className="py-2 text-start">{t("issuedAt")}</th>
                <th className="py-2 text-start">{t("member")}</th>
                <th className="py-2 text-start">{t("invoice")}</th>
                <th className="py-2 text-end">{t("amount")}</th>
                <th className="py-2" />
              </tr>
            </thead>
            <tbody>
              {receipts.map((receipt) => (
                <tr key={receipt.id} style={{ borderTop: "1px solid var(--border)", color: "var(--text)" }}>
                  <td className="py-2 font-semibold">
                    {receipt.receipt_number}
                    {receipt.integrity_verified ? null : (
                      <span className="ms-2 text-xs" style={{ color: "var(--danger)" }}>{t("integrityFailed")}</span>
                    )}
                  </td>
                  <td className="py-2">{receipt.issued_at.slice(0, 10)}</td>
                  <td className="py-2">{receipt.member_display_name ?? receipt.user_id}</td>
                  <td className="py-2">{receipt.invoice_number ?? "—"}</td>
                  <td className="py-2 text-end">{formatMinorUnits(locale, receipt.amount_cents, receipt.currency)}</td>
                  <td className="py-2 text-end">
                    <button
                      className="rounded-full px-3 py-1 text-xs font-semibold"
                      onClick={() => void openDocument(receipt.id, receipt.receipt_number)}
                      style={secondaryButton}
                      type="button"
                    >
                      {t("viewDocument")}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {document ? (
        <RefundReceiptDocumentDialog
          html={document.html}
          onClose={() => setDocument(null)}
          receiptNumber={document.number}
        />
      ) : null}
    </Section>
  );
}

const emptyLine = (): ReconciliationForm => ({
  provider: "",
  externalReference: "",
  externalType: "payment",
  externalStatus: "settled",
  amount: "",
  currency: "EUR",
  occurredOn: todayIso(),
  description: "",
});

function ReconciliationSection() {
  const t = useTranslations("FinanceAccounting");
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [form, setForm] = useState<ReconciliationForm>(emptyLine);
  const [status, setStatus] = useState<"" | "unmatched" | "matched" | "mismatched">("");
  const [selected, setSelected] = useState<ReconciliationRecord | null>(null);
  const [notice, setNotice] = useState<{ tone: "error" | "info"; text: string } | null>(null);

  const recordsQuery = useQuery({
    queryKey: ["admin", "finance", "reconciliation", status],
    enabled: Boolean(token),
    queryFn: () => listReconciliationRecords(token!, status || undefined),
  });

  const candidatesQuery = useQuery({
    queryKey: ["admin", "finance", "reconciliation-candidates", selected?.id],
    enabled: Boolean(token && selected),
    queryFn: () => fetchReconciliationCandidates(token!, selected!.id),
  });

  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: ["admin", "finance", "reconciliation"] });
    void queryClient.invalidateQueries({ queryKey: ["admin", "finance", "reconciliation-candidates"] });
  };

  const recordMutation = useMutation({
    mutationFn: (body: Parameters<typeof recordReconciliationLine>[1]) => recordReconciliationLine(token!, body),
    onSuccess: (response) => {
      setNotice({ tone: "info", text: response.idempotent_replay ? t("lineReplayed") : t("lineRecorded") });
      setForm(emptyLine());
      refresh();
    },
    onError: (cause) => setNotice({ tone: "error", text: t(accountingErrorKey(cause)) }),
  });

  const matchMutation = useMutation({
    mutationFn: (input: { id: string; target_type: "payment" | "reversal"; target_id: string } | { id: string; unmatch: true }) =>
      "unmatch" in input
        ? unmatchReconciliationRecord(token!, input.id)
        : matchReconciliationRecord(token!, input.id, { target_type: input.target_type, target_id: input.target_id }),
    onSuccess: (response) => {
      setSelected(response.reconciliation_record);
      setNotice(null);
      refresh();
    },
    onError: (cause) => setNotice({ tone: "error", text: t(accountingErrorKey(cause)) }),
  });

  const submit = () => {
    const result = buildReconciliationLine(form);
    if (!result.ok) {
      const keys = { required: "errorRequired", amount: "errorAmountInvalid", provider: "errorProviderInvalid", currency: "errorCurrencyInvalid" } as const;
      setNotice({ tone: "error", text: t(keys[result.error]) });
      return;
    }
    recordMutation.mutate(result.body);
  };

  const statusLabel = (value: string) =>
    value === "matched" ? t("statusMatched") : value === "mismatched" ? t("statusMismatched") : t("statusUnmatched");

  const records = recordsQuery.data?.reconciliation_records ?? [];
  const update = (patch: Partial<ReconciliationForm>) => setForm((current) => ({ ...current, ...patch }));

  return (
    <Section intro={t("reconciliationIntro")} title={t("reconciliationTitle")}>
      <div className="grid gap-3 md:grid-cols-4">
        <Field label={t("provider")}>
          <input className={inputClass} onChange={(e) => update({ provider: e.target.value })} style={inputStyle} value={form.provider} />
        </Field>
        <Field label={t("externalReference")}>
          <input className={inputClass} onChange={(e) => update({ externalReference: e.target.value })} style={inputStyle} value={form.externalReference} />
        </Field>
        <Field label={t("externalType")}>
          <Select className={inputClass} onValueChange={(value) => update({ externalType: value as ReconciliationForm["externalType"] })} style={inputStyle} value={form.externalType}>
            <option value="payment">{t("typePayment")}</option>
            <option value="refund">{t("typeRefund")}</option>
          </Select>
        </Field>
        <Field label={t("externalStatus")}>
          <Select className={inputClass} onValueChange={(value) => update({ externalStatus: value as ReconciliationForm["externalStatus"] })} style={inputStyle} value={form.externalStatus}>
            <option value="settled">{t("statusSettled")}</option>
            <option value="pending">{t("statusPending")}</option>
            <option value="failed">{t("statusFailed")}</option>
          </Select>
        </Field>
        <Field label={t("statementAmount")}>
          <input className={inputClass} inputMode="decimal" onChange={(e) => update({ amount: e.target.value })} style={inputStyle} value={form.amount} />
        </Field>
        <Field label={t("currency")}>
          <input className={inputClass} maxLength={3} onChange={(e) => update({ currency: e.target.value })} style={inputStyle} value={form.currency} />
        </Field>
        <Field label={t("statementDate")}>
          <DateInput className={inputClass} onValueChange={(value) => update({ occurredOn: value })} style={inputStyle} value={form.occurredOn} />
        </Field>
        <Field label={t("description")}>
          <input className={inputClass} onChange={(e) => update({ description: e.target.value })} style={inputStyle} value={form.description} />
        </Field>
      </div>
      <button className="rounded-full px-5 py-2 text-sm font-semibold" disabled={recordMutation.isPending} onClick={submit} style={primaryButton} type="button">
        {recordMutation.isPending ? t("recording") : t("recordLine")}
      </button>
      {notice ? <Notice tone={notice.tone}>{notice.text}</Notice> : null}

      <div className="flex flex-wrap gap-2">
        {(["", "unmatched", "mismatched", "matched"] as const).map((value) => (
          <button
            className="rounded-full px-4 py-1.5 text-xs font-semibold"
            key={value || "all"}
            onClick={() => setStatus(value)}
            style={status === value ? primaryButton : secondaryButton}
            type="button"
          >
            {value ? statusLabel(value) : t("filterAll")}
          </button>
        ))}
      </div>

      {records.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{recordsQuery.isLoading ? t("loading") : t("noRecords")}</p>
      ) : (
        <ul className="space-y-2">
          {records.map((record) => (
            <li className="rounded-2xl p-3 text-sm" key={record.id} style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="font-semibold">
                  {record.provider} · {record.external_reference}
                </span>
                <span>
                  {record.external_type === "refund" ? t("typeRefund") : t("typePayment")} ·{" "}
                  {formatMinorUnits(locale, record.statement_amount_cents, record.statement_currency)} · {record.statement_occurred_on}
                </span>
                <span style={{ color: record.status === "mismatched" ? "var(--danger)" : record.status === "matched" ? "var(--success)" : "var(--dim)" }}>
                  {statusLabel(record.status)}
                </span>
                <div className="flex gap-2">
                  {record.status === "unmatched" ? (
                    <button className="rounded-full px-3 py-1 text-xs font-semibold" onClick={() => setSelected(record)} style={secondaryButton} type="button">
                      {t("findMatches")}
                    </button>
                  ) : (
                    <button
                      className="rounded-full px-3 py-1 text-xs font-semibold"
                      disabled={matchMutation.isPending}
                      onClick={() => matchMutation.mutate({ id: record.id, unmatch: true })}
                      style={secondaryButton}
                      type="button"
                    >
                      {t("unmatch")}
                    </button>
                  )}
                </div>
              </div>
              {record.discrepancies.length > 0 ? (
                <p className="mt-1 text-xs" style={{ color: "var(--danger)" }}>
                  {record.discrepancies.map((code) => t(discrepancyMessageKey(code))).join(" · ")}
                </p>
              ) : null}
            </li>
          ))}
        </ul>
      )}

      {selected && selected.status === "unmatched" ? (
        <div className="space-y-2 rounded-2xl p-4" style={{ border: "1px solid var(--border-strong)" }}>
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold" style={{ color: "var(--text)" }}>
              {t("candidatesTitle")} · {selected.external_reference}
            </h3>
            <button className="text-xs font-semibold" onClick={() => setSelected(null)} style={{ color: "var(--dim)" }} type="button">
              {t("close")}
            </button>
          </div>
          {candidatesQuery.isLoading ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
          ) : (candidatesQuery.data?.candidates ?? []).length === 0 ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noCandidates")}</p>
          ) : (
            (candidatesQuery.data?.candidates ?? []).map((candidate) => (
              <div className="flex flex-wrap items-center justify-between gap-2 text-sm" key={candidate.target_id} style={{ color: "var(--text)" }}>
                <span>
                  {candidate.member_name ?? candidate.member_user_id ?? "—"} · {candidate.occurred_on} ·{" "}
                  {formatMinorUnits(locale, candidate.amount_cents, candidate.currency)}
                  {candidate.invoice_number ? ` · ${candidate.invoice_number}` : ""}
                </span>
                <span className="text-xs" style={{ color: candidate.evaluation.status === "matched" ? "var(--success)" : "var(--danger)" }}>
                  {candidate.evaluation.status === "matched"
                    ? t("exactMatch")
                    : candidate.evaluation.discrepancies.map((code) => t(discrepancyMessageKey(code))).join(" · ")}
                </span>
                <button
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  disabled={matchMutation.isPending}
                  onClick={() => matchMutation.mutate({ id: selected.id, target_type: candidate.target_type, target_id: candidate.target_id })}
                  style={primaryButton}
                  type="button"
                >
                  {t("match")}
                </button>
              </div>
            ))
          )}
        </div>
      ) : null}
    </Section>
  );
}

function ExportsSection() {
  const t = useTranslations("FinanceAccounting");
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const today = todayIso();
  const [rangeStart, setRangeStart] = useState(shiftIsoDate(today, -30));
  const [rangeEnd, setRangeEnd] = useState(today);
  const [notice, setNotice] = useState<{ tone: "error" | "info"; text: string } | null>(null);

  const exportsQuery = useQuery({
    queryKey: ["admin", "finance", "accounting-exports"],
    enabled: Boolean(token),
    queryFn: () => listAccountingExports(token!),
  });

  const exportMutation = useMutation({
    mutationFn: () => requestAccountingExport(token!, { range_start: rangeStart, range_end: rangeEnd }),
    onSuccess: (response) => {
      setNotice({ tone: "info", text: response.accounting_export.status === "completed" ? t("exportReady") : t("exportQueued") });
      void queryClient.invalidateQueries({ queryKey: ["admin", "finance", "accounting-exports"] });
    },
    onError: (cause) => setNotice({ tone: "error", text: t(accountingErrorKey(cause)) }),
  });

  const submit = () => {
    const check = validateExportRange(rangeStart, rangeEnd, today);
    if (check !== "ok") {
      setNotice({ tone: "error", text: t(check === "too_long" ? "errorRangeTooLong" : "errorRangeInvalid") });
      return;
    }
    exportMutation.mutate();
  };

  const download = async (id: string) => {
    try {
      const link = await fetchAccountingExportDownload(token!, id);
      window.location.assign(link.download_url);
    } catch (cause) {
      setNotice({ tone: "error", text: t(accountingErrorKey(cause)) });
    }
  };

  const statusLabel: Record<string, string> = {
    queued: t("exportStatusQueued"),
    running: t("exportStatusRunning"),
    completed: t("exportStatusCompleted"),
    failed: t("exportStatusFailed"),
  };

  const runs = exportsQuery.data?.accounting_exports ?? [];

  return (
    <Section intro={t("exportsIntro")} title={t("exportsTitle")}>
      <div className="flex flex-wrap items-end gap-3">
        <Field label={t("rangeStart")}>
          <DateInput className={inputClass} max={today} onValueChange={(value) => setRangeStart(value)} style={inputStyle} value={rangeStart} />
        </Field>
        <Field label={t("rangeEnd")}>
          <DateInput className={inputClass} onValueChange={(value) => setRangeEnd(value)} style={inputStyle} value={rangeEnd} />
        </Field>
        <button className="rounded-full px-5 py-2 text-sm font-semibold" disabled={exportMutation.isPending} onClick={submit} style={primaryButton} type="button">
          {exportMutation.isPending ? t("exporting") : t("requestExport")}
        </button>
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          onClick={() => void queryClient.invalidateQueries({ queryKey: ["admin", "finance", "accounting-exports"] })}
          style={secondaryButton}
          type="button"
        >
          {t("refresh")}
        </button>
      </div>
      {exportRunsInBackground(rangeStart, rangeEnd) ? (
        <p className="text-xs" style={{ color: "var(--muted)" }}>{t("backgroundHint")}</p>
      ) : null}
      {notice ? <Notice tone={notice.tone}>{notice.text}</Notice> : null}

      <h3 className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("history")}</h3>
      {runs.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{exportsQuery.isLoading ? t("loading") : t("noExports")}</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ color: "var(--dim)" }}>
                <th className="py-2 text-start">{t("range")}</th>
                <th className="py-2 text-start">{t("requestedAt")}</th>
                <th className="py-2 text-start">{t("status")}</th>
                <th className="py-2 text-start">{t("checksum")}</th>
                <th className="py-2" />
              </tr>
            </thead>
            <tbody>
              {runs.map((run) => (
                <tr key={run.id} style={{ borderTop: "1px solid var(--border)", color: "var(--text)" }}>
                  <td className="py-2">
                    {run.range_start} → {run.range_end}
                  </td>
                  <td className="py-2">{run.inserted_at?.slice(0, 16).replace("T", " ")}</td>
                  <td className="py-2">{statusLabel[run.status] ?? run.status}</td>
                  <td className="py-2 font-mono text-xs">{run.sha256 ? `${run.sha256.slice(0, 12)}…` : "—"}</td>
                  <td className="py-2 text-end">
                    {run.status === "completed" ? (
                      <button className="rounded-full px-3 py-1 text-xs font-semibold" onClick={() => void download(run.id)} style={secondaryButton} type="button">
                        {t("download")}
                      </button>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Section>
  );
}
