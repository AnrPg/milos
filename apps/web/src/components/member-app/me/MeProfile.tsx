"use client";

import Link from "next/link";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import type { CommunityPost } from "@/api/community";
import { listPRs, type PRRecord } from "@/api/gamification";
import { clubInitials, withoutPinned } from "@/components/community/community";
import { useFeed, useMyClubs } from "@/components/community/use-community";
import { useSession } from "@/components/session-provider";
import { MediaGrid } from "@/components/social/MediaGrid";
import { useUiLocale } from "@/i18n/use-ui-locale";

const TABS = ["posts", "media", "prs", "clubs"] as const;
type Tab = (typeof TABS)[number];

const MY_POSTS = { mine: true };
const SHOWN_PRS = 6;

/**
 * Εγώ's profile half (vision §7.11, mockup «me/mePRs/meClubs»): counts, then
 * «Αναρτήσεις · Πολυμέσα · PRs · Clubs» as tabs: a grid of my posts, my
 * photos and videos (ADR-231), my latest PRs and my clubs, as the people who
 * follow me see them. The fixed list follows.
 */
export function MeProfile({ postsCount, mediaCount }: { postsCount: number; mediaCount: number }) {
  const t = useTranslations("Social");
  const tMe = useTranslations("MemberApp");
  const [tab, setTab] = useState<Tab>("posts");
  const { currentUser } = useSession();
  const clubs = useMyClubs();
  const prs = useMyPrs();
  const shown = profilePrs(prs.data);
  const counts: Record<Tab, number> = {
    posts: postsCount,
    media: mediaCount,
    prs: shown.length,
    clubs: clubs.data?.length ?? 0,
  };

  return (
    <section aria-label={tMe("meProfileTabs")} className="flex flex-col gap-3">
      <div role="tablist" aria-label={tMe("meProfileTabs")} className="grid grid-cols-4 rounded-3xl p-1" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {TABS.map((value) => (
          <button
            key={value}
            type="button"
            role="tab"
            id={`me-tab-${value}`}
            aria-selected={tab === value}
            aria-controls="me-tabpanel"
            onClick={() => setTab(value)}
            className="flex min-h-14 flex-col items-center justify-center rounded-[20px]"
            style={{
              background: tab === value ? "var(--panel-raised)" : "transparent",
              color: tab === value ? "var(--text)" : "var(--dim)",
            }}
          >
            <span className="text-lg font-extrabold leading-tight">{counts[value]}</span>
            <span className="text-xs font-semibold">{t(`personTab.${value}`)}</span>
          </button>
        ))}
      </div>
      <div role="tabpanel" id="me-tabpanel" aria-labelledby={`me-tab-${tab}`}>
        {tab === "posts" ? <PostsGrid /> : null}
        {tab === "media" && currentUser ? <MediaGrid personId={currentUser.id} lock={null} mine /> : null}
        {tab === "prs" ? <PrList shown={shown} hidden={(prs.data?.length ?? 0) - shown.length} pending={prs.isPending} /> : null}
        {tab === "clubs" ? <ClubList /> : null}
      </div>
    </section>
  );
}

function useMyPrs() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  // Same key as the Pantheon's unfiltered list, so both share one cache entry.
  return useQuery({ queryKey: ["prs", ""], enabled: Boolean(token), queryFn: () => listPRs(token!) });
}

/** ADR-196: the profile shows only the PRs I chose to show the people who follow me. */
function profilePrs(prs: PRRecord[] | undefined): PRRecord[] {
  return (prs ?? []).filter((pr) => pr.profile_audience === "followers");
}

function PostsGrid() {
  const t = useTranslations("Social");
  const tMe = useTranslations("MemberApp");
  const feed = useFeed(MY_POSTS);
  const pages = feed.data?.pages ?? [];
  const pinned = pages[0]?.pinned ?? [];
  const posts = [...pinned, ...withoutPinned(pages.flatMap((page) => page.posts ?? []), pinned)];

  if (feed.isPending) return null;
  if (posts.length === 0) return <Note text={t("personPostsEmpty")} />;

  return (
    <div className="flex flex-col gap-2">
      <ul className="grid grid-cols-3 gap-1 overflow-hidden rounded-3xl">
        {posts.slice(0, 9).map((post) => (
          <li key={post.id}>
            <PostTile post={post} />
          </li>
        ))}
      </ul>
      <MoreLink href="/me/posts" label={tMe("meAllPosts")} />
    </div>
  );
}

/** One square of the grid: the post's first photo, or its words. */
function PostTile({ post }: { post: CommunityPost }) {
  const image = post.media?.find((item) => item.status === "ready" && (item.thumb_url || item.feed_url));
  const src = image ? (image.thumb_url ?? image.feed_url) : null;
  const words = post.body?.trim() || attachmentTitle(post) || "";

  return (
    <Link
      href="/me/posts"
      aria-label={words || undefined}
      className="relative flex aspect-square items-center justify-center overflow-hidden p-2 text-center text-xs font-bold"
      style={{ background: "var(--panel-raised)", color: "var(--text)" }}
    >
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
        <img src={src} alt={image?.alt_text ?? ""} className="absolute inset-0 h-full w-full object-cover" />
      ) : (
        <span className="line-clamp-4 break-words">{words}</span>
      )}
    </Link>
  );
}

function attachmentTitle(post: CommunityPost): string | null {
  const title = post.attachment?.title;
  return typeof title === "string" ? title : null;
}

function PrList({ shown, hidden, pending }: { shown: PRRecord[]; hidden: number; pending: boolean }) {
  const t = useTranslations("Social");
  const tMe = useTranslations("MemberApp");
  const locale = useUiLocale();
  if (pending) return null;
  const latest = [...shown].sort((a, b) => b.beaten_on.localeCompare(a.beaten_on)).slice(0, SHOWN_PRS);
  if (latest.length === 0 && hidden === 0) return <Note text={t("prsNone")} />;
  const date = (iso: string) => new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString(locale, { day: "numeric", month: "short" });

  return (
    <div className="flex flex-col gap-2">
      {latest.length === 0 ? <Note text={tMe("mePrsNoneShown")} /> : null}
      <ul className="flex flex-col rounded-3xl px-4 py-1 empty:hidden" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {latest.map((pr) => (
          <li key={pr.id} className="flex min-h-12 items-center gap-3 border-b last:border-b-0" style={{ borderColor: "var(--border)" }}>
            <span aria-hidden="true" style={{ color: "var(--warning)" }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0V4ZM7 6H4a3 3 0 0 0 3 4M17 6h3a3 3 0 0 1-3 4" />
              </svg>
            </span>
            <span className="min-w-0 grow truncate text-sm font-bold" style={{ color: "var(--text)" }}>{pr.name}</span>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{date(pr.beaten_on)}</span>
            <span className="min-w-14 text-right font-mono text-sm" style={{ color: "var(--text)" }}>
              {pr.current_score} {pr.unit}
            </span>
          </li>
        ))}
      </ul>
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        <Link href="/me/sharing#profile-prs" className="underline">
          {hidden > 0 ? tMe("mePrsPrivate", { count: hidden }) : tMe("mePrsWho")}
        </Link>
      </p>
      <MoreLink href="/journal/progress#prs" label={tMe("meAllPrs")} />
    </div>
  );
}

function ClubList() {
  const tMe = useTranslations("MemberApp");
  const clubs = useMyClubs();
  if (clubs.isPending) return null;
  const list = clubs.data ?? [];
  if (list.length === 0) return <Note text={tMe("meClubsNone")} />;

  return (
    <ul className="flex flex-col rounded-3xl px-4 py-1" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      {list.map((club) => (
        <li key={club.id} className="border-b last:border-b-0" style={{ borderColor: "var(--border)" }}>
          <Link href={`/clubs/${club.id}`} className="flex min-h-14 items-center gap-3">
            {club.logo_url ? (
              // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
              <img src={club.logo_url} alt="" className="h-9 w-9 shrink-0 rounded-full object-cover" />
            ) : (
              <span
                aria-hidden="true"
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-extrabold"
                style={{ background: "var(--panel-raised)", color: "var(--text)" }}
              >
                {clubInitials(club.name)}
              </span>
            )}
            <span className="min-w-0 grow truncate text-sm font-bold" style={{ color: "var(--text)" }}>{club.name}</span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

function MoreLink({ href, label }: { href: string; label: string }) {
  return (
    <Link href={href} className="flex min-h-11 items-center text-sm font-bold" style={{ color: "var(--primary-strong, var(--primary))" }}>
      {label} ›
    </Link>
  );
}

function Note({ text }: { text: string }) {
  return (
    <p className="rounded-3xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
      {text}
    </p>
  );
}
