"use client";

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

function Panel({ id, title, children, href, hrefLabel = "Open workspace" }: { id: string; title: string; children: React.ReactNode; href?: string; hrefLabel?: string }) {
  return (
    <article id={id} className="scroll-mt-20 rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>{title}</p>
      <div className="mt-4 text-sm leading-6" style={{ color: "var(--text-soft)" }}>{children}</div>
      {href ? <Link href={href} className="mt-4 inline-flex text-sm font-semibold" style={{ color: "var(--primary)" }}>{hrefLabel} →</Link> : null}
    </article>
  );
}

function Empty({ children }: { children: React.ReactNode }) {
  return <p style={{ color: "var(--muted)" }}>{children}</p>;
}

function date(value: unknown) {
  return typeof value === "string" ? value.slice(0, 10) : "Date unavailable";
}

function useDossierQuery<T>(token: string | undefined, userId: string, key: string, fn: (token: string, id: string) => Promise<T>, enabled = true) {
  return useQuery({
    queryKey: ["admin", "users", userId, key],
    enabled: Boolean(token) && enabled,
    queryFn: () => fn(token!, userId),
  });
}

function AdminEntitlements({ token, userId, entitlement, onRefresh }: { token: string; userId: string; entitlement: EffectiveEntitlement | null | undefined; onRefresh: () => Promise<unknown> }) {
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
        {Object.entries(entitlement?.allowances ?? {}).map(([key, allowance]) => allowance ? <div key={key} className="rounded-xl p-3" style={{ background: "var(--bg-soft)" }}><p className="font-semibold">{label(key)}</p><p>{String(allowance.remaining)} remaining of {String(allowance.limit)}{allowance.extensions > 0 ? ` · +${allowance.extensions} personal` : ""}</p><p className="text-xs" style={{ color: "var(--muted)" }}>Resets after {date(allowance.period_end)}</p></div> : null)}
      </div>
      <form className="mt-5 space-y-3 rounded-2xl p-4" style={{ border: "1px solid var(--border)" }} onSubmit={(event) => { event.preventDefault(); grant.mutate(); }}>
        <p className="font-semibold" style={{ color: "var(--text)" }}>Extend this user&apos;s allowance</p>
        <div className="grid gap-3 sm:grid-cols-3">
          <select value={form.allowance} onChange={(event) => setForm({ ...form, allowance: event.target.value as typeof form.allowance })} className="rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)" }}><option value="class_visits">Class visits</option><option value="coaching_touchpoints">Coaching touchpoints</option></select>
          <input aria-label="Additional units" type="number" min={1} value={form.quantity} onChange={(event) => setForm({ ...form, quantity: Number(event.target.value) })} className="rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)" }} />
          <select value={form.period} onChange={(event) => setForm({ ...form, period: event.target.value as typeof form.period })} className="rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)" }}><option value="calendar_week">This calendar week</option><option value="calendar_month">This calendar month</option><option value="subscription_period">Subscription period</option></select>
        </div>
        <textarea required minLength={3} placeholder="Reason for this personal extension" value={form.reason} onChange={(event) => setForm({ ...form, reason: event.target.value })} className="min-h-20 w-full rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)" }} />
        <button disabled={grant.isPending || form.reason.trim().length < 3} className="rounded-full px-4 py-2 font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--bg)" }}>{grant.isPending ? "Extending…" : "Extend allowance"}</button>
        {grant.isError ? <p style={{ color: "var(--danger)" }}>The extension could not be recorded.</p> : null}
      </form>
      <div className="mt-5 space-y-2">
        <p className="font-semibold" style={{ color: "var(--text)" }}>Personal extension history</p>
        {entries.filter((entry) => entry.event_type === "adjustment" && entry.quantity_delta < 0).map((entry) => <div key={entry.id} className="rounded-xl p-3" style={{ background: "var(--bg-soft)" }}><div className="flex flex-wrap items-center justify-between gap-2"><div><strong>+{Math.abs(entry.quantity_delta)} {label(entry.allowance_key)}</strong><p className="text-xs" style={{ color: "var(--muted)" }}>{entry.reason} · {date(entry.inserted_at)} · valid through {date(entry.period_end)}</p></div>{revoked.has(entry.id) ? <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>Revoked</span> : <button type="button" onClick={() => setRevokeTarget(entry.id)} className="text-xs font-semibold" style={{ color: "var(--danger)" }}>Revoke</button>}</div>{revokeTarget === entry.id ? <form className="mt-3 flex flex-col gap-2 sm:flex-row" onSubmit={(event) => { event.preventDefault(); revoke.mutate(); }}><input required minLength={3} value={revokeReason} onChange={(event) => setRevokeReason(event.target.value)} placeholder="Reason for revocation" className="min-w-0 flex-1 rounded-xl px-3 py-2" style={{ background: "var(--panel)" }} /><button disabled={revoke.isPending || revokeReason.trim().length < 3} className="rounded-full px-3 py-2 text-xs font-semibold disabled:opacity-50" style={{ background: "var(--danger)", color: "white" }}>Confirm revocation</button></form> : null}</div>)}
        {entries.every((entry) => entry.event_type !== "adjustment" || entry.quantity_delta >= 0) ? <Empty>No personal extensions recorded.</Empty> : null}
      </div>
    </>
  );
}

export function AdminUserProfile({ userId }: { userId: string }) {
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

  if (profileQuery.isLoading) return <main className="min-h-screen p-10" style={{ background: "var(--bg)", color: "var(--muted)" }}>Loading profile…</main>;
  if (!profile) return <main className="min-h-screen p-10" style={{ background: "var(--bg)", color: "var(--danger)" }}>User profile could not be loaded.</main>;

  const sections = new Set(profile.available_sections);
  const executions = training.data?.executions ?? [];
  const scores = training.data?.scores ?? [];
  const effectiveEntitlement = finance.data?.summary?.effective_entitlement;

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-6">
        <Link href="/admin/users" className="text-sm font-semibold" style={{ color: "var(--primary)" }}>← Users</Link>
        <section className="rounded-[2.4rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{profile.identity.role}</p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>{profile.identity.nickname}</h1>
          <p className="mt-3 text-sm" style={{ color: "var(--muted)" }}>{profile.account_status} · Joined {date(profile.identity.joined_at)}</p>
        </section>

        <nav aria-label="Profile sections" className="flex gap-2 overflow-x-auto pb-1">
          {profile.available_sections.map((section) => <a key={section} href={`#${section}`} className="shrink-0 rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>{label(section)}</a>)}
        </nav>

        <section className="grid gap-4 md:grid-cols-2">
          <Panel id="overview" title="Overview"><dl className="grid grid-cols-2 gap-3"><div><dt style={{ color: "var(--muted)" }}>Role</dt><dd className="font-semibold">{profile.identity.role}</dd></div><div><dt style={{ color: "var(--muted)" }}>Account</dt><dd className="font-semibold">{profile.account_status}</dd></div></dl></Panel>

          {sections.has("finance") ? <Panel id="finance" title="Entitlements & allowances" href="/admin/finance"><p className="text-2xl font-semibold" style={{ color: "var(--text)" }}>{finance.data?.summary?.credit_balance ?? 0} credits</p><p className="mt-2">{String(finance.data?.summary?.current_status?.state ?? "Loading membership status…")}</p>{token ? <AdminEntitlements token={token} userId={userId} entitlement={effectiveEntitlement} onRefresh={() => queryClient.invalidateQueries({ queryKey: ["admin", "users", userId, "finance"] })} /> : null}</Panel> : null}

          {sections.has("training_history") ? <Panel id="training_history" title="Training history" href="/admin/workouts"><p>{training.data?.summary.completed_count ?? 0} completed of {training.data?.summary.execution_count ?? 0} executions</p><div className="mt-3 space-y-2">{executions.length ? executions.slice(0, 5).map((item) => <div key={item.id} className="rounded-xl p-3" style={{ background: "var(--bg-soft)" }}><span className="font-semibold">{item.workout_title}</span><span className="ml-2" style={{ color: "var(--muted)" }}>{item.status} · {date(item.started_at_utc)}</span></div>) : <Empty>No workout executions recorded.</Empty>}</div></Panel> : null}

          {sections.has("prs") ? <Panel id="prs" title="Personal records"><div className="space-y-2">{prs.data?.prs.length ? prs.data.prs.map((pr) => <div key={pr.id} className="flex justify-between gap-4"><span>{pr.name}</span><strong>{String(pr.current_score)} {pr.unit}</strong></div>) : <Empty>No personal records recorded.</Empty>}</div></Panel> : null}

          {sections.has("scores") ? <Panel id="scores" title="Scores"><div className="space-y-2">{scores.length ? scores.slice(0, 8).map((score, index) => <div key={`${String(score.execution_id)}-${index}`} className="flex justify-between gap-4"><span>{String(score.section_name ?? "Workout section")}</span><strong>{String(score.value ?? "—")} {String(score.unit ?? "")}</strong></div>) : <Empty>No scored workout sections recorded.</Empty>}</div></Panel> : null}

          {sections.has("health_incidents") ? <Panel id="health_incidents" title="Health / incidents" href="/admin/metrics#health-incidents"><p>{incidents.data?.summary.active ?? 0} active · {incidents.data?.summary.total ?? 0} total</p><div className="mt-3 space-y-2">{incidents.data?.incidents.length ? incidents.data.incidents.map((incident) => <div key={incident.id}><strong>{incident.body_area}</strong> · {incident.severity} · {incident.status}{incident.training_limitations ? <p style={{ color: "var(--muted)" }}>{incident.training_limitations}</p> : null}</div>) : <Empty>No health incidents recorded.</Empty>}</div></Panel> : null}

          {sections.has("coaching_context") ? <Panel id="coaching_context" title="Coaching context" href="/admin/coaching-assignments"><p>{String((coaching.data?.drill_down?.recent_activity as Record<string, unknown> | undefined)?.state ?? "Loading activity…")}</p><p className="mt-2">{Array.isArray(coaching.data?.drill_down?.assigned_workouts) ? coaching.data.drill_down.assigned_workouts.length : 0} assigned workout(s) in the coaching window.</p></Panel> : null}

          {sections.has("class_participation") ? <Panel id="class_participation" title="Class participation" href="/admin/class-schedule"><div className="space-y-2">{training.data?.class_participation.length ? training.data.class_participation.map((item) => <p key={item.id}>{item.workout_title} · {date(item.started_at_utc)}</p>) : <Empty>No class-linked workout executions recorded.</Empty>}</div></Panel> : null}

          {sections.has("messages") ? <Panel id="messages" title="Messages" href="/account/activity/chats"><p>{messages.data?.summary.thread_count ?? 0} thread(s) · {messages.data?.summary.unread_thread_count ?? 0} unread</p><div className="mt-3 space-y-2">{messages.data?.threads.length ? messages.data.threads.slice(0, 4).map((thread) => <p key={thread.id}>{thread.latest_message?.body ?? "Empty thread"}</p>) : <Empty>No conversations recorded.</Empty>}</div></Panel> : null}

          {sections.has("admin_actions") ? <Panel id="admin_actions" title="Admin actions"><label className="block"><span className="block text-xs uppercase tracking-wider" style={{ color: "var(--muted)" }}>Account role</span><select value={profile.identity.role} disabled={roleMutation.isPending} onChange={(event) => roleMutation.mutate(event.target.value as AdminUserDirectoryEntry["role"])} className="mt-2 rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}><option value="member">Member</option><option value="athlete">Athlete</option><option value="admin">Admin</option></select></label>{roleMutation.isError ? <p className="mt-2" style={{ color: "var(--danger)" }}>Role update failed.</p> : null}</Panel> : null}
        </section>
      </div>
    </main>
  );
}
