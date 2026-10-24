"use client";

import { useTranslations } from "next-intl";

import { FeedList } from "@/components/community/FeedList";
import { postsFeedFilter } from "@/components/community/PostFilters";
import { useMyClubs } from "@/components/community/use-community";
import { ListFilters } from "@/components/filters/ListFilters";
import { listFilterCount } from "@/components/filters/list-filter";
import { useListFilter } from "@/components/filters/use-remembered-filter";
import { FEED_POST_TYPES } from "@/api/community";
import { HubPage } from "@/components/member-app/HubParts";
import { BackToMe } from "@/components/member-app/me/BackToMe";

/** Club and kind (vision §7.2 «Feed/club»), remembered on `my_posts`. */
const MY_POSTS_SHAPE = { club: "one", type: "many" } as const;

/** Εγώ › Αναρτήσεις: what I posted, in every club. */
export function MyPostsPage() {
  const t = useTranslations("Community");
  const clubs = useMyClubs();
  const { filter, setFilter } = useListFilter("my_posts", MY_POSTS_SHAPE);
  const narrowed = filter !== null && listFilterCount(filter) > 0;

  return (
    <HubPage back={<BackToMe />} title={t("myPostsTitle")}>
      {filter ? (
        <>
          <ListFilters
            shape={MY_POSTS_SHAPE}
            fields={[
              { key: "club", label: t("filterClub"), options: (clubs.data ?? []).map((club) => ({ value: club.id, label: club.name })) },
              { key: "type", label: t("filterType"), options: FEED_POST_TYPES.map((type) => ({ value: type, label: t(`postType.${type}`) })) },
            ]}
            filter={filter}
            onChange={setFilter}
            title={t("postFiltersTitle")}
          />
          <FeedList
            filter={narrowed ? { ...postsFeedFilter({ ...filter, channel: [], coaches: false }, clubs.data ?? []), mine: true } : { mine: true }}
            empty={narrowed ? t("postsNoMatch") : t("myPostsEmpty")}
          />
        </>
      ) : null}
    </HubPage>
  );
}
