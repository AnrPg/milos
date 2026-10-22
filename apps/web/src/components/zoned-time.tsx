"use client";

import { useLocale } from "next-intl";

import { useUiTranslations } from "@/i18n/ui";
import { deviceTimeZone, readZoned, type ZonedFormat } from "@/lib/zoned-time";

type ZonedTimeProps = {
  /** The UTC moment (ISO string or Date). */
  at: string | Date;
  /** The organiser's IANA zone: the gym's, or an event's own. Null: the device's clock. */
  zone: string | null | undefined;
  format?: ZonedFormat;
  className?: string;
  /** Show the organiser's city even when the viewer's clock agrees (a page about one event). */
  showZone?: boolean;
};

/**
 * ADR-179: a moment on its organiser's clock. When the viewer's device reads
 * it differently, the organiser's city is named and a small badge adds the
 * viewer's own time («18:00 your time»).
 */
export function ZonedTime({ at, zone, format = "time", className, showZone = false }: ZonedTimeProps) {
  const locale = useLocale();
  const reading = readZoned(at, zone, deviceTimeZone(), locale, format);
  const iso = typeof at === "string" ? at : at.toISOString();

  return (
    <span className={className}>
      <time dateTime={iso}>{reading.text}</time>
      {reading.local || showZone ? <span style={{ color: "var(--text-soft)" }}> {reading.zone}</span> : null}
      <YourTime at={at} zone={zone} format={format} />
    </span>
  );
}

/**
 * ADR-179: only the "your time" badge, for a line that already shows the
 * organiser's clock. Renders nothing when the viewer's clock agrees.
 */
export function YourTime({ at, zone, format = "time" }: { at: string | Date; zone: string | null | undefined; format?: ZonedFormat }) {
  const locale = useLocale();
  const t = useUiTranslations();
  const reading = readZoned(at, zone, deviceTimeZone(), locale, format);
  if (!reading.local) return null;

  return (
    <span
      className="ml-1 inline-flex items-center whitespace-nowrap rounded-full px-1.5 py-px align-middle text-[0.75em] font-medium"
      style={{ border: "1px solid var(--border)", background: "var(--panel-muted)", color: "var(--text)" }}
      title={t("zonedTimeYoursTitle", { zone: reading.localZone ?? "" })}
    >
      {t("zonedTimeYours", { time: reading.local })}
    </span>
  );
}
