"use client";

import { useInfiniteQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchBoxPosts } from "@/api/social";
import { PostCard } from "@/components/community/PostCard";

/** «Δημόσια»: the posts the gym's staff made public (ADR-142 decision 10). */
export function BoxPosts({ slug, token }: { slug: string; token: string }) {
  const t = useTranslations("BoxPage");
  const posts = useInfiniteQuery({
    queryKey: ["social", "box-posts", slug],
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchBoxPosts(token, slug, pageParam),
    getNextPageParam: (page) => page.next_cursor ?? null,
  });
  const entries = posts.data?.pages.flatMap((page) => page.posts) ?? [];

  return (
    <div className="flex flex-col gap-3">
      {posts.isPending ? <p className="py-6 text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {posts.isSuccess && entries.length === 0 ? <EmptyTab text={t("postsEmpty")} /> : null}
      {entries.map((post) => (
        <PostCard key={post.id} post={post} />
      ))}
      {posts.hasNextPage ? (
        <button
          type="button"
          onClick={() => void posts.fetchNextPage()}
          className="min-h-11 rounded-2xl text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("morePosts")}
        </button>
      ) : null}
    </div>
  );
}

export function EmptyTab({ text }: { text: string }) {
  return (
    <p className="rounded-2xl p-6 text-center text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
      {text}
    </p>
  );
}
