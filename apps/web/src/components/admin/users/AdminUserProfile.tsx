"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";

import {
  fetchAdminUserCoachingContext,
  fetchAdminUserFinance,
  fetchAdminUserIncidents,
  fetchAdminUserMessages,
  fetchAdminUserPRs,
  fetchAdminUserProfile,
  fetchAdminUserTraining,
  updateAdminUserRole,
  type AdminUserDirectoryEntry,
} from "@/api/admin-users";
import { useSession } from "@/components/session-provider";

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

  if (profileQuery.isLoading) return <main className="min-h-screen p-10" style={{ background: "var(--bg)", color: "var(--muted)" }}>Loading profile…</main>;
  if (!profile) return <main className="min-h-screen p-10" style={{ background: "var(--bg)", color: "var(--danger)" }}>User profile could not be loaded.</main>;

  const sections = new Set(profile.available_sections);
  const executions = training.data?.executions ?? [];
  const scores = training.data?.scores ?? [];

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

          {sections.has("finance") ? <Panel id="finance" title="Finance" href="/admin/finance"><p className="text-2xl font-semibold" style={{ color: "var(--text)" }}>{finance.data?.summary?.credit_balance ?? 0} credits</p><p className="mt-2">{String(finance.data?.summary?.current_status?.state ?? "Loading membership status…")}</p>{finance.data?.summary?.outstanding_items?.length ? <p className="mt-2" style={{ color: "var(--warning)" }}>{finance.data.summary.outstanding_items.length} item(s) need attention</p> : <p className="mt-2">No outstanding finance actions.</p>}</Panel> : null}

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
