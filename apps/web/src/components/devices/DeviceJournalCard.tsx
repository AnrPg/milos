"use client";

import { useId, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  DEVICE_PENDING_KEY,
  DEVICE_SUMMARY_KEY,
  fetchDeviceSummary,
  fetchGarminPending,
  markDeviceSummarySeen,
  type DeviceActivity,
} from "@/api/devices";
import { fetchJournalPage, JOURNAL_FEED_KEY, type TypedJournalItem } from "@/api/journal";
import { formatDateTime } from "@/components/client/format";
import { Sheet, SheetButton } from "@/components/community/Sheet";
import { DeviceActivityDetail } from "@/components/devices/DeviceActivityCard";
import { DevicePendingSheet } from "@/components/devices/DevicePendingSheet";
import { formatPercent, metricParts, showsDeviceCard, sportIcon, summaryParts, type SummaryPart } from "@/components/devices/garmin-model";

const RECENT_KEY = [...JOURNAL_FEED_KEY, "device-recent"] as const;

/**
 * The journal's device card above Ροή (board 16 Q7 A): «Garmin · 2 νέες
 * προπονήσεις · 1 χρειάζεται επιβεβαίωση», only when there is something to
 * see (or while history comes in). Tapping marks it seen and opens what
 * needs an answer first, then the new workouts.
 */
export function DeviceJournalCard({ token, locale }: { token: string | null; locale: string }) {
  const t = useTranslations("Devices");
  const queryClient = useQueryClient();
  const [open, setOpen] = useState<"pending" | "new" | null>(null);
  // Whether new workouts came with the question: they open once it is answered.
  const [thenNew, setThenNew] = useState(false);
  const summary = useQuery({ queryKey: DEVICE_SUMMARY_KEY, enabled: Boolean(token), queryFn: () => fetchDeviceSummary(token!), retry: false });
  const pending = useQuery({
    queryKey: DEVICE_PENDING_KEY,
    enabled: Boolean(token) && open !== null && (summary.data?.needs_confirmation ?? 0) > 0,
    queryFn: () => fetchGarminPending(token!),
  });
  const seen = useMutation({
    mutationFn: () => markDeviceSummarySeen(token!),
    onSuccess: (next) => queryClient.setQueryData(DEVICE_SUMMARY_KEY, next),
  });

  const data = summary.data;
  // Keep the card on screen while its sheet is open, even once marked seen.
  if (!token || !data || (!showsDeviceCard(data) && open === null)) return null;

  const text = (part: SummaryPart) =>
    part.key === "importing" ? t("card_importing", { percent: formatPercent(part.count, locale) }) : t(["card", part.key].join("_"), { count: part.count });
  const parts = summaryParts(data);
  const [headline, ...rest] = parts;

  function openCard() {
    if (data?.visible) seen.mutate();
    setThenNew(Boolean(data?.new_counts?.activity));
    setOpen((data?.needs_confirmation ?? 0) > 0 ? "pending" : "new");
  }

  function answered() {
    void queryClient.invalidateQueries({ queryKey: DEVICE_SUMMARY_KEY });
    void queryClient.invalidateQueries({ queryKey: DEVICE_PENDING_KEY });
    void queryClient.invalidateQueries({ queryKey: JOURNAL_FEED_KEY });
  }

  return (
    <>
      {showsDeviceCard(data) ? (
        <button
          type="button"
          onClick={openCard}
          data-testid="journal-device-card"
          className="flex w-full items-center gap-3 rounded-2xl p-4 text-left"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          <span aria-hidden="true" className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-lg" style={{ background: "var(--panel-raised)" }}>⌚</span>
          <span className="flex min-w-0 flex-1 flex-col">
            <b className="text-sm">{[t("provider_garmin"), headline ? text(headline) : null].filter(Boolean).join(" · ")}</b>
            {rest.length ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{rest.map(text).join(" · ")}</span> : null}
          </span>
          <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
        </button>
      ) : null}

      {open === "pending" && pending.data ? (
        pending.data.length ? (
          <DevicePendingSheet
            token={token}
            imports={pending.data}
            locale={locale}
            onAnswered={answered}
            onClose={() => setOpen(thenNew ? "new" : null)}
          />
        ) : (
          <NewFromDeviceSheet token={token} locale={locale} onClose={() => setOpen(null)} />
        )
      ) : null}
      {open === "new" ? <NewFromDeviceSheet token={token} locale={locale} onClose={() => setOpen(null)} /> : null}
    </>
  );
}

/** The latest watch workouts of their own, each opening its detail. */
function NewFromDeviceSheet({ token, locale, onClose }: { token: string; locale: string; onClose: () => void }) {
  const t = useTranslations("Devices");
  const labelId = useId();
  const [detail, setDetail] = useState<DeviceActivity | null>(null);
  const recent = useQuery({
    queryKey: RECENT_KEY,
    queryFn: () => fetchJournalPage(token, { kinds: ["device_activity"], limit: 5 }),
  });
  const items = (recent.data?.items ?? []) as Extract<TypedJournalItem, { kind: "device_activity" }>[];
  if (detail) return <DeviceActivityDetail activity={detail} title={detail.title} locale={locale} onClose={() => setDetail(null)} />;
  return (
    <Sheet
      title={t("newTitle")}
      eyebrow={t("provider_garmin")}
      labelId={labelId}
      onClose={onClose}
      footer={<SheetButton onClick={onClose}>{t("close")}</SheetButton>}
    >
      <div className="flex flex-col gap-3" data-testid="device-new-sheet">
        {recent.isPending ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
        {!recent.isPending && items.length === 0 ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("newEmpty")}</p> : null}
        <ul className="flex flex-col gap-2">
          {items.map((item) => (
            <li key={item.id}>
              <button
                type="button"
                onClick={() => setDetail(item.entry)}
                className="flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-left"
                style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
              >
                <span aria-hidden="true" className="text-lg">{sportIcon(item.entry.sport)}</span>
                <span className="flex min-w-0 flex-col">
                  <b className="text-sm">{item.entry.title}</b>
                  <span className="text-xs tabular-nums" style={{ color: "var(--text-soft)" }}>
                    {[formatDateTime(item.occurred_at, locale), ...metricParts(item.entry, locale).filter((part) => part.key !== "avgHr").map((part) => part.value)].join(" · ")}
                  </span>
                </span>
              </button>
            </li>
          ))}
        </ul>
        <Link href="/me/devices" className="text-sm font-semibold" style={{ color: "var(--primary)" }}>{t("manageDevices")}</Link>
      </div>
    </Sheet>
  );
}
