"use client";

import { useUiTranslations } from "@/i18n/ui";

/** The actions every completed entry offers (ADR-098); sharing where the page allows it. */
export function EntryActions({
  onRepeat,
  onPerformance,
  onShare,
  repeating,
  disabled,
  workoutTitle,
}: {
  onRepeat: () => void;
  onPerformance: () => void;
  onShare?: () => void;
  repeating: boolean;
  disabled: boolean;
  workoutTitle: string;
}) {
  const i18n = useUiTranslations();
  return (
    <div className="flex flex-wrap gap-2">
      <button
        type="button"
        onClick={onPerformance}
        className="rounded-full px-3 py-1.5 text-xs font-semibold"
        style={{ background: "var(--border)", color: "var(--text)" }}
        aria-label={`${i18n("clSeePerformance")}: ${workoutTitle}`}
      >
        {i18n("clSeePerformance")}
      </button>
      <button
        type="button"
        onClick={onRepeat}
        disabled={disabled}
        className="rounded-full px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        aria-label={`${i18n("clDoItAgain")}: ${workoutTitle}`}
      >
        {repeating ? i18n("clStarting") : i18n("clDoItAgain")}
      </button>
      {onShare ? (
        <button
          type="button"
          onClick={onShare}
          className="rounded-full px-3 py-1.5 text-xs font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          aria-label={`${i18n("shareInMilos")}: ${workoutTitle}`}
        >
          {i18n("shareInMilos")}
        </button>
      ) : null}
    </div>
  );
}

/** Small label for how an entry was started; repeats are called out. */
export function SourceBadge({ source }: { source: string }) {
  const i18n = useUiTranslations();
  const label =
    source === "repeat"
      ? i18n("clSourceRepeat")
      : source === "class_booking"
        ? i18n("clSourceClass")
        : source === "assigned"
          ? i18n("clSourceAssigned")
          : source === "self_selected"
            ? i18n("clSourceSelfSelected")
            : source.replaceAll("_", " ");
  return (
    <span
      className="rounded-full px-2 py-0.5 text-[11px] font-semibold"
      style={{
        background: source === "repeat" ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "var(--panel-muted)",
        color: source === "repeat" ? "var(--primary)" : "var(--dim)",
      }}
    >
      {label}
    </span>
  );
}
