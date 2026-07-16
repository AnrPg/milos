"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { listPRs, deletePR, type PRRecord } from "@/api/gamification";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";
import { PantheonCard } from "./PantheonCard";
import { PRFormModal } from "./PRFormModal";
import { PRShareModal } from "./PRShareModal";

export function PantheonPage() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();

  const [search, setSearch] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [searchTimer, setSearchTimer] = useState<ReturnType<typeof setTimeout> | null>(null);

  const [formPR, setFormPR] = useState<PRRecord | null | "new">(null);
  const [sharePR, setSharePR] = useState<PRRecord | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<PRRecord | null>(null);

  function handleSearchChange(q: string) {
    setSearch(q);
    if (searchTimer) clearTimeout(searchTimer);
    setSearchTimer(setTimeout(() => setDebouncedSearch(q), 300));
  }

  const prsQuery = useQuery({
    queryKey: ["prs", debouncedSearch],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => listPRs(tokens!.access_token, debouncedSearch || undefined),
  });

  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      if (!tokens) throw new Error(i18n("notAuthenticated0c91acb"));
      return deletePR(tokens.access_token, id);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["prs"] });
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
      setDeleteConfirm(null);
    },
  });

  const prs = prsQuery.data ?? [];

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-4xl space-y-8">
        {/* Header */}
        <div className="flex items-end justify-between gap-4 flex-wrap">
          <TransientHero label={i18n("personalRecordsIntroduction54be35f")}>
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>
              {i18n("hallOfFamee10f949")}
            </p>
            <h1 className="mt-1 text-3xl font-black" style={{ color: "var(--text)" }}>
              {i18n("personalRecords4769a96")}
            </h1>
          </div>
          </TransientHero>
          <button
            type="button"
            onClick={() => setFormPR("new")}
            className="rounded-2xl px-5 py-3 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {i18n("newPrbfecbc9")}
          </button>
        </div>

        {/* Search */}
        <input
          className="w-full rounded-2xl px-5 py-3 text-sm outline-none"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          placeholder={i18n("searchPrscd652ea")}
          value={search}
          onChange={(e) => handleSearchChange(e.target.value)}
        />

        {/* PR list */}
        {prsQuery.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
        ) : prs.length === 0 ? (
          <div className="rounded-[2rem] px-6 py-10 text-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <p className="text-sm" style={{ color: "var(--dim)" }}>
              {debouncedSearch ? i18n("noPrsMatchYourSearchf6466a7") : i18n("noPersonalRecordsYetAddYourFirstOne84b071a")}
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {prs.map((pr) => (
              <PantheonCard
                key={pr.id}
                pr={pr}
                onEdit={(p) => setFormPR(p)}
                onDelete={(p) => setDeleteConfirm(p)}
                onShare={(p) => setSharePR(p)}
              />
            ))}
          </div>
        )}
      </div>

      {/* Delete confirmation */}
      {deleteConfirm && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: "rgba(0,0,0,0.5)" }}
          onClick={(e) => { if (e.target === e.currentTarget) setDeleteConfirm(null); }}
        >
          <div className="w-full max-w-sm rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <h3 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{i18n("deletePr50a5f9b")}</h3>
            <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
              &quot;{deleteConfirm.name}{i18n("willBePermanentlyRemovedIncludingItsHistory54afba1")}
            </p>
            <div className="mt-5 flex gap-3">
              <button
                type="button"
                disabled={deleteMutation.isPending}
                onClick={() => deleteMutation.mutate(deleteConfirm.id)}
                className="flex-1 rounded-xl py-2.5 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--danger, var(--primary))", color: "#fff" }}
              >
                {deleteMutation.isPending ? i18n("deletingc7ac551") : i18n("deletef6fdbe4")}
              </button>
              <button
                type="button"
                onClick={() => setDeleteConfirm(null)}
                className="flex-1 rounded-xl py-2.5 text-sm font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
              >
                {i18n("cancel77dfd21")}
              </button>
            </div>
          </div>
        </div>
      )}

      {formPR !== null && (
        <PRFormModal pr={formPR === "new" ? null : formPR} onClose={() => setFormPR(null)} />
      )}

      {sharePR && (
        <PRShareModal pr={sharePR} onClose={() => setSharePR(null)} />
      )}
    </main>
  );
}
