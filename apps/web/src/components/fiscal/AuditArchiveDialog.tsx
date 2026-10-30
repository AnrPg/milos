"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchAuditArchive, listClosings, saveBlob, verifyJournal, type Closing } from "@/api/fiscal";
import { Dialog } from "@/components/ui/Dialog";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { archiveFileName, localToday, utcDay } from "./documents-model";
import { Card, formatMoney, ghostButtonClass, ghostButtonStyle, hintStyle, Icon, KeyValue, Pill, primaryButtonStyle } from "./fiscal-ui";
import { PeriodPicker, periodFor, type Period } from "./PeriodPicker";

type DayTotals = { documents?: number; gross_cents?: number; grand_total_cents?: number };

/** The figures of a closing in its first currency. */
function totalsOf(closing: Closing): { currency: string; totals: DayTotals } | null {
  const [currency, totals] = Object.entries(closing.totals ?? {})[0] ?? [];
  return currency && totals && typeof totals === "object" ? { currency, totals: totals as DayTotals } : null;
}

/** «Αρχείο ελέγχου» (mockup s2 auditDlg; ADR-242): check the signed journal and download it for an auditor. */
export function AuditArchiveDialog({ token, onClose }: { token: string; onClose: () => void }) {
  const t = useTranslations("FiscalDocuments");
  const locale = useUiLocale();
  const today = localToday();
  const [period, setPeriod] = useState<Period>({ choice: "month", ...periodFor("month", today, { from: today, to: today }) });
  const [downloaded, setDownloaded] = useState<string | null>(null);
  const latest = useQuery({
    queryKey: ["admin", "fiscal", "closings", "day", "latest"],
    enabled: Boolean(token),
    queryFn: () => listClosings(token, { kind: "day", limit: 1 }),
  });
  const verify = useMutation({ mutationFn: () => verifyJournal(token) });
  const download = useMutation({
    mutationFn: () => fetchAuditArchive(token, period.from, period.to),
    onSuccess: (blob) => {
      const name = archiveFileName(period.from, period.to);
      saveBlob(blob, name);
      setDownloaded(name);
    },
  });

  const closing = latest.data?.closings[0];
  const figures = closing ? totalsOf(closing) : null;
  const result = verify.data?.verification;
  const dayText = closing
    ? new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "numeric", timeZone: "UTC" }).format(utcDay(closing.period_start))
    : null;

  return (
    <Dialog
      variant="sheet"
      size="lg"
      title={t("auditTitle")}
      onClose={onClose}
      dismissible={!download.isPending}
      testId="fiscal-audit-dialog"
      error={download.isError ? t("archiveFailed") : verify.isError ? t("verifyFailed") : null}
      footer={
        downloaded ? null : (
          <button
            type="button"
            className={ghostButtonClass}
            style={primaryButtonStyle}
            onClick={() => download.mutate()}
            disabled={download.isPending || !period.from || !period.to}
            data-testid="fiscal-audit-download"
          >
            <Icon name="download" size={15} />
            {download.isPending ? t("preparing") : t("downloadZip")}
          </button>
        )
      }
    >
      <div className="grid gap-3 text-sm" style={{ color: "var(--text)" }}>
        <p className="text-xs" style={hintStyle}>{t("auditHint")}</p>

        <Card className="!px-3 !py-3" testId="fiscal-audit-integrity">
          <div className="flex items-center gap-3">
            <span style={{ color: result && !result.valid ? "var(--danger)" : "var(--success)" }}><Icon name="shield" size={22} /></span>
            <div className="min-w-0 flex-1">
              <b>{!result ? t("integrityTitle") : result.valid ? t("intactNow") : t("tampered")}</b>
              <p className="text-xs" style={hintStyle}>
                {!result
                  ? t("checkedNightly")
                  : result.valid
                    ? t("intactDetail", { entries: result.entries })
                    : t("tamperedDetail", { position: result.broken_at ?? 0 })}
              </p>
            </div>
            {!result ? (
              <button type="button" className={`${ghostButtonClass} !min-h-8 !px-3 !text-xs`} style={ghostButtonStyle} onClick={() => verify.mutate()} disabled={verify.isPending} data-testid="fiscal-audit-verify">
                {verify.isPending ? t("checking") : t("checkNow")}
              </button>
            ) : result.valid ? (
              <Pill tone="ok" testId="fiscal-audit-result"><Icon name="check" size={11} />{t("auditOk")}</Pill>
            ) : (
              <Pill tone="bad" testId="fiscal-audit-result">{t("tamperedPill")}</Pill>
            )}
          </div>
        </Card>

        {closing && figures ? (
          <div>
            <KeyValue label={t("lastClosing")}>
              <span className="font-sans">
                {t("lastClosingValue", {
                  day: dayText ?? closing.period_start,
                  count: figures.totals.documents ?? 0,
                  amount: formatMoney(locale, figures.totals.gross_cents ?? 0, figures.currency),
                })}
              </span>
            </KeyValue>
            <KeyValue label={t("grandTotal")}>{formatMoney(locale, figures.totals.grand_total_cents ?? 0, figures.currency)}</KeyValue>
          </div>
        ) : null}

        <PeriodPicker label={t("archiveLabel")} today={today} value={period} onChange={(next) => { setPeriod(next); setDownloaded(null); }} testId="fiscal-audit-period" />
        <p className="text-xs" style={hintStyle}>{t("archiveHint")}</p>

        {downloaded ? (
          <div role="status" className="flex items-center gap-2 rounded-xl px-3 py-2.5 text-xs" style={{ background: "var(--deep)", color: "var(--deep-contrast)" }} data-testid="fiscal-audit-started">
            <Icon name="check" size={16} />
            {t("downloadStarted", { file: downloaded })}
          </div>
        ) : null}
      </div>
    </Dialog>
  );
}
