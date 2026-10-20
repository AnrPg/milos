"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  CLUBS_KEY,
  FEED_KEY,
  fetchGroups,
  groupsKey,
  joinGroup,
  reopenGroup,
  type CommunityClub,
  type CommunityGroup,
} from "@/api/community";
import { clientErrorMessage } from "@/components/client/errors";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

import { Badge } from "./MembersTab";
import { ProposeGroupSheet } from "./ProposeGroupSheet";
import { ErrorLine } from "./Sheet";

/**
 * Κανάλια › Ομάδες μελών (board 7 Q2): the gym club's live groups with an
 * «Ομάδα μελών» label, the member's own proposals waiting for staff, the
 * groups they started that were archived (to bring back), and «Πρότεινε
 * ομάδα» when the gym allows it.
 */
export function GroupsCard({ club }: { club: CommunityClub }) {
  const t = useTranslations("Clubs");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [proposing, setProposing] = useState(false);
  const groups = useQuery({
    queryKey: groupsKey(club.id),
    enabled: Boolean(token && club.organization_slug),
    queryFn: () => fetchGroups(token!, club.organization_slug!),
  });

  const settings = groups.data?.settings;
  const live = groups.data?.groups ?? [];
  const pending = club.channels.filter((channel) => channel.kind === "member_group" && channel.status === "pending");
  const archived = groups.data?.archived ?? [];
  if (!groups.data || (settings?.member_groups === "none" && live.length === 0 && pending.length === 0)) return null;

  return (
    <HubCard eyebrow={t("groupsTitle")}>
      {live.length === 0 && pending.length === 0 ? (
        <p className="mb-3 text-sm" style={{ color: "var(--text-soft)" }}>{t("groupsEmpty")}</p>
      ) : (
        <ul className="mb-3 flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
          {pending.map((channel) => (
            <li key={channel.id} className="flex min-h-14 items-center gap-3 py-2">
              <Link href={`/clubs/${club.id}/groups/${channel.id}`} className="min-w-0 grow">
                <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{channel.name}</span>
                <span className="text-xs" style={{ color: "var(--dim)" }}>{t("groupLabel")}</span>
              </Link>
              <Badge muted>{t("groupPending")}</Badge>
            </li>
          ))}
          {live.map((group) => (
            <GroupRow key={group.id} club={club} group={group} />
          ))}
        </ul>
      )}
      {archived.length > 0 ? (
        <ul className="mb-3 flex flex-col gap-2">
          {archived.map((group) => (
            <ArchivedRow key={group.id} club={club} group={group} />
          ))}
        </ul>
      ) : null}
      {settings?.can_propose ? (
        <button
          type="button"
          onClick={() => setProposing(true)}
          className="min-h-11 w-full rounded-2xl text-sm font-bold"
          style={{ border: "1px dashed var(--border)", color: "var(--text)" }}
        >
          + {t("proposeTitle")}
        </button>
      ) : null}
      {proposing ? (
        <ProposeGroupSheet club={club} needsApproval={Boolean(settings?.needs_approval)} onClose={() => setProposing(false)} />
      ) : null}
    </HubCard>
  );
}

function GroupRow({ club, group }: { club: CommunityClub; group: CommunityGroup }) {
  const t = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const join = useMutation({
    mutationFn: () => joinGroup(tokens!.access_token, club.organization_slug!, group.id),
    onSuccess: () =>
      Promise.all([
        queryClient.invalidateQueries({ queryKey: groupsKey(club.id) }),
        queryClient.invalidateQueries({ queryKey: CLUBS_KEY }),
        queryClient.invalidateQueries({ queryKey: FEED_KEY }),
      ]),
  });

  return (
    <li className="flex min-h-14 flex-col gap-1 py-2">
      <div className="flex items-center gap-3">
        <Link href={`/clubs/${club.id}/groups/${group.id}`} className="min-w-0 grow">
          <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{group.name}</span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
            {t("groupLabel")} · {t("groupMembers", { count: group.member_count })}
            {group.description ? ` · ${group.description}` : ""}
          </span>
        </Link>
        {group.membership === "member" ? (
          <Badge muted>{group.admin ? t("groupAdmin") : t("groupIn")}</Badge>
        ) : group.membership === "requested" ? (
          <Badge muted>{t("groupRequested")}</Badge>
        ) : (
          <button
            type="button"
            disabled={join.isPending}
            onClick={() => join.mutate()}
            className="min-h-11 shrink-0 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--bg)" }}
          >
            {group.join_policy === "request" ? t("groupAsk") : t("groupJoin")}
          </button>
        )}
      </div>
      <ErrorLine message={join.error ? clientErrorMessage(join.error, tUi) : null} />
    </li>
  );
}

function ArchivedRow({ club, group }: { club: CommunityClub; group: CommunityGroup }) {
  const t = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const reopen = useMutation({
    mutationFn: () => reopenGroup(tokens!.access_token, club.organization_slug!, group.id),
    onSuccess: () =>
      Promise.all([
        queryClient.invalidateQueries({ queryKey: groupsKey(club.id) }),
        queryClient.invalidateQueries({ queryKey: CLUBS_KEY }),
      ]),
  });

  return (
    <li className="flex flex-col gap-1 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)" }}>
      <div className="flex items-center gap-3">
        <span className="min-w-0 grow">
          <span className="block truncate text-sm font-bold" style={{ color: "var(--text)" }}>{group.name}</span>
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("groupArchived")}</span>
        </span>
        <button
          type="button"
          disabled={reopen.isPending}
          onClick={() => reopen.mutate()}
          className="min-h-11 shrink-0 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("groupReopen")}
        </button>
      </div>
      <ErrorLine message={reopen.error ? clientErrorMessage(reopen.error, tUi) : null} />
    </li>
  );
}
