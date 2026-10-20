"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { CLUBS_KEY, FEED_KEY, fetchOpenClub, openClubKey, setOpenClubJoined, type OpenClub } from "@/api/community";
import { clientErrorMessage } from "@/components/client/errors";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { channelName } from "./community";
import { ErrorLine, SheetButton } from "./Sheet";

/**
 * An open club seen from outside (board 7 Q6): its cover, what it is, who
 * runs it, how many are in, its channels, and «Μπες» (or «Αίτημα» when it
 * asks for approval). Once in, the club page takes over.
 */
export function OpenClubLanding({ clubId, notFound }: { clubId: string; notFound: React.ReactNode }) {
  const t = useTranslations("Clubs");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const club = useQuery({
    queryKey: openClubKey(clubId),
    enabled: Boolean(token),
    queryFn: () => fetchOpenClub(token!, clubId),
    retry: false,
  });

  if (club.isPending) {
    return (
      <HubPage title={t("openClub")}>
        <p style={{ color: "var(--dim)" }}>{t("loading")}</p>
      </HubPage>
    );
  }
  if (!club.data) return <>{notFound}</>;
  return <Landing club={club.data} />;
}

function Landing({ club }: { club: OpenClub }) {
  const t = useTranslations("Clubs");
  const tCommunity = useTranslations("Community");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const toggle = useMutation({
    mutationFn: (joined: boolean) => setOpenClubJoined(tokens!.access_token, club.id, joined),
    onSuccess: (updated) => {
      queryClient.setQueryData(openClubKey(club.id), updated);
      void queryClient.invalidateQueries({ queryKey: CLUBS_KEY });
      void queryClient.invalidateQueries({ queryKey: FEED_KEY });
    },
  });
  const faces = (club.members ?? []).slice(0, 6);

  return (
    <HubPage title={club.name}>
      {club.cover_url ? (
        // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
        <img src={club.cover_url} alt="" className="aspect-[16/7] w-full rounded-3xl object-cover" />
      ) : null}
      <HubCard>
        <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {t("openClub")} · {t("clubMembers", { count: club.member_count })}
        </p>
        {club.box?.name ? (
          <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>
            {club.box.slug ? (
              <Link href={`/b/${club.box.slug}`} className="font-semibold underline">
                {t("runBy", { box: club.box.name })}
              </Link>
            ) : (
              t("runBy", { box: club.box.name })
            )}
          </p>
        ) : null}
        {club.description ? (
          <p className="mt-2 whitespace-pre-wrap text-sm" style={{ color: "var(--text)" }}>{club.description}</p>
        ) : null}
        {faces.length > 0 ? (
          <div className="mt-3 flex -space-x-2" aria-hidden="true">
            {faces.map((row) => (
              <PersonAvatar key={row.person.id} name={row.person.nickname} url={row.person.avatar_url} size={32} />
            ))}
          </div>
        ) : null}
        {(club.channels ?? []).length > 0 ? (
          <p className="mt-3 text-sm" style={{ color: "var(--dim)" }}>
            {(club.channels ?? []).map((channel) => `#${channelName(channel, tCommunity)}`).join(" · ")}
          </p>
        ) : null}
        <div className="mt-4 flex gap-2">
          {club.membership === "requested" ? (
            <>
              <p className="flex grow items-center text-sm font-semibold" style={{ color: "var(--text)" }}>{t("clubRequested")}</p>
              <SheetButton disabled={toggle.isPending} onClick={() => toggle.mutate(false)}>{t("groupCancelRequest")}</SheetButton>
            </>
          ) : (
            <SheetButton primary disabled={toggle.isPending} onClick={() => toggle.mutate(true)}>
              {club.join_policy === "approval" ? t("clubAsk") : t("clubJoin")}
            </SheetButton>
          )}
        </div>
        {club.join_policy === "approval" && club.membership !== "requested" ? (
          <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("clubApprovalHint")}</p>
        ) : null}
        <div className="mt-2">
          <ErrorLine message={toggle.error ? clientErrorMessage(toggle.error, tUi) : null} />
        </div>
      </HubCard>
    </HubPage>
  );
}
