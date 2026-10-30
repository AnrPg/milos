"use client";

import { useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { uploadRoomPhoto } from "@/api/spaces";
import { answerReady, type PointAnswer } from "@/components/spaces/cleaning-points";
import { inputClass, inputStyle, secondaryButtonClass, secondaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { preparePhoto } from "@/lib/media-files";
import { putPresigned } from "@/lib/presigned-upload";

export type CarouselPoint = { id: string; instruction: string; url?: string | null };

/**
 * The visual cleaning checklist of a room (ADR-290): one photo at a time,
 * «Καθαρό» or «Δεν καθαρίστηκε». Not cleaned asks why (required); an
 * "after" photo is optional. «Καθαρό» moves on to the next point.
 */
export function CleaningPointsCarousel({
  token,
  points,
  answers,
  onChange,
}: {
  token: string;
  points: CarouselPoint[];
  answers: Record<string, PointAnswer>;
  onChange: (pointId: string, answer: PointAnswer) => void;
}) {
  const t = useTranslations("Spaces");
  const ui = useUiTranslations();
  const [index, setIndex] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const point = points[Math.min(index, points.length - 1)];
  const answer = answers[point.id] ?? {};

  const afterPhoto = useMutation({
    mutationFn: async (file: File) => {
      const prepared = await preparePhoto(file, "original");
      const mediaId = await uploadRoomPhoto(token, "points", prepared, putPresigned);
      return { mediaId, preview: URL.createObjectURL(prepared.blob) };
    },
    onSuccess: ({ mediaId, preview }) => onChange(point.id, { ...answer, afterMediaId: mediaId, afterPreview: preview }),
  });

  const go = (next: number) => setIndex(Math.max(0, Math.min(points.length - 1, next)));

  return (
    <div className="flex flex-col gap-3" data-testid="cleaning-carousel">
      <div className="relative overflow-hidden rounded-2xl" style={{ border: "1px solid var(--border)", background: "var(--panel-muted)" }}>
        {/* A signed, short-lived URL from object storage: next/image would cache it. */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={point.url ?? ""} alt={point.instruction} className="block aspect-[4/3] w-full object-cover" />
        <span
          className="absolute start-2 top-2 rounded-full px-2 py-0.5 text-xs font-semibold"
          style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {t("cleaningPointPosition", { index: index + 1, total: points.length })}
        </span>
      </div>
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }} data-testid="cleaning-carousel-instruction">{point.instruction}</p>

      <div className="flex gap-2">
        <button
          type="button"
          className="flex-1 rounded-full px-4 py-2.5 text-sm font-semibold"
          data-testid="cleaning-point-cleaned"
          aria-pressed={answer.status === "cleaned"}
          style={answer.status === "cleaned" ? { background: "var(--success)", color: "var(--primary-contrast)" } : { border: "1px solid var(--success)", color: "var(--success)" }}
          onClick={() => {
            onChange(point.id, { ...answer, status: "cleaned" });
            if (index < points.length - 1) go(index + 1);
          }}
        >
          ✓ {t("cleaningPointCleaned")}
        </button>
        <button
          type="button"
          className="flex-1 rounded-full px-4 py-2.5 text-sm font-semibold"
          data-testid="cleaning-point-not-cleaned"
          aria-pressed={answer.status === "not_cleaned"}
          style={answer.status === "not_cleaned" ? { background: "var(--danger)", color: "var(--primary-contrast)" } : { border: "1px solid var(--danger)", color: "var(--danger)" }}
          onClick={() => onChange(point.id, { ...answer, status: "not_cleaned" })}
        >
          ✕ {t("cleaningPointNotCleaned")}
        </button>
      </div>

      {answer.status === "not_cleaned" ? (
        <label className="block">
          <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("cleaningPointWhy")}</span>
          <textarea
            className={`${inputClass} mt-1`}
            style={{ ...inputStyle, borderColor: answer.note?.trim() ? undefined : "var(--danger)" }}
            rows={2}
            maxLength={1000}
            required
            data-testid="cleaning-point-note"
            value={answer.note ?? ""}
            onChange={(event) => onChange(point.id, { ...answer, note: event.target.value })}
          />
          {!answer.note?.trim() ? <span className="text-xs" style={{ color: "var(--danger)" }}>{t("cleaningPointWhyRequired")}</span> : null}
        </label>
      ) : null}

      {answer.status ? (
        <div className="flex items-center gap-3">
          {answer.afterPreview ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={answer.afterPreview} alt={t("cleaningPointAfter")} className="h-14 w-14 rounded-lg object-cover" />
          ) : null}
          <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} disabled={afterPhoto.isPending} onClick={() => input.current?.click()}>
            📷 {afterPhoto.isPending ? t("uploading") : answer.afterMediaId ? t("cleaningPointAfterChange") : t("cleaningPointAfter")}
          </button>
          <input
            ref={input}
            type="file"
            accept="image/*"
            capture="environment"
            hidden
            data-testid="cleaning-point-after-file"
            onChange={(event) => {
              const file = event.target.files?.[0];
              event.target.value = "";
              if (file) afterPhoto.mutate(file);
            }}
          />
        </div>
      ) : null}
      {afterPhoto.isError ? <StatusText tone="error">{localizeError(afterPhoto.error, ui)}</StatusText> : null}

      <div className="flex items-center justify-between gap-2">
        <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} disabled={index === 0} onClick={() => go(index - 1)} aria-label={t("cleaningPointPrevious")}>‹</button>
        <ol className="flex flex-wrap justify-center gap-1.5" aria-label={t("cleaningPoints")}>
          {points.map((item, at) => {
            const given = answers[item.id];
            const colour = !answerReady(given) ? "var(--border)" : given?.status === "cleaned" ? "var(--success)" : "var(--danger)";
            return (
              <li key={item.id}>
                <button
                  type="button"
                  className="block h-3 w-3 rounded-full"
                  aria-label={t("cleaningPointPosition", { index: at + 1, total: points.length })}
                  aria-current={at === index ? "step" : undefined}
                  style={{ background: colour, outline: at === index ? "2px solid var(--primary)" : undefined, outlineOffset: 2 }}
                  onClick={() => go(at)}
                />
              </li>
            );
          })}
        </ol>
        <button type="button" className={secondaryButtonClass} style={secondaryButtonStyle} disabled={index === points.length - 1} onClick={() => go(index + 1)} aria-label={t("cleaningPointNext")}>›</button>
      </div>
    </div>
  );
}
