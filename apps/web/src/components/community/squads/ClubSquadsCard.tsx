"use client";

import { useTranslations } from "next-intl";

import type { CommunityClub } from "@/api/community";
import { HubCard } from "@/components/member-app/HubParts";

import { InvitationRow, SquadRow, useSquads } from "./SquadParts";

/**
 * Κανάλια › Squads (ADR-168): in a gym's club, the invitations waiting for
 * the person and the squads they coach or are in. Nothing for anyone else.
 */
export function ClubSquadsCard({ club }: { club: CommunityClub }) {
  const t = useTranslations("Squads");
  const slug = club.organization_slug ?? null;
  const squads = useSquads(club.kind === "gym" ? slug : null);
  const data = squads.data;
  if (!slug || !data) return null;
  const rows = [...data.coached, ...data.joined];
  if (rows.length === 0 && data.invites.length === 0) return null;

  return (
    <HubCard eyebrow={t("title")}>
      <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
        {data.invites.map((squad) => (
          <InvitationRow key={squad.id} squad={squad} slug={slug} />
        ))}
        {rows.map((squad) => (
          <SquadRow key={squad.id} squad={squad} clubId={club.id} slug={slug} />
        ))}
      </ul>
    </HubCard>
  );
}
