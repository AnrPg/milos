"use client";

import { useId, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import type { DeviceActivity, DeviceMetrics } from "@/api/devices";
import { formatDateTime, formatTime } from "@/components/client/format";
import { Sheet, SheetButton } from "@/components/community/Sheet";
import { attachmentParts, isKnownSport, metricParts, sportIcon, type MetricPart } from "@/components/devices/garmin-model";

function useMetricText() {
  const t = useTranslations("Devices");
  return (part: MetricPart) => (part.key === "avgHr" || part.key === "maxHr" ? t(["metric", part.key].join("_"), { value: part.value }) : part.value);
}

function useSportLabel() {
  const t = useTranslations("Devices");
  return (sport: string) => t(["sport", isKnownSport(sport) ? sport : "other"].join("_"));
}

function useProviderLabel() {
  const t = useTranslations("Devices");
  return (provider: string) => t(["provider", ["garmin", "apple_health", "health_connect"].includes(provider) ? provider : "garmin"].join("_"));
}

/**
 * A watch workout of its own in Ροή (board 16 Q2 A): sport icon, title,
 * distance, duration and average heart rate; tapping opens the detail.
 */
export function DeviceActivityCard({
  activity,
  occurredAt,
  locale,
  badge,
  onOpen,
}: {
  activity: DeviceActivity;
  occurredAt: string;
  locale: string;
  badge: ReactNode;
  onOpen: () => void;
}) {
  const t = useTranslations("Devices");
  const text = useMetricText();
  const sport = useSportLabel();
  const provider = useProviderLabel();
  const line = metricParts(activity, locale).map(text).join(" · ");
  return (
    <li className="flex flex-col gap-2 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="journal-device-activity">
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {sport(activity.sport)} · <time dateTime={occurredAt}>{formatTime(occurredAt, locale)}</time> · {t("fromProvider", { provider: provider(activity.provider) })}
      </p>
      <button type="button" onClick={onOpen} className="flex items-center gap-3 text-left">
        <span aria-hidden="true" className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-lg" style={{ background: "var(--panel-raised)" }}>
          {sportIcon(activity.sport)}
        </span>
        <span className="flex min-w-0 flex-col">
          <span className="break-words text-base font-semibold" style={{ color: "var(--text)" }}>{activity.title}</span>
          <span className="text-sm tabular-nums" style={{ color: "var(--muted)" }}>{line}</span>
        </span>
      </button>
      <div>{badge}</div>
    </li>
  );
}

/** «από Garmin · 52′ · μέσος 148 bpm» on the class or workout the watch matched. */
export function DeviceAttachmentLine({ device, locale, onOpen }: { device: DeviceMetrics; locale: string; onOpen?: () => void }) {
  const t = useTranslations("Devices");
  const text = useMetricText();
  const provider = useProviderLabel();
  const line = [t("fromProvider", { provider: provider(device.provider) }), ...attachmentParts(device, locale).map(text)].join(" · ");
  const content = (
    <>
      <span aria-hidden="true">⌚</span> <span className="tabular-nums">{line}</span>
    </>
  );
  return onOpen ? (
    <button type="button" onClick={onOpen} className="mt-1 text-left text-sm" style={{ color: "var(--text-soft)" }} data-testid="journal-device-attachment">
      {content}
    </button>
  ) : (
    <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }} data-testid="journal-device-attachment">{content}</p>
  );
}

/** The detail of a watch workout, own or merged: every number the watch sent. */
export function DeviceActivityDetail({
  activity,
  title,
  locale,
  onClose,
}: {
  activity: DeviceMetrics;
  title: string;
  locale: string;
  onClose: () => void;
}) {
  const t = useTranslations("Devices");
  const labelId = useId();
  const text = useMetricText();
  const sport = useSportLabel();
  const provider = useProviderLabel();
  const rows: Array<[string, string]> = [
    [t("detail_started"), formatDateTime(activity.started_at, locale)],
    ...metricParts(activity, locale, true).map((part) => [t(["detail", part.key].join("_")), text(part)] as [string, string]),
  ];
  return (
    <Sheet
      title={title}
      eyebrow={[sport(activity.sport), t("fromProvider", { provider: provider(activity.provider) })].join(" · ")}
      labelId={labelId}
      onClose={onClose}
      footer={<SheetButton onClick={onClose}>{t("close")}</SheetButton>}
    >
      <div className="flex flex-col gap-3" data-testid="device-activity-detail">
        <div className="flex items-center gap-3">
          <span aria-hidden="true" className="flex h-12 w-12 items-center justify-center rounded-full text-2xl" style={{ background: "var(--panel-raised)" }}>
            {sportIcon(activity.sport)}
          </span>
        </div>
        <dl className="flex flex-col">
          {rows.map(([label, value]) => (
            <div key={label} className="flex justify-between gap-3 border-b py-2 text-sm last:border-b-0" style={{ borderColor: "var(--border)" }}>
              <dt style={{ color: "var(--text-soft)" }}>{label}</dt>
              <dd className="font-semibold tabular-nums" style={{ color: "var(--text)" }}>{value}</dd>
            </div>
          ))}
        </dl>
        <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("detailPrivacy")}</p>
      </div>
    </Sheet>
  );
}
