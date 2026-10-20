"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import {
  actOnReport,
  decideGroup,
  fetchReports,
  fetchStaffGroups,
  REPORT_ACTIONS,
  REPORTS_KEY,
  reopenStaffGroup,
  STAFF_GROUPS_KEY,
  type ReportAction,
  type ReportRow,
  type StaffGroup,
} from "@/api/admin-community";
import { clientErrorMessage } from "@/components/client/errors";
import { ErrorLine } from "@/components/community/Sheet";
import { SmallButton } from "@/components/community/GroupPage";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

import { MemberGroupsSetting } from "./CommunitySettings";
import { OpenClubsTab } from "./OpenClubsTab";

type Tab = "groups" | "reports" | "clubs";
const TABS: Tab[] = ["groups", "reports", "clubs"];

/**
 * Κοινότητα (board 7 Q3): Ομάδες (proposals to approve, live and archived
 * groups, the member-groups setting) · Αναφορές (the grouped queue, Q5) ·
 * Ανοιχτά clubs (Q6).
 */
export function CommunityAdminPage() {
  const t = useTranslations("CommunityAdmin");
  const params = useSearchParams();
  const router = useRouter();
  const requested = params.get("tab");
  const tab: Tab = TABS.includes(requested as Tab) ? (requested as Tab) : "groups";
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const groups = useQuery({ queryKey: STAFF_GROUPS_KEY, enabled: Boolean(token), queryFn: () => fetchStaffGroups(token) });
  const reports = useQuery({ queryKey: REPORTS_KEY, enabled: Boolean(token), queryFn: () => fetchReports(token) });
  const counts: Record<Tab, number | undefined> = {
    groups: groups.data?.pending.length,
    reports: reports.data?.length,
    clubs: undefined,
  };

  function select(next: Tab) {
    const search = new URLSearchParams(params.toString());
    search.set("tab", next);
    router.replace(`?${search.toString()}`, { scroll: false });
  }

  return (
    <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-3xl flex-col gap-5 pb-28">
        <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("title")}</h1>
        <div role="tablist" aria-label={t("title")} className="flex gap-2">
          {TABS.map((value) => (
            <button
              key={value}
              type="button"
              role="tab"
              aria-selected={tab === value}
              onClick={() => select(value)}
              className="min-h-11 flex-1 rounded-2xl px-2 text-sm font-semibold"
              style={{
                background: tab === value ? "var(--primary)" : "var(--panel)",
                color: tab === value ? "var(--bg)" : "var(--text)",
                border: "1px solid var(--border)",
              }}
            >
              {t(`tab_${value}`)}
              {counts[value] ? ` · ${counts[value]}` : ""}
            </button>
          ))}
        </div>
        {tab === "groups" ? <GroupsTab /> : tab === "reports" ? <ReportsTab /> : <OpenClubsTab />}
      </div>
    </main>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <h2 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{title}</h2>
      {children}
    </section>
  );
}

function GroupsTab() {
  const t = useTranslations("CommunityAdmin");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const { membership } = useSelectedMembershipRole();
  const groups = useQuery({ queryKey: STAFF_GROUPS_KEY, enabled: Boolean(token), queryFn: () => fetchStaffGroups(token) });
  if (!groups.data) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  const { pending, live, archived, settings } = groups.data;

  return (
    <>
      {can(membership, "manage_community") ? <MemberGroupsSetting current={settings.member_groups} /> : null}
      {pending.length > 0 ? (
        <Panel title={t("groupsPending", { count: pending.length })}>
          <ul className="flex flex-col gap-2">
            {pending.map((group) => (
              <StaffGroupRow key={group.id} group={group} mode="pending" />
            ))}
          </ul>
        </Panel>
      ) : null}
      <Panel title={t("groupsLive", { count: live.length })}>
        {live.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("groupsLiveEmpty")}</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {live.map((group) => (
              <StaffGroupRow key={group.id} group={group} mode="live" />
            ))}
          </ul>
        )}
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {t("groupsLifecycle", { warn: settings.lifecycle.warn_after_days, archive: settings.lifecycle.archive_after_days })}
        </p>
      </Panel>
      {archived.length > 0 ? (
        <Panel title={t("groupsArchived", { count: archived.length })}>
          <ul className="flex flex-col gap-2">
            {archived.map((group) => (
              <StaffGroupRow key={group.id} group={group} mode="archived" />
            ))}
          </ul>
        </Panel>
      ) : null}
    </>
  );
}

function StaffGroupRow({ group, mode }: { group: StaffGroup; mode: "pending" | "live" | "archived" }) {
  const t = useTranslations("CommunityAdmin");
  const tUi = useUiTranslations();
  const locale = useLocale();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const act = useMutation({
    mutationFn: (action: "approve" | "decline" | "reopen") =>
      action === "reopen" ? reopenStaffGroup(tokens!.access_token, group.id) : decideGroup(tokens!.access_token, group.id, action),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: STAFF_GROUPS_KEY }),
  });
  const day = (iso: string) => new Intl.DateTimeFormat(locale, { day: "numeric", month: "short" }).format(new Date(iso));
  const detail = [
    group.created_by?.nickname ? t("startedBy", { name: group.created_by.nickname }) : null,
    mode !== "pending" ? t("members", { count: group.member_count }) : null,
    mode === "live" ? (group.last_post_at ? t("lastPost", { date: day(group.last_post_at) }) : t("noPostsYet")) : null,
    mode === "live" && group.archive_warned_at ? t("warned") : null,
    mode === "archived" && group.archived_at ? t("archivedOn", { date: day(group.archived_at) }) : null,
  ].filter(Boolean);

  return (
    <li className="flex flex-col gap-2 rounded-2xl px-4 py-3" style={{ background: "var(--panel-raised)" }}>
      <div className="flex flex-wrap items-center gap-3">
        <div className="min-w-0 grow">
          <p className="font-bold" style={{ color: "var(--text)" }}>{group.name}</p>
          {group.description ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{group.description}</p> : null}
          <p className="text-xs" style={{ color: "var(--dim)" }}>{detail.join(" · ")}</p>
        </div>
        {mode === "pending" ? (
          <div className="flex gap-2">
            <SmallButton disabled={act.isPending} onClick={() => act.mutate("decline")}>{t("decline")}</SmallButton>
            <SmallButton primary disabled={act.isPending} onClick={() => act.mutate("approve")}>{t("approve")}</SmallButton>
          </div>
        ) : mode === "archived" ? (
          <SmallButton disabled={act.isPending} onClick={() => act.mutate("reopen")}>{t("reopen")}</SmallButton>
        ) : null}
      </div>
      <ErrorLine message={act.error ? clientErrorMessage(act.error, tUi) : null} />
    </li>
  );
}

function ReportsTab() {
  const t = useTranslations("CommunityAdmin");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const reports = useQuery({ queryKey: REPORTS_KEY, enabled: Boolean(token), queryFn: () => fetchReports(token) });
  if (!reports.data) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (reports.data.length === 0) {
    return (
      <Panel title={t("tab_reports")}>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("reportsEmpty")}</p>
      </Panel>
    );
  }
  return (
    <ul className="flex flex-col gap-3">
      {reports.data.map((row) => (
        <ReportItem key={`${row.target_type}:${row.target_id}`} row={row} />
      ))}
    </ul>
  );
}

function ReportItem({ row }: { row: ReportRow }) {
  const t = useTranslations("CommunityAdmin");
  const tClubs = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const locale = useLocale();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [done, setDone] = useState<ReportAction | null>(null);
  const act = useMutation({
    mutationFn: (action: ReportAction) => actOnReport(tokens!.access_token, row, action),
    onSuccess: (_result, action) => {
      setDone(action);
      void queryClient.invalidateQueries({ queryKey: REPORTS_KEY });
      void queryClient.invalidateQueries({ queryKey: STAFF_GROUPS_KEY });
    },
  });
  const reasons = Object.entries(row.reasons)
    .sort((a, b) => b[1] - a[1])
    .map(([reason, count]) => `${tClubs(`reason_${reason}`)} ×${count}`);
  const when = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(
    new Date(row.last_reported_at),
  );

  return (
    <li className="flex flex-col gap-2 rounded-3xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
        {t(`target_${row.target_type}`)} · {t("reportCount", { count: row.report_count })} · {when}
      </p>
      {row.author?.nickname ? <p className="text-sm font-bold" style={{ color: "var(--text)" }}>{row.author.nickname}</p> : null}
      <p className="whitespace-pre-wrap rounded-2xl px-3 py-2 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
        {row.preview?.name ?? row.preview?.body ?? t("previewGone")}
        {row.preview?.hidden ? <span className="ml-2 text-xs font-semibold" style={{ color: "var(--warning, #b45309)" }}>{t("alreadyHidden")}</span> : null}
      </p>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{reasons.join(" · ")}</p>
      {row.notes.length > 0 ? (
        <ul className="flex flex-col gap-1">
          {row.notes.map((note, index) => (
            <li key={index} className="text-sm italic" style={{ color: "var(--text-soft)" }}>«{note}»</li>
          ))}
        </ul>
      ) : null}
      {done ? (
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`done_${done}`)}</p>
      ) : (
        <div className="flex flex-wrap gap-2">
          {REPORT_ACTIONS[row.target_type].map((action) => (
            <SmallButton key={action} primary={action !== "dismiss"} disabled={act.isPending} onClick={() => act.mutate(action)}>
              {t(`action_${action}`)}
            </SmallButton>
          ))}
        </div>
      )}
      <ErrorLine message={act.error ? clientErrorMessage(act.error, tUi) : null} />
    </li>
  );
}
