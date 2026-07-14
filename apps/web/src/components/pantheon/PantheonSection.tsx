"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { listPRs, type PRRecord } from "@/api/gamification";
import { useSession } from "@/components/session-provider";
import { PantheonCard } from "./PantheonCard";
import { PRFormModal } from "./PRFormModal";
import { PRShareModal } from "./PRShareModal";

export function PantheonSection() {
  const { tokens } = useSession();
  const [showForm, setShowForm] = useState(false);
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
            <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>Hall of Fame</p>
            <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>Personal Records</h2>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => setShowForm(true)}
              className="rounded-full w-8 h-8 flex items-center justify-center text-lg font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              title="Add PR"
            >
              +
            </button>
            <Link
              href="/my-workouts/pantheon"
              className="rounded-2xl px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
            >
              View all
            </Link>
          </div>
        </div>

        <div className="mt-5">
          {prsQuery.isPending ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>Loading…</p>
          ) : topPRs.length === 0 ? (
            <div className="rounded-2xl px-4 py-5" style={{ background: "var(--panel-muted)" }}>
              <p className="text-sm" style={{ color: "var(--dim)" }}>
                Track your personal records here. Hit{" "}
                <button type="button" onClick={() => setShowForm(true)} className="font-semibold underline" style={{ color: "var(--primary)" }}>
                  + Add PR
                </button>{" "}
                to log your first one.
              </p>
            </div>
          ) : (
            <div className="flex flex-col gap-3">
              {topPRs.map((pr) => (
                <PantheonCard key={pr.id} pr={pr} compact onShare={(p) => setSharePR(p)} />
              ))}
            </div>
          )}
        </div>
      </section>

      {showForm && <PRFormModal onClose={() => setShowForm(false)} />}
      {sharePR && <PRShareModal pr={sharePR} onClose={() => setSharePR(null)} />}
    </>
  );
}
