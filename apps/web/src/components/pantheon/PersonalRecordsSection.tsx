"use client";

import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { deletePR, listPRs, type PRRecord } from "@/api/gamification";
import { ClientCard, EmptyLine, LoadingLine } from "@/components/client/ClientPage";
import { useSession } from "@/components/session-provider";
import { ShareExportDialog } from "@/components/share-export/ShareExportDialog";
import { useShareExport } from "@/components/share-export/useShareExport";
import { Dialog } from "@/components/ui/Dialog";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { buildPRListDocument } from "@/lib/document-export";
import { SPARK_CREATE_STYLE } from "@/lib/spark";

import { PantheonCard } from "./PantheonCard";
import { NewPRFormModal, PRFormModal } from "./PRFormModal";
import { PRShareFlow } from "./PRShareFlow";
import { PRShareModal } from "./PRShareModal";
import { SharedPRsSection } from "./SharedPRsSection";

const SHOWN = 6;
/** A search box only pays for itself once the list is long. */
const SEARCH_FROM = 9;

/**
 * Πρόοδος › «Personal Records» (ANR 2026-10-24): the one home of PRs, a
 * section of Πρόοδος and not a page of its own. Every PR is here: the first
 * six, then the rest in place; add, edit, share, delete and export without
 * leaving; PRs others share with me follow, only when there are some.
 */
export function PersonalRecordsSection() {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const shareExport = useShareExport();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [expanded, setExpanded] = useState(false);
  const [search, setSearch] = useState("");
  const [formPR, setFormPR] = useState<PRRecord | null | "new">(null);
  const [sharePR, setSharePR] = useState<PRRecord | null>(null);
  const [deletePr, setDeletePr] = useState<PRRecord | null>(null);
  const [exportOpen, setExportOpen] = useState(false);

  const prsQuery = useQuery({
    queryKey: ["prs"],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => listPRs(tokens!.access_token),
  });
  const remove = useMutation({
    mutationFn: (id: string) => deletePR(tokens!.access_token, id),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["prs"] });
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
      setDeletePr(null);
    },
  });

  const prs = useMemo(() => prsQuery.data ?? [], [prsQuery.data]);
  const needle = search.trim().toLocaleLowerCase(uiLocale);
  const matching = needle ? prs.filter((pr) => pr.name.toLocaleLowerCase(uiLocale).includes(needle)) : prs;
  const shown = expanded || needle ? matching : matching.slice(0, SHOWN);
  const hidden = matching.length - shown.length;

  return (
    <>
      <ClientCard
        id="prs"
        title={i18n("personalRecords4769a96")}
        aside={
          <button
            type="button"
            onClick={() => setFormPR("new")}
            className="min-h-9 rounded-full px-3 text-sm font-semibold"
            style={SPARK_CREATE_STYLE}
          >
            {i18n("addPr0a5ecff")}
          </button>
        }
      >
        {prsQuery.isPending ? (
          <LoadingLine />
        ) : prs.length === 0 ? (
          <EmptyLine>{i18n("noPersonalRecordsYetAddYourFirstOne84b071a")}</EmptyLine>
        ) : (
          <div className="flex flex-col gap-3">
            {prs.length >= SEARCH_FROM ? (
              <input
                type="search"
                className="min-h-11 w-full rounded-2xl px-4 text-sm outline-none"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                placeholder={i18n("searchPrscd652ea")}
                aria-label={i18n("searchPrscd652ea")}
                value={search}
                onChange={(event) => setSearch(event.target.value)}
              />
            ) : null}
            {shown.length === 0 ? <EmptyLine>{i18n("noPrsMatchYourSearchf6466a7")}</EmptyLine> : null}
            <div className="grid gap-3 sm:grid-cols-2">
              {shown.map((pr) => (
                <PantheonCard key={pr.id} pr={pr} compact onEdit={setFormPR} onShare={setSharePR} onDelete={setDeletePr} />
              ))}
            </div>
            <div className="flex flex-wrap items-center justify-between gap-2">
              {hidden > 0 ? (
                <button
                  type="button"
                  onClick={() => setExpanded(true)}
                  className="min-h-11 text-sm font-bold"
                  style={{ color: "var(--primary-strong, var(--primary))" }}
                >
                  {i18n("prsShowMore", { count: hidden })}
                </button>
              ) : <span />}
              <button
                type="button"
                onClick={() => setExportOpen(true)}
                className="min-h-11 text-sm font-semibold"
                style={{ color: "var(--text-soft)" }}
              >
                {i18n("exportAllPrs")}
              </button>
            </div>
          </div>
        )}
        <SharedPRsSection />
      </ClientCard>

      {formPR === "new" ? (
        <NewPRFormModal onClose={() => setFormPR(null)} />
      ) : formPR !== null ? (
        <PRShareFlow onClose={() => setFormPR(null)}>
          {(onSaved) => <PRFormModal pr={formPR} onClose={() => setFormPR(null)} onSaved={onSaved} />}
        </PRShareFlow>
      ) : null}
      {sharePR ? <PRShareModal pr={sharePR} onClose={() => setSharePR(null)} /> : null}
      {deletePr ? (
        <Dialog
          onClose={() => setDeletePr(null)}
          title={i18n("deletePr50a5f9b")}
          size="sm"
          variant="center"
          footer={
            <div className="flex w-full gap-3">
              <button
                type="button"
                disabled={remove.isPending}
                onClick={() => remove.mutate(deletePr.id)}
                className="min-h-11 flex-1 rounded-xl text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--danger, var(--primary))", color: "var(--danger-contrast)" }}
              >
                {remove.isPending ? i18n("deletingc7ac551") : i18n("deletef6fdbe4")}
              </button>
              <button
                type="button"
                onClick={() => setDeletePr(null)}
                className="min-h-11 flex-1 rounded-xl text-sm font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
              >
                {i18n("cancel77dfd21")}
              </button>
            </div>
          }
        >
          <p className="text-sm" style={{ color: "var(--muted)" }}>
            &quot;{deletePr.name}{i18n("willBePermanentlyRemovedIncludingItsHistory54afba1")}
          </p>
        </Dialog>
      ) : null}
      {exportOpen ? (
        <ShareExportDialog
          copy={shareExport.copy}
          document={buildPRListDocument(prs, shareExport.labels, uiLocale)}
          onClose={() => setExportOpen(false)}
        />
      ) : null}
    </>
  );
}
