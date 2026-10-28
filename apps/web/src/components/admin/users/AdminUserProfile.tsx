"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";

import {
  deleteAdminUser,
  fetchAdminUserCoachingContext,
  fetchAdminUserFinance,
  fetchAdminUserIncidents,
  fetchAdminUserMessages,
  fetchAdminUserPRs,
  fetchAdminUserProfile,
  fetchAdminUserTraining,
  grantAdminUserAllowance,
  revokeAdminUserAllowance,
  updateAdminUserRole,
  type AdminUserDirectoryEntry,
  type AdminUserFinance,
  type AdminUserPR,
  type AdminUserPRMember,
} from "@/api/admin-users";
import type { PRSupportingMetrics } from "@/api/gamification";
import type { EffectiveEntitlement } from "@/api/my-finance";
import { updateFinanceMember } from "@/api/finance";
import { shouldShowAllowanceQuota } from "@/components/finance/billing-entitlement-visibility";
import { dossierMode, grantableAllowances, packageSubscriptionLabel, prSectionContentCount, visibleAdminProfileSections } from "@/components/admin/users/admin-user-profile";
import { MembershipFreezes } from "@/components/admin/users/MembershipFreezes";
import { MembershipLeaving } from "@/components/admin/users/MembershipLeaving";
import { CommitmentOverridePrompt } from "@/components/admin/finance/shared/CommitmentOverridePrompt";
import { commitmentConflict } from "@/components/admin/finance/shared/membership-commitment";
import {
  ADMIN_PROFILE_SECTION_REQUEST,
  openAdminProfileSection,
  type AdminProfileSectionRequest,
} from "@/components/admin/users/admin-profile-navigation";
import { MemberClassPlacementModal } from "@/components/admin/users/MemberClassPlacementModal";
import { HoverHint } from "@/components/HelpTooltip";
import { LocalizedScore } from "@/components/localized-score";
import { CommentList } from "@/components/journal/CommentList";
import { formatPRCardDetails } from "@/components/pantheon/pr-card-details";
import { RoleLabel, SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { allowanceLabel, localizeError, semanticLabel } from "@/i18n/presentation";
import { MemberRolesEditor } from "@/components/admin/users/MemberRolesEditor";
import { CoachAssignmentPanel } from "@/components/admin/users/CoachAssignmentPanel";
import { BoxMessagePanel } from "@/components/admin/users/BoxMessagePanel";
import { CoachNotesPanel, type CoachNoteSubjectOption } from "@/components/admin/users/CoachNotesPanel";
import { CoachBodyPanel } from "@/components/body/CoachBodyPanel";
import { CoachWellnessPanel } from "@/components/buddy/CoachWellnessPanel";
import { CoachTrainingDepthPanel } from "@/components/member-app/progress/CoachTrainingDepthPanel";
import {
  activeProfileTab,
  SECTION_TAB,
  subjectKindsFor,
  visibleProfileTabs,
  type ProfileTab,
} from "@/components/admin/users/member-profile-tabs";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can, membershipRoles } from "@/lib/role-navigation";
import { useUiTranslations } from "@/i18n/ui";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { UserProgrammingSchedule } from "@/components/admin/users/UserProgrammingSchedule";
import { IntegerInput } from "@/components/integer-input";
import { TrainingHistory } from "@/components/history/TrainingHistory";
import { defaultHistoryKind } from "@/lib/training-history";
import { sortComments } from "@/lib/journal-comments";
import { fetchUserTrainingHistory } from "@/api/training-history";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { Select } from "@/components/ui/Select";
import { DateInput } from "@/components/ui/DateInput";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

function Panel({ id, title, children }: { id: string; title: string; children: React.ReactNode; href?: string; hrefLabel?: string }) {
  const i18n = useUiTranslations();
  const [open, setOpen] = useState(true);

  useEffect(() => {
    const initialHashFrame = window.requestAnimationFrame(() => {
      if (window.location.hash === `#${id}`) setOpen(true);
    });

    function handleSectionRequest(event: Event) {
      if ((event as AdminProfileSectionRequest).detail.section === id) setOpen(true);
    }

    window.addEventListener(ADMIN_PROFILE_SECTION_REQUEST, handleSectionRequest);
    return () => {
      window.cancelAnimationFrame(initialHashFrame);
      window.removeEventListener(ADMIN_PROFILE_SECTION_REQUEST, handleSectionRequest);
    };
  }, [id]);

  return (
    <article id={id} className="scroll-mt-20 overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <button
        type="button"
        aria-expanded={open}
        aria-controls={`${id}-content`}
        onClick={() => setOpen((value) => !value)}
        className="flex w-full items-center justify-between gap-4 p-6 text-start"
      >
        <span className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>{title}</span>
        <span className="text-sm font-semibold" style={{ color: "var(--dim)" }}>{open ? i18n("hide34d8b60") : i18n("showd97d1ee")}</span>
      </button>
      {open ? (
        <div id={`${id}-content`} className="border-t px-6 pb-6 pt-4 text-sm leading-6" style={{ borderColor: "var(--border)", color: "var(--text-soft)" }}>
          {children}
        </div>
      ) : null}
    </article>
  );
}

const PROFILE_TAB_KEYS: Record<ProfileTab, string> = {
  overview: "mpTabOverview",
  training: "mpTabTraining",
  wellbeing: "mpTabWellbeing",
  body: "mpTabBody",
  coaching: "mpTabCoaching",
  finance: "mpTabFinance",
  account: "mpTabAccount",
};

function Empty({ children }: { children: React.ReactNode }) {
  return <p style={{ color: "var(--muted)" }}>{children}</p>;
}

function date(value: unknown) {
  return typeof value === "string" ? value.slice(0, 10) : "—";
}

function valueText(value: unknown) {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") return String(value);
  return "—";
}

function useDossierQuery<T>(token: string | undefined, userId: string, key: string, fn: (token: string, id: string) => Promise<T>, enabled = true) {
  return useQuery({
    queryKey: ["admin", "users", userId, key],
    enabled: Boolean(token) && enabled,
    queryFn: () => fn(token!, userId),
  });
}

function Avatar({ user }: { user: Pick<AdminUserDirectoryEntry, "nickname" | "avatar_url"> }) {
  return (
    <div className="flex h-24 w-24 shrink-0 items-center justify-center overflow-hidden rounded-[1.7rem] text-3xl font-semibold" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--primary)" }}>
      {user.avatar_url ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={user.avatar_url} alt="" className="h-full w-full object-cover" />
      ) : (
        <span>{user.nickname.slice(0, 1).toUpperCase()}</span>
      )}
    </div>
  );
}

function StatGrid({ items }: { items: Array<[string, React.ReactNode]> }) {
  return (
    <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      {items.map(([label, value]) => (
        <div key={label} className="rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <dt className="text-xs uppercase tracking-[0.14em]" style={{ color: "var(--muted)" }}>{label}</dt>
          <dd className="mt-1 font-semibold" style={{ color: "var(--text)" }}>{value}</dd>
        </div>
      ))}
    </dl>
  );
}

function DetailCard({ title, meta, value, children, plainChildren = false }: { title: React.ReactNode; meta?: React.ReactNode; value?: React.ReactNode; children?: React.ReactNode; href?: string; plainChildren?: boolean }) {
  const content = (
    <>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate font-semibold" style={{ color: "var(--text)" }}>{title}</p>
          {meta ? <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>{meta}</p> : null}
        </div>
        {value ? <strong className="tabular-nums" style={{ color: "var(--primary)" }}>{value}</strong> : null}
      </div>
      {children ? (
        <div
          className={plainChildren ? "mt-2" : "mt-3 rounded-xl p-3 opacity-90 transition-opacity group-hover:opacity-100"}
          style={plainChildren ? undefined : { background: "var(--panel-muted)", border: "1px solid var(--border)" }}
        >
          {children}
        </div>
      ) : null}
    </>
  );

  return (
    <div className="group relative rounded-[1.4rem] p-4 transition-transform hover:-translate-y-0.5" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      {content}
    </div>
  );
}

function PRCard({ pr }: { pr: AdminUserPR }) {
  const i18n = useUiTranslations();
  const details = formatPRCardDetails((pr.supporting_metrics ?? {}) as PRSupportingMetrics, i18n);

  return (
    <DetailCard
      title={pr.name}
      meta={<>{pr.higher_is_better ? i18n("higherIsBetter7aab104") : i18n("lowerIsBettercf052ba")} · {date(pr.beaten_on)}</>}
      value={<LocalizedScore value={pr.current_score} unit={pr.unit} />}
      plainChildren
    >
      {details ? <p className="text-xs" style={{ color: "var(--text-soft)" }}>{details}</p> : null}
      {pr.comments?.length ? (
        <div className="mt-2">
          <CommentList comments={sortComments(pr.comments)} />
        </div>
      ) : null}
      {pr.history.length ? (
        <div className="mt-3 border-s-2 ps-3" style={{ borderColor: "var(--primary)" }}>
          <p className="text-[10px] font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{i18n("prHistoryf17c6df")}</p>
          <div className="mt-1 space-y-1">
            {pr.history.map((entry) => {
              const historyDetails = formatPRCardDetails(entry.supporting_metrics as PRSupportingMetrics, i18n);
              return (
                <p key={entry.id} className="text-xs" style={{ color: "var(--muted)" }}>
                  <LocalizedScore value={entry.score} unit={pr.unit} /> · {date(entry.beaten_on)}{historyDetails ? ` · ${historyDetails}` : ""}
                </p>
              );
            })}
          </div>
        </div>
      ) : null}
    </DetailCard>
  );
}

function GenericRecordCard({ title, meta, detail, value, href }: { title: React.ReactNode; meta?: React.ReactNode; detail?: React.ReactNode; value?: React.ReactNode; href?: string }) {
  return (
    <DetailCard title={title} meta={meta} value={value} href={href}>
      {detail}
    </DetailCard>
  );
}

function AdminEntitlements({ token, userId, entitlement, onRefresh }: { token: string; userId: string; entitlement: EffectiveEntitlement | null | undefined; onRefresh: () => Promise<unknown> }) {
  const i18n = useUiTranslations();
  const [form, setForm] = useState({ allowance: "class_visits" as string, quantity: 1, period: "calendar_month" as "calendar_week" | "calendar_month" | "subscription_period", reason: "" });
  const [revokeTarget, setRevokeTarget] = useState<string | null>(null);
  const [revokeReason, setRevokeReason] = useState("");
  const grant = useMutation({ mutationFn: () => grantAdminUserAllowance(token, userId, form), onSuccess: async () => { setForm((value) => ({ ...value, quantity: 1, reason: "" })); await onRefresh(); } });
  const revoke = useMutation({ mutationFn: () => revokeAdminUserAllowance(token, userId, revokeTarget!, revokeReason), onSuccess: async () => { setRevokeTarget(null); setRevokeReason(""); await onRefresh(); } });
  const entries = entitlement?.usage_entries ?? [];
  const revoked = new Set(entries.filter((entry) => entry.parent_entry_id).map((entry) => entry.parent_entry_id));

  return (
    <>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        {Object.entries(entitlement?.allowances ?? {}).filter(([key]) => key !== "coaching_touchpoints").map(([key, allowance]) => allowance ? <div key={key} className="rounded-xl p-3" style={{ background: "var(--panel-muted)" }}><p className="font-semibold">{allowanceLabel(key, i18n, entitlement?.class_type_names)}</p>{shouldShowAllowanceQuota(allowance) ? <p>{String(allowance.remaining)} {i18n("remainingOf8553660")} {String(allowance.limit)}{allowance.extensions > 0 ? i18n("personalExtensionCount", { count: allowance.extensions }) : ""}</p> : null}<p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("resetsAftere96e46e")} {date(allowance.period_end)}</p></div> : null)}
      </div>
      <div className="mt-5 space-y-5 rounded-2xl p-4" style={{ border: "1px solid var(--border)" }}>
        <form className="space-y-3" onSubmit={(event) => { event.preventDefault(); grant.mutate(); }}>
          <p className="font-semibold" style={{ color: "var(--text)" }}>{i18n("extendThisUserSAllowance6e08374")}</p>
          <div className="grid gap-3 sm:grid-cols-3">
            <Select aria-label={i18n("classVisits142b3b0")} value={form.allowance} onValueChange={(value) => setForm({ ...form, allowance: value })} className="rounded-xl px-3 py-2" style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)", colorScheme: "dark" }}>{grantableAllowances(entitlement?.allowances).map((key) => <option key={key} value={key}>{allowanceLabel(key, i18n, entitlement?.class_type_names)}</option>)}</Select>
            <IntegerInput aria-label={i18n("additionalUnits1d9dac0")} min={1} value={form.quantity} emptyValue={1} onValueChange={(quantity) => setForm({ ...form, quantity: quantity ?? 1 })} className="rounded-xl px-3 py-2" style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)" }} />
            <Select value={form.period} onValueChange={(value) => setForm({ ...form, period: value as typeof form.period })} className="rounded-xl px-3 py-2" style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)", colorScheme: "dark" }}><option value="calendar_week">{i18n("thisCalendarWeekb05ceca")}</option><option value="calendar_month">{i18n("thisCalendarMonthbb33495")}</option><option value="subscription_period">{i18n("subscriptionPeriod22e7508")}</option></Select>
          </div>
          <textarea required minLength={3} placeholder={i18n("reasonForThisPersonalExtensionbe8ddf7")} value={form.reason} onChange={(event) => setForm({ ...form, reason: event.target.value })} className="min-h-20 w-full rounded-xl px-3 py-2" style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--border)" }} />
          <button disabled={grant.isPending || form.reason.trim().length < 3} className="rounded-full px-4 py-2 font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>{grant.isPending ? i18n("extending80e2fcd") : i18n("extendAllowance2d3fd3a")}</button>
          {grant.isError ? <ErrorNotice>{i18n("theExtensionCouldNotBeRecorded8e3fe5d")}</ErrorNotice> : null}
        </form>
        <div className="mt-5 space-y-2">
          <p className="font-semibold" style={{ color: "var(--text)" }}>{i18n("personalExtensionHistory752eda5")}</p>
          {entries.filter((entry) => entry.allowance_key !== "coaching_touchpoints" && entry.event_type === "adjustment" && entry.quantity_delta < 0).map((entry) => <div key={entry.id} className="rounded-xl p-3" style={{ background: "var(--panel-muted)" }}><div className="flex flex-wrap items-center justify-between gap-2"><div><strong>+{Math.abs(entry.quantity_delta)} {allowanceLabel(entry.allowance_key, i18n, entitlement?.class_type_names)}</strong><p className="text-xs" style={{ color: "var(--muted)" }}>{entry.reason} · {date(entry.inserted_at)} {i18n("validThrough263dc88")} {date(entry.period_end)}</p></div>{revoked.has(entry.id) ? <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{i18n("revoked85f17ac")}</span> : <button type="button" onClick={() => setRevokeTarget(entry.id)} className="text-xs font-semibold" style={{ color: "var(--danger)" }}>{i18n("revoke0be7207")}</button>}</div>{revokeTarget === entry.id ? <form className="mt-3 flex flex-col gap-2 sm:flex-row" onSubmit={(event) => { event.preventDefault(); revoke.mutate(); }}><input required minLength={3} value={revokeReason} onChange={(event) => setRevokeReason(event.target.value)} placeholder={i18n("reasonForRevocationac5b98c")} className="min-w-0 flex-1 rounded-xl px-3 py-2" style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }} /><button disabled={revoke.isPending || revokeReason.trim().length < 3} className="rounded-full px-3 py-2 text-xs font-semibold disabled:opacity-50" style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}>{i18n("confirmRevocationc1a9d03")}</button></form> : null}</div>)}
          {entries.every((entry) => entry.allowance_key === "coaching_touchpoints" || entry.event_type !== "adjustment" || entry.quantity_delta >= 0) ? <Empty>{i18n("noPersonalExtensionsRecorded558dcb3")}</Empty> : null}
        </div>
      </div>
    </>
  );
}

function FinanceDetails({
  finance,
  token,
  userId,
  effectiveEntitlement,
  creditBalance,
  onRefresh,
}: {
  finance: AdminUserFinance;
  token: string;
  userId: string;
  effectiveEntitlement: EffectiveEntitlement | null | undefined;
  creditBalance: unknown;
  onRefresh: () => Promise<unknown>;
}) {
  const i18n = useUiTranslations();
  const membership = finance.details.membership;
  const subscriptions = finance.details.package_subscriptions;
  const claims = finance.details.referral_claims;
  const referredMembers = finance.details.referred_members;
  const rewards = finance.details.referral_rewards;
  const [editing, setEditing] = useState<string | null>(null);
  const [draft, setDraft] = useState(() => ({
    status: valueText(membership?.status) === "—" ? "active" : valueText(membership?.status),
    starts_on: typeof membership?.starts_on === "string" ? membership.starts_on.slice(0, 10) : "",
    expires_on: typeof membership?.expires_on === "string" ? membership.expires_on.slice(0, 10) : "",
    signup_source: valueText(membership?.signup_source) === "—" ? "" : valueText(membership?.signup_source),
    notes: valueText(membership?.notes) === "—" ? "" : valueText(membership?.notes),
  }));
  const [commitment, setCommitment] = useState<{ patch: Record<string, unknown>; endsOn: string | null } | null>(null);
  const updateMembership = useMutation({
    mutationFn: (patch: Record<string, unknown>) => updateFinanceMember(token, userId, patch),
    onSuccess: async () => {
      setEditing(null);
      setCommitment(null);
      await onRefresh();
    },
    // ADR-097: ending a membership inside its minimum commitment needs a reason.
    onError: (error, patch) => {
      const conflict = commitmentConflict(error);
      if (conflict) setCommitment({ patch, endsOn: conflict.endsOn });
    },
  });
  const fieldStyle = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" };
  const packageContent = subscriptions
    .map((subscription) => {
      const label = packageSubscriptionLabel(subscription);
      return [label, semanticLabel(valueText(subscription.status), i18n), money(subscription.price_cents_snapshot)]
        .filter((part) => part && part !== "—")
        .join(" · ");
    })
    .filter(Boolean)
    .join("\n");

  return (
    <div className="mt-5 space-y-6">
      <div>
        <p className="mb-3 font-semibold" style={{ color: "var(--text)" }}>{i18n("membership53bc967")}</p>
        {membership ? (
          <div className="space-y-2">
            <EditableFinanceCard label={i18n("statusbae7d5b")} editing={editing === "status"} value={<SemanticLabel value={draft.status} />} onOpen={() => setEditing("status")}>
              <Select className="w-full rounded-lg px-3 py-2 text-sm outline-none" style={fieldStyle} value={draft.status} onValueChange={(value) => { const status = value; setDraft((current) => ({ ...current, status })); updateMembership.mutate({ status }); }}>
                {['active', 'paused', 'cancelled'].map((status) => <option key={status} value={status}>{semanticLabel(status, i18n)}</option>)}
              </Select>
            </EditableFinanceCard>
            {([['starts_on', i18n("startsOn6d888f7")], ['expires_on', i18n("expiresOn549cabe")]] as const).map(([key, label]) => (
              <EditableFinanceCard key={key} label={label} editing={editing === key} value={date(draft[key])} onOpen={() => setEditing(key)}>
                <DateInput className="w-full rounded-lg px-3 py-2 text-sm outline-none" style={fieldStyle} value={draft[key]} onValueChange={(value) => setDraft((current) => ({ ...current, [key]: value }))} onBlur={() => updateMembership.mutate({ [key]: draft[key] || null })} />
              </EditableFinanceCard>
            ))}
            <EditableFinanceCard label={i18n("packageSubscriptions09a33f1")} value={packageContent || ""} />
            {updateMembership.isPending ? <p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("quickTextSaving")}</p> : null}
            {updateMembership.isError && !commitment ? <ErrorNotice variant="field">{i18n("quickTextSaveError")}</ErrorNotice> : null}
            {commitment ? (
              <CommitmentOverridePrompt
                endsOn={commitment.endsOn}
                pending={updateMembership.isPending}
                onConfirm={(reason) => updateMembership.mutate({ ...commitment.patch, commitment_override_reason: reason })}
                onCancel={() => {
                  setCommitment(null);
                  updateMembership.reset();
                  setDraft((current) => ({ ...current, status: valueText(membership.status) === "—" ? "active" : valueText(membership.status) }));
                }}
              />
            ) : null}
            <MembershipFreezes token={token} userId={userId} subscriptions={subscriptions} onRefresh={onRefresh} />
            <MembershipLeaving token={token} userId={userId} membership={membership} subscriptions={subscriptions} onRefresh={onRefresh} />
          </div>
        ) : <Empty>{i18n("noMembershipRecord741b5d9")}</Empty>}
      </div>

      <details className="rounded-xl p-4" style={{ border: "1px solid var(--border)" }}>
        <summary className="cursor-pointer font-semibold" style={{ color: "var(--text)" }}>{i18n("advancedSettingsc8fef35")}</summary>
        <div className="mt-4 space-y-5">
          <div className="grid gap-3 sm:grid-cols-2"><DetailCard title={i18n("credits66c22fa")} value={valueText(creditBalance) === "—" ? 0 : valueText(creditBalance)} plainChildren /><DetailCard title={i18n("entitlement8994749")} value={effectiveEntitlement?.status ? <SemanticLabel value={effectiveEntitlement.status} /> : ""} plainChildren /></div>
          <AdminEntitlements token={token} userId={userId} entitlement={effectiveEntitlement} onRefresh={onRefresh} />
          {claims.length ? <FinanceRecordList title={i18n("referralEvents8bcf3f4")} records={claims} personKey="referrer_nickname" /> : null}
          {referredMembers.length ? <FinanceRecordList title={i18n("madeReferralsbe27ef7")} records={referredMembers} personKey="referred_nickname" /> : null}
          {rewards.length ? <div><p className="font-semibold" style={{ color: "var(--text)" }}>{i18n("referralRewards22d6a91")}</p><div className="mt-2 grid gap-2 sm:grid-cols-2">{rewards.map((reward) => <GenericRecordCard key={valueText(reward.id)} title={<SemanticLabel value={valueText(reward.reward_type)} />} meta={<><SemanticLabel value={valueText(reward.status)} /> · {date(reward.applied_at ?? reward.inserted_at)}</>} value={valueText(reward.reward_value)} />)}</div></div> : null}
        </div>
      </details>
    </div>
  );
}

function EditableFinanceCard({ label, value, editing = false, onOpen, children }: { label: string; value: React.ReactNode; editing?: boolean; onOpen?: () => void; children?: React.ReactNode }) {
  const content = (
    <>
      <span className="block text-xs uppercase tracking-[0.14em]" style={{ color: "var(--muted)" }}>{label}</span>
      {!editing ? <span className="mt-1 block whitespace-pre-line font-semibold" style={{ color: "var(--text)" }}>{value || ""}</span> : null}
    </>
  );
  return (
    <div className="w-full rounded-[1.25rem] p-4 text-start" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      {onOpen ? <button type="button" className="w-full text-start" onClick={onOpen}>{content}</button> : <div>{content}</div>}
      {editing ? <div className="mt-3">{children}</div> : null}
    </div>
  );
}

function CoachingContextSummary({ drillDown }: { drillDown: Record<string, unknown> | null | undefined }) {
  const i18n = useUiTranslations();
  const activity = (drillDown?.recent_activity as Record<string, unknown> | undefined) ?? {};
  const assignments = (drillDown?.assigned_workouts as Array<Record<string, unknown>> | undefined) ?? [];
  const notes = (drillDown?.notes_context as Array<Record<string, unknown>> | undefined) ?? [];
  const cues = (drillDown?.attention_cues as Array<Record<string, unknown>> | undefined) ?? [];
  const trends = (drillDown?.score_trends as Array<Record<string, unknown>> | undefined) ?? [];

  if (!drillDown) return <Empty>{i18n("notEvaluated4bb5e31")}</Empty>;

  return (
    <div className="space-y-5">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <DetailCard title={i18n("statusbae7d5b")} value={<SemanticLabel value={valueText(activity.state)} />} plainChildren>
          <p className="text-xs" style={{ color: "var(--muted)" }}>{valueText(activity.reason)}</p>
        </DetailCard>
        <DetailCard title={i18n("assignedWorkoutSInTheCoachingWindow2200dd4")} value={assignments.length} plainChildren />
        <DetailCard title={i18n("notes7044004")} value={notes.length} plainChildren />
        <DetailCard title={i18n("scores126cb93")} value={trends.length} plainChildren />
      </div>

      {cues.length ? (
        <div className="rounded-[1.5rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("attention74e0b9c")}</p>
          <div className="mt-3 grid gap-2 sm:grid-cols-2">
            {cues.slice(0, 4).map((cue, index) => (
              <p key={`${valueText(cue.key)}-${index}`} className="rounded-xl p-3 text-xs" style={{ background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border)" }}>
                <SemanticLabel value={valueText(cue.key)} /> · <SemanticLabel value={valueText(cue.severity)} />
              </p>
            ))}
          </div>
        </div>
      ) : null}

      <div className="grid gap-3 lg:grid-cols-2">
        <div>
          <p className="mb-2 font-semibold" style={{ color: "var(--text)" }}>{i18n("packageSubscriptions09a33f1")}</p>
          <div className="space-y-2">
            {assignments.slice(0, 4).map((assignment) => (
              <GenericRecordCard
                key={valueText(assignment.id)}
                title={valueText((assignment.workout as Record<string, unknown> | undefined)?.title)}
                meta={<><SemanticLabel value={valueText(assignment.status)} /> · {date(assignment.scheduled_for)}</>}
                href={`/box/workouts?open_assignment=${valueText(assignment.id)}`}
              />
            ))}
            {assignments.length === 0 ? <Empty>{i18n("none6eef664")}</Empty> : null}
          </div>
        </div>
        <div>
          <p className="mb-2 font-semibold" style={{ color: "var(--text)" }}>{i18n("notes7044004")}</p>
          <div className="space-y-2">
            {notes.slice(0, 4).map((note, index) => (
              <GenericRecordCard
                key={`${valueText(note.id)}-${index}`}
                title={<SemanticLabel value={valueText(note.type)} />}
                meta={date(note.inserted_at)}
                detail={<p className="line-clamp-3">{valueText(note.body)}</p>}
                href="/messages"
              />
            ))}
            {notes.length === 0 ? <Empty>{i18n("noConversationsRecordedd525265")}</Empty> : null}
          </div>
        </div>
      </div>
    </div>
  );
}

function FinanceRecordList({ title, records, personKey }: { title: string; records: Array<Record<string, unknown>>; personKey: string }) {
  return (
    <div>
      <p className="font-semibold" style={{ color: "var(--text)" }}>{title}</p>
      <div className="mt-2 grid gap-2 sm:grid-cols-2">
        {records.map((record) => (
          <GenericRecordCard
            key={valueText(record.id)}
            title={valueText(record[personKey])}
            meta={<><SemanticLabel value={valueText(record.status)} /> · {date(record.inserted_at)}</>}
          />
        ))}
      </div>
    </div>
  );
}

function money(value: unknown) {
  const cents = Number(value);
  return Number.isFinite(cents) ? `${(cents / 100).toFixed(2)} €` : "—";
}

function arrayCount(value: unknown) {
  return Array.isArray(value) ? value.length : 0;
}

/**
 * ADR-132: what a coach sees of a member outside their client scope - the PRs
 * the member recorded in this gym (ADR-129), nothing else.
 */
function PRDossier({ member, prs }: { member: AdminUserPRMember; prs: AdminUserPR[] }) {
  const i18n = useUiTranslations();
  const tPrSharing = useTranslations("PrSharing");
  const organizationSlug = useOrganizationSlug();

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-6">
        <Link href={adminHref("/admin", organizationSlug)} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>← {tPrSharing("dossierBack")}</Link>
        <section className="flex flex-col gap-6 rounded-[2.4rem] p-8 md:flex-row md:items-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <Avatar user={{ nickname: member.nickname, avatar_url: member.avatar_url ?? null }} />
          <div className="min-w-0 flex-1">
            <h1 className="truncate text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>{member.nickname}</h1>
            <p className="mt-3 text-sm" style={{ color: "var(--muted)" }}>{tPrSharing("dossierCoachScope")}</p>
          </div>
        </section>
        <article id="prs" className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>{i18n("personalRecords05223a0")}</p>
          <div className="mt-4 grid gap-3">
            {prs.length ? prs.map((pr) => <PRCard key={pr.id} pr={pr} />) : <Empty>{i18n("noPersonalRecordsRecorded22a0fce")}</Empty>}
          </div>
        </article>
      </div>
    </main>
  );
}

export function AdminUserProfile({ userId }: { userId: string }) {
  const i18n = useUiTranslations();
  const tPrSharing = useTranslations("PrSharing");
  const tDepth = useTranslations("Depth");
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const organizationSlug = useOrganizationSlug();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const queryClient = useQueryClient();
  const { membership: actor } = useSelectedMembershipRole();
  const [hashSection, setHashSection] = useState<string | null>(null);
  const profileQuery = useDossierQuery(token, userId, "profile", fetchAdminUserProfile);
  const profile = profileQuery.data?.user;
  const finance = useDossierQuery(token, userId, "finance", fetchAdminUserFinance, Boolean(profile?.available_sections.includes("finance")));
  const training = useDossierQuery(token, userId, "training", fetchAdminUserTraining, Boolean(profile?.available_sections.includes("training_history")));
  // ADR-132: a coach always fetches the PR panel - it is their fallback when
  // client scope (ADR-100) refuses the full profile.
  const actorCoaches = membershipRoles(actor).includes("coach");
  const prs = useDossierQuery(token, userId, "prs", fetchAdminUserPRs, Boolean(profile?.available_sections.includes("prs")) || actorCoaches);
  const incidents = useDossierQuery(token, userId, "incidents", fetchAdminUserIncidents, Boolean(profile?.available_sections.includes("health_incidents")));
  const messages = useDossierQuery(token, userId, "messages", fetchAdminUserMessages, Boolean(profile?.available_sections.includes("messages")));
  const coaching = useDossierQuery(token, userId, "coaching", fetchAdminUserCoachingContext, Boolean(profile?.available_sections.includes("coaching_context")));
  const roleMutation = useMutation({
    mutationFn: (role: AdminUserDirectoryEntry["role"]) => updateAdminUserRole(token!, userId, role),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "users", userId] });
    },
  });
  const [assignRequestDate, setAssignRequestDate] = useState<string | null>(null);
  const clearAssignRequest = useCallback(() => setAssignRequestDate(null), []);
  const [placementOpen, setPlacementOpen] = useState(false);
  const [scheduleVersion, setScheduleVersion] = useState(0);
  const deleteMutation = useMutation({
    mutationFn: () => deleteAdminUser(token!, userId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
      router.push(adminHref("/admin/users", organizationSlug));
    },
  });

  // A `#section` link or request opens the section's tab (ADR-140 §8).
  useEffect(() => {
    const frame = window.requestAnimationFrame(() => setHashSection(window.location.hash.slice(1) || null));
    function handleSectionRequest(event: Event) {
      setHashSection((event as AdminProfileSectionRequest).detail.section);
    }
    window.addEventListener(ADMIN_PROFILE_SECTION_REQUEST, handleSectionRequest);
    return () => {
      window.cancelAnimationFrame(frame);
      window.removeEventListener(ADMIN_PROFILE_SECTION_REQUEST, handleSectionRequest);
    };
  }, []);

  useEffect(() => {
    function handleUserSync(event: Event) {
      const detail = (event as CustomEvent<UserSyncDetail>).detail;
      if (detail.scopes.includes("finance_entitlement")) {
        void queryClient.invalidateQueries({ queryKey: ["admin", "users", userId, "finance"] });
      }
    }

    window.addEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);
    return () => window.removeEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);
  }, [queryClient, userId]);

  const mode = dossierMode({
    profileLoading: profileQuery.isLoading,
    profileLoaded: Boolean(profile),
    actorCoaches,
    prsLoading: prs.isLoading,
    prs: prs.data,
  });
  if (mode === "loading") return <main className="min-h-screen p-10" style={{ background: "var(--bg)", color: "var(--muted)" }}>{i18n("loadingProfile548faad")}</main>;
  if (mode === "prs_only" && prs.data?.member) return <PRDossier member={prs.data.member} prs={prs.data.prs} />;
  if (!profile) return <main className="min-h-screen p-10" style={{ background: "var(--bg)" }}><ErrorNotice>{i18n("userProfileCouldNotBeLoaded7bc2d73")}</ErrorNotice></main>;

  const executions = training.data?.executions ?? [];
  const scores = training.data?.scores ?? [];
  const effectiveEntitlement = finance.data?.summary?.effective_entitlement;
  const canDelete = currentUser?.id !== userId;
  const coachingDrillDown = coaching.data?.drill_down;
  const coachingCount = coachingDrillDown
    ? arrayCount(coachingDrillDown.assigned_workouts) +
      arrayCount(coachingDrillDown.execution_history) +
      arrayCount(coachingDrillDown.notes_context)
    : 0;
  const visibleSections = visibleAdminProfileSections(profile.available_sections, {
    training_history: executions.length,
    prs: prSectionContentCount(prs.data),
    scores: scores.length,
    health_incidents: incidents.data?.incidents.length ?? 0,
    coaching_context: coachingCount,
    class_participation: training.data?.class_participation.length ?? 0,
    messages: messages.data?.threads.length ?? 0,
  });
  const sections = new Set(visibleSections);
  if (profile.identity.role === "member" || profile.identity.role === "athlete") sections.add("schedule");
  // ADR-100/101: coaches and private coach notes belong to client profiles.
  const isClient = profile.membership?.roles?.length
    ? profile.membership.roles.some((role) => role === "member" || role === "athlete")
    : profile.identity.role === "member" || profile.identity.role === "athlete";
  const showCoachNotes = isClient && (can(actor, "write_coach_notes") || can(actor, "read_coach_notes"));
  const showCoaches = isClient && (can(actor, "assign_coaches") || can(actor, "manage_coaching"));
  const showBoxMessage = isClient && can(actor, "message_from_box");
  const trains = profile.identity.role === "member" || profile.identity.role === "athlete";

  // ADR-140 §8: six tabs, each shown when one of its sections is.
  const tabSections = new Set(sections);
  if (trains) tabSections.add("training_history");
  if (showCoaches) tabSections.add("coaching_relationships");
  if (showCoachNotes) tabSections.add("coach_notes");
  if (showBoxMessage) tabSections.add("box_message");
  // ADR-158: a client's coach sees the body snapshots the member shared.
  const showBody = isClient && actorCoaches && can(actor, "view_health");
  if (showBody) tabSections.add("body");
  // ADR-160: and the weekly wellness summary, only when the member shares it.
  if (showBody) tabSections.add("wellness_summary");
  // ADR-165: coverage, qualities and load from the entries the client shares.
  if (isClient && actorCoaches && can(actor, "view_client_training")) tabSections.add("training_depth");
  const tabs = visibleProfileTabs(tabSections);
  const tab = activeProfileTab(tabs, searchParams.get("tab"), hashSection);
  const inTab = (section: string) => SECTION_TAB[section] === tab && tabSections.has(section);
  const selectTab = (next: ProfileTab) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("tab", next);
    setHashSection(null);
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  };

  // What a new coach note can be about (ADR-140 §5).
  const trainingSubjects: CoachNoteSubjectOption[] = [
    ...(prs.data?.prs ?? []).map((pr) => ({ kind: "pr" as const, id: pr.id, label: pr.name })),
    ...executions
      .filter((execution) => execution.completed_at_utc)
      .slice(0, 20)
      .map((execution) => ({
        kind: "execution" as const,
        id: execution.id,
        label: `${execution.workout_title} · ${date(execution.completed_at_utc)}`,
      })),
  ];
  const wellbeingSubjects: CoachNoteSubjectOption[] = (incidents.data?.incidents ?? []).map((incident) => ({
    kind: "injury" as const,
    id: incident.id,
    label: `${semanticLabel(incident.body_area, i18n)} · ${date(incident.started_on)}`,
  }));
  const overviewItems: Array<[string, React.ReactNode]> = [
    [i18n("rolec3f104d"), <RoleLabel key="role" role={profile.identity.role} />],
    [i18n("account85dfa32"), <SemanticLabel key="account" value={profile.account_status} />],
    [i18n("joinedbbc56ef").replace("· ", ""), date(profile.identity.joined_at)],
    [i18n("avatar7631b26"), profile.identity.avatar_url ? i18n("activea733b80") : "—"],
  ];

  if (sections.has("finance")) {
    overviewItems.push(
      [i18n("finance1b48d3f"), finance.data?.summary?.current_status?.state ? <SemanticLabel key="finance" value={String(finance.data.summary.current_status.state)} /> : "—"],
    );
  }
  if (executions.length) overviewItems.push([i18n("totalCompletionsfa16f4c"), training.data?.summary.completed_count ?? 0]);
  if (incidents.data?.incidents.length) overviewItems.push([i18n("activeInjuriesdaecfa6"), incidents.data.summary.active]);

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-6">
        <Link href={adminHref("/admin/users", organizationSlug)} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>← {i18n("users206fc04")}</Link>
        <section className="flex flex-col gap-6 rounded-[2.4rem] p-8 md:flex-row md:items-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <Avatar user={profile.identity} />
          <div className="min-w-0 flex-1">
            <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}><RoleLabel role={profile.identity.role} /></p>
            <h1 className="mt-4 truncate text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>{profile.identity.nickname}</h1>
            <p className="mt-3 text-sm" style={{ color: "var(--muted)" }}><SemanticLabel value={profile.account_status} /> {i18n("joinedbbc56ef")} {date(profile.identity.joined_at)}</p>
          </div>
          {token && profile.identity.role === "athlete" ? (
            <HoverHint hint={i18n("featureAssignWorkoutHint")} align="end">
              <button
                type="button"
                className="inline-flex items-center gap-2 rounded-full px-5 py-3 text-sm font-semibold"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                onClick={() => {
                  setAssignRequestDate(new Date(Date.now() - new Date().getTimezoneOffset() * 60_000).toISOString().slice(0, 10));
                  openAdminProfileSection("schedule");
                }}
              >
                <span aria-hidden>🏋️</span>
                {i18n("featureAssignWorkoutAction")}
              </button>
            </HoverHint>
          ) : null}
          {token && profile.identity.role === "member" ? (
            <HoverHint hint={i18n("featureMoveToClassHint")} align="end">
              <button
                type="button"
                className="inline-flex items-center gap-2 rounded-full px-5 py-3 text-sm font-semibold"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                onClick={() => setPlacementOpen(true)}
              >
                <span aria-hidden>🗓️</span>
                {i18n("featureMoveToClassAction")}
              </button>
            </HoverHint>
          ) : null}
        </section>
        {placementOpen && token ? (
          <MemberClassPlacementModal
            token={token}
            userId={userId}
            nickname={profile.identity.nickname}
            onClose={() => setPlacementOpen(false)}
            onPlaced={() => {
              setScheduleVersion((version) => version + 1);
              void queryClient.invalidateQueries({ queryKey: ["admin", "users", userId] });
            }}
          />
        ) : null}

        <SegmentPicker
          ariaLabel={i18n("mpTabs")}
          variant="track"
          idPrefix="profile"
          panelId="profile-tab-panel"
          value={tab}
          onChange={selectTab}
          options={tabs.map((item) => ({ value: item, label: i18n(PROFILE_TAB_KEYS[item]) }))}
        />

        <section id="profile-tab-panel" role="tabpanel" aria-labelledby={`profile-tab-${tab}`} className="space-y-4">
          {tab === "overview" ? (
            <Panel id="overview" title={i18n("overview0efc2e6")}>
              <StatGrid items={overviewItems} />
            </Panel>
          ) : null}

          {inTab("box_message") ? (
            <Panel id="box_message" title={i18n("bmTitle")}>
              <BoxMessagePanel userId={userId} />
            </Panel>
          ) : null}

          {token && trains && inTab("schedule") ? <Panel id="schedule" title={i18n("featureScheduleProgramming")}><UserProgrammingSchedule key={scheduleVersion} token={token} userId={userId} role={profile.identity.role} nickname={profile.identity.nickname} assignRequestDate={assignRequestDate} onAssignRequestHandled={clearAssignRequest} /></Panel> : null}

          {inTab("finance") ? <Panel id="finance" title={i18n("finance1b48d3f")}>{finance.data && token ? <FinanceDetails finance={finance.data} token={token} userId={userId} effectiveEntitlement={effectiveEntitlement} creditBalance={finance.data?.summary?.credit_balance ?? 0} onRefresh={() => queryClient.invalidateQueries({ queryKey: ["admin", "users", userId, "finance"] })} /> : null}</Panel> : null}


          {token && inTab("training_history") ? (
            <TrainingHistory
              id="training_history"
              queryKey={["admin", "users", userId]}
              fetchPage={(kind, offset) => fetchUserTrainingHistory(token, userId, kind, offset)}
              defaultKind={defaultHistoryKind(profile.identity.role)}
            />
          ) : null}

          {token && inTab("training_depth") ? (
            <Panel id="training_depth" title={tDepth("coach.title")}>
              <CoachTrainingDepthPanel userId={userId} />
            </Panel>
          ) : null}

          {inTab("prs") ? <Panel id="prs" title={i18n("personalRecords05223a0")}><div className="grid gap-3">{prs.data?.visibility === "coach_role_required" ? <Empty>{tPrSharing("dossierCoachOnly")}</Empty> : prs.data?.prs.length ? prs.data.prs.map((pr) => <PRCard key={pr.id} pr={pr} />) : <Empty>{i18n("noPersonalRecordsRecorded22a0fce")}</Empty>}</div></Panel> : null}


          {token && showCoachNotes && tab === "training" ? (
            <Panel id="training_notes" title={i18n("rhCoachNotes")}>
              <CoachNotesPanel userId={userId} kinds={subjectKindsFor("training")} subjects={trainingSubjects} />
            </Panel>
          ) : null}

          {inTab("health_incidents") ? <Panel id="health_incidents" title={i18n("healthIncidentse3ca869")} href={adminHref("/admin/metrics#health-incidents", organizationSlug)}><p>{incidents.data?.summary.active ?? 0} {i18n("active4c71073")} {incidents.data?.summary.total ?? 0} {i18n("total5a537e2")}</p><div className="mt-3 grid gap-3">{incidents.data?.incidents.length ? incidents.data.incidents.map((incident) => <GenericRecordCard key={incident.id} title={incident.body_area} meta={<><SemanticLabel value={incident.severity} /> · <SemanticLabel value={incident.status} /> · {date(incident.started_on)}</>} detail={incident.training_limitations ? <p style={{ color: "var(--muted)" }}>{incident.training_limitations}</p> : null} href={adminHref("/admin/metrics#health-incidents", organizationSlug)} />) : <Empty>{i18n("noHealthIncidentsRecorded91c9d4e")}</Empty>}</div></Panel> : null}

          {token && showCoachNotes && tab === "wellbeing" ? (
            <Panel id="wellbeing_notes" title={i18n("rhCoachNotes")}>
              <CoachNotesPanel userId={userId} kinds={subjectKindsFor("wellbeing")} subjects={wellbeingSubjects} />
            </Panel>
          ) : null}

          {token && inTab("wellness_summary") ? (
            <CoachWellnessPanel
              userId={userId}
              nickname={profile.identity.nickname}
              frame={(content) => <Panel id="wellness_summary" title={i18n("mpWellnessSummary")}>{content}</Panel>}
            />
          ) : null}

          {token && inTab("body") ? (
            <Panel id="body" title={i18n("mpTabBody")}>
              <CoachBodyPanel userId={userId} nickname={profile.identity.nickname} />
            </Panel>
          ) : null}

          {inTab("coaching_context") ? <Panel id="coaching_context" title={i18n("coachingContexteb3075d")} href={adminHref("/admin/coaching-assignments", organizationSlug)}><CoachingContextSummary drillDown={coaching.data?.drill_down} /></Panel> : null}

          {token && inTab("coaching_relationships") ? <Panel id="coaching_relationships" title={i18n("rhCoaches")}><CoachAssignmentPanel userId={userId} /></Panel> : null}

          {token && inTab("coach_notes") ? <Panel id="coach_notes" title={i18n("rhCoachNotes")}><CoachNotesPanel userId={userId} subjects={[...trainingSubjects, ...wellbeingSubjects]} /></Panel> : null}


          {inTab("messages") ? <Panel id="messages" title={i18n("chat2ced57f")} href="/messages"><p>{messages.data?.summary.thread_count ?? 0} {i18n("threadS2bddeec")} {messages.data?.summary.unread_thread_count ?? 0} {i18n("unread1b9aebd")}</p><div className="mt-3 grid gap-3">{messages.data?.threads.length ? messages.data.threads.slice(0, 6).map((thread) => <GenericRecordCard key={thread.id} title={<SemanticLabel value={thread.context_type} />} meta={`${thread.message_count} ${i18n("threadS2bddeec")} · ${date(thread.latest_message?.inserted_at)}`} detail={<p>{thread.latest_message?.body ?? i18n("emptyThreadfee51b1")}</p>} href="/messages" />) : <Empty>{i18n("noConversationsRecordedd525265")}</Empty>}</div></Panel> : null}

          {inTab("admin_actions") ? (
            <Panel id="admin_actions" title={i18n("adminActionsfa81c61")}>
              <div className="space-y-5">
                {profile.membership && token ? (
                  <MemberRolesEditor token={token} userId={userId} membership={profile.membership} />
                ) : (
                <div>
                  <span className="block text-xs uppercase tracking-wider" style={{ color: "var(--muted)" }}>{i18n("accountRole39514a0")}</span>
                  <div className="mt-2 flex flex-wrap gap-2">
                    {(["member", "athlete", "admin"] as const).map((role) => {
                      const selected = profile.identity.role === role;
                      return (
                        <button
                          key={role}
                          type="button"
                          disabled={roleMutation.isPending || selected}
                          onClick={() => roleMutation.mutate(role)}
                          className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-70"
                          style={{ background: selected ? "var(--primary)" : "var(--panel-muted)", border: "1px solid var(--border)", color: selected ? "var(--primary-contrast)" : "var(--text-soft)" }}
                        >
                          <RoleLabel role={role} />
                        </button>
                      );
                    })}
                  </div>
                  {roleMutation.isError ? <ErrorNotice className="mt-2">{i18n("roleUpdateFailed493da52")}</ErrorNotice> : null}
                </div>
                )}
                <div className="rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                  <button
                    type="button"
                    disabled={!canDelete || deleteMutation.isPending}
                    onClick={() => {
                      if (window.confirm(i18n("delete63346e8") + profile.identity.nickname + "\"?")) deleteMutation.mutate();
                    }}
                    className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-40"
                    style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
                  >
                    {deleteMutation.isPending ? i18n("loading33ce417") : i18n("deletef6fdbe4")}
                  </button>
                  {deleteMutation.isError ? (
                    <ErrorNotice className="mt-2">
                      {localizeError(deleteMutation.error, i18n)}
                    </ErrorNotice>
                  ) : null}
                </div>
              </div>
            </Panel>
          ) : null}
        </section>
      </div>
    </main>
  );
}
