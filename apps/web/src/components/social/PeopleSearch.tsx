"use client";

import Link from "next/link";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { peopleSearchKey, searchPeople, type PeopleSearchPerson } from "@/api/social";
import { useSession } from "@/components/session-provider";
import { FollowButton } from "@/components/social/FollowButton";
import { PersonAvatar } from "@/components/social/PersonAvatar";

import { BuddyBadge } from "./SocialBits";
import { isPeopleSearch, relationKey } from "./social-model";

/**
 * People search across Palee (ADR-193 §4): from two characters on, ranked by
 * the API (your clubs, Buddies, follows, nearby, then anyone public).
 */
export function usePeopleSearch(term: string) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const q = term.trim();
  return useQuery({
    queryKey: peopleSearchKey(q),
    enabled: Boolean(token) && isPeopleSearch(q),
    queryFn: () => searchPeople(token!, q),
    placeholderData: keepPreviousData,
  });
}

/** A search field with a line magnifier, for «Βρες άτομα». */
export function PeopleSearchField({
  id,
  value,
  onChange,
  label,
}: {
  id: string;
  value: string;
  onChange: (value: string) => void;
  label: string;
}) {
  return (
    <div className="relative">
      <label className="sr-only" htmlFor={id}>{label}</label>
      <svg
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        aria-hidden="true"
        className="pointer-events-none absolute start-3.5 top-1/2 -translate-y-1/2"
        style={{ color: "var(--dim)" }}
      >
        <circle cx="11" cy="11" r="7" />
        <path d="m20 20-3.5-3.5" />
      </svg>
      <input
        id={id}
        type="search"
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={label}
        maxLength={80}
        autoComplete="off"
        className="min-h-11 w-full rounded-2xl pe-4 ps-10 text-sm outline-none"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
      />
    </div>
  );
}

/** One result: photo, name, @handle and the tie you have, then Follow. */
export function PersonResultRow({ person }: { person: PeopleSearchPerson }) {
  const t = useTranslations("Social");
  const relation = relationKey(person);
  const name = person.nickname ?? person.handle ?? "?";
  return (
    <li className="flex items-center gap-3 rounded-3xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <Link href={`/people/${person.id}`} className="flex min-w-0 flex-1 items-center gap-3">
        <PersonAvatar name={name} url={person.avatar_url} />
        <span className="min-w-0">
          <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{name}</span>
          <span className="flex min-w-0 items-center gap-1.5 text-xs" style={{ color: "var(--dim)" }}>
            {person.handle ? <span className="truncate">@{person.handle}</span> : null}
            {relation === "buddyBadge" ? (
              <BuddyBadge />
            ) : relation ? (
              <span className="shrink-0">{person.handle ? "· " : ""}{t(relation)}</span>
            ) : null}
          </span>
        </span>
      </Link>
      <div className="shrink-0">
        <FollowButton targetType="user" targetId={person.id} initialStatus={person.my_status} buddy={person.buddy} />
      </div>
    </li>
  );
}

/** The results list, or why it's empty. `null` while the term is too short. */
export function PeopleResults({ term }: { term: string }) {
  const t = useTranslations("Social");
  const found = usePeopleSearch(term);
  if (!isPeopleSearch(term)) return null;
  const people = found.data?.people ?? [];
  if (found.isPending) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (found.isError) return <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t("peopleSearchFailed")}</p>;
  if (people.length === 0)
    return (
      <p className="rounded-3xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
        {t("peopleNoMatch")}
      </p>
    );
  return (
    <ul className="flex flex-col gap-2" aria-live="polite">
      {people.map((person) => (
        <PersonResultRow key={person.id} person={person} />
      ))}
    </ul>
  );
}
