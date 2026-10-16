"use client";

import { useMemo } from "react";
import { useTranslations } from "next-intl";

import { ClubBar } from "@/components/community/ClubBar";
import { ComposeButton } from "@/components/community/ComposeSheet";
import { FeedList } from "@/components/community/FeedList";
import { useClubRealtime, useMyClubs } from "@/components/community/use-community";
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
 * leaderboard, then the feed of the member's clubs (ADR-138) under the club
 * bar, with ⊕ to post. The WOD and challenges slots become the club's
 * #wod-σήμερα and #challenges cards (M8); their place does not change.
 */
export function HomeHub() {
  const t = useTranslations("MemberApp");
  const { currentUser, tokens } = useSession();
  const landing = useLanding();
  const gamification = landing.data?.gamification;
  const clubs = useMyClubs();
  useClubRealtime(clubs.data);

  return (
    <HubPage title={t("homeTitle")} actions={<ComposeButton clubs={clubs.data ?? []} />}>
      {clubs.data && clubs.data.length > 0 ? <ClubBar clubs={clubs.data} /> : null}
      <GreetingCard nickname={currentUser?.nickname ?? ""} quote={landing.data?.quote} />
      <WodTodayCard token={tokens?.access_token ?? null} />
      <ChallengesCard challenges={gamification?.active_challenges ?? []} />
      {gamification ? <LeaderboardCard leaderboard={gamification.leaderboard} /> : null}
      <section aria-label={t("feedPosts")} className="flex flex-col gap-3">
        <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("feedPosts")}</p>
        <FeedList filter={{}} empty={t("feedPostsEmpty")} />
      </section>
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
