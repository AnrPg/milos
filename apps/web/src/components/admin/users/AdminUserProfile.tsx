"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

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
  type AdminUserExecution,
  type AdminUserFinance,
  type AdminUserPR,
} from "@/api/admin-users";
import type { PRSupportingMetrics } from "@/api/gamification";
import type { EffectiveEntitlement } from "@/api/my-finance";
import { updateFinanceMember } from "@/api/finance";
import { shouldShowAllowanceQuota } from "@/app/account/billing/billing-entitlement-visibility";
import { packageSubscriptionLabel, visibleAdminProfileSections } from "@/components/admin/users/admin-user-profile";
import {
  ADMIN_PROFILE_SECTION_REQUEST,
  type AdminProfileSectionRequest,
} from "@/components/admin/users/admin-profile-navigation";
import { LocalizedScore } from "@/components/localized-score";
import { formatPRCardDetails } from "@/components/pantheon/pr-card-details";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { localizeError, semanticLabel } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { UserProgrammingSchedule } from "@/components/admin/users/UserProgrammingSchedule";
import { IntegerInput } from "@/components/integer-input";

function Panel({ id, title, children }: { id: string; title: string; children: React.ReactNode; href?: string; hrefLabel?: string }) {
  const i18n = useUiTranslations();
  const [open, setOpen] = useState(id === "overview" || id === "finance" || id === "admin_actions");

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
    <div className="flex h-24 w-24 shrink-0 items-center justify-center overflow-hidden rounded-[1.7rem] text-3xl font-semibold" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)", color: "var(--primary)" }}>
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
        <div key={label} className="rounded-2xl p-4" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}>
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
    <div className="group relative rounded-[1.4rem] p-4 transition-transform hover:-translate-y-0.5" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}>
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
      {pr.notes ? <p className="mt-2 text-xs" style={{ color: "var(--muted)" }}>{pr.notes}</p> : null}
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

function ExecutionCard({ item, href }: { item: AdminUserExecution; href?: string }) {
  const i18n = useUiTranslations();

  return (
    <DetailCard
      title={item.workout_title}
      meta={<><SemanticLabel value={item.status} /> · <SemanticLabel value={item.source} /> · {date(item.started_at_utc)}</>}
      value={item.total_elapsed_ms ? `${Math.round(item.total_elapsed_ms / 60000)}m` : undefined}
      href={href}
    >
      {item.section_scores?.length ? (
        <div className="grid gap-2 sm:grid-cols-2">
          {item.section_scores.slice(0, 6).map((score, index) => (
            <p key={`${item.id}-${index}`} className="text-xs">
              <span style={{ color: "var(--muted)" }}>{valueText(score.section_name ?? score["section_name"])}:</span>{" "}
              <LocalizedScore value={score.value ?? score["value"] ?? "—"} unit={valueText(score.unit ?? score["unit"])} />
            </p>
          ))}
        </div>
      ) : (
        <Empty>{i18n("noScoredWorkoutSectionsRecordedcfa7742")}</Empty>
      )}
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
  const [form, setForm] = useState({ allowance: "class_visits" as const, quantity: 1, period: "calendar_month" as "calendar_week" | "calendar_month" | "subscription_period", reason: "" });
  const [revokeTarget, setRevokeTarget] = useState<string | null>(null);
  const [revokeReason, setRevokeReason] = useState("");
  const grant = useMutation({ mutationFn: () => grantAdminUserAllowance(token, userId, form), onSuccess: async () => { setForm((value) => ({ ...value, quantity: 1, reason: "" })); await onRefresh(); } });
  const revoke = useMutation({ mutationFn: () => revokeAdminUserAllowance(token, userId, revokeTarget!, revokeReason), onSuccess: async () => { setRevokeTarget(null); setRevokeReason(""); await onRefresh(); } });
  const entries = entitlement?.usage_entries ?? [];
  const revoked = new Set(entries.filter((entry) => entry.parent_entry_id).map((entry) => entry.parent_entry_id));

  return (
    <>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        {Object.entries(entitlement?.allowances ?? {}).filter(([key]) => key !== "coaching_touchpoints").map(([key, allowance]) => allowance ? <div key={key} className="rounded-xl p-3" style={{ background: "var(--bg-soft)" }}><p className="font-semibold">{semanticLabel(key, i18n)}</p>{shouldShowAllowanceQuota(allowance) ? <p>{String(allowance.remaining)} {i18n("remainingOf8553660")} {String(allowance.limit)}{allowance.extensions > 0 ? i18n("personalExtensionCount", { count: allowance.extensions }) : ""}</p> : null}<p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("resetsAftere96e46e")} {date(allowance.period_end)}</p></div> : null)}
      </div>
      <div className="mt-5 space-y-5 rounded-2xl p-4" style={{ border: "1px solid var(--border)" }}>
        <form className="space-y-3" onSubmit={(event) => { event.preventDefault(); grant.mutate(); }}>
          <p className="font-semibold" style={{ color: "var(--text)" }}>{i18n("extendThisUserSAllowance6e08374")}</p>
          <div className="grid gap-3 sm:grid-cols-3">
            <select value={form.allowance} onChange={() => setForm({ ...form, allowance: "class_visits" })} className="rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)", color: "var(--text)", border: "1px solid var(--border)", colorScheme: "dark" }}><option value="class_visits">{i18n("classVisits142b3b0")}</option></select>
            <IntegerInput aria-label={i18n("additionalUnits1d9dac0")} min={1} value={form.quantity} emptyValue={1} onValueChange={(quantity) => setForm({ ...form, quantity: quantity ?? 1 })} className="rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)", color: "var(--text)", border: "1px solid var(--border)" }} />
            <select value={form.period} onChange={(event) => setForm({ ...form, period: event.target.value as typeof form.period })} className="rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)", color: "var(--text)", border: "1px solid var(--border)", colorScheme: "dark" }}><option value="calendar_week">{i18n("thisCalendarWeekb05ceca")}</option><option value="calendar_month">{i18n("thisCalendarMonthbb33495")}</option><option value="subscription_period">{i18n("subscriptionPeriod22e7508")}</option></select>
          </div>
          <textarea required minLength={3} placeholder={i18n("reasonForThisPersonalExtensionbe8ddf7")} value={form.reason} onChange={(event) => setForm({ ...form, reason: event.target.value })} className="min-h-20 w-full rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)", color: "var(--text)", border: "1px solid var(--border)" }} />
          <button disabled={grant.isPending || form.reason.trim().length < 3} className="rounded-full px-4 py-2 font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--bg)" }}>{grant.isPending ? i18n("extending80e2fcd") : i18n("extendAllowance2d3fd3a")}</button>
          {grant.isError ? <p style={{ color: "var(--danger)" }}>{i18n("theExtensionCouldNotBeRecorded8e3fe5d")}</p> : null}
        </form>
        <div className="mt-5 space-y-2">
          <p className="font-semibold" style={{ color: "var(--text)" }}>{i18n("personalExtensionHistory752eda5")}</p>
          {entries.filter((entry) => entry.allowance_key !== "coaching_touchpoints" && entry.event_type === "adjustment" && entry.quantity_delta < 0).map((entry) => <div key={entry.id} className="rounded-xl p-3" style={{ background: "var(--bg-soft)" }}><div className="flex flex-wrap items-center justify-between gap-2"><div><strong>+{Math.abs(entry.quantity_delta)} {semanticLabel(entry.allowance_key, i18n)}</strong><p className="text-xs" style={{ color: "var(--muted)" }}>{entry.reason} · {date(entry.inserted_at)} {i18n("validThrough263dc88")} {date(entry.period_end)}</p></div>{revoked.has(entry.id) ? <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{i18n("revoked85f17ac")}</span> : <button type="button" onClick={() => setRevokeTarget(entry.id)} className="text-xs font-semibold" style={{ color: "var(--danger)" }}>{i18n("revoke0be7207")}</button>}</div>{revokeTarget === entry.id ? <form className="mt-3 flex flex-col gap-2 sm:flex-row" onSubmit={(event) => { event.preventDefault(); revoke.mutate(); }}><input required minLength={3} value={revokeReason} onChange={(event) => setRevokeReason(event.target.value)} placeholder={i18n("reasonForRevocationac5b98c")} className="min-w-0 flex-1 rounded-xl px-3 py-2" style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }} /><button disabled={revoke.isPending || revokeReason.trim().length < 3} className="rounded-full px-3 py-2 text-xs font-semibold disabled:opacity-50" style={{ background: "var(--danger)", color: "white" }}>{i18n("confirmRevocationc1a9d03")}</button></form> : null}</div>)}
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
  const updateMembership = useMutation({
    mutationFn: (patch: Record<string, unknown>) => updateFinanceMember(token, userId, patch),
    onSuccess: async () => {
      setEditing(null);
      await onRefresh();
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
              <select className="w-full rounded-lg px-3 py-2 text-sm outline-none" style={fieldStyle} value={draft.status} onChange={(event) => { const status = event.target.value; setDraft((current) => ({ ...current, status })); updateMembership.mutate({ status }); }}>
                {['active', 'inactive', 'cancelled'].map((status) => <option key={status} value={status}>{semanticLabel(status, i18n)}</option>)}
              </select>
            </EditableFinanceCard>
            {([['starts_on', i18n("startsOn6d888f7")], ['expires_on', i18n("expiresOn549cabe")]] as const).map(([key, label]) => (
              <EditableFinanceCard key={key} label={label} editing={editing === key} value={date(draft[key])} onOpen={() => setEditing(key)}>
                <input className="w-full rounded-lg px-3 py-2 text-sm outline-none" style={fieldStyle} type="date" value={draft[key]} onChange={(event) => setDraft((current) => ({ ...current, [key]: event.target.value }))} onBlur={() => updateMembership.mutate({ [key]: draft[key] || null })} />
              </EditableFinanceCard>
            ))}
            <EditableFinanceCard label={i18n("packageSubscriptions09a33f1")} value={packageContent || ""} />
            {updateMembership.isPending ? <p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("quickTextSaving")}</p> : null}
            {updateMembership.isError ? <p className="text-xs" style={{ color: "var(--danger)" }}>{i18n("quickTextSaveError")}</p> : null}
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
    <div className="w-full rounded-[1.25rem] p-4 text-start" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}>
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
        <div className="rounded-[1.5rem] p-4" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}>
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
                href={`/my-workouts?open_assignment=${valueText(assignment.id)}`}
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
                href="/account/activity/chats"
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

export function AdminUserProfile({ userId }: { userId: string }) {
  const i18n = useUiTranslations();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token;
  const organizationSlug = useOrganizationSlug();
  const router = useRouter();
  const queryClient = useQueryClient();
  const profileQuery = useDossierQuery(token, userId, "profile", fetchAdminUserProfile);
  const profile = profileQuery.data?.user;
  const finance = useDossierQuery(token, userId, "finance", fetchAdminUserFinance, Boolean(profile?.available_sections.includes("finance")));
  const training = useDossierQuery(token, userId, "training", fetchAdminUserTraining, Boolean(profile?.available_sections.includes("training_history")));
  const prs = useDossierQuery(token, userId, "prs", fetchAdminUserPRs, Boolean(profile?.available_sections.includes("prs")));
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
  const deleteMutation = useMutation({
    mutationFn: () => deleteAdminUser(token!, userId),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
      router.push(adminHref("/admin/users", organizationSlug));
    },
  });

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

  if (profileQuery.isLoading) return <main className="min-h-screen p-10" style={{ background: "var(--bg)", color: "var(--muted)" }}>{i18n("loadingProfile548faad")}</main>;
  if (!profile) return <main className="min-h-screen p-10" style={{ background: "var(--bg)", color: "var(--danger)" }}>{i18n("userProfileCouldNotBeLoaded7bc2d73")}</main>;

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
    prs: prs.data?.prs.length ?? 0,
    scores: scores.length,
    health_incidents: incidents.data?.incidents.length ?? 0,
    coaching_context: coachingCount,
    class_participation: training.data?.class_participation.length ?? 0,
    messages: messages.data?.threads.length ?? 0,
  });
  const sections = new Set(visibleSections);
  if (profile.identity.role === "member" || profile.identity.role === "athlete") sections.add("schedule");
  const overviewItems: Array<[string, React.ReactNode]> = [
    [i18n("rolec3f104d"), <SemanticLabel key="role" value={profile.identity.role} />],
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
            <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}><SemanticLabel value={profile.identity.role} /></p>
            <h1 className="mt-4 truncate text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>{profile.identity.nickname}</h1>
            <p className="mt-3 text-sm" style={{ color: "var(--muted)" }}><SemanticLabel value={profile.account_status} /> {i18n("joinedbbc56ef")} {date(profile.identity.joined_at)}</p>
          </div>
        </section>

        <section className="space-y-4">
          <Panel id="overview" title={i18n("overview0efc2e6")}>
            <StatGrid items={overviewItems} />
          </Panel>

          {token && (profile.identity.role === "member" || profile.identity.role === "athlete") ? <Panel id="schedule" title={i18n("featureScheduleProgramming")}><UserProgrammingSchedule token={token} userId={userId} role={profile.identity.role} /></Panel> : null}

          {sections.has("finance") ? <Panel id="finance" title={i18n("finance1b48d3f")}>{finance.data && token ? <FinanceDetails finance={finance.data} token={token} userId={userId} effectiveEntitlement={effectiveEntitlement} creditBalance={finance.data?.summary?.credit_balance ?? 0} onRefresh={() => queryClient.invalidateQueries({ queryKey: ["admin", "users", userId, "finance"] })} /> : null}</Panel> : null}

          {sections.has("training_history") ? <Panel id="training_history" title={i18n("trainingHistorya512053")} href={adminHref("/admin/workouts", organizationSlug)}><p>{training.data?.summary.completed_count ?? 0} {i18n("completedOf88964ae")} {training.data?.summary.execution_count ?? 0} {i18n("executions8319d6e")}</p><div className="mt-3 grid gap-3">{executions.length ? executions.slice(0, 8).map((item) => <ExecutionCard key={item.id} item={item} href={adminHref("/admin/workouts", organizationSlug)} />) : <Empty>{i18n("noWorkoutExecutionsRecorded0a0b1d0")}</Empty>}</div></Panel> : null}

          {sections.has("prs") ? <Panel id="prs" title={i18n("personalRecords05223a0")}><div className="grid gap-3">{prs.data?.prs.length ? prs.data.prs.map((pr) => <PRCard key={pr.id} pr={pr} />) : <Empty>{i18n("noPersonalRecordsRecorded22a0fce")}</Empty>}</div></Panel> : null}

          {sections.has("scores") ? <Panel id="scores" title={i18n("scores126cb93")}><div className="grid gap-3">{scores.length ? scores.slice(0, 10).map((score, index) => <GenericRecordCard key={`${String(score.execution_id)}-${index}`} title={String(score.section_name ?? i18n("workoutSection881e276"))} meta={`${date(score.completed_at_utc)} · ${String(score.workout_title ?? "—")}`} value={<LocalizedScore value={score.value ?? "—"} unit={valueText(score.unit)} />} />) : <Empty>{i18n("noScoredWorkoutSectionsRecordedcfa7742")}</Empty>}</div></Panel> : null}

          {sections.has("health_incidents") ? <Panel id="health_incidents" title={i18n("healthIncidentse3ca869")} href={adminHref("/admin/metrics#health-incidents", organizationSlug)}><p>{incidents.data?.summary.active ?? 0} {i18n("active4c71073")} {incidents.data?.summary.total ?? 0} {i18n("total5a537e2")}</p><div className="mt-3 grid gap-3">{incidents.data?.incidents.length ? incidents.data.incidents.map((incident) => <GenericRecordCard key={incident.id} title={incident.body_area} meta={<><SemanticLabel value={incident.severity} /> · <SemanticLabel value={incident.status} /> · {date(incident.started_on)}</>} detail={incident.training_limitations ? <p style={{ color: "var(--muted)" }}>{incident.training_limitations}</p> : null} href={adminHref("/admin/metrics#health-incidents", organizationSlug)} />) : <Empty>{i18n("noHealthIncidentsRecorded91c9d4e")}</Empty>}</div></Panel> : null}

          {sections.has("coaching_context") ? <Panel id="coaching_context" title={i18n("coachingContexteb3075d")} href={adminHref("/admin/coaching-assignments", organizationSlug)}><CoachingContextSummary drillDown={coaching.data?.drill_down} /></Panel> : null}

          {sections.has("class_participation") ? <Panel id="class_participation" title={i18n("classParticipation9ef4001")} href={adminHref("/admin/class-schedule", organizationSlug)}><div className="grid gap-3">{training.data?.class_participation.length ? training.data.class_participation.map((item) => <ExecutionCard key={item.id} item={item} href={adminHref("/admin/class-schedule", organizationSlug)} />) : <Empty>{i18n("noClassLinkedWorkoutExecutionsRecordedf8ca7a6")}</Empty>}</div></Panel> : null}

          {sections.has("messages") ? <Panel id="messages" title={i18n("chat2ced57f")} href="/account/activity/chats"><p>{messages.data?.summary.thread_count ?? 0} {i18n("threadS2bddeec")} {messages.data?.summary.unread_thread_count ?? 0} {i18n("unread1b9aebd")}</p><div className="mt-3 grid gap-3">{messages.data?.threads.length ? messages.data.threads.slice(0, 6).map((thread) => <GenericRecordCard key={thread.id} title={<SemanticLabel value={thread.context_type} />} meta={`${thread.message_count} ${i18n("threadS2bddeec")} · ${date(thread.latest_message?.inserted_at)}`} detail={<p>{thread.latest_message?.body ?? i18n("emptyThreadfee51b1")}</p>} href="/account/activity/chats" />) : <Empty>{i18n("noConversationsRecordedd525265")}</Empty>}</div></Panel> : null}

          {sections.has("admin_actions") ? (
            <Panel id="admin_actions" title={i18n("adminActionsfa81c61")}>
              <div className="space-y-5">
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
                          style={{ background: selected ? "var(--primary)" : "var(--bg-soft)", border: "1px solid var(--border)", color: selected ? "var(--bg)" : "var(--text-soft)" }}
                        >
                          <SemanticLabel value={role} />
                        </button>
                      );
                    })}
                  </div>
                  {roleMutation.isError ? <p className="mt-2" style={{ color: "var(--danger)" }}>{i18n("roleUpdateFailed493da52")}</p> : null}
                </div>
                <div className="rounded-2xl p-4" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}>
                  <button
                    type="button"
                    disabled={!canDelete || deleteMutation.isPending}
                    onClick={() => {
                      if (window.confirm(i18n("delete63346e8") + profile.identity.nickname + "\"?")) deleteMutation.mutate();
                    }}
                    className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-40"
                    style={{ background: "var(--danger)", color: "white" }}
                  >
                    {deleteMutation.isPending ? i18n("loading33ce417") : i18n("deletef6fdbe4")}
                  </button>
                  {deleteMutation.isError ? (
                    <p className="mt-2 text-sm" style={{ color: "var(--danger)" }}>
                      {localizeError(deleteMutation.error, i18n)}
                    </p>
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
