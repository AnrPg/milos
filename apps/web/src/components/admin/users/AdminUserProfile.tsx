"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useEffect, useState } from "react";

import {
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
} from "@/api/admin-users";
import type { EffectiveEntitlement } from "@/api/my-finance";
import { useSession } from "@/components/session-provider";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";

function label(section: string) {
  return section.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function Panel({ id, title, children, href, hrefLabel }: { id: string; title: string; children: React.ReactNode; href?: string; hrefLabel?: string }) {
  const i18n = useUiTranslations();
  const resolvedHrefLabel = hrefLabel ?? i18n("openWorkspace8b23311");
  const [open, setOpen] = useState(id === "overview" || id === "admin_actions");

  return (
    <article id={id} className="scroll-mt-20 rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <button
        type="button"
        aria-expanded={open}
        aria-controls={(id) + "-content"}
        onClick={() => setOpen((value) => !value)}
        className="flex w-full items-center justify-between gap-4 text-start"
      >
        <span className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>{title}</span>
        <span className="text-sm font-semibold" style={{ color: "var(--dim)" }}>{open ? i18n("hide34d8b60") : i18n("showd97d1ee")}</span>
      </button>
      {open ? (
        <div id={(id) + "-content"} className="mt-4 text-sm leading-6" style={{ color: "var(--text-soft)" }}>
          {children}
          {href ? <Link href={href} className="mt-4 inline-flex items-center gap-1 text-sm font-semibold" style={{ color: "var(--primary)" }}>{resolvedHrefLabel} <span className="inline-block rtl:rotate-180">→</span></Link> : null}
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

function useDossierQuery<T>(token: string | undefined, userId: string, key: string, fn: (token: string, id: string) => Promise<T>, enabled = true) {
  
  return useQuery({
    queryKey: ["admin", "users", userId, key],
    enabled: Boolean(token) && enabled,
    queryFn: () => fn(token!, userId),
  });
}

function AdminEntitlements({ token, userId, entitlement, onRefresh }: { token: string; userId: string; entitlement: EffectiveEntitlement | null | undefined; onRefresh: () => Promise<unknown> }) {
  const i18n = useUiTranslations();
  const [form, setForm] = useState({ allowance: "class_visits" as "class_visits" | "coaching_touchpoints", quantity: 1, period: "calendar_month" as "calendar_week" | "calendar_month" | "subscription_period", reason: "" });
  const [revokeTarget, setRevokeTarget] = useState<string | null>(null);
  const [revokeReason, setRevokeReason] = useState("");
  const grant = useMutation({ mutationFn: () => grantAdminUserAllowance(token, userId, form), onSuccess: async () => { setForm((value) => ({ ...value, quantity: 1, reason: "" })); await onRefresh(); } });
  const revoke = useMutation({ mutationFn: () => revokeAdminUserAllowance(token, userId, revokeTarget!, revokeReason), onSuccess: async () => { setRevokeTarget(null); setRevokeReason(""); await onRefresh(); } });
  const entries = entitlement?.usage_entries ?? [];
  const revoked = new Set(entries.filter((entry) => entry.parent_entry_id).map((entry) => entry.parent_entry_id));

  return (
    <>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        {Object.entries(entitlement?.allowances ?? {}).map(([key, allowance]) => allowance ? <div key={key} className="rounded-xl p-3" style={{ background: "var(--bg-soft)" }}><p className="font-semibold">{label(key)}</p><p>{String(allowance.remaining)} {i18n("remainingOf8553660")} {String(allowance.limit)}{allowance.extensions > 0 ? "· +" + (allowance.extensions) + " personal" : ""}</p><p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("resetsAftere96e46e")} {date(allowance.period_end)}</p></div> : null)}
      </div>
      <form className="mt-5 space-y-3 rounded-2xl p-4" style={{ border: "1px solid var(--border)" }} onSubmit={(event) => { event.preventDefault(); grant.mutate(); }}>
        <p className="font-semibold" style={{ color: "var(--text)" }}>{i18n("extendThisUserSAllowance6e08374")}</p>
        <div className="grid gap-3 sm:grid-cols-3">
          <select value={form.allowance} onChange={(event) => setForm({ ...form, allowance: event.target.value as typeof form.allowance })} className="rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)" }}><option value="class_visits">{i18n("classVisits142b3b0")}</option><option value="coaching_touchpoints">{i18n("coachingTouchpoints23bfcb6")}</option></select>
          <input aria-label={i18n("additionalUnits1d9dac0")} type="number" min={1} value={form.quantity} onChange={(event) => setForm({ ...form, quantity: Number(event.target.value) })} className="rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)" }} />
          <select value={form.period} onChange={(event) => setForm({ ...form, period: event.target.value as typeof form.period })} className="rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)" }}><option value="calendar_week">{i18n("thisCalendarWeekb05ceca")}</option><option value="calendar_month">{i18n("thisCalendarMonthbb33495")}</option><option value="subscription_period">{i18n("subscriptionPeriod22e7508")}</option></select>
        </div>
        <textarea required minLength={3} placeholder={i18n("reasonForThisPersonalExtensionbe8ddf7")} value={form.reason} onChange={(event) => setForm({ ...form, reason: event.target.value })} className="min-h-20 w-full rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)" }} />
        <button disabled={grant.isPending || form.reason.trim().length < 3} className="rounded-full px-4 py-2 font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--bg)" }}>{grant.isPending ? i18n("extending80e2fcd") : i18n("extendAllowance2d3fd3a")}</button>
        {grant.isError ? <p style={{ color: "var(--danger)" }}>{i18n("theExtensionCouldNotBeRecorded8e3fe5d")}</p> : null}
      </form>
      <div className="mt-5 space-y-2">
        <p className="font-semibold" style={{ color: "var(--text)" }}>{i18n("personalExtensionHistory752eda5")}</p>
        {entries.filter((entry) => entry.event_type === "adjustment" && entry.quantity_delta < 0).map((entry) => <div key={entry.id} className="rounded-xl p-3" style={{ background: "var(--bg-soft)" }}><div className="flex flex-wrap items-center justify-between gap-2"><div><strong>+{Math.abs(entry.quantity_delta)} {label(entry.allowance_key)}</strong><p className="text-xs" style={{ color: "var(--muted)" }}>{entry.reason} · {date(entry.inserted_at)} {i18n("validThrough263dc88")} {date(entry.period_end)}</p></div>{revoked.has(entry.id) ? <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{i18n("revoked85f17ac")}</span> : <button type="button" onClick={() => setRevokeTarget(entry.id)} className="text-xs font-semibold" style={{ color: "var(--danger)" }}>{i18n("revoke0be7207")}</button>}</div>{revokeTarget === entry.id ? <form className="mt-3 flex flex-col gap-2 sm:flex-row" onSubmit={(event) => { event.preventDefault(); revoke.mutate(); }}><input required minLength={3} value={revokeReason} onChange={(event) => setRevokeReason(event.target.value)} placeholder={i18n("reasonForRevocationac5b98c")} className="min-w-0 flex-1 rounded-xl px-3 py-2" style={{ background: "var(--panel)" }} /><button disabled={revoke.isPending || revokeReason.trim().length < 3} className="rounded-full px-3 py-2 text-xs font-semibold disabled:opacity-50" style={{ background: "var(--danger)", color: "white" }}>{i18n("confirmRevocationc1a9d03")}</button></form> : null}</div>)}
        {entries.every((entry) => entry.event_type !== "adjustment" || entry.quantity_delta >= 0) ? <Empty>{i18n("noPersonalExtensionsRecorded558dcb3")}</Empty> : null}
      </div>
    </>
  );
}

export function AdminUserProfile({ userId }: { userId: string }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token;
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
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["admin", "users"] }),
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

  const sections = new Set(profile.available_sections);
  const executions = training.data?.executions ?? [];
  const scores = training.data?.scores ?? [];
  const effectiveEntitlement = finance.data?.summary?.effective_entitlement;

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-6">
        <Link href="/admin/users" className="text-sm font-semibold" style={{ color: "var(--primary)" }}>{i18n("users206fc04")}</Link>
        <section className="rounded-[2.4rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{profile.identity.role}</p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>{profile.identity.nickname}</h1>
          <p className="mt-3 text-sm" style={{ color: "var(--muted)" }}>{profile.account_status} {i18n("joinedbbc56ef")} {date(profile.identity.joined_at)}</p>
        </section>

        <nav aria-label={i18n("profileSectionscd4815c")} className="flex gap-2 overflow-x-auto pb-1">
          {profile.available_sections.map((section) => <a key={section} href={"#" + (section)} className="shrink-0 rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>{label(section)}</a>)}
        </nav>

        <section className="grid gap-4 md:grid-cols-2">
          <Panel id="overview" title={i18n("overview0efc2e6")}><dl className="grid grid-cols-2 gap-3"><div><dt style={{ color: "var(--muted)" }}>{i18n("rolec3f104d")}</dt><dd className="font-semibold">{profile.identity.role}</dd></div><div><dt style={{ color: "var(--muted)" }}>{i18n("account85dfa32")}</dt><dd className="font-semibold">{profile.account_status}</dd></div></dl></Panel>

          {sections.has("finance") ? <Panel id="finance" title={i18n("entitlementsAllowancescac0ef7")} href="/admin/finance"><p className="text-2xl font-semibold" style={{ color: "var(--text)" }}>{finance.data?.summary?.credit_balance ?? 0} {i18n("credits66c22fa")}</p><p className="mt-2">{String(finance.data?.summary?.current_status?.state ?? i18n("loadingMembershipStatusa609a3f"))}</p>{token ? <AdminEntitlements token={token} userId={userId} entitlement={effectiveEntitlement} onRefresh={() => queryClient.invalidateQueries({ queryKey: ["admin", "users", userId, "finance"] })} /> : null}</Panel> : null}

          {sections.has("training_history") ? <Panel id="training_history" title={i18n("trainingHistorya512053")} href="/admin/workouts"><p>{training.data?.summary.completed_count ?? 0} {i18n("completedOf88964ae")} {training.data?.summary.execution_count ?? 0} {i18n("executions8319d6e")}</p><div className="mt-3 space-y-2">{executions.length ? executions.slice(0, 5).map((item) => <div key={item.id} className="rounded-xl p-3" style={{ background: "var(--bg-soft)" }}><span className="font-semibold">{item.workout_title}</span><span className="ms-2" style={{ color: "var(--muted)" }}>{item.status} · {date(item.started_at_utc)}</span></div>) : <Empty>{i18n("noWorkoutExecutionsRecorded0a0b1d0")}</Empty>}</div></Panel> : null}

          {sections.has("prs") ? <Panel id="prs" title={i18n("personalRecords05223a0")}><div className="space-y-2">{prs.data?.prs.length ? prs.data.prs.map((pr) => <div key={pr.id} className="flex justify-between gap-4"><span>{pr.name}</span><strong>{String(pr.current_score)} {pr.unit}</strong></div>) : <Empty>{i18n("noPersonalRecordsRecorded22a0fce")}</Empty>}</div></Panel> : null}

          {sections.has("scores") ? <Panel id="scores" title={i18n("scores126cb93")}><div className="space-y-2">{scores.length ? scores.slice(0, 8).map((score, index) => <div key={(String(score.execution_id)) + "-" + (index)} className="flex justify-between gap-4"><span>{String(score.section_name ?? i18n("workoutSection881e276"))}</span><strong>{String(score.value ?? "—")} {String(score.unit ?? "")}</strong></div>) : <Empty>{i18n("noScoredWorkoutSectionsRecordedcfa7742")}</Empty>}</div></Panel> : null}

          {sections.has("health_incidents") ? <Panel id="health_incidents" title={i18n("healthIncidentse3ca869")} href="/admin/metrics#health-incidents"><p>{incidents.data?.summary.active ?? 0} {i18n("active4c71073")} {incidents.data?.summary.total ?? 0} {i18n("total5a537e2")}</p><div className="mt-3 space-y-2">{incidents.data?.incidents.length ? incidents.data.incidents.map((incident) => <div key={incident.id}><strong>{incident.body_area}</strong> · {incident.severity} · {incident.status}{incident.training_limitations ? <p style={{ color: "var(--muted)" }}>{incident.training_limitations}</p> : null}</div>) : <Empty>{i18n("noHealthIncidentsRecorded91c9d4e")}</Empty>}</div></Panel> : null}

          {sections.has("coaching_context") ? <Panel id="coaching_context" title={i18n("coachingContexteb3075d")} href="/admin/coaching-assignments"><p>{String((coaching.data?.drill_down?.recent_activity as Record<string, unknown> | undefined)?.state ?? i18n("loadingActivity4c959ab"))}</p><p className="mt-2">{Array.isArray(coaching.data?.drill_down?.assigned_workouts) ? coaching.data.drill_down.assigned_workouts.length : 0} {i18n("assignedWorkoutSInTheCoachingWindow2200dd4")}</p></Panel> : null}

          {sections.has("class_participation") ? <Panel id="class_participation" title={i18n("classParticipation9ef4001")} href="/admin/class-schedule"><div className="space-y-2">{training.data?.class_participation.length ? training.data.class_participation.map((item) => <p key={item.id}>{item.workout_title} · {date(item.started_at_utc)}</p>) : <Empty>{i18n("noClassLinkedWorkoutExecutionsRecordedf8ca7a6")}</Empty>}</div></Panel> : null}

          {sections.has("messages") ? <Panel id="messages" title={i18n("chat2ced57f")} href="/account/activity/chats"><p>{messages.data?.summary.thread_count ?? 0} {i18n("threadS2bddeec")} {messages.data?.summary.unread_thread_count ?? 0} {i18n("unread1b9aebd")}</p><div className="mt-3 space-y-2">{messages.data?.threads.length ? messages.data.threads.slice(0, 4).map((thread) => <p key={thread.id}>{thread.latest_message?.body ?? i18n("emptyThreadfee51b1")}</p>) : <Empty>{i18n("noConversationsRecordedd525265")}</Empty>}</div></Panel> : null}

          {sections.has("admin_actions") ? <Panel id="admin_actions" title={i18n("adminActionsfa81c61")}><label className="block"><span className="block text-xs uppercase tracking-wider" style={{ color: "var(--muted)" }}>{i18n("accountRole39514a0")}</span><select value={profile.identity.role} disabled={roleMutation.isPending} onChange={(event) => roleMutation.mutate(event.target.value as AdminUserDirectoryEntry["role"])} className="mt-2 rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}><option value="member">{i18n("member6853c98")}</option><option value="athlete">{i18n("athleteaa86fd2")}</option><option value="admin">{i18n("admin4e7afeb")}</option></select></label>{roleMutation.isError ? <p className="mt-2" style={{ color: "var(--danger)" }}>{i18n("roleUpdateFailed493da52")}</p> : null}</Panel> : null}
        </section>
      </div>
    </main>
  );
}
