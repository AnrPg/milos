"use client";

import { useTranslations } from "next-intl";

import type { CommunityClub } from "@/api/community";
import { builtInChannel, channelName } from "@/components/community/community";
import { useFeed } from "@/components/community/use-community";
import { HubButton, HubCard } from "@/components/member-app/HubParts";

/**
 * Box › Ανακοινώσεις (mockup «Τι δείχνει το Box» 5): the gym's latest
 * announcement, pinned first, and a link to its #ανακοινώσεις channel.
 */
export function AnnouncementsCard({ club }: { club: CommunityClub }) {
  const t = useTranslations("Community");
  const channel = builtInChannel(club, "announcements");
  const feed = useFeed({ channelId: channel?.id ?? null });
  if (!channel) return null;

  const page = feed.data?.pages[0];
  const latest = page?.pinned[0] ?? page?.posts[0] ?? null;

  return (
    <HubCard eyebrow={`#${channelName(channel, t)}`}>
      <div className="flex flex-col gap-3">
        {feed.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : latest ? (
          <div>
            <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
              {latest.author.nickname ?? ""}
              {latest.pinned ? ` · ${t("pinned")}` : ""}
            </p>
            <p className="line-clamp-3 whitespace-pre-line text-sm" style={{ color: "var(--text)" }}>{latest.body}</p>
          </div>
        ) : (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("announcementsEmpty")}</p>
        )}
        <HubButton href={`/clubs/${club.id}?channel=${channel.id}`}>{t("announcementsOpen")}</HubButton>
      </div>
    </HubCard>
  );
}
