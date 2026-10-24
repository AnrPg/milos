"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import type { CommunityClub } from "@/api/community";
import type { PtSquadsOverview } from "@/api/squads";
import { CountBadge, DashboardCard } from "@/components/admin/DashboardWidgets";
import { gymClubFor } from "@/components/community/community";
import { useMyClubs } from "@/components/community/use-community";
import { HubCard } from "@/components/member-app/HubParts";
import { clientErrorMessage } from "@/components/client/errors";
import { useUiTranslations } from "@/i18n/ui";
import type { useSelectedMembershipRole } from "@/lib/membership-role";

import { CreateSquadSheet, InvitationRow, SquadRow, useSquads } from "./SquadParts";
import { hasSquadContent } from "./squads";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

type Membership = ReturnType<typeof useSelectedMembershipRole>["membership"];

/**
 * «Πελάτες μου › Squads» (ADR-168): the coach's squads, the ones they
 * archived (to bring back) and «Νέο squad». Rendered under the clients block.
 */
export function SquadsSection({ membership }: { membership: Membership }) {
  const t = useTranslations("Squads");
  const slug = membership?.organization.slug ?? null;
  const squads = useSquads(slug);
  const club = useGymClub(membership);
  const [creating, setCreating] = useState(false);
  const data = squads.data;
  if (!slug || !data?.can_create) return null;

  return (
    <DashboardCard
      id="home-my-squads"
      eyebrow={t("title")}
      badge={<CountBadge value={data.coached.length} />}
      action={<NewSquadButton onClick={() => setCreating(true)} />}
    >
      <CoachList data={data} club={club} slug={slug} />
      {creating ? (
        <CreateSquadSheet slug={slug} clients={data.clients} maxMembers={data.limits.max_members} onClose={() => setCreating(false)} />
      ) : null}
    </DashboardCard>
  );
}

/**
 * Box › Squads (ADR-168): invitations to answer and the squads the person is
 * in; for a coach whose Box is their home (`showCoach`) also their own squads
 * and «Νέο squad». Hidden when there is nothing to show.
 */
export function SquadsBoxSection({ membership, showCoach = false }: { membership: Membership; showCoach?: boolean }) {
  const t = useTranslations("Squads");
  const tUi = useUiTranslations();
  const slug = membership?.organization.slug ?? null;
  const squads = useSquads(slug);
  const club = useGymClub(membership);
  const [creating, setCreating] = useState(false);
  const data = squads.data;

  if (squads.isError) {
    return showCoach ? (
      <HubCard eyebrow={t("title")}>
        <ErrorNotice>{clientErrorMessage(squads.error, tUi)}</ErrorNotice>
      </HubCard>
    ) : null;
  }
  if (!slug || !data || !hasSquadContent(data, showCoach || data.coached.length > 0)) return null;
  const coach = data.can_create && (showCoach || data.coached.length > 0);

  return (
    <HubCard eyebrow={t("title")}>
      {data.invites.length > 0 ? (
        <ul aria-label={t("invitesTitle")} className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
          {data.invites.map((squad) => (
            <InvitationRow key={squad.id} squad={squad} slug={slug} />
          ))}
        </ul>
      ) : null}
      {data.joined.length > 0 ? (
        <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
          {data.joined.map((squad) => (
            <SquadRow key={squad.id} squad={squad} clubId={club?.id ?? null} slug={slug} />
          ))}
        </ul>
      ) : null}
      {coach ? (
        <div className="mt-2 flex flex-col gap-3">
          <CoachList data={data} club={club} slug={slug} />
          <NewSquadButton wide onClick={() => setCreating(true)} />
        </div>
      ) : null}
      {creating ? (
        <CreateSquadSheet slug={slug} clients={data.clients} maxMembers={data.limits.max_members} onClose={() => setCreating(false)} />
      ) : null}
    </HubCard>
  );
}

function CoachList({ data, club, slug }: { data: PtSquadsOverview; club: CommunityClub | null; slug: string }) {
  const t = useTranslations("Squads");
  if (data.coached.length === 0 && data.archived.length === 0) {
    return <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("coachedEmpty")}</p>;
  }
  return (
    <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
      {data.coached.map((squad) => (
        <SquadRow key={squad.id} squad={squad} clubId={club?.id ?? null} slug={slug} />
      ))}
      {data.archived.map((squad) => (
        <SquadRow key={squad.id} squad={squad} clubId={club?.id ?? null} slug={slug} />
      ))}
    </ul>
  );
}

function NewSquadButton({ onClick, wide }: { onClick: () => void; wide?: boolean }) {
  const t = useTranslations("Squads");
  return (
    <button
      type="button"
      onClick={onClick}
      className={`min-h-11 rounded-2xl px-4 text-sm font-bold ${wide ? "w-full" : ""}`}
      style={{ border: "1px dashed var(--border)", color: "var(--text)" }}
    >
      + {t("newSquad")}
    </button>
  );
}

function useGymClub(membership: Membership) {
  const clubs = useMyClubs();
  return gymClubFor(clubs.data ?? [], membership?.organization.id) ?? null;
}
