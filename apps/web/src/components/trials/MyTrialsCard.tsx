"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { fetchMyTrials, MY_TRIALS_KEY } from "@/api/trials";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";

import { FollowUp, StatusPill } from "./TrialPage";

/**
 * Αρχική (board 6 Q5–Q6): upcoming trials at other boxes, and after a visit
 * «Πώς σου φάνηκε;». Nothing shows for someone with no trials.
 */
export function MyTrialsCard() {
  const t = useTranslations("Trials");
  const locale = useLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const trials = useQuery({ queryKey: MY_TRIALS_KEY, enabled: Boolean(token), queryFn: () => fetchMyTrials(token) });

  // "Upcoming" as of the last fetch, so render stays pure.
  const now = trials.dataUpdatedAt;
  const upcoming = (trials.data ?? []).filter(
    (trial) => (trial.status === "requested" || trial.status === "booked") && new Date(trial.class.scheduled_at).getTime() > now,
  );
  const followUps = (trials.data ?? []).filter((trial) => trial.follow_up && trial.box);
  if (upcoming.length === 0 && followUps.length === 0) return null;

  const when = (iso: string) =>
    new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));

  return (
    <>
      {followUps.slice(0, 1).map((trial) => (
        <HubCard key={trial.id} eyebrow={trial.box!.name} highlighted>
          <FollowUp trial={trial} token={token} compact />
        </HubCard>
      ))}
      {upcoming.length > 0 ? (
        <HubCard eyebrow={t("homeEyebrow")}>
          <ul className="flex flex-col gap-2">
            {upcoming.map((trial) => (
              <li key={trial.id}>
                <Link
                  href={`/trials/${trial.id}`}
                  className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3"
                  style={{ background: "var(--panel-raised)" }}
                >
                  <span className="flex min-w-0 flex-col">
                    <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>
                      {trial.box?.name} · {trial.class.name}
                    </span>
                    <span className="text-xs first-letter:uppercase" style={{ color: "var(--text-soft)" }}>{when(trial.class.scheduled_at)}</span>
                  </span>
                  <StatusPill status={trial.status} />
                </Link>
              </li>
            ))}
          </ul>
        </HubCard>
      ) : null}
    </>
  );
}
