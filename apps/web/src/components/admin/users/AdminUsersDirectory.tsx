"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useDeferredValue, useEffect, useMemo, useRef, useState, type ReactNode } from "react";

import { fetchAdminUsers, type AdminUserDirectoryEntry } from "@/api/admin-users";
import { InviteClientsButton } from "@/components/invites/InviteClients";
import { PageHeader } from "@/components/PageHeader";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import {
  avatarHue,
  filterDirectory,
  initialsOf,
  roleCounts,
  type DirectoryFilters,
  type DirectoryRole,
  type DirectorySort,
} from "@/lib/users-directory";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

const ROLES: DirectoryRole[] = ["all", "member", "athlete", "admin"];
const SORTS: DirectorySort[] = ["name", "newest", "oldest"];
const PAGE_SIZE = 50;
const MAX_USERS = 1_000;
const EDITABLE_SELECTOR = ["input", "textarea", "select", "[contenteditable='true']"].join(",");

/** Loads the whole tenant directory so search, counts and sorting are instant. */
async function fetchWholeDirectory(token: string) {
  const users: AdminUserDirectoryEntry[] = [];
  let offset = 0;

  while (offset < MAX_USERS) {
    const page = await fetchAdminUsers(token, { offset, limit: PAGE_SIZE });
    users.push(...page.users);
    if (!page.meta.has_more) break;
    offset += PAGE_SIZE;
  }

  return users;
}

export function AdminUsersDirectory() {
  const t = useTranslations("UsersDirectory");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const organizationSlug = useOrganizationSlug();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const searchRef = useRef<HTMLInputElement>(null);

  const [filters, setFilters] = useState<DirectoryFilters>(() => ({
    query: searchParams.get("q") ?? "",
    role: (ROLES as string[]).includes(searchParams.get("role") ?? "") ? (searchParams.get("role") as DirectoryRole) : "all",
    finance: searchParams.get("finance") ?? "all",
    sort: (SORTS as string[]).includes(searchParams.get("sort") ?? "") ? (searchParams.get("sort") as DirectorySort) : "name",
  }));
  const deferredQuery = useDeferredValue(filters.query);

  const usersQuery = useQuery({
    queryKey: ["admin", "users", "directory"],
    enabled: Boolean(token),
    queryFn: () => fetchWholeDirectory(token!),
    staleTime: 30_000,
  });

  const allUsers = useMemo(() => usersQuery.data ?? [], [usersQuery.data]);
  const counts = useMemo(() => roleCounts(allUsers, deferredQuery), [allUsers, deferredQuery]);
  const users = useMemo(() => filterDirectory(allUsers, { ...filters, query: deferredQuery }), [allUsers, filters, deferredQuery]);
  const financeStatuses = useMemo(
    () => Array.from(new Set(allUsers.map((user) => user.finance_status ?? "none"))).sort(),
    [allUsers],
  );
  const filtersActive = Boolean(filters.query.trim()) || filters.role !== "all" || filters.finance !== "all";

  // Keep filters in the URL so a view can be bookmarked or shared.
  useEffect(() => {
    const params = new URLSearchParams();
    if (filters.query.trim()) params.set("q", filters.query.trim());
    if (filters.role !== "all") params.set("role", filters.role);
    if (filters.finance !== "all") params.set("finance", filters.finance);
    if (filters.sort !== "name") params.set("sort", filters.sort);
    const next = params.toString();
    if (next !== searchParams.toString()) router.replace(next ? `${pathname}?${next}` : pathname, { scroll: false });
  }, [filters, pathname, router, searchParams]);

  // "/" focuses search, as in most admin consoles.
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null;
      if (event.key !== "/" || target?.closest(EDITABLE_SELECTOR)) return;
      event.preventDefault();
      searchRef.current?.focus();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  function update(patch: Partial<DirectoryFilters>) {
    setFilters((current) => ({ ...current, ...patch }));
  }

  function clearFilters() {
    setFilters((current) => ({ ...current, query: "", role: "all", finance: "all" }));
  }

  const dateFormat = new Intl.DateTimeFormat(locale, { dateStyle: "medium" });

  return (
    <main className="min-h-screen px-4 py-8 sm:px-6 md:px-10 md:py-12" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-5">
        <PageHeader
          title={
            <span className="flex items-baseline gap-3">
              {i18n("users57f2b18")}
              {usersQuery.data ? (
                <span className="text-base font-medium" style={{ color: "var(--muted)" }}>{allUsers.length}</span>
              ) : null}
            </span>
          }
          actions={<InviteClientsButton />}
        />

        <section className="space-y-3 rounded-[1.6rem] p-3 sm:p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} aria-label={t("filters")}>
          <div className="flex flex-col gap-3 lg:flex-row lg:items-center">
            <div className="relative min-w-0 flex-1">
              <span aria-hidden="true" className="pointer-events-none absolute inset-y-0 start-3 flex items-center text-sm" style={{ color: "var(--dim)" }}>⌕</span>
              <input
                ref={searchRef}
                type="search"
                aria-label={t("searchLabel")}
                placeholder={t("searchPlaceholder")}
                value={filters.query}
                onChange={(event) => update({ query: event.target.value })}
                className="w-full rounded-xl py-2.5 pe-16 ps-9 text-sm outline-none"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              />
              <kbd className="pointer-events-none absolute inset-y-0 end-3 my-auto hidden h-6 items-center rounded-md px-2 text-[11px] sm:flex" style={{ border: "1px solid var(--border)", color: "var(--dim)" }}>/</kbd>
            </div>
            <div className="grid grid-cols-2 gap-2 sm:flex">
              <label className="sr-only" htmlFor="users-finance-filter">{t("financeFilter")}</label>
              <select
                id="users-finance-filter"
                value={filters.finance}
                onChange={(event) => update({ finance: event.target.value })}
                className="rounded-xl px-3 py-2.5 text-sm"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              >
                <option value="all">{t("financeAll")}</option>
                {financeStatuses.map((status) => (
                  <option key={status} value={status}>
                    {status === "none" ? i18n("noFinanceProfilef804f44") : status.replaceAll("_", " ")}
                  </option>
                ))}
              </select>
              <label className="sr-only" htmlFor="users-sort">{t("sortLabel")}</label>
              <select
                id="users-sort"
                value={filters.sort}
                onChange={(event) => update({ sort: event.target.value as DirectorySort })}
                className="rounded-xl px-3 py-2.5 text-sm"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              >
                {SORTS.map((sort) => (
                  <option key={sort} value={sort}>{t(`sort.${sort}`)}</option>
                ))}
              </select>
            </div>
          </div>

          <div role="tablist" aria-label={t("roleFilter")} className="flex gap-1 overflow-x-auto">
            {ROLES.map((role) => (
              <button
                key={role}
                type="button"
                role="tab"
                aria-selected={filters.role === role}
                onClick={() => update({ role })}
                className="inline-flex shrink-0 items-center gap-2 rounded-lg px-3 py-2 text-sm font-semibold"
                style={filters.role === role ? { background: "var(--text)", color: "var(--bg)" } : { color: "var(--muted)" }}
              >
                {t(`roles.${role}`)}
                <span className="rounded-full px-1.5 text-[11px] font-bold" style={{ background: filters.role === role ? "color-mix(in srgb, var(--bg) 25%, transparent)" : "var(--panel-muted)" }}>
                  {counts[role]}
                </span>
              </button>
            ))}
          </div>

          {filtersActive && usersQuery.data ? (
            <div className="flex flex-wrap items-center justify-between gap-2 text-sm" style={{ color: "var(--muted)" }}>
              <p aria-live="polite">{t("showing", { shown: users.length, total: allUsers.length })}</p>
              <button type="button" onClick={clearFilters} className="font-semibold underline" style={{ color: "var(--primary)" }}>
                {t("clearFilters")}
              </button>
            </div>
          ) : null}
        </section>

        {usersQuery.isLoading ? <SkeletonRows /> : null}

        {usersQuery.isError ? (
          <div role="alert" className="flex flex-wrap items-center justify-between gap-3 rounded-2xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--danger)" }}>
            <span>{localizeError(usersQuery.error, i18n)}</span>
            <button type="button" onClick={() => void usersQuery.refetch()} className="rounded-lg px-3 py-1.5 font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
              {t("retry")}
            </button>
          </div>
        ) : null}

        {usersQuery.isSuccess && allUsers.length <= 1 && !filtersActive ? (
          <EmptyState title={t("emptyTitle")} body={t("emptyBody")} action={<InviteClientsButton label={t("inviteFirst")} />} />
        ) : null}

        {usersQuery.isSuccess && users.length === 0 && filtersActive ? (
          <EmptyState
            title={t("noMatchesTitle")}
            body={t("noMatchesBody")}
            action={
              <button type="button" onClick={clearFilters} className="rounded-xl px-4 py-2 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
                {t("clearFilters")}
              </button>
            }
          />
        ) : null}

        {usersQuery.isSuccess && users.length > 0 && !(allUsers.length <= 1 && !filtersActive) ? (
          <section aria-label={t("listLabel")} className="overflow-hidden rounded-[1.6rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <div className="hidden grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_auto] gap-4 px-5 py-3 text-[11px] font-semibold uppercase tracking-[0.16em] md:grid" style={{ color: "var(--dim)", borderBottom: "1px solid var(--border)" }}>
              <span>{t("columns.person")}</span>
              <span>{t("columns.finance")}</span>
              <span>{t("columns.joined")}</span>
              <span className="sr-only">{t("columns.open")}</span>
            </div>
            <ul>
              {users.map((user) => (
                <li key={user.id} style={{ borderBottom: "1px solid var(--border)" }} className="last:border-b-0">
                  <Link
                    href={adminHref(`/admin/users/${user.id}`, organizationSlug)}
                    className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 px-4 py-3 transition-colors hover:bg-[var(--panel-muted)] focus-visible:bg-[var(--panel-muted)] md:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_auto] md:gap-4 md:px-5"
                  >
                    <span className="flex min-w-0 items-center gap-3">
                      <Avatar user={user} />
                      <span className="min-w-0">
                        <span className="block truncate font-semibold" style={{ color: "var(--text)" }}>{user.nickname}</span>
                        <span className="mt-0.5 flex flex-wrap items-center gap-x-2 text-xs" style={{ color: "var(--muted)" }}>
                          <RoleBadge role={user.role} />
                          <span className="md:hidden">
                            {user.finance_status ? <SemanticLabel value={user.finance_status} /> : i18n("noFinanceProfilef804f44")}
                          </span>
                        </span>
                      </span>
                    </span>
                    <span className="hidden text-sm md:block" style={{ color: "var(--muted)" }}>
                      {user.finance_status ? <FinanceBadge status={user.finance_status} /> : <span style={{ color: "var(--dim)" }}>{i18n("noFinanceProfilef804f44")}</span>}
                    </span>
                    <span className="hidden text-sm md:block" style={{ color: "var(--muted)" }}>
                      {user.joined_at ? dateFormat.format(new Date(user.joined_at)) : "—"}
                    </span>
                    <span aria-hidden="true" className="text-lg" style={{ color: "var(--dim)" }}>›</span>
                  </Link>
                </li>
              ))}
            </ul>
          </section>
        ) : null}
      </div>
    </main>
  );
}

function Avatar({ user }: { user: AdminUserDirectoryEntry }) {
  if (user.avatar_url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={user.avatar_url} alt="" className="h-10 w-10 shrink-0 rounded-full object-cover" />;
  }

  const hue = avatarHue(user.id);
  return (
    <span
      aria-hidden="true"
      className="grid h-10 w-10 shrink-0 place-items-center rounded-full text-sm font-bold"
      style={{ background: `hsl(${hue} 55% 42% / 0.22)`, color: `hsl(${hue} 60% 62%)` }}
    >
      {initialsOf(user.nickname)}
    </span>
  );
}

function RoleBadge({ role }: { role: AdminUserDirectoryEntry["role"] }) {
  const color = role === "admin" ? "var(--primary)" : role === "athlete" ? "var(--success)" : "var(--muted)";
  return (
    <span className="inline-flex items-center gap-1 font-semibold uppercase tracking-[0.12em]" style={{ color }}>
      <span aria-hidden="true" className="h-1.5 w-1.5 rounded-full" style={{ background: color }} />
      <SemanticLabel value={role} />
    </span>
  );
}

function FinanceBadge({ status }: { status: string }) {
  const good = ["active", "paid", "current"].includes(status);
  const bad = ["overdue", "expired", "suspended", "cancelled", "canceled", "frozen"].includes(status);
  const color = good ? "var(--success)" : bad ? "var(--danger)" : "var(--warning)";
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-semibold" style={{ background: `color-mix(in srgb, ${color} 14%, transparent)`, color }}>
      <SemanticLabel value={status} />
    </span>
  );
}

function EmptyState({ title, body, action }: { title: string; body: string; action: ReactNode }) {
  return (
    <section className="rounded-[1.6rem] px-6 py-12 text-center" style={{ background: "var(--panel)", border: "1px dashed var(--border-strong, var(--border))" }}>
      <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{title}</h2>
      <p className="mx-auto mt-2 max-w-md text-sm leading-6" style={{ color: "var(--muted)" }}>{body}</p>
      <div className="mt-5 flex justify-center">{action}</div>
    </section>
  );
}

function SkeletonRows() {
  return (
    <div aria-hidden="true" className="space-y-2">
      {Array.from({ length: 6 }, (_, index) => (
        <div key={index} className="flex animate-pulse items-center gap-3 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <span className="h-10 w-10 rounded-full" style={{ background: "var(--panel-muted)" }} />
          <span className="h-3 w-40 rounded" style={{ background: "var(--panel-muted)" }} />
        </div>
      ))}
    </div>
  );
}
