"use client";

import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import type { CommunityClub } from "@/api/community";
import {
  answerSquadInvite,
  archiveSquad,
  fetchSquad,
  leaveSquad,
  removeFromSquad,
  squadKey,
  updateSquad,
  type PtSquad,
  type PtSquadMember,
} from "@/api/squads";
import { clientErrorMessage } from "@/components/client/errors";
import { ComposeButton } from "@/components/community/ComposeSheet";
import { FeedList } from "@/components/community/FeedList";
import { Badge } from "@/components/community/MembersTab";
import { MoreMenu } from "@/components/community/PostCard";
import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { useClubRealtime, useMyClubs } from "@/components/community/use-community";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { InviteClientsSheet, SmallAction, useSquadRefresh, useSquads } from "./SquadParts";
import { seatsLeft } from "./squads";

/**
 * A PT squad (ADR-168): its posts and people for the coach and its members;
 * an invitation to answer for someone invited. The coach invites more of
 * their clients, removes people, renames and archives; a member may leave.
 */
export function SquadPage({ clubId, squadId }: { clubId: string; squadId: string }) {
  const t = useTranslations("Squads");
  const clubs = useMyClubs();
  useClubRealtime(clubs.data);
  const club = clubs.data?.find((entry) => entry.id === clubId);
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const squad = useQuery({
    queryKey: squadKey(squadId),
    enabled: Boolean(token && club?.organization_slug),
    queryFn: () => fetchSquad(token!, club!.organization_slug!, squadId),
    retry: false,
  });

  if (clubs.isPending || (club && squad.isPending)) {
    return (
      <HubPage title={t("label")}>
        <p style={{ color: "var(--dim)" }}>{t("loading")}</p>
      </HubPage>
    );
  }
  if (!club || !squad.data) {
    return (
      <HubPage title={t("label")}>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("notFound")}</p>
        <Link href={club ? `/clubs/${club.id}` : "/"} className="text-sm font-semibold underline" style={{ color: "var(--text)" }}>
          {t("backToClub")}
        </Link>
      </HubPage>
    );
  }
  return <SquadView club={club} clubs={clubs.data ?? []} squad={squad.data} />;
}

function SquadView({ club, clubs, squad }: { club: CommunityClub; clubs: CommunityClub[]; squad: PtSquad }) {
  const t = useTranslations("Squads");
  const [tab, setTab] = useState<"feed" | "members">(squad.role === "invited" ? "members" : "feed");
  const canPost = club.channels.some((channel) => channel.id === squad.id && channel.can_post);

  return (
    <HubPage title={squad.name} actions={canPost ? <ComposeButton clubs={clubs} clubId={club.id} channelId={squad.id} /> : null}>
      <Link href={`/clubs/${club.id}`} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
        ‹ {club.name}
      </Link>
      <HubCard>
        <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {t("label")} · {t("members", { count: squad.member_count })}
        </p>
        <div className="mt-2 flex items-center gap-3">
          <PersonAvatar name={squad.coach.nickname} url={squad.coach.avatar_url} size={32} />
          <p className="text-sm" style={{ color: "var(--text)" }}>{t("coachedBy", { coach: squad.coach.nickname ?? "?" })}</p>
        </div>
        {squad.description ? <p className="mt-2 text-sm" style={{ color: "var(--text)" }}>{squad.description}</p> : null}
        <p className="mt-2 text-xs" style={{ color: "var(--text-soft)" }}>
          {squad.role === "coach" ? t("followsCoaching") : t("privacyNote", { coach: squad.coach.nickname ?? "?" })}
        </p>
        <SquadActions club={club} squad={squad} />
      </HubCard>
      {squad.role === "invited" ? null : (
        <div role="tablist" aria-label={squad.name} className="flex gap-2">
          {(["feed", "members"] as const).map((id) => (
            <button
              key={id}
              type="button"
              role="tab"
              aria-selected={tab === id}
              onClick={() => setTab(id)}
              className="min-h-11 flex-1 rounded-2xl text-sm font-semibold"
              style={{
                background: tab === id ? "var(--primary)" : "var(--panel)",
                color: tab === id ? "var(--bg)" : "var(--text)",
                border: "1px solid var(--border)",
              }}
            >
              {id === "feed" ? t("tabFeed") : t("tabMembers")}
            </button>
          ))}
        </div>
      )}
      {squad.role !== "invited" && tab === "feed" ? (
        <FeedList filter={{ clubId: club.id, channelId: squad.id }} />
      ) : squad.role !== "invited" ? (
        <SquadMembers club={club} squad={squad} />
      ) : null}
    </HubPage>
  );
}

function SquadActions({ club, squad }: { club: CommunityClub; squad: PtSquad }) {
  const t = useTranslations("Squads");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const router = useRouter();
  const slug = club.organization_slug!;
  const refresh = useSquadRefresh(slug, squad.id);
  const overview = useSquads(squad.role === "coach" ? slug : null);
  const [sheet, setSheet] = useState<"invite" | "edit" | "leave" | "archive" | null>(null);
  const done = async () => {
    setSheet(null);
    await refresh();
    router.push(`/clubs/${club.id}`);
  };

  const answer = useMutation({
    mutationFn: (accept: boolean) => answerSquadInvite(tokens!.access_token, slug, squad.id, accept),
    onSuccess: async (_data, accept) => (accept ? refresh() : done()),
  });
  const leave = useMutation({ mutationFn: () => leaveSquad(tokens!.access_token, slug, squad.id), onSuccess: done });
  const archive = useMutation({ mutationFn: () => archiveSquad(tokens!.access_token, slug, squad.id), onSuccess: done });
  const failure = answer.error ?? leave.error ?? archive.error;
  const maxMembers = overview.data?.limits.max_members ?? 30;

  return (
    <div className="mt-3 flex flex-col gap-2">
      {squad.role === "invited" ? (
        <>
          <p className="rounded-2xl px-3 py-2 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
            {t("invitedBanner", { coach: squad.coach.nickname ?? "?" })}
          </p>
          <div className="flex gap-2">
            <SheetButton disabled={answer.isPending} onClick={() => answer.mutate(false)}>{t("decline")}</SheetButton>
            <SheetButton primary disabled={answer.isPending} onClick={() => answer.mutate(true)}>{t("accept")}</SheetButton>
          </div>
        </>
      ) : squad.role === "coach" ? (
        <div className="flex flex-wrap gap-2">
          <SheetButton primary disabled={!overview.data} onClick={() => setSheet("invite")}>{t("invite")}</SheetButton>
          <SheetButton onClick={() => setSheet("edit")}>{t("edit")}</SheetButton>
          <SheetButton onClick={() => setSheet("archive")}>{t("archive")}</SheetButton>
        </div>
      ) : (
        <div className="flex gap-2">
          <SheetButton onClick={() => setSheet("leave")}>{t("leave")}</SheetButton>
        </div>
      )}
      <ErrorLine message={failure ? clientErrorMessage(failure, tUi) : null} />
      {sheet === "invite" && overview.data ? (
        <InviteClientsSheet
          slug={slug}
          squad={squad}
          members={squad.members ?? []}
          clients={overview.data.clients}
          seats={seatsLeft(squad, maxMembers)}
          onClose={() => setSheet(null)}
        />
      ) : null}
      {sheet === "edit" ? <EditSquadSheet slug={slug} squad={squad} onClose={() => setSheet(null)} /> : null}
      {sheet === "leave" || sheet === "archive" ? (
        <Sheet
          labelId="squad-confirm"
          eyebrow={squad.name}
          title={sheet === "leave" ? t("leaveTitle") : t("archiveTitle")}
          onClose={() => setSheet(null)}
          footer={
            <>
              <SheetButton onClick={() => setSheet(null)}>{t("cancel")}</SheetButton>
              <SheetButton
                primary
                disabled={leave.isPending || archive.isPending}
                onClick={() => (sheet === "leave" ? leave.mutate() : archive.mutate())}
              >
                {sheet === "leave" ? t("leave") : t("archive")}
              </SheetButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{sheet === "leave" ? t("leaveBody") : t("archiveBody")}</p>
        </Sheet>
      ) : null}
    </div>
  );
}

function EditSquadSheet({ slug, squad, onClose }: { slug: string; squad: PtSquad; onClose: () => void }) {
  const t = useTranslations("Squads");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const refresh = useSquadRefresh(slug, squad.id);
  const [name, setName] = useState(squad.name);
  const [description, setDescription] = useState(squad.description ?? "");
  const save = useMutation({
    mutationFn: () => updateSquad(tokens!.access_token, slug, squad.id, { name: name.trim(), description: description.trim() || null }),
    onSuccess: async () => {
      await refresh();
      onClose();
    },
  });
  const valid = name.trim().length >= 2;

  return (
    <Sheet
      labelId="edit-squad"
      eyebrow={squad.name}
      title={t("edit")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary type="submit" form="edit-squad-form" disabled={!valid || save.isPending}>
            {t("save")}
          </SheetButton>
        </>
      }
    >
      <form
        id="edit-squad-form"
        className="flex flex-col gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          if (valid) save.mutate();
        }}
      >
        <Field label={t("name")}>
          <input value={name} maxLength={60} onChange={(event) => setName(event.target.value)} className="min-h-11 rounded-2xl px-3 text-sm font-normal" style={inputStyle} />
        </Field>
        <Field label={t("about")}>
          <input
            value={description}
            maxLength={200}
            onChange={(event) => setDescription(event.target.value)}
            className="min-h-11 rounded-2xl px-3 text-sm font-normal"
            style={inputStyle}
          />
        </Field>
        <ErrorLine message={save.error ? clientErrorMessage(save.error, tUi) : null} />
      </form>
    </Sheet>
  );
}

function SquadMembers({ club, squad }: { club: CommunityClub; squad: PtSquad }) {
  const t = useTranslations("Squads");
  const rows = squad.members ?? [];
  const members = rows.filter((row) => row.status === "member");
  const invited = rows.filter((row) => row.status === "invited");

  return (
    <>
      <HubCard eyebrow={t("members", { count: members.length })}>
        <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
          <li className="flex min-h-12 items-center gap-3 py-2">
            <Link href={`/people/${squad.coach.id}`} className="flex min-w-0 grow items-center gap-3">
              <PersonAvatar name={squad.coach.nickname} url={squad.coach.avatar_url} />
              <span className="truncate font-bold" style={{ color: "var(--text)" }}>{squad.coach.nickname ?? "?"}</span>
            </Link>
            <Badge>{t("coachLabel")}</Badge>
          </li>
          {members.map((row) => (
            <MemberRow key={row.person.id} club={club} squad={squad} row={row} />
          ))}
        </ul>
        {members.length === 0 ? <p className="mt-2 text-sm" style={{ color: "var(--text-soft)" }}>{t("noMembersYet")}</p> : null}
      </HubCard>
      {squad.role === "coach" && invited.length > 0 ? (
        <HubCard eyebrow={t("invitesOpen", { count: invited.length })}>
          <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
            {invited.map((row) => (
              <MemberRow key={row.person.id} club={club} squad={squad} row={row} />
            ))}
          </ul>
        </HubCard>
      ) : null}
    </>
  );
}

function MemberRow({ club, squad, row }: { club: CommunityClub; squad: PtSquad; row: PtSquadMember }) {
  const t = useTranslations("Squads");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const slug = club.organization_slug!;
  const refresh = useSquadRefresh(slug, squad.id);
  const remove = useMutation({
    mutationFn: () => removeFromSquad(tokens!.access_token, slug, squad.id, row.person.id),
    onSuccess: refresh,
  });

  return (
    <li className="flex flex-col gap-1 py-2">
      <div className="flex min-h-12 items-center gap-3">
        <Link href={`/people/${row.person.id}`} className="flex min-w-0 grow items-center gap-3">
          <PersonAvatar name={row.person.nickname} url={row.person.avatar_url} />
          <span className="truncate font-bold" style={{ color: "var(--text)" }}>{row.person.nickname ?? "?"}</span>
        </Link>
        {row.status === "invited" ? <Badge muted>{t("statusInvited")}</Badge> : null}
        {squad.role === "coach" ? (
          row.status === "invited" ? (
            <SmallAction disabled={remove.isPending} onClick={() => remove.mutate()}>{t("withdraw")}</SmallAction>
          ) : (
            <MoreMenu label={t("memberActions")} items={[{ label: t("remove"), onSelect: () => remove.mutate() }]} />
          )
        ) : null}
      </div>
      <ErrorLine message={remove.error ? clientErrorMessage(remove.error, tUi) : null} />
    </li>
  );
}
