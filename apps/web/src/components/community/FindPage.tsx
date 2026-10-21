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
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

import { ClubBar } from "./ClubBar";
import { clubInitials } from "./community";
import { SmallButton } from "./GroupPage";
import { Badge } from "./MembersTab";
import { ErrorLine } from "./Sheet";
import { useMyClubs } from "./use-community";

/**
 * «+ Βρες» (board 7 Q7): open clubs of the boxes you belong to or follow, and
 * member groups of your gyms you're not in, with a search, and «Κοντά μου»:
 * open clubs near you from Γύρω μου (ADR-154).
 */
export function FindPage() {
  const t = useTranslations("Clubs");
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
  const openClubs = found.data?.clubs ?? [];
  const groups = (found.data?.groups ?? []).filter((group) => group.membership !== "member");

  return (
    <HubPage title={t("findTitle")}>
      <ClubBar clubs={clubs.data ?? []} findActive />
      <label className="sr-only" htmlFor="find-clubs">{t("findSearch")}</label>
      <input
        id="find-clubs"
        type="search"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder={t("findSearch")}
        className="min-h-11 w-full rounded-2xl px-3 text-sm"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
      />
      {found.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : (
        <>
          <HubCard eyebrow={t("findOpenClubs")}>
            {openClubs.length === 0 ? (
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{q ? t("findNoMatch") : t("findNoClubs")}</p>
            ) : (
              <ul className="flex flex-col gap-3">
                {openClubs.map((club) => (
                  <OpenClubRow key={club.id} club={club} />
                ))}
              </ul>
            )}
          </HubCard>
          {groups.length > 0 ? (
            <HubCard eyebrow={t("findGroups")}>
              <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
                {groups.map((group) => (
                  <GroupResult key={group.id} group={group} />
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
          <SmallButton primary disabled={join.isPending} onClick={() => join.mutate()}>
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
          <SmallButton primary disabled={join.isPending} onClick={() => join.mutate()}>
            {group.join_policy === "request" ? t("groupAsk") : t("groupJoin")}
          </SmallButton>
        ) : null}
      </div>
      <ErrorLine message={join.error ? clientErrorMessage(join.error, tUi) : null} />
    </li>
  );
}
