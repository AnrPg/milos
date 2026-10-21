"use client";

import { useState } from "react";
import Link from "next/link";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { CLUBS_KEY, NOTIFY_LEVELS, setNotifyLevel, type CommunityClub, type NotifyLevel } from "@/api/community";
import { clientErrorMessage } from "@/components/client/errors";
import { clubInitials } from "@/components/community/community";
import { MyGymsCard } from "@/components/community/MyGymsCard";
import { useMyClubs } from "@/components/community/use-community";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Εγώ › Τα box και τα clubs μου (mockup «myClubs»): your gyms (and joining
 * another), then each club and how much you hear from it.
 */
export function MyClubsPage() {
  const t = useTranslations("Community");
  const clubs = useMyClubs();

  return (
    <HubPage title={t("myClubsTitle")}>
      <MyGymsCard />
      <HubCard eyebrow={t("myClubsNotify")}>
        {clubs.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : (clubs.data ?? []).length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("myClubsEmpty")}</p>
        ) : (
          <ul className="flex flex-col gap-3">
            {(clubs.data ?? []).map((club) => (
              <ClubRow key={club.id} club={club} />
            ))}
          </ul>
        )}
      </HubCard>
    </HubPage>
  );
}

function ClubRow({ club }: { club: CommunityClub }) {
  const t = useTranslations("Community");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [error, setError] = useState<string | null>(null);
  const selectId = `notify-${club.id}`;

  async function change(level: NotifyLevel) {
    if (!tokens?.access_token) return;
    setError(null);
    try {
      await setNotifyLevel(tokens.access_token, club, level);
      await queryClient.invalidateQueries({ queryKey: CLUBS_KEY });
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    }
  }

  return (
    <li className="flex items-center gap-3">
      <span
        aria-hidden="true"
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-sm font-extrabold"
        style={{ background: "var(--panel-raised)", color: "var(--text)" }}
      >
        {clubInitials(club.name)}
      </span>
      <div className="min-w-0 grow">
        <Link href={`/clubs/${club.id}`} className="block truncate font-bold" style={{ color: "var(--text)" }}>
          {club.name}
        </Link>
        <label htmlFor={selectId} className="text-xs" style={{ color: "var(--dim)" }}>{t("notifyLabel")}</label>
        {error ? <p role="alert" className="text-xs" style={{ color: "var(--danger)" }}>{error}</p> : null}
      </div>
      <select
        id={selectId}
        value={club.notify_level}
        onChange={(event) => void change(event.target.value as NotifyLevel)}
        className="min-h-11 rounded-2xl px-3 text-sm"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
      >
        {NOTIFY_LEVELS.map((level) => (
          <option key={level} value={level}>{t(`notify.${level}`)}</option>
        ))}
      </select>
    </li>
  );
}
