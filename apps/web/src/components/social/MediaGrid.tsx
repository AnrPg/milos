"use client";

import { useState } from "react";
import { useInfiniteQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import type { CommunityPost } from "@/api/community";
import { fetchPersonMedia, personKey } from "@/api/social";
import { PostCard } from "@/components/community/PostCard";
import { useSession } from "@/components/session-provider";
import { LockedNote } from "@/components/social/SocialBits";
import { mediaTile, type MediaTile } from "@/components/social/social-model";
import { Dialog } from "@/components/ui/Dialog";

export const personMediaKey = (id: string) => [...personKey(id), "media"] as const;

/**
 * ADR-231: a profile's «Πολυμέσα» tab, Instagram-like. Their posts with photos
 * or a video as a three-wide grid of squares, newest first; a square opens the
 * whole post (photos, video, kudos, comments) over the grid. The API applies
 * the posts' audience, so `lock` only explains what is still held back.
 */
export function MediaGrid({ personId, lock, mine = false }: { personId: string; lock: string | null; mine?: boolean }) {
  const t = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [openId, setOpenId] = useState<string | null>(null);
  const media = useInfiniteQuery({
    queryKey: personMediaKey(personId),
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchPersonMedia(token!, personId, pageParam),
    getNextPageParam: (page) => page.next_cursor ?? null,
  });
  const posts = media.data?.pages.flatMap((page) => page.posts) ?? [];
  // Read from the list, so a post deleted from the dialog closes it.
  const open = openId ? posts.find((post) => post.id === openId) : undefined;

  if (media.isPending) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;

  return (
    <div className="flex flex-col gap-3">
      {posts.length === 0 && !lock ? (
        <p className="rounded-3xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
          {t(mine ? "mediaEmptyMine" : "mediaEmpty")}
        </p>
      ) : null}
      {posts.length > 0 ? (
        <ul className="grid grid-cols-3 gap-0.5 overflow-hidden rounded-3xl" data-testid="media-grid">
          {posts.map((post) => (
            <li key={post.id}>
              <Tile post={post} onOpen={() => setOpenId(post.id)} />
            </li>
          ))}
        </ul>
      ) : null}
      {media.hasNextPage ? (
        <button
          type="button"
          onClick={() => void media.fetchNextPage()}
          disabled={media.isFetchingNextPage}
          className="min-h-11 rounded-2xl text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("more")}
        </button>
      ) : null}
      {lock ? <LockedNote textKey={lock} /> : null}
      {open ? (
        <Dialog onClose={() => setOpenId(null)} ariaLabel={t("mediaPostOf", { name: open.author.nickname ?? "?" })} size="lg" variant="sheet" bodyClassName="p-0 sm:p-2">
          <PostCard post={open} />
        </Dialog>
      ) : null}
    </div>
  );
}

function Tile({ post, onOpen }: { post: CommunityPost; onOpen: () => void }) {
  const t = useTranslations("Social");
  const tile = mediaTile(post);
  if (!tile) return null;

  return (
    <button
      type="button"
      onClick={onOpen}
      aria-label={tileLabel(tile, t)}
      className="relative block aspect-square w-full overflow-hidden"
      style={{ background: "var(--panel-raised)", outlineColor: "var(--primary)" }}
    >
      {tile.placeholder ? (
        <span
          aria-hidden="true"
          className="absolute inset-0 scale-110"
          style={{ backgroundImage: `url("${tile.placeholder}")`, backgroundSize: "cover", backgroundPosition: "center", filter: "blur(12px)" }}
        />
      ) : null}
      {tile.src ? (
        // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
        <img src={tile.src} alt="" loading="lazy" decoding="async" className="absolute inset-0 h-full w-full object-cover" />
      ) : null}
      {tile.processing ? (
        <span className="absolute inset-0 flex items-center justify-center p-2 text-center text-xs font-bold" style={{ background: "var(--media-control)", color: "var(--on-media)" }}>
          {t("mediaProcessing")}
        </span>
      ) : null}
      {tile.kind !== "photo" ? (
        <span
          aria-hidden="true"
          className="absolute right-1.5 top-1.5 flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[11px] font-bold tabular-nums"
          style={{ background: "var(--media-control)", color: "var(--on-media)" }}
        >
          {tile.kind === "video" ? (
            <>
              {tile.duration}
              <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
                <path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5Z" />
              </svg>
            </>
          ) : (
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinejoin="round">
              <rect x="8" y="8" width="13" height="13" rx="2" />
              <path d="M16 4H5a2 2 0 0 0-2 2v11" />
            </svg>
          )}
        </span>
      ) : null}
    </button>
  );
}

function tileLabel(tile: MediaTile, t: ReturnType<typeof useTranslations<"Social">>): string {
  const what =
    tile.kind === "video" ? t("mediaVideo", { duration: tile.duration ?? "" }) : tile.kind === "album" ? t("mediaAlbum", { count: tile.count }) : t("mediaPhoto");
  return tile.alt ? `${what}: ${tile.alt}` : what;
}
