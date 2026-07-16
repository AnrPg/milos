"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchFinanceQueues, type FinanceRecord } from "@/api/finance";
import { useSession } from "@/components/session-provider";

type QueueKey = "expiring" | "pending" | "overdue" | "rewards" | "promos";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

function dateText(value: unknown) {
  if (!value) return "—";
  return String(value).slice(0, 10);
}

export function QueuesTab() {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const CHIPS: Array<{ id: QueueKey; label: string }> = [
    { id: "expiring", label: i18n("expiringb98d672") },
    { id: "pending", label: i18n("pendingPayments9126c11") },
    { id: "overdue", label: i18n("overdueInvoices739b616") },
    { id: "rewards", label: i18n("pendingRewardse6d6885") },
    { id: "promos", label: i18n("promoRedemptions2388269") },
  ];
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [active, setActive] = useState<QueueKey>("expiring");

  const queuesQuery = useQuery({
    queryKey: ["admin", "finance", "queues"],
    enabled: Boolean(token),
    queryFn: () => fetchFinanceQueues(token!, { expires_within_days: "30" }),
  });

  const queues = (queuesQuery.data?.queues ?? {}) as Record<string, FinanceRecord[]>;

  const rowsByKey: Record<QueueKey, FinanceRecord[]> = {
    expiring: queues.expiring_memberships ?? [],
    pending: queues.pending_payments ?? [],
    overdue: queues.overdue_invoices ?? [],
    rewards: queues.pending_referral_rewards ?? [],
    promos: queues.promotion_redemptions ?? [],
  };

  const rows = rowsByKey[active];

  return (
    <div className="space-y-6">
      {/* Filter chips */}
      <div className="flex flex-wrap gap-2">
        {CHIPS.map(({ id, label }) => (
          <button
            key={id}
            className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
            style={
              active === id
                ? { background: "var(--text)", color: "var(--bg)" }
                : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--dim)" }
            }
            onClick={() => setActive(id)}
            type="button"
          >
            {label}
            {rowsByKey[id].length > 0 && (
              <span
                className="ms-2 rounded-full px-2 py-0.5 text-xs"
                style={{
                  background: active === id ? "color-mix(in srgb, var(--bg) 15%, transparent)" : "color-mix(in srgb, var(--primary) 15%, transparent)",
                  color: active === id ? "var(--bg)" : "var(--primary)",
                }}
              >
                {rowsByKey[id].length}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Queue list */}
      <div className="rounded-[2rem] overflow-hidden" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {queuesQuery.isLoading ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{i18n("loadingQueuea1e2a39")}</p>
        ) : rows.length === 0 ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{i18n("noItemsInThisQueuec992fc9")}</p>
        ) : (
          <div>
            {active === "expiring" && rows.map((row, i) => (
              <QueueRow key={field(row, "id", String(i))} last={i === rows.length - 1}>
                <span style={{ color: "var(--text)" }}>{field(row, "nickname", field(row, "user_id"))}</span>
                <span style={{ color: "var(--muted)" }}>{i18n("expiresa99be3d")} {dateText(row.expires_on)}</span>
              </QueueRow>
            ))}

            {active === "pending" && rows.map((row, i) => (
              <QueueRow key={field(row, "id", String(i))} last={i === rows.length - 1}>
                <span style={{ color: "var(--text)" }}>{field(row, "nickname", field(row, "membership_id"))}</span>
                <span style={{ color: "var(--muted)" }}>{money(uiLocale, row.amount_cents)}</span>
              </QueueRow>
            ))}

            {active === "overdue" && rows.map((row, i) => (
              <QueueRow key={field(row, "id", String(i))} last={i === rows.length - 1}>
                <span style={{ color: "var(--text)" }}>{field(row, "invoice_number")}</span>
                <span style={{ color: "var(--primary-strong)" }}>{money(uiLocale, row.balance_due_cents)} {i18n("overdueba2fff4")}</span>
              </QueueRow>
            ))}

            {active === "rewards" && rows.map((row, i) => (
              <QueueRow key={field(row, "id", String(i))} last={i === rows.length - 1}>
                <span style={{ color: "var(--text)" }}>{field(row, "nickname", field(row, "recipient_user_id"))}</span>
                <span style={{ color: "var(--muted)" }}>{field(row, "reward_type")} · {field(row, "reward_value")}</span>
              </QueueRow>
            ))}

            {active === "promos" && rows.map((row, i) => (
              <QueueRow key={field(row, "id", String(i))} last={i === rows.length - 1}>
                <span style={{ color: "var(--text)" }}>{field(row, "membership_id")}</span>
                <span style={{ color: "var(--muted)" }}>{i18n("discountb524936")} {field(row, "discount_value_snapshot")}</span>
              </QueueRow>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function QueueRow({ children, last }: { children: React.ReactNode; last: boolean }) {
  
  return (
    <div
      className="flex items-center justify-between gap-4 px-6 py-4 text-sm"
      style={{ borderBottom: last ? "none" : "1px solid var(--border)" }}
    >
      {children}
    </div>
  );
}
