"use client";

import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  answerGroupRequest,
  archiveGroup,
  CLUBS_KEY,
  FEED_KEY,
  fetchGroup,
  groupKey,
  groupsKey,
  joinGroup,
  leaveGroup,
  removeGroupMember,
  setGroupAdmin,
  updateGroup,
  type CommunityClub,
  type CommunityGroup,
  type CommunityGroupMember,
  type GroupJoinPolicy,
} from "@/api/community";
import { ApiError } from "@/api/client";
import { clientErrorMessage } from "@/components/client/errors";
import { ClubEventsTab } from "@/components/events/ClubEventsTab";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { ComposeButton } from "./ComposeSheet";
import { FeedList } from "./FeedList";
import { Badge } from "./MembersTab";
import { MoreMenu } from "./PostCard";
import { Field, inputStyle, JoinPolicyPicker } from "./ProposeGroupSheet";
import { ReportSheet } from "./ReportSheet";
import { ErrorLine, Sheet, SheetButton } from "./Sheet";
import { useClubRealtime, useMyClubs } from "./use-community";
import { BackLink } from "@/components/ui/BackLink";

/**
 * A member group (board 7 Q2): its posts and events (ADR-153) for members, who is in it, and for
 * its admins the requests, admins, editing and archiving. The last admin hands
 * over before leaving; a quiet group is warned at 50 days and archived at 60,
 * and whoever started it can bring it back (Q8).
 */
export function GroupPage({ clubId, groupId }: { clubId: string; groupId: string }) {
  const t = useTranslations("Clubs");
  const clubs = useMyClubs();
  useClubRealtime(clubs.data);
  const club = clubs.data?.find((entry) => entry.id === clubId);
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const group = useQuery({
    queryKey: groupKey(groupId),
    enabled: Boolean(token && club?.organization_slug),
    queryFn: () => fetchGroup(token!, club!.organization_slug!, groupId),
  });

  if (clubs.isPending || (club && group.isPending)) {
    return (
      <HubPage title={t("groupLabel")}>
        <p style={{ color: "var(--dim)" }}>{t("loading")}</p>
      </HubPage>
    );
  }
  if (!club || !group.data) {
    return (
      <HubPage title={t("groupLabel")}>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("groupNotFound")}</p>
        <Link href={club ? `/clubs/${club.id}` : "/"} className="text-sm font-semibold underline" style={{ color: "var(--text)" }}>
          {t("backToClub")}
        </Link>
      </HubPage>
    );
  }
  return <GroupView club={club} clubs={clubs.data ?? []} group={group.data} />;
}

function GroupView({ club, clubs, group }: { club: CommunityClub; clubs: CommunityClub[]; group: CommunityGroup }) {
  const t = useTranslations("Clubs");
  const member = group.membership === "member";
  const [tab, setTab] = useState<"feed" | "events" | "members">(member && group.status === "active" ? "feed" : "members");
  const requests = (group.members ?? []).filter((row) => row.status === "requested");
  const canPost = club.channels.some((channel) => channel.id === group.id && channel.can_post);

  return (
    <HubPage
      title={group.name}
      actions={canPost ? <ComposeButton clubs={clubs} clubId={club.id} channelId={group.id} /> : <GroupMenu club={club} group={group} />}
    >
      <BackLink href={`/clubs/${club.id}`} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>{club.name}</BackLink>
      <HubCard>
        <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {t("groupLabel")} · {t("groupMembers", { count: group.member_count })}
        </p>
        {group.description ? (
          <p className="mt-1 text-sm" style={{ color: "var(--text)" }}>{group.description}</p>
        ) : null}
        <p className="mt-1 text-xs" style={{ color: "var(--text-soft)" }}>
          {group.join_policy === "request" ? t("joinRequestHint") : t("joinOpenHint")}
        </p>
        <StatusNotes group={group} />
        <GroupActions club={club} group={group} />
      </HubCard>
      {group.status === "active" ? (
        <div role="tablist" aria-label={group.name} className="flex gap-2">
          {(["feed", "events", "members"] as const).map((id) => (
            <button
              key={id}
              type="button"
              role="tab"
              aria-selected={tab === id}
              onClick={() => setTab(id)}
              className="min-h-11 flex-1 rounded-2xl text-sm font-semibold"
              style={{
                background: tab === id ? "var(--primary)" : "var(--panel)",
                color: tab === id ? "var(--primary-contrast)" : "var(--text)",
                border: "1px solid var(--border)",
              }}
            >
              {id === "feed" ? t("tabFeed") : id === "events" ? t("tabEvents") : requests.length > 0 ? t("tabMembersRequests", { count: requests.length }) : t("tabMembers")}
            </button>
          ))}
        </div>
      ) : null}
      {tab === "events" && group.status === "active" ? (
        member || group.can_manage ? (
          <ClubEventsTab club={club} group={group} />
        ) : (
          <HubCard>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("groupFeedMembersOnly")}</p>
          </HubCard>
        )
      ) : tab === "feed" && group.status === "active" ? (
        member || group.can_manage ? (
          <FeedList filter={{ clubId: club.id, channelId: group.id }} />
        ) : (
          <HubCard>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("groupFeedMembersOnly")}</p>
          </HubCard>
        )
      ) : (
        <GroupMembers club={club} group={group} />
      )}
    </HubPage>
  );
}

function StatusNotes({ group }: { group: CommunityGroup }) {
  const t = useTranslations("Clubs");
  const notes: string[] = [];
  if (group.status === "pending") notes.push(group.created_by_me ? t("groupPendingMine") : t("groupPendingStaff"));
  if (group.status === "declined") notes.push(t("groupDeclined"));
  if (group.status === "active" && group.archive_warned_at && (group.can_manage || group.membership === "member")) {
    notes.push(t("groupQuietWarning"));
  }
  if (notes.length === 0) return null;
  return (
    <div className="mt-3 flex flex-col gap-1">
      {notes.map((note) => (
        <p key={note} className="rounded-2xl px-3 py-2 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
          {note}
        </p>
      ))}
    </div>
  );
}

function useGroupRefresh(club: CommunityClub, groupId: string) {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: groupKey(groupId) }),
      queryClient.invalidateQueries({ queryKey: groupsKey(club.id) }),
      queryClient.invalidateQueries({ queryKey: CLUBS_KEY }),
      queryClient.invalidateQueries({ queryKey: FEED_KEY }),
    ]);
}

function GroupActions({ club, group }: { club: CommunityClub; group: CommunityGroup }) {
  const t = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const router = useRouter();
  const refresh = useGroupRefresh(club, group.id);
  const slug = club.organization_slug!;
  const [editing, setEditing] = useState(false);
  const [confirm, setConfirm] = useState<"leave" | "archive" | null>(null);

  const join = useMutation({ mutationFn: () => joinGroup(tokens!.access_token, slug, group.id), onSuccess: refresh });
  const leave = useMutation({
    mutationFn: () => leaveGroup(tokens!.access_token, slug, group.id),
    onSuccess: async () => {
      setConfirm(null);
      await refresh();
      router.push(`/clubs/${club.id}`);
    },
  });
  const archive = useMutation({
    mutationFn: () => archiveGroup(tokens!.access_token, slug, group.id),
    onSuccess: async () => {
      setConfirm(null);
      await refresh();
      router.push(`/clubs/${club.id}`);
    },
  });

  const failure = join.error ?? leave.error ?? archive.error;
  const handOver = failure instanceof ApiError && failure.payload.code === "hand_over_first";
  const lastAdmin = group.admin && (group.members ?? []).filter((row) => row.role === "admin" && row.status === "member").length <= 1;
  const alone = group.member_count <= 1;

  if (group.status !== "active") return null;
  return (
    <div className="mt-3 flex flex-col gap-2">
      <div className="flex flex-wrap gap-2">
        {group.membership === "none" ? (
          <SheetButton primary disabled={join.isPending} onClick={() => join.mutate()}>
            {group.join_policy === "request" ? t("groupAsk") : t("groupJoin")}
          </SheetButton>
        ) : group.membership === "requested" ? (
          <SheetButton disabled={leave.isPending} onClick={() => leave.mutate()}>{t("groupCancelRequest")}</SheetButton>
        ) : (
          <SheetButton onClick={() => setConfirm("leave")}>{t("groupLeave")}</SheetButton>
        )}
        {group.can_manage ? (
          <>
            <SheetButton onClick={() => setEditing(true)}>{t("groupEdit")}</SheetButton>
            <SheetButton onClick={() => setConfirm("archive")}>{t("groupArchive")}</SheetButton>
          </>
        ) : null}
      </div>
      <ErrorLine message={handOver ? t("groupHandOverFirst") : failure ? clientErrorMessage(failure, tUi) : null} />
      {editing ? <EditGroupSheet club={club} group={group} onClose={() => setEditing(false)} /> : null}
      {confirm ? (
        <Sheet
          labelId="group-confirm"
          eyebrow={group.name}
          title={confirm === "leave" ? t("groupLeaveTitle") : t("groupArchiveTitle")}
          onClose={() => setConfirm(null)}
          footer={
            <>
              <SheetButton onClick={() => setConfirm(null)}>{t("cancel")}</SheetButton>
              <SheetButton
                primary
                disabled={leave.isPending || archive.isPending || (confirm === "leave" && lastAdmin && !alone)}
                onClick={() => (confirm === "leave" ? leave.mutate() : archive.mutate())}
              >
                {confirm === "leave" ? t("groupLeave") : t("groupArchive")}
              </SheetButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {confirm === "archive"
              ? t("groupArchiveBody")
              : alone
                ? t("groupLeaveLastBody")
                : lastAdmin
                  ? t("groupHandOverFirst")
                  : t("groupLeaveBody")}
          </p>
        </Sheet>
      ) : null}
    </div>
  );
}

/** ⋯ for someone who can't post here: report the group (board 7 Q4). */
function GroupMenu({ club, group }: { club: CommunityClub; group: CommunityGroup }) {
  const tCommunity = useTranslations("Community");
  const router = useRouter();
  const refresh = useGroupRefresh(club, group.id);
  const [reporting, setReporting] = useState(false);
  if (!group.can_report) return null;
  return (
    <>
      <MoreMenu label={tCommunity("more")} items={[{ label: tCommunity("report"), onSelect: () => setReporting(true) }]} />
      {reporting ? (
        <ReportSheet
          target="channel"
          targetId={group.id}
          onClose={() => setReporting(false)}
          onReported={() => {
            void refresh();
            router.push(`/clubs/${club.id}`);
          }}
        />
      ) : null}
    </>
  );
}

function EditGroupSheet({ club, group, onClose }: { club: CommunityClub; group: CommunityGroup; onClose: () => void }) {
  const t = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const refresh = useGroupRefresh(club, group.id);
  const [name, setName] = useState(group.name);
  const [description, setDescription] = useState(group.description ?? "");
  const [policy, setPolicy] = useState<GroupJoinPolicy>(group.join_policy);
  const save = useMutation({
    mutationFn: () =>
      updateGroup(tokens!.access_token, club.organization_slug!, group.id, {
        name: name.trim(),
        description: description.trim() || null,
        join_policy: policy,
      }),
    onSuccess: async () => {
      await refresh();
      onClose();
    },
  });

  return (
    <Sheet
      labelId="edit-group"
      eyebrow={group.name}
      title={t("groupEdit")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary type="submit" form="edit-group-form" disabled={name.trim().length < 2 || save.isPending}>
            {t("save")}
          </SheetButton>
        </>
      }
    >
      <form
        id="edit-group-form"
        className="flex flex-col gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          if (name.trim().length >= 2) save.mutate();
        }}
      >
        <Field label={t("groupName")}>
          <input value={name} maxLength={60} onChange={(event) => setName(event.target.value)} className="min-h-11 rounded-2xl px-3 text-sm font-normal" style={inputStyle} />
        </Field>
        <Field label={t("groupAbout")}>
          <input
            value={description}
            maxLength={200}
            onChange={(event) => setDescription(event.target.value)}
            className="min-h-11 rounded-2xl px-3 text-sm font-normal"
            style={inputStyle}
          />
        </Field>
        <JoinPolicyPicker value={policy} onChange={setPolicy} />
        <ErrorLine message={save.error ? clientErrorMessage(save.error, tUi) : null} />
      </form>
    </Sheet>
  );
}

function GroupMembers({ club, group }: { club: CommunityClub; group: CommunityGroup }) {
  const t = useTranslations("Clubs");
  const rows = group.members ?? [];
  const requests = rows.filter((row) => row.status === "requested");
  const members = rows
    .filter((row) => row.status === "member")
    .sort((a, b) => Number(b.role === "admin") - Number(a.role === "admin"));

  return (
    <>
      {group.can_manage && requests.length > 0 ? (
        <HubCard eyebrow={t("groupRequests", { count: requests.length })}>
          <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
            {requests.map((row) => (
              <MemberRow key={row.person.id} club={club} group={group} row={row} />
            ))}
          </ul>
        </HubCard>
      ) : null}
      <HubCard eyebrow={t("groupMembers", { count: members.length })}>
        <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
          {members.map((row) => (
            <MemberRow key={row.person.id} club={club} group={group} row={row} />
          ))}
        </ul>
      </HubCard>
    </>
  );
}

function MemberRow({ club, group, row }: { club: CommunityClub; group: CommunityGroup; row: CommunityGroupMember }) {
  const t = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const { tokens, currentUser } = useSession();
  const refresh = useGroupRefresh(club, group.id);
  const slug = club.organization_slug!;
  const userId = row.person.id;
  const act = useMutation({
    mutationFn: (action: "approve" | "decline" | "admin" | "unadmin" | "remove") => {
      const token = tokens!.access_token;
      if (action === "approve" || action === "decline") return answerGroupRequest(token, slug, group.id, userId, action === "approve");
      if (action === "remove") return removeGroupMember(token, slug, group.id, userId);
      return setGroupAdmin(token, slug, group.id, userId, action === "admin");
    },
    onSuccess: refresh,
  });
  const self = currentUser?.id === userId;
  const manage = group.can_manage && !self;

  return (
    <li className="flex flex-col gap-1 py-2">
      <div className="flex min-h-12 items-center gap-3">
        <Link href={`/people/${userId}`} className="flex min-w-0 grow items-center gap-3">
          <PersonAvatar name={row.person.nickname} url={row.person.avatar_url} />
          <span className="truncate font-bold" style={{ color: "var(--text)" }}>{row.person.nickname ?? "?"}</span>
        </Link>
        {row.role === "admin" && row.status === "member" ? <Badge>{t("groupAdmin")}</Badge> : null}
        {manage && row.status === "requested" ? (
          <>
            <SmallButton disabled={act.isPending} onClick={() => act.mutate("decline")}>{t("decline")}</SmallButton>
            <SmallButton primary disabled={act.isPending} onClick={() => act.mutate("approve")}>{t("approve")}</SmallButton>
          </>
        ) : null}
        {manage && row.status === "member" ? (
          <MoreMenu
            label={t("memberActions")}
            items={[
              row.role === "admin"
                ? { label: t("groupUnmakeAdmin"), onSelect: () => act.mutate("unadmin") }
                : { label: t("groupMakeAdmin"), onSelect: () => act.mutate("admin") },
              { label: t("groupRemove"), onSelect: () => act.mutate("remove") },
            ]}
          />
        ) : null}
      </div>
      <ErrorLine message={act.error ? clientErrorMessage(act.error, tUi) : null} />
    </li>
  );
}

export function SmallButton({
  children,
  onClick,
  primary,
  spark,
  disabled,
}: {
  children: string;
  onClick: () => void;
  primary?: boolean;
  /** A go-now action (join): Spark instead of Dojo (ADR-182). */
  spark?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="min-h-11 shrink-0 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
      style={{
        background: spark ? "var(--spark)" : primary ? "var(--primary)" : "var(--panel-raised)",
        color: spark ? "var(--spark-contrast)" : primary ? "var(--primary-contrast)" : "var(--text)",
        border: primary || spark ? "none" : "1px solid var(--border)",
      }}
    >
      {children}
    </button>
  );
}
