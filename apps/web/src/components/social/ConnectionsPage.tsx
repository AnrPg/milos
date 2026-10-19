"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { useInfiniteQuery, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchPRSharing, fetchPRsSharedWithMe } from "@/api/pr-sharing";
import {
  fetchFollowers,
  fetchFollowing,
  removeFollower,
  SOCIAL_KEY,
  type FollowEntry,
  type FollowPage,
} from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { useMyClubs } from "@/components/community/use-community";
import { HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { BookingSharingOffer } from "@/components/social/BookingSharing";
import { FollowButton } from "@/components/social/FollowButton";
import { FollowRequestsRow } from "@/components/social/FollowRequestsRow";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useSocialSummary } from "@/components/social/use-social";
import { useUiTranslations } from "@/i18n/ui";

const TABS = ["followers", "following", "boxes", "clubs", "prs"] as const;
type Tab = (typeof TABS)[number];

/**
 * Connections (plan §5a Q12), opened from the line under the name in Εγώ:
 * followers (with pending requests on top), people and boxes followed, the
 * member's clubs and PR sharing in both directions.
 */
export function ConnectionsPage() {
  const t = useTranslations("Social");
  const router = useRouter();
  const params = useSearchParams();
  const requested = params.get("tab");
  const tab: Tab = TABS.includes(requested as Tab) ? (requested as Tab) : "followers";
  const summary = useSocialSummary();

  const label = (value: Tab) => {
    switch (value) {
      case "followers":
        return t("tabFollowers", { count: summary.data?.followers_count ?? 0 });
      case "following":
        return t("tabFollowing", { count: summary.data?.following_count ?? 0 });
      case "boxes":
        return t("tabBoxes");
      case "clubs":
        return t("tabClubs");
      case "prs":
        return t("tabPrs");
    }
  };

  return (
    <HubPage title={t("connectionsTitle")}>
      <div role="tablist" aria-label={t("connectionsTitle")} className="-mx-4 flex gap-1 overflow-x-auto px-4">
        {TABS.map((value) => (
          <button
            key={value}
            type="button"
            role="tab"
            aria-selected={tab === value}
            onClick={() => router.replace(`/me/connections?tab=${value}`, { scroll: false })}
            className="min-h-11 shrink-0 rounded-full px-4 text-sm font-semibold"
            style={
              tab === value
                ? { background: "var(--primary)", color: "var(--bg)" }
                : { background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border)" }
            }
          >
            {label(value)}
          </button>
        ))}
      </div>
      <div role="tabpanel" className="flex flex-col gap-2">
        {tab === "followers" ? <Followers /> : null}
        {tab === "following" ? <People type="user" /> : null}
        {tab === "boxes" ? <People type="organization" /> : null}
        {tab === "clubs" ? <Clubs /> : null}
        {tab === "prs" ? <PrSharing /> : null}
      </div>
    </HubPage>
  );
}

function usePaged(key: readonly unknown[], fetch: (token: string, cursor: string | null) => Promise<FollowPage>) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useInfiniteQuery({
    queryKey: key,
    enabled: Boolean(token),
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetch(token!, pageParam),
    getNextPageParam: (page) => page.next_cursor ?? null,
  });
}

function List({ query, empty, render }: { query: ReturnType<typeof usePaged>; empty: string; render: (entry: FollowEntry) => React.ReactNode }) {
  const t = useTranslations("Social");
  const entries = query.data?.pages.flatMap((page) => page.entries) ?? [];
  return (
    <>
      {query.isPending ? <p style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
      {query.isSuccess && entries.length === 0 ? <Empty text={empty} /> : null}
      <ul className="flex flex-col gap-2">{entries.map(render)}</ul>
      {query.hasNextPage ? (
        <button
          type="button"
          onClick={() => void query.fetchNextPage()}
          className="min-h-11 rounded-2xl text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("more")}
        </button>
      ) : null}
    </>
  );
}

function Followers() {
  const t = useTranslations("Social");
  const query = usePaged([...SOCIAL_KEY, "followers"], fetchFollowers);
  return (
    <>
      <FollowRequestsRow />
      <BookingSharingOffer />
      <List
        query={query}
        empty={t("followersEmpty")}
        render={(entry) =>
          entry.person ? (
            <PersonRow key={entry.follow_id} entry={entry}>
              <FollowButton targetType="user" targetId={entry.person.id} initialStatus={entry.person.my_status} followsMe />
              <RemoveFollower followId={entry.follow_id} />
            </PersonRow>
          ) : null
        }
      />
    </>
  );
}

function People({ type }: { type: "user" | "organization" }) {
  const t = useTranslations("Social");
  const query = usePaged([...SOCIAL_KEY, "following", type], (token, cursor) => fetchFollowing(token, type, cursor));
  return (
    <List
      query={query}
      empty={type === "user" ? t("followingEmpty") : t("boxesEmpty")}
      render={(entry) =>
        entry.person ? (
          <PersonRow key={entry.follow_id} entry={entry}>
            <FollowButton targetType="user" targetId={entry.person.id} initialStatus={entry.status} />
          </PersonRow>
        ) : entry.box ? (
          <Row key={entry.follow_id} href={`/b/${entry.box.slug}`} name={entry.box.name} image={entry.box.logo_url}>
            <FollowButton targetType="organization" targetId={entry.box.organization_id} initialStatus={entry.status} />
          </Row>
        ) : null
      }
    />
  );
}

function PersonRow({ entry, children }: { entry: FollowEntry; children: React.ReactNode }) {
  const person = entry.person!;
  return (
    <Row href={`/people/${person.id}`} name={person.nickname ?? "?"} image={person.avatar_url}>
      {children}
    </Row>
  );
}

function Row({ href, name, image, children }: { href: string; name: string; image?: string | null; children?: React.ReactNode }) {
  return (
    <li className="flex items-center gap-3 rounded-3xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <Link href={href} className="flex min-w-0 flex-1 items-center gap-3">
        <PersonAvatar name={name} url={image} />
        <span className="truncate font-bold" style={{ color: "var(--text)" }}>{name}</span>
      </Link>
      <div className="flex shrink-0 items-center gap-2">{children}</div>
    </li>
  );
}

function RemoveFollower({ followId }: { followId: string }) {
  const t = useTranslations("Social");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function remove() {
    if (!tokens?.access_token) return;
    try {
      await removeFollower(tokens.access_token, followId);
      await queryClient.invalidateQueries({ queryKey: SOCIAL_KEY });
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={() => (confirming ? void remove() : setConfirming(true))}
        onBlur={() => setConfirming(false)}
        className="min-h-11 rounded-2xl px-3 text-xs font-semibold"
        style={{ color: confirming ? "var(--danger, #dc2626)" : "var(--dim)", border: "1px solid var(--border)" }}
      >
        {confirming ? t("removeConfirm") : t("remove")}
      </button>
      {error ? <span role="alert" className="sr-only">{error}</span> : null}
    </>
  );
}

function Clubs() {
  const t = useTranslations("Social");
  const clubs = useMyClubs();
  if (clubs.isPending) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if ((clubs.data ?? []).length === 0) return <Empty text={t("clubsEmpty")} />;
  return (
    <ul className="flex flex-col gap-2">
      {(clubs.data ?? []).map((club) => (
        <Row key={club.id} href={`/clubs/${club.id}`} name={club.name} image={club.logo_url ?? undefined} />
      ))}
    </ul>
  );
}

function PrSharing() {
  const t = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const mine = useQuery({ queryKey: ["pr-sharing"], enabled: Boolean(token), queryFn: () => fetchPRSharing(token!) });
  const withMe = useQuery({ queryKey: ["pr-sharing", "shared-with-me"], enabled: Boolean(token), queryFn: () => fetchPRsSharedWithMe(token!) });

  return (
    <>
      <h2 className="mt-2 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("prsWithMe")}</h2>
      {withMe.isSuccess && withMe.data.shared.length === 0 ? <Empty text={t("prsWithMeEmpty")} /> : null}
      <ul className="flex flex-col gap-2">
        {(withMe.data?.shared ?? []).map((collection) => (
          <Row
            key={collection.owner.id}
            href={`/people/${collection.owner.id}?tab=prs`}
            name={collection.owner.display_nickname}
            image={collection.owner.avatar_url}
          >
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t("prsCount", { count: collection.prs.length })}</span>
          </Row>
        ))}
      </ul>
      <h2 className="mt-4 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("prsByMe")}</h2>
      {mine.isSuccess && mine.data.grants.length === 0 ? <Empty text={t("prsByMeEmpty")} /> : null}
      <ul className="flex flex-col gap-2">
        {(mine.data?.grants ?? []).map((grant) => (
          <Row key={grant.id} href={`/people/${grant.grantee.id}`} name={grant.grantee.display_nickname} />
        ))}
      </ul>
      <Link
        href="/me/sharing"
        className="mt-2 flex min-h-11 items-center justify-center rounded-2xl text-sm font-semibold"
        style={{ border: "1px solid var(--border)", color: "var(--text)" }}
      >
        {t("prsManage")}
      </Link>
    </>
  );
}

function Empty({ text }: { text: string }) {
  return (
    <p className="rounded-3xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
      {text}
    </p>
  );
}

