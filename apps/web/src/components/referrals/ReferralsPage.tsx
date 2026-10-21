"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";

import { createEventInvite } from "@/api/events";
import {
  fetchMyReferrals,
  myReferralsKey,
  rotateReferralCode,
  type ReferralEvent,
  type ReferralInvite,
  type ReferralOverview,
} from "@/api/referrals";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { formatPrice, formatWhen } from "@/components/events/events";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";

import { giftText, invitePill, inviteUrl, qualifyingText, rewardText, stageText, type Tone } from "./referrals";
import { QrCode } from "./QrCode";

type ReferralsTab = "invite" | "invites";

/**
 * Εγώ › Φέρε φίλο (mockup 34, board 11 Q2 B): one page per box, in two tabs.
 * «Κάλεσε» holds the offer (what the friend gets, what the member gets and
 * when), the personal link and its QR, and an invite to an upcoming event;
 * «Οι προσκλήσεις σου» shows how each invited friend is doing (first name
 * and step, board 11 Q5 A). Members of several boxes pick the box on top.
 * `?box=` opens one box and `?tab=invites` the list (notifications link there).
 */
export function ReferralsPage() {
  const t = useTranslations("Referrals");
  const searchParams = useSearchParams();
  const router = useRouter();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const { memberships, selectedOrganizationSlug, isLoading } = useSelectedMembershipRole();
  const boxes = memberships.map((entry) => ({
    slug: entry.organization.slug,
    name: entry.settings?.brand_name?.trim() || entry.organization.name,
  }));
  const requested = searchParams.get("box");
  const tab: ReferralsTab = searchParams.get("tab") === "invites" ? "invites" : "invite";
  const slug =
    boxes.find((box) => box.slug === requested)?.slug ??
    boxes.find((box) => box.slug === selectedOrganizationSlug)?.slug ??
    boxes[0]?.slug ??
    null;

  const overview = useQuery({
    queryKey: myReferralsKey(slug ?? ""),
    enabled: Boolean(token && slug),
    queryFn: () => fetchMyReferrals(token!, slug!),
  });

  function setParam(key: "box" | "tab", value: string) {
    const params = new URLSearchParams(searchParams.toString());
    params.set(key, value);
    router.replace(`?${params.toString()}`, { scroll: false });
  }

  return (
    <HubPage title={t("title")}>
      {boxes.length > 1 ? (
        <div role="radiogroup" aria-label={t("pickBox")} className="flex gap-2 overflow-x-auto">
          {boxes.map((box) => (
            <ChoicePill key={box.slug} selected={box.slug === slug} onSelect={() => setParam("box", box.slug)}>
              {box.name}
            </ChoicePill>
          ))}
        </div>
      ) : null}

      {!isLoading && !slug ? (
        <HubCard>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("noBox")}</p>
        </HubCard>
      ) : overview.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : overview.isError ? (
        <HubCard>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("loadFailed")}</p>
        </HubCard>
      ) : (
        <Overview
          data={overview.data}
          slug={slug!}
          boxName={boxes.find((box) => box.slug === slug)?.name ?? ""}
          tab={tab}
          onTab={(next) => setParam("tab", next)}
        />
      )}
    </HubPage>
  );
}

function Overview({
  data,
  slug,
  boxName,
  tab,
  onTab,
}: {
  data: ReferralOverview;
  slug: string;
  boxName: string;
  tab: ReferralsTab;
  onTab: (tab: ReferralsTab) => void;
}) {
  const t = useTranslations("Referrals");
  const locale = useLocale();
  const [qrOpen, setQrOpen] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);
  const link = typeof window === "undefined" ? "" : inviteUrl(window.location.origin, data.code);
  const program = data.program;
  const gift = giftText(program?.gift, t, locale);
  const reward = program ? rewardText(program.reward, t, locale) : null;

  async function share(url: string, key: string, text: string) {
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ title: boxName, text, url });
        return;
      } catch {
        // Closed the share sheet: fall back to copying.
      }
    }
    try {
      await navigator.clipboard.writeText(url);
      setCopied(key);
      window.setTimeout(() => setCopied(null), 2000);
    } catch {
      setCopied(null);
    }
  }

  const tabs: { value: ReferralsTab; label: string }[] = [
    { value: "invite", label: t("tabs.invite") },
    { value: "invites", label: t("tabs.invites", { count: data.invites.length }) },
  ];

  return (
    <>
      <div
        role="tablist"
        aria-label={t("title")}
        className="grid grid-cols-2 gap-1 rounded-2xl p-1"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        {tabs.map((entry) => (
          <button
            key={entry.value}
            type="button"
            role="tab"
            aria-selected={tab === entry.value}
            onClick={() => onTab(entry.value)}
            className="min-h-11 truncate rounded-xl px-3 text-sm font-semibold"
            style={tab === entry.value ? { background: "var(--primary)", color: "var(--bg)" } : { color: "var(--text-soft)" }}
          >
            {entry.label}
          </button>
        ))}
      </div>

      {tab === "invite" ? (
        <div role="tabpanel" className="flex flex-col gap-3">
          <HubCard highlighted eyebrow={program ? `${boxName} · ${program.name}` : boxName}>
            {program ? (
              <>
                <h2 className="text-lg font-extrabold" style={{ color: "var(--text)" }}>
                  {gift ? t("offer.friend", { gift }) : t("offer.friendNothing")}
                </h2>
                {data.earns_rewards && reward ? (
                  <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>
                    {t("offer.you", { reward, when: qualifyingText(program, t) })}
                  </p>
                ) : null}
                {data.earns_rewards && program.yearly_cap ? (
                  <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{t("offer.cap", { count: program.yearly_cap })}</p>
                ) : null}
                {!data.earns_rewards ? (
                  <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>{t("offer.staff")}</p>
                ) : null}
              </>
            ) : (
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("offer.noProgram")}</p>
            )}
          </HubCard>

          <div className="flex gap-2">
            <SheetButton primary onClick={() => void share(link, "link", t("shareText", { box: boxName }))}>
              {copied === "link" ? t("copied") : t("shareLink")}
            </SheetButton>
            <SheetButton onClick={() => setQrOpen(true)}>{t("showQr")}</SheetButton>
          </div>

          {data.events.length > 0 ? (
            <HubCard eyebrow={t("events.title")}>
              <ul className="flex flex-col gap-3">
                {data.events.map((event) => (
                  <EventInviteRow
                    key={event.id}
                    event={event}
                    code={data.code}
                    copied={copied === event.id}
                    onShare={(url) => void share(url, event.id, t("events.shareText", { title: event.title }))}
                  />
                ))}
              </ul>
            </HubCard>
          ) : null}

          <NewLink slug={slug} />
        </div>
      ) : (
        <div role="tabpanel" className="flex flex-col gap-3">
          <HubCard eyebrow={t("list.title")}>
            {data.invites.length === 0 ? (
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("list.empty")}</p>
            ) : (
              <>
                <p className="mb-2 text-xs" style={{ color: "var(--dim)" }}>
                  {t("list.totals", { invited: data.totals.invited, trials: data.totals.trials, paid: data.totals.paid })}
                </p>
                <ul className="flex flex-col">
                  {data.invites.map((invite) => (
                    <InviteRow key={invite.id} invite={invite} />
                  ))}
                </ul>
              </>
            )}
          </HubCard>
        </div>
      )}

      {qrOpen ? <QrSheet code={data.code} boxName={boxName} onClose={() => setQrOpen(false)} /> : null}
    </>
  );
}

function EventInviteRow({
  event,
  code,
  copied,
  onShare,
}: {
  event: ReferralEvent;
  code: string;
  copied: boolean;
  onShare: (url: string) => void;
}) {
  const t = useTranslations("Referrals");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const { tokens } = useSession();
  const price = formatPrice(event.price_cents, event.currency, locale);
  // A guest-pass event shares the member's guest pass with their code; an open one, the invite page.
  const pass = useMutation({ mutationFn: () => createEventInvite(tokens!.access_token, event.id) });

  async function invite() {
    if (event.access === "open") {
      onShare(inviteUrl(window.location.origin, code, { eventId: event.id }));
      return;
    }
    const created = await pass.mutateAsync();
    const url = new URL(created.path, window.location.origin);
    url.searchParams.set("ref", code);
    onShare(url.toString());
  }

  return (
    <li className="flex items-center gap-3">
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{event.title}</p>
        {event.good_for_friends ? (
          <p className="text-xs font-semibold" style={{ color: "var(--primary-strong)" }}>{t("events.goodForFriends")}</p>
        ) : null}
        <p className="truncate text-xs" style={{ color: "var(--dim)" }}>
          {[formatWhen(event.starts_at, event.ends_at, locale), event.place_name, price ?? t("events.free")].filter(Boolean).join(" · ")}
        </p>
        {pass.error ? <ErrorLine message={localizeError(pass.error, i18n)} /> : null}
      </div>
      <button
        type="button"
        onClick={() => void invite().catch(() => {})}
        disabled={pass.isPending}
        className="min-h-11 shrink-0 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
      >
        {copied ? t("copied") : t("events.invite")}
      </button>
    </li>
  );
}

const TONES: Record<Tone, { background: string; color: string }> = {
  ok: { background: "color-mix(in srgb, var(--success) 14%, transparent)", color: "var(--success)" },
  accent: { background: "color-mix(in srgb, var(--primary) 14%, transparent)", color: "var(--primary-strong)" },
  neutral: { background: "var(--panel-raised)", color: "var(--text-soft)" },
  muted: { background: "var(--panel-raised)", color: "var(--dim)" },
};

function InviteRow({ invite }: { invite: ReferralInvite }) {
  const t = useTranslations("Referrals");
  const locale = useLocale();
  const pill = invitePill(invite, t);
  const reward = invite.reward && invite.reward.status === "given" ? rewardText(invite.reward, t, locale) : null;
  const name = invite.friend.nickname ?? t("list.someone");

  return (
    <li className="flex items-center gap-3 py-2">
      <PersonAvatar name={name} url={invite.friend.avatar_url} size={36} />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{name}</p>
        <p className="truncate text-xs" style={{ color: "var(--dim)" }}>
          {reward ? t("list.earned", { reward }) : stageText(invite.stage, t)}
        </p>
      </div>
      <span className="shrink-0 rounded-full px-3 py-1 text-xs font-bold" style={TONES[pill.tone]}>
        {pill.label}
      </span>
    </li>
  );
}

/** «Νέος σύνδεσμος»: for a link that went somewhere it shouldn't. */
function NewLink({ slug }: { slug: string }) {
  const t = useTranslations("Referrals");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const rotate = useMutation({
    mutationFn: () => rotateReferralCode(tokens!.access_token, slug),
    onSuccess: async () => {
      setConfirming(false);
      await queryClient.invalidateQueries({ queryKey: myReferralsKey(slug) });
    },
  });

  return (
    <div className="px-1">
      {confirming ? (
        <div className="flex flex-col gap-2">
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("newLink.confirm")}</p>
          <div className="flex gap-2">
            <SheetButton primary disabled={rotate.isPending} onClick={() => rotate.mutate()}>{t("newLink.yes")}</SheetButton>
            <SheetButton onClick={() => setConfirming(false)}>{t("newLink.no")}</SheetButton>
          </div>
          {rotate.error ? <ErrorLine message={localizeError(rotate.error, i18n)} /> : null}
        </div>
      ) : (
        <button type="button" onClick={() => setConfirming(true)} className="min-h-11 text-sm font-semibold underline" style={{ color: "var(--dim)" }}>
          {t("newLink.action")}
        </button>
      )}
    </div>
  );
}

function QrSheet({ code, boxName, onClose }: { code: string; boxName: string; onClose: () => void }) {
  const t = useTranslations("Referrals");
  const url = inviteUrl(window.location.origin, code, { via: "qr" });
  return (
    <Sheet title={t("qr.title")} eyebrow={boxName} onClose={onClose} labelId="referral-qr-title" footer={<SheetButton onClick={onClose}>{t("qr.close")}</SheetButton>}>
      <div className="flex flex-col items-center gap-3 py-2">
        <div className="rounded-2xl bg-[var(--paper)] p-4">
          <QrCode value={url} size={260} label={t("qr.alt")} />
        </div>
        <p className="font-mono text-lg font-bold tracking-[0.2em]" style={{ color: "var(--text)" }}>{code}</p>
        <p className="text-center text-sm" style={{ color: "var(--text-soft)" }}>{t("qr.hint")}</p>
      </div>
    </Sheet>
  );
}
