"use client";

import type { ReactNode } from "react";
import { useTranslations } from "next-intl";

import type { CommunityClub, CommunityPost } from "@/api/community";
import { withoutPinned } from "@/components/community/community";
import { PostCard } from "@/components/community/PostCard";
import { useFeed, useWodToday } from "@/components/community/use-community";
import { WodCard } from "@/components/community/WodCard";
import { EventList } from "@/components/events/EventParts";
import { useClubEvents } from "@/components/events/use-events";
import { ChallengesCard } from "@/components/member-app/home/ChallengesCard";
import { HubCard } from "@/components/member-app/HubParts";
import { useLanding } from "@/components/member-app/progress/use-landing";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const EVENTS_SHOWN = 3;

/** A PR a member chose to share as a post: the club's PR celebrations (opt-in by sharing). */
const isPrCelebration = (post: CommunityPost) => post.attachment_type === "pr";

/**
 * A club's Ροή (vision §7.1), in a fixed order: pinned announcement → the
 * #wod-σήμερα card with its leaderboard → challenges → PR celebrations →
 * upcoming events → members' posts. Each is hidden when it has nothing
 * (§4.2); only a club with nothing at all says so, once, in one quiet line
 * (its about text when it has one). Challenges are the gym's, so they show
 * on the club of the gym the member has selected.
 */
export function ClubFeed({ club, onShowEvents }: { club: CommunityClub; onShowEvents: () => void }) {
  const t = useTranslations("Community");
  const tClubs = useTranslations("Clubs");
  const tEvents = useTranslations("Events");
  const { membership } = useSelectedMembershipRole();
  const gym = club.kind === "gym";
  const feed = useFeed({ clubId: club.id });
  const wod = useWodToday(gym ? club.organization_slug : null);
  const events = useClubEvents(club.id, "upcoming");
  const landing = useLanding();
  const ownGym = gym && club.organization_id === membership?.organization.id;
  const challenges = ownGym ? (landing.data?.gamification?.active_challenges ?? []) : [];

  const pages = feed.data?.pages ?? [];
  const pinned = pages[0]?.pinned ?? [];
  const posts = withoutPinned(pages.flatMap((page) => page.posts), pinned);
  const prs = posts.filter(isPrCelebration);
  const memberPosts = posts.filter((post) => !isPrCelebration(post));
  // An event already posted to the feed shows once, as its post card (with «Θα έρθω»).
  const posted = new Set(posts.filter((post) => post.attachment_type === "event").map((post) => post.attachment_id));
  const upcoming = (events.data ?? []).filter((event) => !posted.has(event.id));

  if (feed.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;

  const settled = !(gym && wod.isPending) && !events.isPending && !(ownGym && landing.isPending);
  const blank =
    settled && pinned.length === 0 && posts.length === 0 && !wod.data?.workout && challenges.length === 0 && upcoming.length === 0;

  return (
    <>
      <Posts posts={pinned} />
      {gym ? <WodCard club={club} showOrigin={false} /> : null}
      <ChallengesCard challenges={challenges} />
      <Posts posts={prs} />
      {upcoming.length > 0 ? (
        <HubCard eyebrow={tClubs("tabEvents")}>
          <EventList events={upcoming.slice(0, EVENTS_SHOWN)} lead={(event) => event.group?.name ?? undefined} />
          {upcoming.length > EVENTS_SHOWN ? (
            <button
              type="button"
              onClick={onShowEvents}
              className="mt-2 flex min-h-11 items-center text-sm font-bold"
              style={{ color: "var(--primary-strong, var(--primary))" }}
            >
              {tEvents("allEvents")} ›
            </button>
          ) : null}
        </HubCard>
      ) : null}
      <Posts posts={memberPosts} />
      {feed.isError ? <ErrorNotice>{t("loadFailed")}</ErrorNotice> : null}
      {feed.hasNextPage ? (
        <button
          type="button"
          onClick={() => void feed.fetchNextPage()}
          disabled={feed.isFetchingNextPage}
          className="min-h-11 rounded-2xl text-sm font-semibold disabled:opacity-50"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {feed.isFetchingNextPage ? t("loadingMore") : t("loadMore")}
        </button>
      ) : null}
      {blank && !feed.isError ? <BlankClub club={club} /> : null}
    </>
  );
}

function Posts({ posts }: { posts: CommunityPost[] }): ReactNode {
  return posts.map((post) => <PostCard key={post.id} post={post} />);
}

/** Nothing in the club yet: its about text, or one quiet line. An open club's about is already in the header. */
function BlankClub({ club }: { club: CommunityClub }) {
  const t = useTranslations("Community");
  const about = club.description?.trim();
  if (about && club.kind === "open") return null;
  return <p className="text-sm" style={{ color: "var(--text-soft)" }}>{about || t("feedEmpty")}</p>;
}
