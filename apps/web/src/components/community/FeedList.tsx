"use client";

import { useTranslations } from "next-intl";

import type { FeedFilter } from "@/api/community";
import { withoutPinned } from "@/components/community/community";
import { PostCard } from "@/components/community/PostCard";
import { useFeed } from "@/components/community/use-community";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** A feed of posts: pinned announcements first, then newest first (ADR-138). */
export function FeedList({ filter, empty }: { filter: FeedFilter; empty?: string }) {
  const t = useTranslations("Community");
  const feed = useFeed(filter);
  const pages = feed.data?.pages ?? [];
  const pinned = pages[0]?.pinned ?? [];
  const posts = withoutPinned(
    pages.flatMap((page) => page.posts),
    pinned,
  );

  if (feed.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (feed.isError) return <ErrorNotice>{t("loadFailed")}</ErrorNotice>;
  if (pinned.length === 0 && posts.length === 0)
    return <p className="text-sm" style={{ color: "var(--text-soft)" }}>{empty ?? t("feedEmpty")}</p>;

  return (
    <div className="flex flex-col gap-3">
      {[...pinned, ...posts].map((post) => (
        <PostCard key={post.id} post={post} />
      ))}
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
    </div>
  );
}
