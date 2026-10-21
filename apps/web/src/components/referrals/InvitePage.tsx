"use client";

import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

import { REFERRALS_KEY, type ReferralClaimResult, type ReferralInvitePage } from "@/api/referrals";
import { HubButton, HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { codeKey, inviteChannel, rememberReferral } from "@/lib/referral-claim";

import { claimPendingReferrals } from "./claim";
import { giftText } from "./referrals";

type ClaimState =
  | { kind: "idle" }
  | { kind: "claiming" }
  | { kind: "done"; result: ReferralClaimResult }
  | { kind: "failed" };

/**
 * `/r/<code>` (ADR-156, board 11 Q1 A): a personal invite. The box, the
 * member who invites, what the friend gets and what the member will see.
 * The invite is kept on the device (30 days) and credited as soon as the
 * friend is signed in, here or after signing up.
 */
export function InvitePage({
  invite,
  via,
  eventId,
}: {
  invite: ReferralInvitePage;
  via: string | null;
  eventId: string | null;
}) {
  const t = useTranslations("Referrals");
  const tags = useTranslations("BoxTags");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const { status, tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [claim, setClaim] = useState<ClaimState>({ kind: "idle" });
  const source = inviteChannel({ via, event: eventId });
  const here = `/r/${encodeURIComponent(invite.code)}${source.event_id ? `?event=${source.event_id}` : via === "qr" ? "?via=qr" : ""}`;
  const name = invite.inviter.nickname ?? null;
  const gift = giftText(invite.gift, t, locale);
  const box = invite.box;

  useEffect(() => {
    rememberReferral({ code: invite.code, channel: source.channel, event_id: source.event_id });
    if (status !== "authenticated" || !token) return;
    let cancelled = false;
    queueMicrotask(() => {
      if (!cancelled) setClaim({ kind: "claiming" });
    });
    void claimPendingReferrals(token).then((results) => {
      if (cancelled) return;
      void queryClient.invalidateQueries({ queryKey: REFERRALS_KEY });
      const result = results.get(codeKey(invite.code));
      // Not kept any more (another tab claimed it first): the invite stands.
      if (result === "failed") setClaim({ kind: "failed" });
      else setClaim({ kind: "done", result: result ?? { outcome: "unchanged", box: { slug: box.slug, name: box.name } } });
    });
    return () => {
      cancelled = true;
    };
  }, [box.name, box.slug, invite.code, queryClient, source.channel, source.event_id, status, token]);

  const facts = [box.disciplines.slice(0, 2).map((key) => tags(`discipline.${key}`)).join(" · "), box.neighbourhood]
    .filter(Boolean)
    .join(" · ");

  return (
    <HubPage title={t("invite.heading")}>
      <section className="overflow-hidden rounded-3xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {box.cover?.url ? (
          // eslint-disable-next-line @next/next/no-img-element -- media origin
          <img src={box.cover.url} alt="" className="h-40 w-full object-cover" />
        ) : null}
        <div className="flex items-center gap-4 p-5">
          {box.logo_url ? (
            // eslint-disable-next-line @next/next/no-img-element -- media origin
            <img src={box.logo_url} alt="" className="h-14 w-14 shrink-0 rounded-2xl object-cover" />
          ) : (
            <span
              aria-hidden="true"
              className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl text-lg font-extrabold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {box.name.slice(0, 2).toUpperCase()}
            </span>
          )}
          <div className="min-w-0">
            <p className="truncate text-xl font-extrabold" style={{ color: "var(--text)" }}>{box.name}</p>
            {facts ? <p className="truncate text-sm" style={{ color: "var(--dim)" }}>{facts}</p> : null}
          </div>
        </div>
      </section>

      <HubCard highlighted>
        <div className="flex items-center gap-3">
          <PersonAvatar name={name} url={invite.inviter.avatar_url} size={44} />
          <p className="text-base font-bold" style={{ color: "var(--text)" }}>
            {name ? t("invite.from", { name, box: box.name }) : t("invite.fromMember", { box: box.name })}
          </p>
        </div>
        {source.event_id ? (
          <p className="mt-3 text-sm" style={{ color: "var(--text-soft)" }}>{t("invite.toEvent")}</p>
        ) : null}
        {gift ? (
          <p className="mt-3 text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("invite.gift", { gift })}</p>
        ) : null}
        {gift && invite.window_days ? (
          <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{t("invite.giftWhen")}</p>
        ) : null}
      </HubCard>

      {status === "authenticated" ? (
        <ClaimResult state={claim} invite={invite} eventId={source.event_id} />
      ) : status === "guest" ? (
        <HubCard>
          <div className="flex flex-col gap-2">
            <HubButton primary href={`/register?next=${encodeURIComponent(here)}`}>{t("invite.signUp")}</HubButton>
            <HubButton href={`/login?next=${encodeURIComponent(here)}`}>{t("invite.signIn")}</HubButton>
            {box.published ? (
              <Link href={`/b/${encodeURIComponent(box.slug)}`} className="py-2 text-center text-sm font-semibold underline" style={{ color: "var(--text-soft)" }}>
                {t("invite.seeBox")}
              </Link>
            ) : null}
          </div>
        </HubCard>
      ) : null}

      <p className="px-1 text-xs leading-5" style={{ color: "var(--dim)" }}>
        {name ? t("invite.consent", { name }) : t("invite.consentNoName")}
      </p>
    </HubPage>
  );
}

function ClaimResult({ state, invite, eventId }: { state: ClaimState; invite: ReferralInvitePage; eventId: string | null }) {
  const t = useTranslations("Referrals");
  const box = invite.box;
  const boxHref = `/b/${encodeURIComponent(box.slug)}`;

  if (state.kind === "idle" || state.kind === "claiming") {
    return (
      <HubCard>
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("invite.claiming")}</p>
      </HubCard>
    );
  }
  if (state.kind === "failed") {
    return (
      <HubCard>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("invite.failed")}</p>
      </HubCard>
    );
  }

  const outcome = state.result.outcome;
  const accepted = outcome === "claimed" || outcome === "unchanged";
  const message =
    outcome === "already_member"
      ? t("invite.alreadyMember", { box: box.name })
      : outcome === "already_invited"
        ? t("invite.alreadyInvited")
        : outcome === "self"
          ? t("invite.self")
          : t("invite.claimed", { box: box.name });

  return (
    <HubCard>
      <p className="text-sm font-semibold" style={{ color: accepted ? "var(--success)" : "var(--text-soft)" }} role="status">
        {message}
      </p>
      <div className="mt-4 flex flex-col gap-2">
        {outcome === "self" ? (
          <HubButton primary href={`/me/referrals?box=${encodeURIComponent(box.slug)}`}>{t("invite.openMine")}</HubButton>
        ) : (
          <>
            {eventId && outcome !== "already_member" ? (
              <HubButton primary href={`/events/${encodeURIComponent(eventId)}`}>{t("invite.openEvent")}</HubButton>
            ) : null}
            {box.published && invite.trials_enabled && outcome !== "already_member" ? (
              <HubButton primary={!eventId} href={`${boxHref}?trial=1`}>{t("invite.bookTrial")}</HubButton>
            ) : null}
            {box.published ? <HubButton href={boxHref}>{t("invite.seeBox")}</HubButton> : null}
          </>
        )}
      </div>
    </HubCard>
  );
}

/** A code that no longer leads anywhere. */
export function InviteNotFound() {
  const t = useTranslations("Referrals");
  return (
    <HubPage title={t("invite.heading")}>
      <HubCard>
        <p className="text-base font-bold" style={{ color: "var(--text)" }}>{t("invite.gone")}</p>
        <p className="mt-2 text-sm" style={{ color: "var(--text-soft)" }}>{t("invite.goneHint")}</p>
        <div className="mt-4 flex">
          <HubButton href="/">{t("invite.home")}</HubButton>
        </div>
      </HubCard>
    </HubPage>
  );
}
