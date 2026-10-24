"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  CLUBS_KEY,
  FEED_KEY,
  setChannelJoined,
  setOpenClubJoined,
  type CommunityChannel,
  type CommunityClub,
} from "@/api/community";
import { clientErrorMessage } from "@/components/client/errors";
import { channelName, channelSections } from "@/components/community/community";
import { ClubBar } from "@/components/community/ClubBar";
import { ClubFeed } from "@/components/community/ClubFeed";
import { ComposeButton } from "@/components/community/ComposeSheet";
import { FeedList } from "@/components/community/FeedList";
import { GroupsCard } from "@/components/community/GroupsCard";
import { ClubSquadsCard } from "@/components/community/squads/ClubSquadsCard";
import { MembersTab } from "@/components/community/MembersTab";
import { OpenClubLanding } from "@/components/community/OpenClubLanding";
import { MoreMenu } from "@/components/community/PostCard";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { WodCard } from "@/components/community/WodCard";
import { ClubEventsTab } from "@/components/events/ClubEventsTab";
import { useClubRealtime, useMyClubs } from "@/components/community/use-community";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

type ClubTab = "feed" | "channels" | "events" | "members";
const TABS: ClubTab[] = ["feed", "channels", "events", "members"];
const TAB_KEYS: Record<ClubTab, string> = { feed: "tabFeed", channels: "tabChannels", events: "tabEvents", members: "tabMembers" };

/**
 * A club's page (vision §7.1, mockup «club», board 7): Ροή (`ClubFeed`:
 * pinned announcement → WOD and leaderboard → challenges → PR celebrations →
 * events → members' posts; or one channel's posts), Κανάλια (the box's channels, member groups, class groups
 * with the ones offered to the member first), Events (ADR-153) and Μέλη. An open
 * club the member hasn't joined shows its landing with «Μπες».
 */
export function ClubPage({ clubId, channelId = null }: { clubId: string; channelId?: string | null }) {
  const t = useTranslations("Community");
  const tClubs = useTranslations("Clubs");
  const clubs = useMyClubs();
  useClubRealtime(clubs.data);
  const [tab, setTab] = useState<ClubTab>("feed");
  const [openChannelId, setOpenChannelId] = useState<string | null>(channelId);
  const club = clubs.data?.find((entry) => entry.id === clubId);
  const openChannel = club?.channels.find((channel) => channel.id === openChannelId) ?? null;

  function showChannel(id: string) {
    setOpenChannelId(id);
    setTab("feed");
  }

  if (clubs.isPending) return <HubPage title={t("clubTitle")}><p style={{ color: "var(--dim)" }}>{t("loading")}</p></HubPage>;
  if (!club)
    return (
      <OpenClubLanding
        clubId={clubId}
        notFound={
          <HubPage title={t("clubTitle")}>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("clubNotFound")}</p>
          </HubPage>
        }
      />
    );

  return (
    <HubPage
      title={club.name}
      actions={
        <div className="flex items-center gap-1">
          {club.kind === "open" && club.role !== "staff" ? <LeaveOpenClub club={club} /> : null}
          <ComposeButton clubs={clubs.data ?? []} clubId={club.id} channelId={openChannel?.id} />
        </div>
      }
    >
      <ClubBar clubs={clubs.data ?? []} activeClubId={club.id} />
      <p className="text-sm" style={{ color: "var(--dim)" }}>
        {club.kind === "open" ? `${tClubs("openClub")} · ` : ""}
        {club.role === "staff" ? t("roleStaff") : t("roleMember")}
      </p>
      {club.kind === "open" && club.description ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{club.description}</p>
      ) : null}
      <div role="tablist" aria-label={club.name} className="grid grid-cols-4 gap-2">
        {TABS.map((id) => (
          <button
            key={id}
            type="button"
            role="tab"
            aria-selected={tab === id}
            onClick={() => setTab(id)}
            className="min-h-11 rounded-2xl px-1 text-sm font-semibold"
            style={{
              background: tab === id ? "var(--primary)" : "var(--panel)",
              color: tab === id ? "var(--primary-contrast)" : "var(--text)",
              border: "1px solid var(--border)",
            }}
          >
            {tClubs(TAB_KEYS[id])}
          </button>
        ))}
      </div>
      {tab === "channels" ? (
        <>
          <ChannelList club={club} onOpen={showChannel} />
          {club.kind === "gym" ? <GroupsCard club={club} /> : null}
          {club.kind === "gym" ? <ClubSquadsCard club={club} /> : null}
        </>
      ) : tab === "events" ? (
        <ClubEventsTab club={club} />
      ) : tab === "members" ? (
        <MembersTab club={club} />
      ) : openChannel ? (
        <>
          <div className="flex items-center gap-2">
            <p className="grow font-bold" style={{ color: "var(--text)" }}>#{channelName(openChannel, t)}</p>
            <button
              type="button"
              onClick={() => setOpenChannelId(null)}
              className="min-h-11 rounded-full px-4 text-sm font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("channelShowAll")}
            </button>
          </div>
          {openChannel.kind === "wod" ? <WodCard club={club} showOrigin={false} /> : null}
          <FeedList filter={{ clubId: club.id, channelId: openChannel.id }} />
        </>
      ) : (
        <ClubFeed club={club} onShowEvents={() => setTab("events")} />
      )}
    </HubPage>
  );
}

/** ⋯ › Αποχώρηση from an open club, behind a confirmation. */
function LeaveOpenClub({ club }: { club: CommunityClub }) {
  const t = useTranslations("Clubs");
  const tCommunity = useTranslations("Community");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const leave = useMutation({
    mutationFn: () => setOpenClubJoined(tokens!.access_token, club.id, false),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: CLUBS_KEY }),
        queryClient.invalidateQueries({ queryKey: FEED_KEY }),
      ]);
      router.push("/clubs/find");
    },
  });
  return (
    <>
      <MoreMenu label={tCommunity("more")} items={[{ label: t("clubLeave"), onSelect: () => setConfirming(true) }]} />
      {confirming ? (
        <Sheet
          labelId="leave-club"
          eyebrow={club.name}
          title={t("clubLeaveTitle")}
          onClose={() => setConfirming(false)}
          footer={
            <>
              <SheetButton onClick={() => setConfirming(false)}>{t("cancel")}</SheetButton>
              <SheetButton primary disabled={leave.isPending} onClick={() => leave.mutate()}>{t("clubLeave")}</SheetButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("clubLeaveBody")}</p>
          <ErrorLine message={leave.error ? clientErrorMessage(leave.error, tUi) : null} />
        </Sheet>
      ) : null}
    </>
  );
}

function ChannelList({ club, onOpen }: { club: CommunityClub; onOpen: (id: string) => void }) {
  const t = useTranslations("Community");
  const { box, classes, other } = channelSections(club.channels);
  const sections = [
    { key: "box", title: club.kind === "open" ? t("channelsOfClub") : t("channelsOfBox"), channels: box },
    { key: "classes", title: t("channelsClassGroups"), channels: classes },
    { key: "other", title: t("channelsOther"), channels: other },
  ].filter((section) => section.channels.length > 0);

  return (
    <>
      {sections.map((section) => (
        <HubCard key={section.key} eyebrow={section.title}>
          <ul className="flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
            {section.channels.map((channel) => (
              <ChannelRow key={channel.id} club={club} channel={channel} onOpen={onOpen} />
            ))}
          </ul>
        </HubCard>
      ))}
    </>
  );
}

const WRITE_KEYS: Record<CommunityChannel["write_policy"], string> = {
  staff: "writeStaff",
  members: "writeMembers",
  participants: "writeParticipants",
  system_and_members: "writeSystem",
};

function ChannelRow({
  club,
  channel,
  onOpen,
}: {
  club: CommunityClub;
  channel: CommunityChannel;
  onOpen: (id: string) => void;
}) {
  const t = useTranslations("Community");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function toggle() {
    if (!tokens?.access_token || !club.organization_slug) return;
    setBusy(true);
    setError(null);
    try {
      await setChannelJoined(tokens.access_token, club.organization_slug, channel.id, !channel.joined);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: CLUBS_KEY }),
        queryClient.invalidateQueries({ queryKey: FEED_KEY }),
      ]);
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    } finally {
      setBusy(false);
    }
  }

  return (
    <li className="flex items-center gap-3 py-3">
      <span aria-hidden="true" className="text-lg font-bold" style={{ color: "var(--dim)" }}>#</span>
      <div className="min-w-0 grow">
        <button type="button" onClick={() => onOpen(channel.id)} className="text-left font-bold" style={{ color: "var(--text)" }}>
          {channelName(channel, t)}
        </button>
        {channel.suggested ? (
          <p className="text-xs font-semibold" style={{ color: "var(--primary)" }}>
            {t("channelSuggested")} · {t("channelSuggestedHint")}
          </p>
        ) : null}
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {t(WRITE_KEYS[channel.write_policy])} · {channel.membership === "everyone" ? t("channelEveryone") : t("channelOptIn")}
        </p>
        {error ? <p role="alert" className="text-xs" style={{ color: "var(--danger)" }}>{error}</p> : null}
      </div>
      {channel.can_leave ? (
        <button
          type="button"
          onClick={() => void toggle()}
          disabled={busy}
          className="min-h-11 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
          style={{
            background: channel.joined ? "var(--panel-raised)" : "var(--spark)",
            color: channel.joined ? "var(--text)" : "var(--spark-contrast)",
            border: "1px solid var(--border)",
          }}
        >
          {channel.joined ? t("channelLeave") : t("channelJoin")}
        </button>
      ) : null}
    </li>
  );
}
