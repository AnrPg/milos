"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BUDDIES_KEY, claimBuddyInvite, fetchBuddyInvite } from "@/api/buddies";
import { ErrorLine } from "@/components/community/Sheet";
import { HubButton, HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { buddyErrorMessage } from "./errors";

/**
 * `/buddy/<token>` (board 15 q2 A): someone shared a buddy link. What a
 * buddy is, who invites, then sign in or sign up and accept; claiming the
 * link is the acceptance. Nothing starts before that.
 */
export function BuddyInviteLanding({ inviteToken }: { inviteToken: string }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const { status, tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const here = `/buddy/${encodeURIComponent(inviteToken)}`;

  const preview = useQuery({
    queryKey: ["buddy-invite", inviteToken],
    queryFn: () => fetchBuddyInvite(token, inviteToken),
    retry: false,
  });
  const claim = useMutation({
    mutationFn: () => claimBuddyInvite(token!, inviteToken),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: BUDDIES_KEY }),
  });

  const name = preview.data?.inviter?.nickname?.trim() || null;
  const state = preview.isError ? "unavailable" : (preview.data?.status ?? null);

  return (
    <HubPage title={t("inviteHeading")}>
      <HubCard highlighted>
        <div className="flex items-center gap-3">
          <PersonAvatar name={name ?? "?"} url={preview.data?.inviter?.avatar_url} size={48} />
          <p className="text-base font-bold" style={{ color: "var(--text)" }} data-testid="buddy-inviter">
            {preview.isPending ? t("loading") : name ? t("inviteFrom", { name }) : t("inviteFromSomeone")}
          </p>
        </div>
      </HubCard>

      <HubCard eyebrow={t("whatIsBuddy")}>
        <ul className="flex list-disc flex-col gap-2 ps-5 text-sm" style={{ color: "var(--text-soft)" }}>
          <li>{t("whatOnly")}</li>
          <li>{t("whatReplies")}</li>
          <li>{t("whatQuiet")}</li>
          <li>{t("whatStop")}</li>
        </ul>
      </HubCard>

      {claim.isSuccess ? (
        <HubCard>
          <p role="status" className="text-sm font-semibold" style={{ color: "var(--success)" }}>
            {name ? t("inviteAccepted", { name }) : t("inviteAcceptedNoName")}
          </p>
          <div className="mt-4 flex">
            <HubButton primary href="/me/buddy">{t("openBuddy")}</HubButton>
          </div>
        </HubCard>
      ) : state === "expired" || state === "unavailable" ? (
        <HubCard>
          <p className="text-sm" style={{ color: "var(--text-soft)" }} data-testid="buddy-invite-state">
            {state === "expired" ? t("inviteExpired") : t("inviteUnavailable")}
          </p>
        </HubCard>
      ) : state === "pending" && status === "authenticated" ? (
        <HubCard>
          <div className="flex flex-col gap-2">
            <button
              type="button"
              onClick={() => claim.mutate()}
              disabled={claim.isPending}
              className="flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--bg)" }}
            >
              {name ? t("acceptName", { name }) : t("accept")}
            </button>
            <Link href="/" className="py-2 text-center text-sm font-semibold underline" style={{ color: "var(--text-soft)" }}>
              {t("notNow")}
            </Link>
            <ErrorLine message={buddyErrorMessage(claim.error, t, tUi)} />
          </div>
        </HubCard>
      ) : state === "pending" && status === "guest" ? (
        <HubCard>
          <div className="flex flex-col gap-2">
            <HubButton primary href={`/register?next=${encodeURIComponent(here)}`}>{t("inviteSignUp")}</HubButton>
            <HubButton href={`/login?next=${encodeURIComponent(here)}`}>{t("inviteSignIn")}</HubButton>
          </div>
        </HubCard>
      ) : null}

      <p className="px-1 text-xs leading-5" style={{ color: "var(--dim)" }}>{t("inviteFooter")}</p>
    </HubPage>
  );
}
