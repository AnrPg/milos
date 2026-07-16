"use client";



import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { listPRs, type PRRecord } from "@/api/gamification";
import { useSession } from "@/components/session-provider";
import { PantheonCard } from "./PantheonCard";
import { PRFormModal } from "./PRFormModal";
import { PRShareModal } from "./PRShareModal";

export function PantheonSection() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const [formPR, setFormPR] = useState<PRRecord | null | "new">(null);
  const [sharePR, setSharePR] = useState<PRRecord | null>(null);

  const prsQuery = useQuery({
    queryKey: ["prs"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => listPRs(tokens!.access_token),
  });

  const topPRs = (prsQuery.data ?? []).slice(0, 6);

  return (
    <>
      <section className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <div className="flex items-center justify-between gap-4">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{i18n("hallOfFamee10f949")}</p>
            <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{i18n("personalRecords4769a96")}</h2>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => setFormPR("new")}
              className="rounded-full w-8 h-8 flex items-center justify-center text-lg font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              title={i18n("addPr24c8c6f")}
            >
              +
            </button>
            <Link
              href="/my-workouts/pantheon"
              className="rounded-2xl px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
            >
              {i18n("viewAll931e1a4")}
            </Link>
          </div>
        </div>

        <div className="mt-5">
          {prsQuery.isPending ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
          ) : topPRs.length === 0 ? (
            <div className="rounded-2xl px-4 py-5" style={{ background: "var(--panel-muted)" }}>
              <p className="text-sm" style={{ color: "var(--dim)" }}>
                {i18n("trackYourPersonalRecordsHereHit7333a2f")}{" "}
                <button type="button" onClick={() => setFormPR("new")} className="font-semibold underline" style={{ color: "var(--primary)" }}>
                  {i18n("addPr0a5ecff")}
                </button>{" "}
                {i18n("toLogYourFirstOne2361efa")}
              </p>
            </div>
          ) : (
            <div className="flex flex-col gap-3">
              {topPRs.map((pr) => (
                <PantheonCard
                  key={pr.id}
                  pr={pr}
                  compact
                  onEdit={(record) => setFormPR(record)}
                  onShare={(record) => setSharePR(record)}
                />
              ))}
            </div>
          )}
        </div>
      </section>

      {formPR !== null && (
        <PRFormModal
          pr={formPR === "new" ? null : formPR}
          onClose={() => setFormPR(null)}
        />
      )}
      {sharePR && <PRShareModal pr={sharePR} onClose={() => setSharePR(null)} />}
    </>
  );
}
