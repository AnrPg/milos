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
import { FEED_POSTS_SHAPE, PostFilters, narrowsPosts, postsFeedFilter } from "@/components/community/PostFilters";
import { useListFilter } from "@/components/filters/use-remembered-filter";
import type { CommunityClub } from "@/api/community";
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
import { MyTrialsCard } from "@/components/trials/MyTrialsCard";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/**
 * Αρχική (brief §6.1, §7.1): what is happening at my gym. Fixed order:
 * greeting, the gym's WOD of the day, «Τα events μου» (ADR-153), challenges,
 * leaderboard (trials at other boxes and their follow-up after the greeting,
 * board 6), then the feed of the member's clubs (ADR-138) under the club
 * bar, with ⊕ to post and ♡ for notifications and follow requests. The WOD slot is the selected gym club's #wod-σήμερα
 * card with its leaderboard (ADR-138 D6). «Οι δικοί μου | Γύρω μου» switches
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
      action={<ComposeButton clubs={clubs.data ?? []} />}
    >
      {/* Always there, so «+ Βρες» is reachable before the first club (vision §6.1). */}
      <ClubBar clubs={clubs.data ?? []} />
      <ScopeToggle current="clubs" />
      <GreetingCard
        nickname={currentUser?.nickname ?? ""}
        quote={landing.data?.quote}
      />
      <SupportInbox />
      <WellnessStrip />
      <MyTrialsCard />
      {gymClub ? <WodCard club={gymClub} /> : null}
      <MyEventsCard />
      <ChallengesCard challenges={gamification?.active_challenges ?? []} />
      {gamification && membership ? (
        <LeaderboardCard leaderboard={gamification.leaderboard} />
      ) : null}
      <ClubPosts clubs={clubs.data ?? []} />
    </FeedPage>
  );
}

/**
 * «Από το club σου»: the clubs' posts, shown only once there is one, with
 * the Feed/club filters (vision §7.2), remembered in the `feed` surface.
 */
function ClubPosts({ clubs }: { clubs: CommunityClub[] }) {
  const t = useTranslations("MemberApp");
  const tCommunity = useTranslations("Community");
  const feed = useFeed(HOME_FEED);
  const { filter, setFilter } = useListFilter("feed", FEED_POSTS_SHAPE, "posts");
  if (!feedHasPosts(feed.data) || filter === null) return null;

  return (
    <section aria-label={t("feedPosts")} className="flex flex-col gap-3">
      <p
        className="text-xs font-bold uppercase tracking-[0.18em]"
        style={{ color: "var(--dim)" }}
      >
        {t("feedPosts")}
      </p>
      <PostFilters shape={FEED_POSTS_SHAPE} filter={filter} onChange={setFilter} clubs={clubs} />
      <FeedList
        filter={narrowsPosts(filter) ? postsFeedFilter(filter, clubs) : HOME_FEED}
        empty={narrowsPosts(filter) ? tCommunity("postsNoMatch") : undefined}
      />
    </section>
  );
}

const HOME_FEED = {};
