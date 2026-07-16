"use client";






import {useUiTranslations} from "@/i18n/ui";
import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import { fetchAdminUsers } from "@/api/admin-users";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";
import { SemanticLabel } from "@/components/semantic-label";
import { localizeError } from "@/i18n/presentation";

export function AdminUsersDirectory() {
  const i18n = useUiTranslations();
  const FILTERS = [
    ["all", i18n("all6a72085")],
    ["member", i18n("members1cb449c")],
    ["athlete", i18n("athletesda22204")],
    ["admin", i18n("adminsed6b524")],
  ] as const;
  const { tokens } = useSession();
  const [role, setRole] = useState<(typeof FILTERS)[number][0]>("all");
  const [query, setQuery] = useState("");
  const token = tokens?.access_token;

  const usersQuery = useQuery({
    queryKey: ["admin", "users", role, query],
    enabled: Boolean(token),
    queryFn: () => fetchAdminUsers(token!, { q: query.trim() || undefined, role: role === "all" ? undefined : role }),
  });

  const users = usersQuery.data?.users ?? [];

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-6">
        <TransientHero collapsedTitle={i18n("users57f2b18")} label={i18n("usersDirectoryIntroduction17b72fb")} timeoutMs={3000}>
          <section className="rounded-[2.4rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{i18n("users57f2b18")}</p>
            <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
              {i18n("everyPersonOneDirectory0de5809")}
            </h1>
            <p className="mt-4 max-w-3xl text-base leading-7" style={{ color: "var(--muted)" }}>
              {i18n("findMembersAthletesAndAdminsThenOpenTheird68819b")}
            </p>
          </section>
        </TransientHero>

        <section className="rounded-[2rem] p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
            <div className="flex flex-wrap gap-2">
              {FILTERS.map(([value, label]) => (
                <button
                  key={value}
                  type="button"
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  onClick={() => setRole(value)}
                  style={role === value ? { background: "var(--text)", color: "var(--bg)" } : { background: "var(--panel-muted)", color: "var(--muted)" }}
                >
                  {label}
                </button>
              ))}
            </div>
            <input
              aria-label={i18n("searchUsers1bd6226")}
              className="min-w-64 rounded-full px-4 py-2.5 text-sm outline-none"
              placeholder={i18n("searchNickname30e8842")}
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
          </div>
        </section>

        <section className="grid gap-3">
          {usersQuery.isLoading ? <p className="p-5 text-sm" style={{ color: "var(--muted)" }}>{i18n("loadingUsersb6443c9")}</p> : null}
          {usersQuery.isError ? <p className="rounded-2xl p-5 text-sm" role="alert" style={{ background: "var(--panel)", color: "var(--danger)" }}>{localizeError(usersQuery.error, i18n)}</p> : null}
          {!usersQuery.isLoading && !usersQuery.isError && users.length === 0 ? <p className="rounded-2xl p-5 text-sm" style={{ background: "var(--panel)", color: "var(--muted)" }}>{i18n("noUsersMatchThisView93693f5")}</p> : null}
          {users.map((user) => (
            <Link
              key={user.id}
              href={`/admin/users/${user.id}`}
              className="grid items-center gap-3 rounded-[1.6rem] p-5 transition-transform hover:-translate-y-0.5 md:grid-cols-[1fr_auto_auto_auto]"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <div>
                <p className="font-semibold" style={{ color: "var(--text)" }}>{user.nickname}</p>
                <p className="mt-1 text-xs uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}><SemanticLabel value={user.role} /></p>
              </div>
              <span className="text-sm" style={{ color: "var(--muted)" }}><SemanticLabel value={user.account_status} /></span>
              <span className="text-sm" style={{ color: "var(--muted)" }}>{user.finance_status ? <SemanticLabel value={user.finance_status} /> : i18n("noFinanceProfilef804f44")}</span>
              <span className="text-sm font-semibold" style={{ color: "var(--primary)" }}>{i18n("open6f4789b")}</span>
            </Link>
          ))}
        </section>
      </div>
    </main>
  );
}
