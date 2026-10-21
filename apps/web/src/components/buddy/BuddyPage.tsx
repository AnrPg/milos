"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BUDDIES_KEY, changeBuddyLink, updateBuddyLink, updateBuddySettings, type BuddyLink, type BuddySettings } from "@/api/buddies";
import { currentZone } from "@/api/wellness";
import { Card, Eyebrow, PillButton, dateFormat } from "@/components/body/BodyBits";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { ChoicePill, ErrorLine } from "@/components/community/Sheet";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { AddBuddySheet } from "./AddBuddySheet";
import { BackLink, CountBadge, HeartIcon, Muted, SwitchRow } from "./BuddyBits";
import { activeBuddies, freeBuddySlots, key, overviewLists, personName, quietHoursLabel, validQuietHours, visibleLinks } from "./buddy-model";
import { buddyErrorMessage } from "./errors";
import { NeedSupportSheet } from "./SupportSend";
import { useBuddies, useBuddyToken } from "./use-buddies";

/**
 * Εγώ › Buddy για στήριξη (ADR-160, board 15, mockup «buddy»): up to two
 * people of mine, each with what they receive; the people I support with
 * their invitations; quiet hours and phone sharing (off by default). Either
 * side can stop any time; the other sees it here, without a push.
 */
export function BuddyPage() {
  const t = useTranslations("Buddy");
  const overview = useBuddies();
  const [adding, setAdding] = useState(false);
  const [asking, setAsking] = useState(false);

  if (overview.isPending) return <LoadingLine />;
  if (overview.isError) return <QueryProblem error={overview.error} onRetry={() => void overview.refetch()} />;

  const lists = overviewLists(overview.data);
  const mine = visibleLinks(lists.buddies);
  const supporting = visibleLinks(lists.supporting);
  const free = freeBuddySlots(overview.data);
  const canAsk = activeBuddies(overview.data).length > 0;

  return (
    <div className="flex flex-col gap-4">
      <div>
        <BackLink href="/me">{t("backToMe")}</BackLink>
        <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("title")}</h1>
        <Muted>{t("intro")}</Muted>
      </div>

      <Card label={t("myBuddies")}>
        <Eyebrow>{t("myBuddies")}</Eyebrow>
        {mine.length === 0 ? <Muted>{t("noBuddies")}</Muted> : null}
        <ul className="flex flex-col gap-4">
          {mine.map((link) => (
            <li key={link.id}>
              <MyBuddy link={link} />
            </li>
          ))}
        </ul>
        {free > 0 ? (
          <button
            type="button"
            onClick={() => setAdding(true)}
            className="flex min-h-11 items-center justify-center gap-2 rounded-2xl px-4 text-sm font-bold"
            style={{ background: mine.length === 0 ? "var(--primary)" : "var(--panel-raised)", color: mine.length === 0 ? "var(--primary-contrast)" : "var(--text)", border: "1px solid var(--border)" }}
          >
            {t("add")}
          </button>
        ) : (
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("full", { max: lists.maxBuddies })}</p>
        )}
        {canAsk ? (
          <button
            type="button"
            onClick={() => setAsking(true)}
            className="flex min-h-11 items-center justify-center gap-2 rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
          >
            <HeartIcon />
            {t("needSupport")}
          </button>
        ) : null}
      </Card>

      {lists.invitations.length > 0 ? (
        <Card label={t("invitationsTitle")}>
          <Eyebrow>{t("invitationsTitle")}</Eyebrow>
          <ul className="flex flex-col gap-3">
            {lists.invitations.map((link) => (
              <li key={link.id}>
                <Invitation link={link} />
              </li>
            ))}
          </ul>
        </Card>
      ) : null}

      <Card label={t("supportingTitle")}>
        <Eyebrow>{t("supportingTitle")}</Eyebrow>
        {supporting.length === 0 ? <Muted>{t("supportingEmpty")}</Muted> : null}
        <ul className="flex flex-col gap-3">
          {supporting.map((link) => (
            <li key={link.id}>
              <Supported link={link} />
            </li>
          ))}
        </ul>
      </Card>

      <MySettings settings={overview.data.settings ?? null} />

      <p className="px-1 text-xs leading-5" style={{ color: "var(--dim)" }} data-testid="buddy-footer">{t("footer")}</p>

      {adding ? <AddBuddySheet inviteDays={lists.inviteDays} onClose={() => setAdding(false)} /> : null}
      {asking ? <NeedSupportSheet onClose={() => setAsking(false)} /> : null}
    </div>
  );
}

function useLinkAction() {
  const token = useBuddyToken();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, action }: { id: string; action: "accept" | "decline" | "leave" }) => changeBuddyLink(token!, id, action),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: BUDDIES_KEY }),
  });
}

function statusLine(link: BuddyLink, t: ReturnType<typeof useTranslations>, dates: ReturnType<typeof dateFormat>) {
  if (link.status === "pending") {
    return link.expires_at ? t("statusPendingUntil", { date: dates.day(link.expires_at) }) : t("statusPending");
  }
  if (link.status === "active") return link.started_at ? t("statusActiveSince", { date: dates.dayYear(link.started_at) }) : t("statusActive");
  if (link.status === "ended") return link.ended_by_me ? t("statusEndedByMe") : t("statusEndedByThem");
  return t(key("status", link.status));
}

function PersonHeader({ link, chat }: { link: BuddyLink; chat: boolean }) {
  const t = useTranslations("Buddy");
  const locale = useUiLocale();
  const dates = dateFormat(locale);
  const name = link.person ? personName(link.person, t("someone")) : t("unclaimedLink");
  const unread = link.unread_messages ?? 0;
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="flex min-w-0 items-center gap-3">
        <PersonAvatar name={name} url={link.person?.avatar_url} size={44} />
        <span className="min-w-0">
          <span className="block truncate text-base font-bold" style={{ color: "var(--text)" }}>{name}</span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }} data-testid="buddy-status">{statusLine(link, t, dates)}</span>
        </span>
      </span>
      {chat ? (
        <Link
          href={`/me/buddy/${encodeURIComponent(link.id)}/chat`}
          className="inline-flex min-h-9 shrink-0 items-center gap-2 rounded-full px-3 text-xs font-bold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("chat")}
          <CountBadge count={unread} label={t("unreadCount", { count: unread })} />
        </Link>
      ) : null}
    </div>
  );
}

/** One of my buddies: status, what they receive, leave (or withdraw) after a confirm. */
function MyBuddy({ link }: { link: BuddyLink }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const token = useBuddyToken();
  const queryClient = useQueryClient();
  const action = useLinkAction();
  const [confirm, setConfirm] = useState(false);
  const receives = useMutation({
    mutationFn: (weekly: boolean) => updateBuddyLink(token!, link.id, { receives_weekly_summary: weekly }),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: BUDDIES_KEY }),
  });
  const open = link.status === "pending" || link.status === "active";
  const name = link.person ? personName(link.person, t("someone")) : t("unclaimedLink");
  const weekly = receives.isPending && receives.variables !== undefined ? receives.variables : link.receives_weekly_summary;

  return (
    <div className="flex flex-col gap-3">
      <PersonHeader link={link} chat={Boolean(link.started_at)} />
      {open ? (
        <div className="flex flex-col gap-2" role="radiogroup" aria-label={t("receivesTitle", { name })}>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("receivesTitle", { name })}</p>
          <ChoicePill selected={!weekly} onSelect={() => receives.mutate(false)} hint={t("receivesOnlyHint")}>
            {t("receivesOnly")}
          </ChoicePill>
          <ChoicePill selected={weekly} onSelect={() => receives.mutate(true)} hint={t("receivesWeeklyHint")}>
            {t("receivesWeekly")}
          </ChoicePill>
          <ErrorLine message={buddyErrorMessage(receives.error, t, tUi)} />
        </div>
      ) : null}
      {open ? (
        <LeaveControl
          confirm={confirm}
          setConfirm={setConfirm}
          label={link.status === "pending" ? t("withdraw") : t("stop")}
          question={link.status === "pending" ? t("withdrawConfirm", { name }) : t("stopConfirm", { name })}
          busy={action.isPending}
          onConfirm={() => action.mutate({ id: link.id, action: "leave" }, { onSuccess: () => setConfirm(false) })}
        />
      ) : null}
      <ErrorLine message={buddyErrorMessage(action.error, t, tUi)} />
    </div>
  );
}

function Invitation({ link }: { link: BuddyLink }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const action = useLinkAction();
  const name = personName(link.person, t("someone"));
  return (
    <div className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "color-mix(in srgb, var(--primary) 8%, var(--panel))", border: "1px solid var(--border)" }}>
      <PersonHeader link={link} chat={false} />
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("invitationBody", { name })}</p>
      <div className="flex gap-2">
        <PillButton disabled={action.isPending} onClick={() => action.mutate({ id: link.id, action: "decline" })}>{t("decline")}</PillButton>
        <PillButton primary disabled={action.isPending} onClick={() => action.mutate({ id: link.id, action: "accept" })}>{t("accept")}</PillButton>
      </div>
      <ErrorLine message={buddyErrorMessage(action.error, t, tUi)} />
    </div>
  );
}

function Supported({ link }: { link: BuddyLink }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const action = useLinkAction();
  const [confirm, setConfirm] = useState(false);
  const name = personName(link.person, t("someone"));
  return (
    <div className="flex flex-col gap-2">
      <PersonHeader link={link} chat={Boolean(link.started_at)} />
      {link.status === "active" ? (
        <>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{link.receives_weekly_summary ? t("supportingWeekly") : t("supportingOnly")}</p>
          <LeaveControl
            confirm={confirm}
            setConfirm={setConfirm}
            label={t("stop")}
            question={t("stopSupportingConfirm", { name })}
            busy={action.isPending}
            onConfirm={() => action.mutate({ id: link.id, action: "leave" }, { onSuccess: () => setConfirm(false) })}
          />
        </>
      ) : null}
      <ErrorLine message={buddyErrorMessage(action.error, t, tUi)} />
    </div>
  );
}

function LeaveControl({
  confirm,
  setConfirm,
  label,
  question,
  busy,
  onConfirm,
}: {
  confirm: boolean;
  setConfirm: (next: boolean) => void;
  label: string;
  question: string;
  busy: boolean;
  onConfirm: () => void;
}) {
  const t = useTranslations("Buddy");
  if (!confirm) {
    return (
      <div>
        <PillButton onClick={() => setConfirm(true)}>{label}</PillButton>
      </div>
    );
  }
  return (
    <div className="flex flex-col gap-2 rounded-2xl p-3" role="group" aria-label={label} style={{ background: "var(--panel-raised)" }}>
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{question}</p>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("stopQuiet")}</p>
      <div className="flex gap-2">
        <PillButton onClick={() => setConfirm(false)}>{t("cancel")}</PillButton>
        <PillButton danger disabled={busy} onClick={onConfirm}>{t("stopYes")}</PillButton>
      </div>
    </div>
  );
}

/** Quiet hours (requests still arrive, silently) and the phone for «Πάρε με τηλέφωνο», off by default. */
function MySettings({ settings }: { settings: BuddySettings | null }) {
  const t = useTranslations("Buddy");
  const tUi = useUiTranslations();
  const token = useBuddyToken();
  const queryClient = useQueryClient();
  const [quietOn, setQuietOn] = useState(Boolean(settings?.quiet_hours));
  const [from, setFrom] = useState(settings?.quiet_hours?.from ?? "23:00");
  const [to, setTo] = useState(settings?.quiet_hours?.to ?? "07:00");
  const [sharePhone, setSharePhone] = useState(settings?.share_phone ?? false);
  const [phone, setPhone] = useState(settings?.phone ?? "");
  const save = useMutation({
    mutationFn: () =>
      updateBuddySettings(token!, {
        tz: currentZone(),
        quiet_hours: quietOn ? { from, to } : null,
        share_phone: sharePhone,
        phone: phone.trim() || null,
      }),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: BUDDIES_KEY }),
  });
  const timesValid = !quietOn || validQuietHours(from, to);
  const phoneMissing = sharePhone && !phone.trim();
  const saved = quietHoursLabel(settings?.quiet_hours);
  const inputStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

  return (
    <Card label={t("settingsTitle")}>
      <Eyebrow>{t("settingsTitle")}</Eyebrow>
      <SwitchRow checked={quietOn} onChange={setQuietOn} label={t("quietHours")} hint={t("quietHoursHint")} />
      {quietOn ? (
        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
            {t("quietFrom")}
            <input type="time" value={from} onChange={(event) => setFrom(event.target.value)} className="min-h-11 rounded-2xl px-3" style={inputStyle} />
          </label>
          <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
            {t("quietTo")}
            <input type="time" value={to} onChange={(event) => setTo(event.target.value)} className="min-h-11 rounded-2xl px-3" style={inputStyle} />
          </label>
        </div>
      ) : null}
      {saved ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("quietSaved", { range: saved })}</p> : null}
      <div className="border-t pt-3" style={{ borderColor: "var(--border)" }}>
        <SwitchRow checked={sharePhone} onChange={setSharePhone} label={t("sharePhone")} hint={t("sharePhoneHint")} />
        {sharePhone ? (
          <label className="mt-2 flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
            {t("phone")}
            <input
              type="tel"
              inputMode="tel"
              autoComplete="tel"
              value={phone}
              onChange={(event) => setPhone(event.target.value)}
              className="min-h-11 rounded-2xl px-3 text-sm"
              style={inputStyle}
            />
          </label>
        ) : null}
      </div>
      {!timesValid ? <p className="text-xs" role="alert" style={{ color: "var(--danger)" }}>{t("errors.invalid_quiet_hours")}</p> : null}
      {phoneMissing ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("errors.phone_required")}</p> : null}
      <div>
        <PillButton primary disabled={save.isPending || !timesValid || phoneMissing} onClick={() => save.mutate()}>
          {save.isPending ? t("saving") : t("save")}
        </PillButton>
      </div>
      {save.isSuccess ? <p className="text-xs" role="status" style={{ color: "var(--muted)" }}>{t("saved")}</p> : null}
      <ErrorLine message={buddyErrorMessage(save.error, t, tUi)} />
    </Card>
  );
}
