"use client";

import Link from "next/link";
import { useDeferredValue, useState } from "react";
import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { AROUND_KEY } from "@/api/around";
import {
  CLUBS_KEY,
  discoverKey,
  FEED_KEY,
  fetchDiscover,
  joinGroup,
  setOpenClubJoined,
  type CommunityGroup,
  type OpenClub,
} from "@/api/community";
import { NearbyClubs } from "@/components/around/Nearby";
import { clientErrorMessage } from "@/components/client/errors";
import { ListFilters } from "@/components/filters/ListFilters";
import { distinctOptions, picked } from "@/components/filters/list-filter";
import { useListFilter } from "@/components/filters/use-remembered-filter";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { BoxResultRow, useBoxSearch } from "@/components/social/BoxSearch";
import { PersonResultRow, usePeopleSearch } from "@/components/social/PeopleSearch";
import { isPeopleSearch } from "@/components/social/social-model";
import { useDebounced } from "@/hooks/useDebounced";
import { useUiTranslations } from "@/i18n/ui";

import { ClubBar } from "./ClubBar";
import { clubInitials } from "./community";
import { SmallButton } from "./GroupPage";
import { Badge } from "./MembersTab";
import { ErrorLine } from "./Sheet";
import { useMyClubs } from "./use-community";

/** Kind and box (vision §7.2 «Find»), remembered on `find_clubs`; client-side, the list is one page. */
const FIND_SHAPE = { kind: "one", box: "many" } as const;

/**
 * «+ Βρες» (board 7 Q7): open clubs of the boxes you belong to or follow, and
 * member groups of your gyms you're not in, with a search, and «Κοντά μου»:
 * open clubs near you from Γύρω μου (ADR-154). The search finds people on
 * Palee too (ADR-193 §4), and boxes and coaches by name (ADR-221), each in
 * a card shown only when something matches.
 */
export function FindPage() {
  const t = useTranslations("Clubs");
  const tSocial = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const clubs = useMyClubs();
  const [query, setQuery] = useState("");
  const q = useDeferredValue(query.trim());
  const found = useQuery({
    queryKey: discoverKey(q),
    enabled: Boolean(token),
    queryFn: () => fetchDiscover(token!, q),
    placeholderData: keepPreviousData,
  });
  const allClubs = found.data?.clubs ?? [];
  const allGroups = (found.data?.groups ?? []).filter((group) => group.membership !== "member");
  const { filter, setFilter } = useListFilter("find_clubs", FIND_SHAPE);
  const kind = filter?.kind[0] ?? null;
  const boxes = filter?.box ?? [];
  const openClubs = kind === "groups" ? [] : allClubs.filter((club) => picked(boxes, club.box?.slug));
  const groups = kind === "clubs" ? [] : allGroups.filter((group) => picked(boxes, group.club?.organization_slug));
  const narrowed = kind !== null || boxes.length > 0;
  const kinds = [
    ...(allClubs.length > 0 ? [{ value: "clubs", label: t("findOpenClubs") }] : []),
    ...(allGroups.length > 0 ? [{ value: "groups", label: t("findGroups") }] : []),
  ];
  const boxOptions = [
    ...distinctOptions(allClubs, (club) => club.box?.slug, (club) => club.box?.name ?? ""),
    ...distinctOptions(allGroups, (group) => group.club?.organization_slug, (group) => group.club?.name ?? ""),
  ].filter((option, index, all) => all.findIndex((other) => other.value === option.value) === index);
  // ADR-193 §4: the same field finds people too, from two characters on.
  const peopleTerm = useDebounced(q, 250);
  const people = usePeopleSearch(peopleTerm);
  const peopleFound = isPeopleSearch(q) && isPeopleSearch(peopleTerm) ? (people.data?.people ?? []) : [];
  const boxSearch = useBoxSearch(peopleTerm);
  const boxesFound = isPeopleSearch(q) && isPeopleSearch(peopleTerm) ? (boxSearch.data?.boxes ?? []) : [];

  return (
    <HubPage title={t("findTitle")}>
      <ClubBar clubs={clubs.data ?? []} findActive />
      <label className="sr-only" htmlFor="find-clubs">{tSocial("findClubsBoxesPeople")}</label>
      <input
        id="find-clubs"
        type="search"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder={tSocial("findClubsBoxesPeople")}
        className="min-h-11 w-full rounded-2xl px-3 text-sm"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
      />
      {filter && !found.isPending ? (
        <ListFilters
          shape={FIND_SHAPE}
          fields={[
            { key: "kind", label: t("filterKind"), options: kinds },
            { key: "box", label: t("filterBox"), options: boxOptions },
          ]}
          filter={filter}
          onChange={setFilter}
          title={t("findFiltersTitle")}
          resultCount={openClubs.length + groups.length}
        />
      ) : null}
      {found.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : (
        <>
          {kind !== "groups" ? (
            <HubCard eyebrow={t("findOpenClubs")}>
              {openClubs.length === 0 ? (
                <p className="text-sm" style={{ color: "var(--text-soft)" }}>{q || narrowed ? t("findNoMatch") : t("findNoClubs")}</p>
              ) : (
                <ul className="flex flex-col gap-3">
                  {openClubs.map((club) => (
                    <OpenClubRow key={club.id} club={club} />
                  ))}
                </ul>
              )}
            </HubCard>
          ) : groups.length === 0 ? (
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("findNoMatch")}</p>
          ) : null}
          {groups.length > 0 ? (
            <HubCard eyebrow={t("findGroups")}>
              <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
                {groups.map((group) => (
                  <GroupResult key={group.id} group={group} />
                ))}
              </ul>
            </HubCard>
          ) : null}
          {/* Only while a search finds something: no empty card (vision §4 principle 2). */}
          {boxesFound.length > 0 ? (
            <HubCard eyebrow={tSocial("boxesTitle")}>
              <ul className="flex flex-col gap-2">
                {boxesFound.map((box) => (
                  <BoxResultRow key={box.organization_id} box={box} />
                ))}
              </ul>
            </HubCard>
          ) : null}
          {peopleFound.length > 0 ? (
            <HubCard eyebrow={tSocial("peopleTitle")}>
              <ul className="flex flex-col gap-2">
                {peopleFound.map((person) => (
                  <PersonResultRow key={person.id} person={person} />
                ))}
              </ul>
            </HubCard>
          ) : null}
          <NearbyClubs />
        </>
      )}
    </HubPage>
  );
}

function useDiscoverRefresh() {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: ["community", "discover"] }),
      queryClient.invalidateQueries({ queryKey: CLUBS_KEY }),
      queryClient.invalidateQueries({ queryKey: FEED_KEY }),
      queryClient.invalidateQueries({ queryKey: AROUND_KEY }),
    ]);
}

/** An open club with «Μπες» (or «Αίτημα»); `detail` adds e.g. the distance (Γύρω μου). */
export function OpenClubRow({ club, detail }: { club: OpenClub; detail?: string }) {
  const t = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const refresh = useDiscoverRefresh();
  const join = useMutation({ mutationFn: () => setOpenClubJoined(tokens!.access_token, club.id, true), onSuccess: refresh });

  return (
    <li className="flex flex-col gap-2 overflow-hidden rounded-2xl" style={{ background: "var(--panel-raised)" }}>
      {club.cover_url ? (
        // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
        <img src={club.cover_url} alt="" className="aspect-[16/6] w-full object-cover" />
      ) : null}
      <div className="flex items-center gap-3 px-4 pb-3" style={{ paddingTop: club.cover_url ? 0 : 12 }}>
        {!club.cover_url ? (
          <span
            aria-hidden="true"
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-sm font-extrabold"
            style={{ background: "var(--panel)", color: "var(--text)" }}
          >
            {clubInitials(club.name)}
          </span>
        ) : null}
        <Link href={`/clubs/${club.id}`} className="min-w-0 grow">
          <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{club.name}</span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
            {[club.box?.name, t("clubMembers", { count: club.member_count }), detail].filter(Boolean).join(" · ")}
          </span>
        </Link>
        {club.membership === "member" || club.role === "staff" ? (
          <Badge muted>{t("groupIn")}</Badge>
        ) : club.membership === "requested" ? (
          <Badge muted>{t("groupRequested")}</Badge>
        ) : (
          <SmallButton spark disabled={join.isPending} onClick={() => join.mutate()}>
            {club.join_policy === "approval" ? t("clubAsk") : t("clubJoin")}
          </SmallButton>
        )}
      </div>
      {join.error ? (
        <div className="px-4 pb-3">
          <ErrorLine message={clientErrorMessage(join.error, tUi)} />
        </div>
      ) : null}
    </li>
  );
}

function GroupResult({ group }: { group: CommunityGroup }) {
  const t = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const refresh = useDiscoverRefresh();
  const slug = group.club?.organization_slug;
  const join = useMutation({ mutationFn: () => joinGroup(tokens!.access_token, slug!, group.id), onSuccess: refresh });

  return (
    <li className="flex flex-col gap-1 py-2">
      <div className="flex min-h-12 items-center gap-3">
        <Link href={`/clubs/${group.club_id}/groups/${group.id}`} className="min-w-0 grow">
          <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{group.name}</span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
            {[group.club?.name, t("groupMembers", { count: group.member_count })].filter(Boolean).join(" · ")}
          </span>
        </Link>
        {group.membership === "requested" ? (
          <Badge muted>{t("groupRequested")}</Badge>
        ) : slug ? (
          <SmallButton spark disabled={join.isPending} onClick={() => join.mutate()}>
            {group.join_policy === "request" ? t("groupAsk") : t("groupJoin")}
          </SmallButton>
        ) : null}
      </div>
      <ErrorLine message={join.error ? clientErrorMessage(join.error, tUi) : null} />
    </li>
  );
}
