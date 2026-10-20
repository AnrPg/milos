"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";

import {
  STAFF_REFERRALS_KEY,
  applyFriendGift,
  approveReferral,
  fetchStaffReferrals,
  markReferralGiven,
  reassignReferral,
  rejectReferral,
  staffReferralsKey,
  type StaffReferralFilter,
  type StaffReferralInvite,
} from "@/api/referrals";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";
import {
  giftText,
  reachedSteps,
  rewardStatusText,
  rewardText,
  sortForStaff,
  stageText,
  type Translate,
} from "@/components/referrals/referrals";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * «Οικονομικά › Συστάσεις», the invites (ADR-156): who brought whom, how far
 * the friend got, and the decisions staff take: approve or reject a reward,
 * hand over one that is given by hand, apply the friend's gift on the first
 * sale, or give the invite to another member (board 11 Q4) with a note.
 */
export function ReferralInvites() {
  const t = useTranslations("Referrals");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [filter, setFilter] = useState<StaffReferralFilter>("review");
  const [openId, setOpenId] = useState<string | null>(null);
  const list = useQuery({
    queryKey: staffReferralsKey(filter),
    enabled: Boolean(token),
    queryFn: () => fetchStaffReferrals(token, filter),
  });
  const invites = sortForStaff(list.data?.invites ?? []);
  const open = invites.find((invite) => invite.id === openId) ?? null;
  const stats = list.data?.stats ?? {};

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
          {t("staff.title")}
        </p>
        <div role="radiogroup" aria-label={t("staff.filter")} className="flex rounded-full p-0.5" style={{ background: "var(--border)" }}>
          {(["review", "all"] as const).map((value) => (
            <button
              key={value}
              type="button"
              role="radio"
              aria-checked={filter === value}
              onClick={() => setFilter(value)}
              className="rounded-full px-4 py-1.5 text-sm font-semibold"
              style={filter === value ? { background: "var(--text)", color: "var(--bg)" } : { color: "var(--dim)" }}
            >
              {t(`staff.filter_${value}`)}
            </button>
          ))}
        </div>
      </div>

      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {t("staff.stats", {
          open: stats.open ?? 0,
          qualified: stats.qualified ?? 0,
          expired: stats.expired ?? 0,
        })}
      </p>

      <div className="overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {list.isPending ? (
          <p className="px-6 py-6 text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : invites.length === 0 ? (
          <p className="px-6 py-6 text-sm" style={{ color: "var(--dim)" }}>
            {filter === "review" ? t("staff.emptyReview") : t("staff.empty")}
          </p>
        ) : (
          invites.map((invite, index) => (
            <InviteRow key={invite.id} invite={invite} last={index === invites.length - 1} onOpen={() => setOpenId(invite.id)} />
          ))
        )}
      </div>

      {open ? <InvitePanel invite={open} onClose={() => setOpenId(null)} /> : null}
    </div>
  );
}

function names(invite: StaffReferralInvite, t: Translate) {
  return {
    friend: invite.friend.nickname ?? t("list.someone"),
    referrer: invite.referrer?.nickname ?? t("staff.noReferrer"),
  };
}

function statusLine(invite: StaffReferralInvite, t: Translate) {
  if (invite.reward && invite.reward.status !== "upcoming" && invite.reward.status !== "none") {
    return rewardStatusText(invite.reward.status, t);
  }
  return t(`status.${invite.status}`);
}

function InviteRow({ invite, last, onOpen }: { invite: StaffReferralInvite; last: boolean; onOpen: () => void }) {
  const t = useTranslations("Referrals");
  const who = names(invite, t);
  const waiting = invite.reward?.status === "pending";
  return (
    <button
      type="button"
      onClick={onOpen}
      className="flex w-full flex-wrap items-center justify-between gap-4 px-6 py-4 text-start"
      style={{ borderBottom: last ? "none" : "1px solid var(--border)" }}
    >
      <span className="min-w-0">
        <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("staff.row", { friend: who.friend, referrer: who.referrer })}
        </span>
        <span className="mt-0.5 block text-xs" style={{ color: "var(--dim)" }}>
          {[stageText(invite.stage, t), t(`channel.${invite.channel}`), invite.program?.name].filter(Boolean).join(" · ")}
        </span>
      </span>
      <span
        className="rounded-full px-3 py-1 text-xs font-semibold"
        style={
          waiting
            ? { background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }
            : { background: "var(--border)", color: "var(--text-soft)" }
        }
      >
        {statusLine(invite, t)}
      </span>
    </button>
  );
}

function InvitePanel({ invite, onClose }: { invite: StaffReferralInvite; onClose: () => void }) {
  const t = useTranslations("Referrals");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [note, setNote] = useState("");
  const [reassigning, setReassigning] = useState(false);
  const [newReferrer, setNewReferrer] = useState("");
  const who = names(invite, t);
  const reward = invite.reward ? rewardText(invite.reward, t, locale) : null;
  const gift = giftText(invite.friend_gift, t, locale);
  const dateTime = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric" });

  const action = useMutation({
    mutationFn: (kind: "approve" | "reject" | "given" | "gift" | "reassign") => {
      const text = note.trim() || null;
      switch (kind) {
        case "approve":
          return approveReferral(token, invite.id);
        case "reject":
          return rejectReferral(token, invite.id, text);
        case "given":
          return markReferralGiven(token, invite.id);
        case "gift":
          return applyFriendGift(token, invite.id);
        case "reassign":
          return reassignReferral(token, invite.id, newReferrer, text);
      }
    },
    onSuccess: async () => {
      setReassigning(false);
      setNote("");
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: STAFF_REFERRALS_KEY }),
        queryClient.invalidateQueries({ queryKey: ["admin", "finance"] }),
      ]);
    },
  });

  const status = invite.reward?.status;
  const canReassign = invite.status === "open" || invite.status === "expired" || invite.status === "void";
  const canGift = Boolean(invite.friend_gift) && !invite.friend_gift_applied_at && invite.status !== "void";

  return (
    <SidePanel
      title={t("staff.row", { friend: who.friend, referrer: who.referrer })}
      subtitle={t("staff.panel")}
      onClose={onClose}
      footer={
        <div className="flex flex-wrap gap-2">
          {status === "pending" ? (
            <>
              <PanelButton primary disabled={action.isPending} onClick={() => action.mutate("approve")}>{t("staff.approve")}</PanelButton>
              <PanelButton danger disabled={action.isPending} onClick={() => action.mutate("reject")}>{t("staff.reject")}</PanelButton>
            </>
          ) : null}
          {status === "approved" ? (
            <PanelButton primary disabled={action.isPending} onClick={() => action.mutate("given")}>{t("staff.given")}</PanelButton>
          ) : null}
          {canGift ? (
            <PanelButton disabled={action.isPending} onClick={() => action.mutate("gift")}>{t("staff.applyGift")}</PanelButton>
          ) : null}
          {canReassign && !reassigning ? (
            <PanelButton disabled={action.isPending} onClick={() => setReassigning(true)}>{t("staff.reassign")}</PanelButton>
          ) : null}
        </div>
      }
    >
      <div className="space-y-4">
        <ol className="space-y-1.5">
          {reachedSteps(invite).map((step) => (
            <li key={step.stage} className="flex justify-between gap-3 text-sm">
              <span style={{ color: "var(--text)" }}>{stageText(step.stage, t)}</span>
              <span style={{ color: "var(--dim)" }}>{dateTime.format(new Date(step.at))}</span>
            </li>
          ))}
        </ol>

        <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
          <dt style={{ color: "var(--dim)" }}>{t("staff.status")}</dt>
          <dd style={{ color: "var(--text-soft)" }}>{statusLine(invite, t)}{invite.void_reason ? ` · ${t(`staff.void_${invite.void_reason === "referrer_not_eligible" ? "staff" : "other"}`)}` : ""}</dd>
          <dt style={{ color: "var(--dim)" }}>{t("staff.channel")}</dt>
          <dd style={{ color: "var(--text-soft)" }}>{t(`channel.${invite.channel}`)}{invite.new_account ? ` · ${t("staff.newAccount")}` : ""}</dd>
          <dt style={{ color: "var(--dim)" }}>{t("staff.window")}</dt>
          <dd style={{ color: "var(--text-soft)" }}>{t("staff.until", { date: dateTime.format(new Date(invite.expires_at)) })}</dd>
          {invite.program ? (
            <>
              <dt style={{ color: "var(--dim)" }}>{t("staff.program")}</dt>
              <dd style={{ color: "var(--text-soft)" }}>{invite.program.name}</dd>
            </>
          ) : null}
          {reward ? (
            <>
              <dt style={{ color: "var(--dim)" }}>{t("staff.reward")}</dt>
              <dd style={{ color: "var(--text-soft)" }}>{reward}</dd>
            </>
          ) : null}
          {gift ? (
            <>
              <dt style={{ color: "var(--dim)" }}>{t("staff.gift")}</dt>
              <dd style={{ color: "var(--text-soft)" }}>
                {gift}
                {invite.friend_gift_applied_at ? ` · ${t("staff.giftApplied", { date: dateTime.format(new Date(invite.friend_gift_applied_at)) })}` : ""}
              </dd>
            </>
          ) : null}
          {invite.previous_referrer ? (
            <>
              <dt style={{ color: "var(--dim)" }}>{t("staff.previous")}</dt>
              <dd style={{ color: "var(--text-soft)" }}>{invite.previous_referrer.nickname ?? t("list.someone")}</dd>
            </>
          ) : null}
          {invite.notes ? (
            <>
              <dt style={{ color: "var(--dim)" }}>{t("staff.notes")}</dt>
              <dd className="whitespace-pre-wrap" style={{ color: "var(--text-soft)" }}>{invite.notes}</dd>
            </>
          ) : null}
        </dl>

        {reassigning ? (
          <div className="space-y-2">
            <UserSearchField
              label={t("staff.newReferrer")}
              value={newReferrer}
              token={token}
              onChange={(userId) => setNewReferrer(userId)}
              excludeUserId={invite.friend.id}
            />
            <div className="flex gap-2">
              <PanelButton primary disabled={!newReferrer || action.isPending} onClick={() => action.mutate("reassign")}>
                {t("staff.reassignSave")}
              </PanelButton>
              <PanelButton onClick={() => setReassigning(false)}>{t("staff.cancel")}</PanelButton>
            </div>
          </div>
        ) : null}

        {status === "pending" || reassigning ? (
          <label className="block space-y-1">
            <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("staff.note")}</span>
            <textarea
              value={note}
              maxLength={500}
              onChange={(event) => setNote(event.target.value)}
              rows={2}
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
          </label>
        ) : null}

        {action.error ? (
          <p role="alert" className="text-sm" style={{ color: "var(--primary-strong)" }}>{localizeError(action.error, i18n)}</p>
        ) : null}
      </div>
    </SidePanel>
  );
}

function PanelButton({
  children,
  onClick,
  primary,
  danger,
  disabled,
}: {
  children: React.ReactNode;
  onClick: () => void;
  primary?: boolean;
  danger?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
      style={
        primary
          ? { background: "var(--text)", color: "var(--bg)" }
          : danger
            ? { background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 30%, transparent)", color: "var(--primary)" }
            : { background: "var(--border)", color: "var(--text-soft)" }
      }
    >
      {children}
    </button>
  );
}

