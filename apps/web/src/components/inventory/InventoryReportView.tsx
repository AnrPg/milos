"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchInventoryReport } from "@/api/inventory";
import { barPercent, formatMoney } from "@/components/inventory/inventory-helpers";
import { subtleText } from "@/components/inventory/inventory-ui";
import { captionClass, captionStyle, inputStyle, StaffPanel, StatusText } from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

const MONTH_OPTIONS = [3, 6, 12, 24];

function monthLabel(month: string, locale: string) {
  const date = new Date(`${month.slice(0, 7)}-01T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return month;
  return new Intl.DateTimeFormat(locale, { month: "short", year: "2-digit", timeZone: "UTC" }).format(date);
}

/** Managers' spend report: monthly expenses and per-item consumption (ADR-104). */
export function InventoryReportView({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const [months, setMonths] = useState(12);
  const report = useQuery({
    queryKey: ["staff", "inventory", "report", months],
    queryFn: () => fetchInventoryReport(token, months),
  });
  const money = (cents: number | null | undefined) => formatMoney(cents, locale);
  const number = (value: number) => new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(value);

  const data = report.data;
  const max = Math.max(0, ...(data?.expenses ?? []).map((row) => row.total_cents));
  const items = [...(data?.supplies ?? [])].sort((a, b) => b.spent_cents - a.spent_cents);

  return (
    <div className="flex flex-col gap-4">
      <label className="flex items-center gap-2 self-start">
        <span className={captionClass} style={captionStyle}>
          {i18n("invPeriod")}
        </span>
        <select className="rounded-xl px-3 py-1.5 text-sm" style={inputStyle} value={months} onChange={(event) => setMonths(Number(event.target.value))}>
          {MONTH_OPTIONS.map((option) => (
            <option key={option} value={option}>
              {i18n("invLastMonths", { count: option })}
            </option>
          ))}
        </select>
      </label>

      {report.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : report.isError || !data ? (
        <StatusText tone="error">{localizeError(report.error, i18n)}</StatusText>
      ) : (
        <>
          <StaffPanel labelledBy="inv-report-expenses" title={i18n("invMonthlyExpenses")}>
            <div className="mb-4 flex flex-wrap gap-x-6 gap-y-2 text-sm">
              <Legend color="var(--primary)" label={i18n("invSupplies")} value={money(data.totals.supplies_cents)} />
              <Legend color="var(--warning)" label={i18n("invMachines")} value={money(data.totals.machines_cents)} />
              <span style={{ color: "var(--text)" }}>
                <strong>{i18n("invTotal")}</strong> {money(data.totals.supplies_cents + data.totals.machines_cents)}
              </span>
            </div>
            {data.expenses.length === 0 ? (
              <StatusText tone="muted">{i18n("invNoExpenses")}</StatusText>
            ) : (
              <ul className="flex flex-col gap-2">
                {data.expenses.map((row) => (
                  <li key={row.month} className="grid grid-cols-[3.5rem_1fr_auto] items-center gap-2 text-xs">
                    <span style={subtleText}>{monthLabel(row.month, locale)}</span>
                    <span
                      className="flex h-3 overflow-hidden rounded-full"
                      style={{ background: "var(--panel-muted)" }}
                      title={`${i18n("invSupplies")}: ${money(row.supplies_cents)} · ${i18n("invMachines")}: ${money(row.machines_cents)}`}
                    >
                      <span style={{ width: `${barPercent(row.supplies_cents, max)}%`, background: "var(--primary)" }} />
                      <span style={{ width: `${barPercent(row.machines_cents, max)}%`, background: "var(--warning)" }} />
                    </span>
                    <span className="text-end tabular-nums" style={{ color: "var(--text-soft)" }}>
                      {money(row.total_cents)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </StaffPanel>

          <StaffPanel labelledBy="inv-report-items" title={i18n("invPerItem")}>
            {items.length === 0 ? (
              <StatusText tone="muted">{i18n("invNoSupplies")}</StatusText>
            ) : (
              <div className="-mx-2 overflow-x-auto">
                <table className="w-full min-w-[22rem] text-sm">
                  <thead>
                    <tr className="text-start text-[11px] uppercase tracking-[0.12em]" style={subtleText}>
                      <th className="px-2 py-1 text-start font-semibold">{i18n("invItem")}</th>
                      <th className="px-2 py-1 text-end font-semibold">{i18n("invUsedPerMonth")}</th>
                      <th className="px-2 py-1 text-end font-semibold">{i18n("invSpendPerMonth")}</th>
                      <th className="px-2 py-1 text-end font-semibold">{i18n("invTotalSpend")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {items.map((item) => (
                      <tr key={item.supply_id} className="border-t" style={{ borderColor: "var(--border)", color: "var(--text-soft)" }}>
                        <td className="px-2 py-2" style={{ color: "var(--text)" }}>
                          {item.name}
                        </td>
                        <td className="px-2 py-2 text-end tabular-nums">
                          {number(item.consumed_per_month)}
                          {item.unit ? ` ${item.unit}` : ""}
                        </td>
                        <td className="px-2 py-2 text-end tabular-nums">{money(item.spent_per_month_cents ?? null)}</td>
                        <td className="px-2 py-2 text-end tabular-nums">{money(item.spent_cents)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </StaffPanel>
        </>
      )}
    </div>
  );
}

function Legend({ color, label, value }: { color: string; label: string; value: string }) {
  return (
    <span className="flex items-center gap-2" style={{ color: "var(--text-soft)" }}>
      <span aria-hidden className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: color }} />
      {label} <strong style={{ color: "var(--text)" }}>{value}</strong>
    </span>
  );
}
