"use client";

import { useTranslations } from "next-intl";

import { FEED_POST_TYPES, type CommunityClub, type FeedFilter, type FeedPostType } from "@/api/community";
import { channelName } from "@/components/community/community";
import { ListFilters, type ListFilterField } from "@/components/filters/ListFilters";
import { listFilterCount, type ListFilter } from "@/components/filters/list-filter";

/**
 * Feed and club Ροή filters (vision §7.2 «Feed/club»: club, channel, type,
 * coaches only; ADR-197). The Feed remembers them under its `feed` surface's
 * `posts` entry, a club's Ροή under the `club` surface by club id. Types and
 * coaches-only are the API's, so paging stays right.
 */
export const FEED_POSTS_SHAPE = { club: "one", channel: "one", type: "many", coaches: "toggle" } as const;
export const CLUB_POSTS_SHAPE = { channel: "one", type: "many", coaches: "toggle" } as const;

type PostsShape = typeof FEED_POSTS_SHAPE | typeof CLUB_POSTS_SHAPE;
type PostsFilter = ListFilter<typeof CLUB_POSTS_SHAPE> & { club?: string[] };

const isType = (value: string): value is FeedPostType => (FEED_POST_TYPES as string[]).includes(value);

/** What the feed API is asked for; a club or channel the member no longer reaches is dropped. */
export function postsFeedFilter(filter: PostsFilter, clubs: readonly CommunityClub[], clubId?: string): FeedFilter {
  const club = clubs.find((entry) => entry.id === (clubId ?? filter.club?.[0])) ?? null;
  const channel = club?.channels.find((entry) => entry.id === filter.channel[0]) ?? null;
  return {
    clubId: club?.id ?? null,
    channelId: channel?.id ?? null,
    types: filter.type.filter(isType),
    coachesOnly: filter.coaches,
  };
}

/** Whether the filter narrows what is shown (the «nothing matches» line, the club's plain list). */
export const narrowsPosts = (filter: PostsFilter) => listFilterCount(filter as Record<string, string[] | boolean>) > 0;

export function PostFilters<S extends PostsShape>({
  shape,
  filter,
  onChange,
  clubs,
  clubId,
}: {
  shape: S;
  filter: ListFilter<S>;
  onChange: (filter: ListFilter<S>) => void;
  clubs: readonly CommunityClub[];
  /** A club's own Ροή: the club is fixed, its channels are the choices. */
  clubId?: string;
}) {
  const t = useTranslations("Community");
  const posts = filter as PostsFilter;
  const club = clubs.find((entry) => entry.id === (clubId ?? posts.club?.[0])) ?? null;
  const channels = (club?.channels ?? []).filter((channel) => (channel.status ?? "active") === "active");

  const fields: ListFilterField<typeof FEED_POSTS_SHAPE>[] = [
    ...(clubId ? [] : [{ key: "club" as const, label: t("filterClub"), options: clubs.map((entry) => ({ value: entry.id, label: entry.name })) }]),
    { key: "channel", label: t("filterChannel"), chip: Boolean(clubId), options: channels.map((channel) => ({ value: channel.id, label: `#${channelName(channel, t)}` })) },
    { key: "type", label: t("filterType"), options: FEED_POST_TYPES.map((type) => ({ value: type, label: t(`postType.${type}`) })) },
    { key: "coaches", label: t("filterCoachesOnly"), section: t("filterAuthor") },
  ];

  return (
    <ListFilters
      shape={shape}
      fields={fields as ListFilterField<S>[]}
      filter={filter}
      onChange={(next) => {
        const picked = next as PostsFilter;
        // A channel belongs to its club: another club clears it.
        const clubChanged = !clubId && (picked.club?.[0] ?? null) !== (posts.club?.[0] ?? null);
        onChange((clubChanged ? { ...next, channel: [] } : next) as ListFilter<S>);
      }}
      title={t("postFiltersTitle")}
    />
  );
}
