"use client";

import { useState } from "react";
import { useLocale } from "next-intl";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchGamificationPreferences, updateGamificationPreferences } from "@/api/gamification";
import { MAX_OFF_DAYS, toggleOffDay } from "@/components/member-app/me/off-days";
import { LANDING_QUERY_KEY } from "@/components/member-app/progress/use-landing";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** Weekly rest days, which streak and consistency scores skip (moved from Ρυθμίσεις, ADR-137). */
export function RestDaysSettings() {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const dayLabels = Array.from({ length: 7 }, (_, dayOffset) =>
    new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" }).format(new Date(Date.UTC(2024, 0, 7 + dayOffset))),
  );

  const prefs = useQuery({
    queryKey: ["gamification", "preferences"],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchGamificationPreferences(tokens!.access_token),
  });
  const [draft, setDraft] = useState<number[] | null>(null);
  const offDays = draft ?? prefs.data?.off_days ?? [];

  const save = useMutation({
    mutationFn: (days: number[]) => updateGamificationPreferences(tokens!.access_token, { off_days: days }),
    onSuccess: (data) => {
      void queryClient.invalidateQueries({ queryKey: ["gamification", "preferences"] });
      void queryClient.invalidateQueries({ queryKey: LANDING_QUERY_KEY });
      setDraft(data.off_days);
    },
  });

  function toggle(dow: number) {
    const next = toggleOffDay(offDays, dow);
    setDraft(next);
    save.mutate(next);
  }

  return (
    <div className="space-y-5">
      <p className="text-sm" style={{ color: "var(--muted)" }}>
        {i18n("offDaysAreTransparentToYourStreakMissingb808660")}
      </p>
      <div className="flex flex-wrap gap-2">
        {dayLabels.map((label, dow) => {
          const selected = offDays.includes(dow);
          const disabled = !selected && offDays.length >= MAX_OFF_DAYS;
          return (
            <button
              key={dow}
              type="button"
              aria-pressed={selected}
              disabled={disabled || save.isPending}
              onClick={() => toggle(dow)}
              className="rounded-xl px-4 py-2 text-sm font-semibold transition-opacity disabled:opacity-40"
              style={{
                background: selected ? "var(--primary)" : "var(--panel-muted)",
                color: selected ? "var(--primary-contrast)" : "var(--text-soft)",
                border: selected ? "1px solid var(--primary)" : "1px solid var(--border)",
              }}
            >
              {label}
            </button>
          );
        })}
      </div>
      {save.isError ? (
        <ErrorNotice>{i18n("failedToSavePleaseTryAgainb68b7e7")}</ErrorNotice>
      ) : null}
    </div>
  );
}
