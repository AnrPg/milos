"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { setAroundVisibility } from "@/api/around";
import { SUMMARY_KEY, type SocialSummary } from "@/api/social";
import { ErrorLine } from "@/components/community/Sheet";
import { useSession } from "@/components/session-provider";
import { useSocialSummary } from "@/components/social/use-social";

import { AreaPicker, useAroundError, useNeighbourhoodName } from "./AreaPicker";
import { useAroundArea } from "./use-around";

/**
 * Κοινοποίηση & ορατότητα › «Φαίνομαι στο Γύρω μου» (ADR-154 §6): your public
 * posts show in Γύρω μου at your main neighbourhood, never closer. Off by
 * default, and it needs «Η περιοχή μου».
 */
export function AroundVisibilitySetting() {
  const t = useTranslations("Around");
  const aroundError = useAroundError();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const summary = useSocialSummary();
  const setting = summary.data?.around_visibility;
  const visible = setting?.visible ?? false;
  const save = useMutation({
    mutationFn: (next: boolean) => setAroundVisibility(tokens!.access_token, next),
    onSuccess: (result) =>
      queryClient.setQueryData<SocialSummary>(SUMMARY_KEY, (current) => (current ? { ...current, around_visibility: result } : current)),
  });
  if (summary.isPending) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-4">
        <span id="around-visibility-label" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("visibilityToggle")}
        </span>
        <button
          type="button"
          role="switch"
          aria-checked={visible}
          aria-labelledby="around-visibility-label"
          aria-describedby="around-visibility-state"
          disabled={save.isPending || !summary.data}
          onClick={() => save.mutate(!visible)}
          className="hit-area relative h-8 w-14 shrink-0 rounded-full disabled:opacity-60"
          style={{ background: visible ? "var(--primary)" : "var(--panel-raised)", border: "1px solid var(--border)" }}
        >
          <span
            aria-hidden="true"
            className="absolute top-1 h-5 w-5 rounded-full transition-all"
            style={{ left: visible ? "1.9rem" : "0.25rem", background: visible ? "var(--bg)" : "var(--text)" }}
          />
        </button>
      </div>
      <p id="around-visibility-state" className="text-sm" style={{ color: "var(--muted)" }}>
        {visible ? t("visibilityOn") : t("visibilityOff")}
      </p>
      {setting && !setting.has_area ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>
          {t("visibilityNeedsArea")}{" "}
          <Link href="/me/settings#around-area" className="font-semibold underline" style={{ color: "var(--text)" }}>
            {t("setArea")}
          </Link>
        </p>
      ) : null}
      <ErrorLine message={aroundError(save.error)} />
    </div>
  );
}

/** Εγώ › Ρυθμίσεις › «Η περιοχή μου»: where Γύρω μου starts. */
export function AroundAreaSetting() {
  const t = useTranslations("Around");
  const area = useAroundArea();
  const name = useNeighbourhoodName();
  const [saved, setSaved] = useState(false);
  if (area.isPending) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  return (
    <div className="space-y-3">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {area.data && area.data.length > 0 ? t("areaCurrent", { place: name(area.data[0]) }) : t("areaNone")}
      </p>
      <AreaPicker key={(area.data ?? []).map((place) => place.id).join(",")} initial={area.data ?? []} submitLabel={t("save")} onSaved={() => setSaved(true)} />
      {saved ? (
        <p role="status" className="text-sm" style={{ color: "var(--text)" }}>{t("areaSaved")}</p>
      ) : null}
    </div>
  );
}
