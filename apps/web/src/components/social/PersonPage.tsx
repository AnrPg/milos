"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchPRsSharedWithMe } from "@/api/pr-sharing";
import { fetchPerson, fetchPersonPosts, personKey, type PersonProfile } from "@/api/social";
import { PostCard } from "@/components/community/PostCard";
import { SharedPRCard } from "@/components/pantheon/SharedPRsSection";
import { MessageButton } from "@/components/conversations/MessageButton";
import { useSession } from "@/components/session-provider";
import { FollowButton } from "@/components/social/FollowButton";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { BuddyBadge, CountsLine } from "@/components/social/SocialBits";
import { postsLockKey } from "@/components/social/social-model";

const TABS = ["posts", "prs", "clubs"] as const;
type Tab = (typeof TABS)[number];

/**
 * A person's profile (vision §3: «Αναρτήσεις · PRs · Clubs»; plan §5a Q9,
 * board 5 Q3). Followers posts stay hidden until you follow: at once for a
 * public account, once they accept you for a private one (ADR-193 §2). PRs
 * show only when they share them with you (ADR-129).
 */
export function PersonPage({ id }: { id: string }) {
  const t = useTranslations("Social");
  const router = useRouter();
  const params = useSearchParams();
  const requested = params.get("tab");
  const tab: Tab = TABS.includes(requested as Tab) ? (requested as Tab) : "posts";
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const person = useQuery({ queryKey: personKey(id), enabled: Boolean(token), queryFn: () => fetchPerson(token!, id) });

  if (person.isPending) return <main className="mx-auto w-full max-w-xl p-4" style={{ color: "var(--dim)" }}>{t("loading")}</main>;
  if (!person.data)
    return (
      <main className="mx-auto w-full max-w-xl p-4">
        <p role="alert" style={{ color: "var(--text-soft)" }}>{t("personMissing")}</p>
      </main>
    );
  const profile = person.data;

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-6 pt-4">
      <header className="flex flex-col items-center gap-2 text-center">
        <PersonAvatar name={profile.nickname} url={profile.avatar_url} size={88} />
        <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{profile.nickname ?? "?"}</h1>
        {profile.handle ? <p className="-mt-1 text-sm" style={{ color: "var(--dim)" }}>@{profile.handle}</p> : null}
        {profile.is_me ? null : profile.buddy ? (
          <BuddyBadge />
        ) : profile.follows_me ? (
          <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}>
            {t("followsYou")}
          </span>
        ) : null}
        <CountsLine groups={profile.follow_groups} mine={false} centered />
        {profile.is_me ? null : (
          <FollowButton
            targetType="user"
            targetId={profile.id}
            initialStatus={profile.my_status}
            followsMe={profile.follows_me}
            buddy={profile.buddy}
            wide
          />
        )}
        {profile.is_me ? null : <MessageButton personId={profile.id} name={profile.nickname} wide />}
      </header>

      <div role="tablist" aria-label={profile.nickname ?? ""} className="flex gap-6 border-b" style={{ borderColor: "var(--border)" }}>
        {TABS.map((value) => (
          <button
            key={value}
            type="button"
            role="tab"
            aria-selected={tab === value}
            onClick={() => router.replace(`/people/${id}?tab=${value}`, { scroll: false })}
            className="min-h-11 text-sm font-semibold"
            style={{
              color: tab === value ? "var(--text)" : "var(--dim)",
              boxShadow: tab === value ? "inset 0 -2px var(--primary)" : "none",
            }}
          >
            {t(`personTab.${value}`)}
          </button>
        ))}
      </div>
      <div role="tabpanel" className="flex flex-col gap-3">
        {tab === "posts" ? <Posts profile={profile} /> : null}
        {tab === "prs" ? <Prs profile={profile} /> : null}
        {tab === "clubs" ? <Empty text={t("personClubsEmpty")} /> : null}
      </div>
    </main>
  );
}

function Posts({ profile }: { profile: PersonProfile }) {
  const t = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const posts = useInfiniteQuery({
    queryKey: [...personKey(profile.id), "posts"],
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchPersonPosts(token!, profile.id, pageParam),
    getNextPageParam: (page) => page.next_cursor ?? null,
  });
  const list = posts.data?.pages.flatMap((page) => page.posts) ?? [];
  const lock = postsLockKey(profile);
  const locked = lock !== null;

  return (
    <>
      {posts.isSuccess && list.length === 0 && !locked ? <Empty text={t("personPostsEmpty")} /> : null}
      {list.map((post) => (
        <PostCard key={post.id} post={post} />
      ))}
      {posts.hasNextPage ? (
        <button
          type="button"
          onClick={() => void posts.fetchNextPage()}
          className="min-h-11 rounded-2xl text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("more")}
        </button>
      ) : null}
      {locked ? (
        <p className="flex items-center gap-3 rounded-3xl p-4 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true" className="shrink-0">
            <rect width="18" height="11" x="3" y="11" rx="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
          {t(lock)}
        </p>
      ) : null}
    </>
  );
}

function Prs({ profile }: { profile: PersonProfile }) {
  const t = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const shared = useQuery({
    queryKey: ["pr-sharing", "shared-with-me"],
    enabled: Boolean(token) && !profile.is_me,
    queryFn: () => fetchPRsSharedWithMe(token!),
  });
  if (profile.is_me)
    return (
      <Link href="/journal/progress#prs" className="rounded-3xl p-4 text-sm font-semibold" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}>
        {t("myPrsLink")}
      </Link>
    );
  const collection = shared.data?.shared.find((entry) => entry.owner.id === profile.id);
  if (shared.isPending) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (!collection) return <Empty text={t("prsNotShared")} />;
  if (collection.prs.length === 0) return <Empty text={t("prsNone")} />;
  return (
    <div className="flex flex-col gap-2">
      {collection.prs.map((pr) => (
        <SharedPRCard key={pr.id} pr={pr} />
      ))}
    </div>
  );
}

function Empty({ text }: { text: string }) {
  return (
    <p className="rounded-3xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
      {text}
    </p>
  );
}
