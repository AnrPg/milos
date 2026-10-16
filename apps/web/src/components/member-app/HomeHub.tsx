"use client";

import { useMemo } from "react";
import { useTranslations } from "next-intl";

import { ChallengesCard } from "@/components/member-app/home/ChallengesCard";
import { GreetingCard } from "@/components/member-app/home/GreetingCard";
import { LeaderboardCard } from "@/components/member-app/home/LeaderboardCard";
import { useBoxSchedule } from "@/components/member-app/box/BoxToday";
import { gymWodToday } from "@/components/member-app/box/today-training";
import { HubButton, HubCard, HubPage } from "@/components/member-app/HubParts";
import { useLanding } from "@/components/member-app/progress/use-landing";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";

/**
 * Αρχική (brief §6.1, §7.1): what is happening at my gym. Fixed slots, each
 * with an empty state: greeting, the gym's WOD of the day, challenges,
 * leaderboard, then club posts. The WOD, challenges and posts slots become
 * the club's #wod-σήμερα, #challenges and feed when the Community context
 * lands (ADR-138); their place on the screen does not change.
 */
export function HomeHub() {
  const t = useTranslations("MemberApp");
  const { currentUser, tokens } = useSession();
  const landing = useLanding();
  const gamification = landing.data?.gamification;

  return (
    <HubPage title={t("homeTitle")}>
      <GreetingCard nickname={currentUser?.nickname ?? ""} quote={landing.data?.quote} />
      <WodTodayCard token={tokens?.access_token ?? null} />
      <ChallengesCard challenges={gamification?.active_challenges ?? []} />
      {gamification ? <LeaderboardCard leaderboard={gamification.leaderboard} /> : null}
      <HubCard eyebrow={t("feedPosts")}>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("feedPostsEmpty")}</p>
      </HubCard>
    </HubPage>
  );
}

function WodTodayCard({ token }: { token: string | null }) {
  const t = useTranslations("MemberApp");
  const locale = useUiLocale();
  const now = useMemo(() => new Date(), []);
  const schedule = useBoxSchedule(token, now);
  const wod = gymWodToday(schedule.data?.slots ?? [], now);
  const time = (iso: string) => new Date(iso).toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" });

  return (
    <HubCard eyebrow={t("wodToday")}>
      {schedule.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : wod ? (
        <div className="flex flex-col gap-3">
          <div>
            <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{wod.workout.title}</h2>
            <p className="text-sm" style={{ color: "var(--dim)" }}>
              {wod.classes.map((entry) => time(entry.scheduledAt)).join(" · ")}
            </p>
          </div>
          <HubButton href="/box">{t("openInBox")}</HubButton>
        </div>
      ) : (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("wodTodayEmpty")}</p>
      )}
    </HubCard>
  );
}
