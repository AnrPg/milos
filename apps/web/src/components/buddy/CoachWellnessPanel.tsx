"use client";

import { useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import { fetchClientWellnessSummary } from "@/api/buddies";
import { localDate } from "@/components/member-app/wellness/wellness-model";

import { shiftWeek, weekStart } from "./buddy-model";
import { useBuddyToken } from "./use-buddies";

/**
 * The coach's «Ευεξία» summary of a client (ADR-160 §9, board 15 q6 A):
 * only when the member turned it on, counts only, cravings as a count and
 * times only with the second toggle, a week at a time. Every read is in the
 * member's access log, so the panel says so. Nothing shows without the grant.
 */
export function CoachWellnessPanel({ userId, nickname, frame }: { userId: string; nickname: string; frame: (content: ReactNode) => ReactNode }) {
  const t = useTranslations("Buddy");
  const format = useFormatter();
  const token = useBuddyToken();
  const current = weekStart(localDate(new Date()));
  const [week, setWeek] = useState(current);
  const summary = useQuery({
    queryKey: ["staff", "clients", userId, "wellness-summary", week],
    enabled: Boolean(token),
    queryFn: () => fetchClientWellnessSummary(token!, userId, week),
    staleTime: 5 * 60_000,
    retry: false,
  });

  const data = summary.data;
  if (!data?.shared || !data.summary) return null;
  const s = data.summary;
  const day = (iso: string) => format.dateTime(new Date(`${iso}T12:00:00`), { day: "numeric", month: "short" });
  const range = `${day(s.week_start)} – ${day(s.week_end)}`;

  return frame(
    <div className="flex flex-col gap-3" data-testid="coach-wellness-summary">
      <div className="flex items-center justify-between gap-2">
        <button
          type="button"
          onClick={() => setWeek(shiftWeek(week, -1))}
          aria-label={t("weekPrevious")}
          className="hit-area h-9 w-9 rounded-full"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          ‹
        </button>
        <p className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("weekOf", { range })}</p>
        <button
          type="button"
          onClick={() => setWeek(shiftWeek(week, 1))}
          disabled={week >= current}
          aria-label={t("weekNext")}
          className="hit-area h-9 w-9 rounded-full disabled:opacity-40"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          ›
        </button>
      </div>
      <ul className="flex flex-col gap-1 text-sm" style={{ color: "var(--text)" }}>
        <li>{t("coachSleep", { on: s.sleep?.nights_on_goal ?? 0, logged: s.sleep?.nights_logged ?? 0 })}</li>
        <li>{t("coachWater", { on: s.water?.days_on_goal ?? 0, logged: s.water?.days_logged ?? 0 })}</li>
        <li>{t("coachMeals", { days: s.meals?.days_logged ?? 0 })}</li>
        {s.cravings ? <li>{t("coachCravings", { count: s.cravings.count ?? 0 })}</li> : null}
      </ul>
      {s.cravings?.moments?.length ? (
        <ul className="flex flex-wrap gap-2" aria-label={t("coachCravingTimes")}>
          {s.cravings.moments.map((moment, index) => (
            <li key={`${moment.date}-${moment.time}-${index}`} className="rounded-full px-2 py-0.5 text-xs" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}>
              {moment.date ? day(moment.date) : ""} {moment.time ?? ""}
            </li>
          ))}
        </ul>
      ) : null}
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {s.allowed_since
          ? t("coachAllowedSince", { name: nickname, date: format.dateTime(new Date(s.allowed_since), { day: "numeric", month: "short", year: "numeric" }) })
          : t("coachAllowed", { name: nickname })}
      </p>
    </div>,
  );
}
