"use client";

import Link from "next/link";
import { useDeferredValue, useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchClubMembers, membersKey, type CommunityClub } from "@/api/community";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";

/**
 * Μέλη (board 7 Q1): everyone in the club but you, coaches first, with a
 * search. People who chose to stay off the list (Κοινοποίηση & ορατότητα)
 * don't show.
 */
export function MembersTab({ club }: { club: Pick<CommunityClub, "id"> }) {
  const t = useTranslations("Clubs");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [query, setQuery] = useState("");
  const q = useDeferredValue(query.trim());
  const members = useQuery({
    queryKey: membersKey(club.id, q),
    enabled: Boolean(token),
    queryFn: () => fetchClubMembers(token!, club.id, q),
    placeholderData: keepPreviousData,
  });
  const rows = members.data?.members ?? [];

  return (
    <HubCard eyebrow={members.data ? t("membersCount", { count: members.data.count }) : t("membersTitle")}>
      <label className="sr-only" htmlFor={`members-${club.id}`}>{t("membersSearch")}</label>
      <input
        id={`members-${club.id}`}
        type="search"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder={t("membersSearch")}
        className="mb-3 min-h-11 w-full rounded-2xl px-3 text-sm"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
      />
      {members.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : rows.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{q ? t("membersNoMatch") : t("membersEmpty")}</p>
      ) : (
        <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
          {rows.map((member) => (
            <li key={member.id}>
              <Link href={`/people/${member.id}`} className="flex min-h-14 items-center gap-3 py-2">
                <PersonAvatar name={member.nickname} url={member.avatar_url} />
                <span className="min-w-0 grow truncate font-bold" style={{ color: "var(--text)" }}>
                  {member.nickname ?? "?"}
                </span>
                {member.coach ? <Badge>{t("coach")}</Badge> : null}
                {member.following ? <Badge muted>{t("following")}</Badge> : null}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </HubCard>
  );
}

export function Badge({ children, muted }: { children: string; muted?: boolean }) {
  return (
    <span
      className="shrink-0 rounded-full px-2.5 py-1 text-xs font-bold"
      style={{
        background: muted ? "var(--panel-raised)" : "color-mix(in srgb, var(--primary) 16%, transparent)",
        color: muted ? "var(--text-soft)" : "var(--primary-strong, var(--primary))",
      }}
    >
      {children}
    </span>
  );
}
