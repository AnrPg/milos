"use client";

import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { CLUBS_KEY, FEED_KEY, setChannelJoined, type CommunityChannel, type CommunityClub } from "@/api/community";
import { clientErrorMessage } from "@/components/client/errors";
import { channelName, channelSections } from "@/components/community/community";
import { ClubBar } from "@/components/community/ClubBar";
import { ComposeButton } from "@/components/community/ComposeSheet";
import { FeedList } from "@/components/community/FeedList";
import { WodCard } from "@/components/community/WodCard";
import { useClubRealtime, useMyClubs } from "@/components/community/use-community";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

/**
 * A club's page (vision §7.1, mockup «club»): Ροή (pinned announcements, the
 * #wod-σήμερα card, then every channel's posts; or one channel's posts) and
 * Κανάλια (the box's channels, class groups with the ones offered to the
 * member first; opt-in ones can be joined or left). Events and Μέλη arrive
 * with Phase 2.
 */
export function ClubPage({ clubId, channelId = null }: { clubId: string; channelId?: string | null }) {
  const t = useTranslations("Community");
  const clubs = useMyClubs();
  useClubRealtime(clubs.data);
  const [tab, setTab] = useState<"feed" | "channels">("feed");
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
      <HubPage title={t("clubTitle")}>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("clubNotFound")}</p>
      </HubPage>
    );

  return (
    <HubPage title={club.name} actions={<ComposeButton clubs={clubs.data ?? []} clubId={club.id} />}>
      <ClubBar clubs={clubs.data ?? []} activeClubId={club.id} />
      <p className="text-sm" style={{ color: "var(--dim)" }}>
        {club.role === "staff" ? t("roleStaff") : t("roleMember")}
      </p>
      <div role="tablist" aria-label={club.name} className="flex gap-2">
        {(["feed", "channels"] as const).map((id) => (
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
            {id === "feed" ? t("tabFeed") : t("tabChannels")}
          </button>
        ))}
      </div>
      {tab === "channels" ? (
        <ChannelList club={club} onOpen={showChannel} />
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
        <>
          {club.kind === "gym" ? <WodCard club={club} showOrigin={false} /> : null}
          <FeedList filter={{ clubId: club.id }} />
        </>
      )}
    </HubPage>
  );
}

function ChannelList({ club, onOpen }: { club: CommunityClub; onOpen: (id: string) => void }) {
  const t = useTranslations("Community");
  const { box, classes, other } = channelSections(club.channels);
  const sections = [
    { key: "box", title: t("channelsOfBox"), channels: box },
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
    if (!tokens?.access_token) return;
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
        {error ? <p role="alert" className="text-xs" style={{ color: "var(--danger, #dc2626)" }}>{error}</p> : null}
      </div>
      {channel.can_leave ? (
        <button
          type="button"
          onClick={() => void toggle()}
          disabled={busy}
          className="min-h-11 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
          style={{
            background: channel.joined ? "var(--panel-raised)" : "var(--primary)",
            color: channel.joined ? "var(--text)" : "var(--bg)",
            border: "1px solid var(--border)",
          }}
        >
          {channel.joined ? t("channelLeave") : t("channelJoin")}
        </button>
      ) : null}
    </li>
  );
}
