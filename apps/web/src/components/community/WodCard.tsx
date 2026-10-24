"use client";

import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";

import { WOD_KEY, type CommunityClub, type WodLeaderboardEntry } from "@/api/community";
import { builtInChannel, channelName, clubInitials } from "@/components/community/community";
import { useWodToday } from "@/components/community/use-community";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { TrainingLogDialog, type TrainingLogDialogState } from "@/components/training-log/TrainingLog";
import { useUiLocale } from "@/i18n/use-ui-locale";

/**
 * The club's #wod-σήμερα card (ADR-138 D6, mockup «lbCard»): today's class
 * WOD, its classes, and the leaderboard of members who opted in, with the
 * member's own row and «Καταχώρησε το σκορ σου» until they log it. Shown
 * only when there is a workout today (ANR 2026-10-24, vision §4.2).
 */
export function WodCard({ club, showOrigin = true }: { club: CommunityClub; showOrigin?: boolean }) {
  const t = useTranslations("Community");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const card = useWodToday(club.organization_slug);
  const [logDialog, setLogDialog] = useState<TrainingLogDialogState>({ mode: "closed" });
  const wod = builtInChannel(club, "wod");
  const time = (iso: string) => new Date(iso).toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" });
  const data = card.data;
  const mine = data?.leaderboard.find((row) => row.me) ?? null;

  function closeLog() {
    setLogDialog({ mode: "closed" });
    void queryClient.invalidateQueries({ queryKey: WOD_KEY });
  }

  if (!data?.workout) return null;

  return (
    <HubCard eyebrow={showOrigin && wod ? `${club.name} › #${channelName(wod, t)}` : `#${channelName({ kind: "wod" }, t)}`}>
      <div className="flex flex-col gap-3">
        {/* The screen's hero (BRAND.md): the WOD on the deep surface, tagged in
            Spark, with a Dojo edge so Spark and Graphite never stand alone. */}
        <div
          className="rounded-2xl p-4"
          style={{ background: "var(--deep)", color: "var(--deep-contrast)", borderInlineStart: "4px solid var(--primary)" }}
        >
          <span
            className="inline-block rounded-full px-2 py-0.5 text-[11px] font-extrabold uppercase tracking-[0.14em]"
            style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
          >
            #{channelName({ kind: "wod" }, t)}
          </span>
          <h2 className="mt-2 text-xl font-extrabold">{data.workout.title}</h2>
          <p className="text-sm" style={{ opacity: 0.75 }}>
            {[...data.classes.map((entry) => time(entry.scheduled_at)), t("wodScoreCount", { count: data.leaderboard.length })].join(" · ")}
          </p>
        </div>
        {data.score ? (
          <ol className="flex flex-col gap-1" aria-label={t("wodLeaderboard")}>
            {data.leaderboard.map((row) => (
              <LeaderboardRow key={row.user_id} row={row} />
            ))}
            {!mine ? (
              <li className="flex items-center gap-3 rounded-xl px-2 py-1.5" style={{ background: "var(--panel-raised)" }}>
                <span className="w-5 text-center font-mono text-sm" style={{ color: "var(--dim)" }}>–</span>
                <b className="grow text-sm" style={{ color: "var(--text)" }}>{t("wodYou")}</b>
                <span className="text-xs" style={{ color: "var(--dim)" }}>{t("wodNoScore")}</span>
              </li>
            ) : null}
          </ol>
        ) : null}
        {mine && !mine.opted_in ? (
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            {t("wodOptInHint")}{" "}
            <Link href="/me/sharing" className="font-semibold underline" style={{ color: "var(--primary)" }}>
              {t("wodOptInLink")}
            </Link>
          </p>
        ) : null}
        {!data.logged_by_me && token ? (
          <button
            type="button"
            onClick={() => setLogDialog({ mode: "pick" })}
            className="min-h-11 rounded-2xl text-sm font-semibold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("wodLogScore")}
          </button>
        ) : null}
      </div>
      {logDialog.mode !== "closed" && token ? (
        <TrainingLogDialog state={logDialog} token={token} onNavigate={setLogDialog} onClose={closeLog} />
      ) : null}
    </HubCard>
  );
}

function LeaderboardRow({ row }: { row: WodLeaderboardEntry }) {
  const t = useTranslations("Community");
  const name = row.me ? t("wodYou") : (row.nickname ?? "?");
  const value = [row.value, row.unit].filter(Boolean).join(" ");

  return (
    <li
      className="flex items-center gap-3 rounded-xl px-2 py-1.5"
      style={{ background: row.me ? "var(--panel-raised)" : "transparent" }}
    >
      <span className="w-5 text-center font-mono text-sm font-bold" style={{ color: "var(--dim)" }}>{row.rank}</span>
      {row.avatar_url ? (
        // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
        <img src={row.avatar_url} alt="" className="h-8 w-8 shrink-0 rounded-full object-cover" />
      ) : (
        <span
          aria-hidden="true"
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-xs font-extrabold"
          style={{ background: "var(--panel-raised)", color: "var(--text)" }}
        >
          {clubInitials(row.nickname ?? "?")}
        </span>
      )}
      <b className="grow truncate text-sm" style={{ color: "var(--text)" }}>
        {name}
        {row.scale_level_slug ? (
          <span className="ml-1 text-xs font-normal" style={{ color: "var(--dim)" }}>{row.scale_level_slug}</span>
        ) : null}
      </b>
      <span className="font-mono text-sm" style={{ color: "var(--text)" }}>{value}</span>
    </li>
  );
}
