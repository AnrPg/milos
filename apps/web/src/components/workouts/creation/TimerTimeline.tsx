"use client";

import { useUiTranslations } from "@/i18n/ui";
import { useEffect, useMemo, useState } from "react";

import { previewSectionTimer, type TimerPreview } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { segmentLabel } from "@/lib/segment-label";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import type { DraftSection } from "@/types/workout";

import { formatDurationInput } from "./TimeInput";

const PREVIEW_DEBOUNCE_MS = 400;
const MAX_LISTED_SEGMENTS = 40;
const PHASE_COLORS = {
  work: "var(--primary)",
  rest: "var(--info, var(--success))",
  transition: "var(--warning)",
} as const;

/**
 * Live preview of the timer a draft section produces, so coaches see the
 * total length and every interval while they edit instead of discovering the
 * result during the workout.
 */
export function TimerTimeline({ section }: { section: DraftSection }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const accessToken = tokens?.access_token;
  const [result, setResult] = useState<{ key: string; preview: TimerPreview | null; failed: boolean } | null>(null);

  const payload = useMemo(() => {
    const store = useWorkoutCreationStore.getState();
    const index = store.sections.findIndex((candidate) => candidate.localId === section.localId);
    const sections = (store.toApiPayload() as { sections: Record<string, unknown>[] }).sections;
    return index >= 0 ? sections[index] ?? null : null;
    // `section` changes whenever any of its fields is edited.
  }, [section]);
  const payloadKey = useMemo(() => JSON.stringify(payload), [payload]);

  useEffect(() => {
    if (!accessToken || !payload) return;
    let cancelled = false;

    const timeoutId = window.setTimeout(() => {
      previewSectionTimer(accessToken, payload)
        .then((preview) => {
          if (!cancelled) setResult({ key: payloadKey, preview, failed: false });
        })
        .catch(() => {
          if (!cancelled) setResult({ key: payloadKey, preview: null, failed: true });
        });
    }, PREVIEW_DEBOUNCE_MS);

    return () => {
      cancelled = true;
      window.clearTimeout(timeoutId);
    };
    // payloadKey captures every change to the section payload.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accessToken, payloadKey]);

  const stale = result?.key !== payloadKey;
  const preview = result?.preview ?? null;

  if (!result) return null;

  if (result.failed && !stale) {
    return (
      <p className="mt-3 text-xs" style={{ color: "var(--warning)" }} role="status">
        {i18n("timerPreviewInvalid")}
      </p>
    );
  }

  if (!preview || preview.segments.length === 0) return null;

  const timedTotal = preview.segments.reduce((sum, segment) => sum + blockSeconds(segment), 0);

  return (
    <div className={`mt-3 flex flex-col gap-2 transition-opacity ${stale ? "opacity-60" : ""}`} aria-busy={stale}>
      <div className="flex items-baseline justify-between gap-2 text-xs" style={{ color: "var(--muted)" }}>
        <span className="font-bold uppercase tracking-widest">{i18n("timerPreviewTitle")}</span>
        <span className="tabular-nums" style={{ color: "var(--text-soft)" }}>
          {i18n("timerPreviewSummary", {
            count: preview.segments.length,
            duration: formatDurationInput(preview.total_seconds) || "0:00",
          })}
          {preview.open_ended ? ` ${i18n("timerPreviewOpenEnded")}` : ""}
        </span>
      </div>

      <div className="flex h-3 w-full gap-px overflow-hidden rounded-full" aria-hidden="true">
        {preview.segments.slice(0, 200).map((segment, index) => (
          <span
            key={index}
            className="h-full"
            style={{
              flexGrow: blockSeconds(segment) || Math.max(timedTotal / 12, 1),
              flexBasis: 0,
              background: PHASE_COLORS[segment.phase] ?? PHASE_COLORS.work,
              opacity: segment.kind === "countdown" ? 1 : 0.45,
            }}
          />
        ))}
      </div>

      <details className="text-xs" style={{ color: "var(--text-soft)" }}>
        <summary className="cursor-pointer select-none" style={{ color: "var(--muted)" }}>
          {i18n("timerPreviewShowSegments")}
        </summary>
        <ol className="mt-2 flex flex-col gap-1">
          {preview.segments.slice(0, MAX_LISTED_SEGMENTS).map((segment, index) => (
            <li key={index} className="flex justify-between gap-2">
              <span className="truncate">{segmentLabel(segment, i18n)}</span>
              <span className="shrink-0 tabular-nums" style={{ color: "var(--muted)" }}>
                {segmentDurationLabel(segment, i18n)}
              </span>
            </li>
          ))}
          {preview.segments.length > MAX_LISTED_SEGMENTS ? <li aria-hidden="true">…</li> : null}
        </ol>
      </details>
    </div>
  );
}

function blockSeconds(segment: TimerPreview["segments"][number]) {
  if (segment.kind === "countdown") return segment.duration_seconds ?? 0;
  if (segment.kind === "interval_cycle" && segment.total_rounds) {
    return (segment.duration_seconds ?? 0) * segment.total_rounds;
  }
  return 0;
}

function segmentDurationLabel(
  segment: TimerPreview["segments"][number],
  i18n: ReturnType<typeof useUiTranslations>,
) {
  const duration = formatDurationInput(segment.duration_seconds);
  switch (segment.kind) {
    case "countdown":
      return duration;
    case "countup":
      return duration ? `${i18n("timerPreviewStopwatch")} · ${i18n("capa8fba29")} ${duration}` : i18n("timerPreviewStopwatch");
    case "interval_cycle":
      return segment.total_rounds
        ? `${segment.total_rounds} × ${duration}`
        : `${duration} × ${i18n("timerPreviewUntilStop")}`;
    default:
      return i18n("timerPreviewManual");
  }
}
