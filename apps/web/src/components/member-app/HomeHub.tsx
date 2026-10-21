"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";

import { ScopeToggle } from "@/components/around/ScopeToggle";
import { useHomeScope } from "@/components/around/use-around";

import { ClubBar } from "@/components/community/ClubBar";
import { gymClubFor } from "@/components/community/community";
import { ComposeButton } from "@/components/community/ComposeSheet";
import { FeedList } from "@/components/community/FeedList";
import { useClubRealtime, useMyClubs } from "@/components/community/use-community";
import { WodCard } from "@/components/community/WodCard";
import { SupportInbox } from "@/components/buddy/SupportRequestCard";
import { MyEventsCard } from "@/components/events/MyEventsCard";
import { ChallengesCard } from "@/components/member-app/home/ChallengesCard";
import { GreetingCard } from "@/components/member-app/home/GreetingCard";
import { LeaderboardCard } from "@/components/member-app/home/LeaderboardCard";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { WellnessStrip } from "@/components/member-app/wellness/WellnessStrip";
import { useLanding } from "@/components/member-app/progress/use-landing";
import { useSession } from "@/components/session-provider";
import { HeartButton } from "@/components/social/HeartButton";
import { MyTrialsCard } from "@/components/trials/MyTrialsCard";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/**
 * Αρχική (brief §6.1, §7.1): what is happening at my gym. Fixed slots, each
 * with an empty state: greeting, the gym's WOD of the day, «Τα events μου»
 * (ADR-153), challenges,
 * leaderboard (trials at other boxes and their follow-up after the greeting,
 * board 6), then the feed of the member's clubs (ADR-138) under the club
 * bar, with ⊕ to post and ♡ for notifications and follow requests. The WOD slot is the selected gym club's #wod-σήμερα
 * card with its leaderboard (ADR-138 D6). «Τα clubs μου | Γύρω μου» switches
 * to /around (ADR-154) and is remembered.
 */
export function HomeHub() {
  const t = useTranslations("MemberApp");
  const { currentUser } = useSession();
  const { membership } = useSelectedMembershipRole();
  const landing = useLanding();
  const gamification = landing.data?.gamification;
  const clubs = useMyClubs();
  useClubRealtime(clubs.data);
  const gymClub = gymClubFor(clubs.data ?? [], membership?.organization.id);
  const router = useRouter();
  const scope = useHomeScope();
  // «Remember the last choice» (vision §7.1): Αρχική opens in Γύρω μου when that was it.
  const openAround = scope.settled && scope.scope === "around";
  useEffect(() => {
    if (openAround) router.replace("/around");
  }, [openAround, router]);

  return (
    <HubPage
      title={t("homeTitle")}
      actions={
        <div className="flex items-center gap-2">
          <HeartButton />
          <ComposeButton clubs={clubs.data ?? []} />
        </div>
      }
    >
      {clubs.data && clubs.data.length > 0 ? <ClubBar clubs={clubs.data} /> : null}
      <ScopeToggle current="clubs" />
      <GreetingCard nickname={currentUser?.nickname ?? ""} quote={landing.data?.quote} />
      <SupportInbox />
      <WellnessStrip />
      <MyTrialsCard />
      {gymClub ? (
        <WodCard club={gymClub} />
      ) : (
        <HubCard eyebrow={t("wodToday")}>
          <p className="text-sm" style={{ color: clubs.isPending ? "var(--dim)" : "var(--text-soft)" }}>
            {clubs.isPending ? t("loading") : t("wodTodayEmpty")}
          </p>
        </HubCard>
      )}
      <MyEventsCard />
      <ChallengesCard challenges={gamification?.active_challenges ?? []} />
      {gamification ? <LeaderboardCard leaderboard={gamification.leaderboard} /> : null}
      <section aria-label={t("feedPosts")} className="flex flex-col gap-3">
        <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("feedPosts")}</p>
        <FeedList filter={{}} empty={t("feedPostsEmpty")} />
      </section>
    </HubPage>
  );
}
