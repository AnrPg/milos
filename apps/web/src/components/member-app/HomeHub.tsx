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
import { feedHasPosts } from "@/components/community/community";
import {
  useClubRealtime,
  useFeed,
  useMyClubs,
} from "@/components/community/use-community";
import { WodCard } from "@/components/community/WodCard";
import { SupportInbox } from "@/components/buddy/SupportRequestCard";
import { MyEventsCard } from "@/components/events/MyEventsCard";
import { ChallengesCard } from "@/components/member-app/home/ChallengesCard";
import { GreetingCard } from "@/components/member-app/home/GreetingCard";
import { LeaderboardCard } from "@/components/member-app/home/LeaderboardCard";
import { FeedPage } from "@/components/member-app/HubParts";
import { WellnessStrip } from "@/components/member-app/wellness/WellnessStrip";
import { useLanding } from "@/components/member-app/progress/use-landing";
import { useSession } from "@/components/session-provider";
import { FeedInboxButtons } from "@/components/chat/MessagesButton";
import { MyTrialsCard } from "@/components/trials/MyTrialsCard";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/**
 * Αρχική (brief §6.1, §7.1): what is happening at my gym. Fixed order:
 * greeting, the gym's WOD of the day, «Τα events μου» (ADR-153), challenges,
 * leaderboard (trials at other boxes and their follow-up after the greeting,
 * board 6), then the feed of the member's clubs (ADR-138) under the club
 * bar, with ⊕ to post and ♡ for notifications and follow requests. The WOD slot is the selected gym club's #wod-σήμερα
 * card with its leaderboard (ADR-138 D6). «Τα clubs μου | Γύρω μου» switches
 * to /around (ADR-154) and is remembered.
 *
 * A card with nothing in it is not shown at all (ANR 2026-10-24, vision §4
 * principle 2): no WOD, no events, no challenges or no posts means no card,
 * and the gym's cards need a gym. The order of the cards that are shown never
 * changes.
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
    <FeedPage
      title={t("homeTitle")}
      start={<ComposeButton clubs={clubs.data ?? []} />}
      end={
        <div className="flex items-center gap-2">
          <FeedInboxButtons />
        </div>
      }
    >
      {clubs.data && clubs.data.length > 0 ? (
        <ClubBar clubs={clubs.data} />
      ) : null}
      <ScopeToggle current="clubs" />
      <GreetingCard
        nickname={currentUser?.nickname ?? ""}
        quote={landing.data?.quote}
      />
      <SupportInbox />
      <WellnessStrip />
      <MyTrialsCard />
      {gymClub ? <WodCard club={gymClub} hideWhenEmpty /> : null}
      <MyEventsCard />
      <ChallengesCard challenges={gamification?.active_challenges ?? []} />
      {gamification && membership ? (
        <LeaderboardCard leaderboard={gamification.leaderboard} />
      ) : null}
      <ClubPosts />
    </FeedPage>
  );
}

/** «Από το club σου»: the clubs' posts, shown only once there is one. */
function ClubPosts() {
  const t = useTranslations("MemberApp");
  const feed = useFeed(HOME_FEED);
  if (!feedHasPosts(feed.data)) return null;

  return (
    <section aria-label={t("feedPosts")} className="flex flex-col gap-3">
      <p
        className="text-xs font-bold uppercase tracking-[0.18em]"
        style={{ color: "var(--dim)" }}
      >
        {t("feedPosts")}
      </p>
      <FeedList filter={HOME_FEED} />
    </section>
  );
}

const HOME_FEED = {};
