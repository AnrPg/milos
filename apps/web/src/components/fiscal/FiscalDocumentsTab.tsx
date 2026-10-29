"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useMemo, useState } from "react";

import { listClosings, listFiscalDocuments, type FiscalDocument } from "@/api/fiscal";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { AccountingExportDialog } from "./AccountingExportDialog";
import { AuditArchiveDialog } from "./AuditArchiveDialog";
import { DocumentPanel } from "./DocumentPanel";
import { FISCAL_DOCUMENTS_KEY, paymentKey, TransmissionPill } from "./document-bits";
import { buyerName, groupByDay, localToday, matchesFilter, monthRange, transmissionState, utcDay, type KindFilter } from "./documents-model";
import { Card, Chip, formatMoney, hintStyle, Icon, linkButtonClass, linkButtonStyle, Pill } from "./fiscal-ui";

export { FISCAL_DOCUMENTS_KEY };

const PAGE = 200;
const MONTHS = 12;

/** Finance › «Παραστατικά» (mockup s2, option A grouped per day; ADR-241–245). */
export function FiscalDocumentsTab() {
  const t = useTranslations("FiscalDocuments");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const today = localToday();
  const [filter, setFilter] = useState<KindFilter>("all");
  const [number, setNumber] = useState("");
  const [monthOffset, setMonthOffset] = useState(0);
  const [pages, setPages] = useState(1);
  const [openId, setOpenId] = useState<string | null>(null);
  const [dialog, setDialog] = useState<"audit" | "export" | null>(null);
  const range = monthRange(today, monthOffset);
  const kind = filter === "all" || filter === "pending" ? undefined : filter;
  const search = number.trim();

  const documents = useQuery({
    queryKey: [...FISCAL_DOCUMENTS_KEY, range.from, kind ?? "all", search, pages],
    enabled: Boolean(token),
    placeholderData: keepPreviousData,
    queryFn: () => listFiscalDocuments(token, { from: range.from, to: range.to, kind, number: search || undefined, limit: PAGE * pages }),
  });
  const closings = useQuery({
    queryKey: ["admin", "fiscal", "closings", "day", range.from],
    enabled: Boolean(token),
    queryFn: () => listClosings(token, { kind: "day", from: range.from, to: range.to, limit: 62 }),
  });

  const loaded = documents.data?.documents ?? [];
  const pendingCount = loaded.filter((document) => transmissionState(document.transmission) === "pending").length;
  const shown = loaded.filter((document) => matchesFilter(document, filter));
  const days = useMemo(() => groupByDay(shown, closings.data?.closings ?? []), [shown, closings.data]);
  const months = useMemo(
    () =>
      Array.from({ length: MONTHS }, (_, index) => {
        const { from } = monthRange(today, -index);
        const label = new Intl.DateTimeFormat(locale, { month: "long", year: "numeric", timeZone: "UTC" }).format(utcDay(from));
        return { value: String(-index), label: label.charAt(0).toLocaleUpperCase(locale) + label.slice(1) };
      }),
    [today, locale],
  );

  const filters: Array<[KindFilter, string]> = [
    ["all", t("filter.all")],
    ["receipt", t("filter.receipts")],
    ["invoice", t("filter.invoices")],
    ["credit_note", t("filter.creditNotes")],
    ...(pendingCount > 0 || filter === "pending" ? [["pending", t("filter.pending", { count: pendingCount })] as [KindFilter, string]] : []),
  ];

  return (
    <div className="grid gap-3" data-testid="fiscal-documents">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex flex-wrap gap-1.5" role="group" aria-label={t("filter.label")}>
          {filters.map(([value, label]) => (
            <Chip key={value} on={filter === value} onClick={() => setFilter(value)} testId={`fiscal-filter-${value}`}>
              {label}
            </Chip>
          ))}
        </div>
        <span className="hidden flex-1 sm:block" />
        <label className="flex min-h-9 min-w-0 flex-1 items-center gap-1.5 rounded-xl px-3 text-sm sm:max-w-56 sm:flex-none" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--placeholder)" }}>
          <Icon name="search" size={15} />
          <input
            value={number}
            onChange={(event) => {
              setNumber(event.target.value);
              setPages(1);
            }}
            placeholder={t("searchPlaceholder")}
            aria-label={t("searchPlaceholder")}
            data-testid="fiscal-search"
            className="min-w-0 flex-1 bg-transparent outline-none"
            style={{ color: "var(--text)" }}
          />
        </label>
        <Select
          aria-label={t("month")}
          data-testid="fiscal-month"
          value={String(monthOffset)}
          onValueChange={(value) => {
            setMonthOffset(Number(value));
            setPages(1);
          }}
          className="min-h-9 rounded-xl px-3 text-sm"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {months.map((month) => (
            <option key={month.value} value={month.value}>{month.label}</option>
          ))}
        </Select>
      </div>

      {documents.isError ? <ErrorNotice>{t("loadFailed")}</ErrorNotice> : null}

      <Card>
        {documents.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : days.length === 0 ? (
          <p className="text-sm" style={hintStyle} data-testid="fiscal-empty">{search ? t("noMatch") : t("empty")}</p>
        ) : (
          <div className="grid gap-4">
            {days.map((day) => (
              <section key={day.date} aria-label={dayLabel(t, locale, day.date, today)} data-testid={`fiscal-day-${day.date}`}>
                <header className="flex items-center gap-2 pb-1">
                  <h3 className="min-w-0 flex-1 text-sm font-extrabold" style={{ color: "var(--text)" }}>{dayLabel(t, locale, day.date, today)}</h3>
                  {day.closed ? (
                    <Pill tone="ok" testId="fiscal-day-state"><Icon name="lock" size={11} />{t("dayClosed")}</Pill>
                  ) : (
                    <Pill tone="info" testId="fiscal-day-state">{t("dayOpen")}</Pill>
                  )}
                </header>
                <ul>
                  {day.documents.map((document) => (
                    <DocumentRow key={document.id} document={document} selected={openId === document.id} onOpen={() => setOpenId(document.id)} />
                  ))}
                </ul>
              </section>
            ))}
            {(documents.data?.total ?? 0) > loaded.length ? (
              <button type="button" className={`${linkButtonClass} justify-self-center`} style={linkButtonStyle} onClick={() => setPages((count) => count + 1)} data-testid="fiscal-more">
                {t("more")}
              </button>
            ) : null}
          </div>
        )}
      </Card>

      <div className="flex flex-wrap items-center justify-between gap-2 text-xs" style={hintStyle}>
        <span>{t("numbering")}</span>
        <span className="flex flex-wrap gap-4">
          <button type="button" className={linkButtonClass} style={linkButtonStyle} onClick={() => setDialog("export")} data-testid="fiscal-export-open">
            <Icon name="download" size={13} />
            {t("exportLink")} ›
          </button>
          <button type="button" className={linkButtonClass} style={linkButtonStyle} onClick={() => setDialog("audit")} data-testid="fiscal-audit-open">
            <Icon name="shield" size={13} />
            {t("auditLink")} ›
          </button>
        </span>
      </div>

      {openId && !dialog ? <DocumentPanel token={token} documentId={openId} onOpen={setOpenId} onClose={() => setOpenId(null)} /> : null}
      {dialog === "audit" ? <AuditArchiveDialog token={token} onClose={() => setDialog(null)} /> : null}
      {dialog === "export" ? <AccountingExportDialog token={token} onClose={() => setDialog(null)} /> : null}
    </div>
  );
}

type Translate = ReturnType<typeof useTranslations<"FiscalDocuments">>;

function dayLabel(t: Translate, locale: string, date: string, today: string) {
  const text = new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "numeric", timeZone: "UTC" }).format(utcDay(date));
  const day = text.charAt(0).toLocaleUpperCase(locale) + text.slice(1);
  return date === today ? t("today", { day }) : day;
}

function DocumentRow({ document, selected, onOpen }: { document: FiscalDocument; selected: boolean; onOpen: () => void }) {
  const t = useTranslations("FiscalDocuments");
  const locale = useUiLocale();
  const buyer = buyerName(document);
  const time = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(document.issued_at));
  const credit = document.kind === "credit_note";
  return (
    <li className="border-b last:border-b-0" style={{ borderColor: "var(--border)" }}>
      <button
        type="button"
        onClick={onOpen}
        data-testid={`fiscal-doc-${document.number}`}
        className="grid w-full grid-cols-[28px_minmax(0,1fr)_auto] items-center gap-x-3 gap-y-1 rounded-xl px-2 py-2.5 text-start"
        style={{ background: selected ? "color-mix(in srgb, var(--primary) 7%, transparent)" : "transparent" }}
      >
        <span style={{ color: "var(--primary)" }}><Icon name={credit ? "refresh" : "receipt"} size={22} /></span>
        <span className="min-w-0">
          <span className="block truncate text-sm font-bold" style={{ color: "var(--text)" }}>
            <span className="font-mono">{document.number}</span>
            {buyer ? ` · ${buyer}` : null}
          </span>
          <span className="flex flex-wrap gap-x-2.5 text-xs" style={hintStyle}>
            <span>{t(`kind.${document.kind}`)}</span>
            {document.payment_method ? <span>{t(`payment.${paymentKey(document.payment_method)}`)}</span> : null}
            <span>{time}</span>
          </span>
        </span>
        <span className="flex flex-wrap items-center justify-end gap-1.5">
          <TransmissionPill document={document} />
          <span className="font-mono text-sm font-bold" style={{ color: "var(--text)" }}>
            {formatMoney(locale, credit ? -Math.abs(document.gross_cents) : document.gross_cents, document.currency)}
          </span>
        </span>
      </button>
    </li>
  );
}
