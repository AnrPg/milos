"use client";

import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";

import { fetchMyInjuries, markMyInjuryHealed, reportInjury } from "@/api/wellbeing";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";

export function MyWellbeing() {
  const { tokens } = useSession();
  const [bodyArea, setBodyArea] = useState("");
  const [severity, setSeverity] = useState("mild");
  const [limitations, setLimitations] = useState("");

  const injuriesQuery = useQuery({
    queryKey: ["my", "wellbeing", "injuries"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchMyInjuries(tokens!.access_token),
  });

  const reportMutation = useMutation({
    mutationFn: async () =>
      reportInjury(tokens!.access_token, {
        body_area: bodyArea,
        severity,
        training_limitations: limitations,
      }),
    onSuccess: () => {
      setBodyArea("");
      setLimitations("");
      injuriesQuery.refetch();
    },
  });

  const healMutation = useMutation({
    mutationFn: async (id: string) => markMyInjuryHealed(tokens!.access_token, id),
    onSuccess: () => injuriesQuery.refetch(),
  });

  return (
    <main className="min-h-screen bg-[var(--bg)] px-6 py-10 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-4xl space-y-6">
        <TransientHero label="wellbeing introduction">
        <section className="rounded-[2rem] border border-[var(--border)] bg-[var(--panel)] p-5">
          <p className="text-xs font-bold uppercase tracking-[0.24em] text-[var(--primary)]">My wellbeing</p>
          <h1 className="mt-2 text-3xl font-black">Report injuries and mark healing.</h1>
        </section>
        </TransientHero>

        <form
          className="space-y-4 rounded-[1.6rem] border border-[var(--border)] bg-[var(--panel)] p-6"
          onSubmit={(event) => {
            event.preventDefault();
            reportMutation.mutate();
          }}
        >
          <input
            className="w-full rounded-2xl border px-4 py-3"
            placeholder="Body area, e.g. shoulder"
            required
            value={bodyArea}
            onChange={(event) => setBodyArea(event.target.value)}
          />
          <select className="w-full rounded-2xl border px-4 py-3" value={severity} onChange={(event) => setSeverity(event.target.value)}>
            <option value="mild">Mild</option>
            <option value="moderate">Moderate</option>
            <option value="severe">Severe</option>
          </select>
          <textarea
            className="min-h-28 w-full rounded-2xl border px-4 py-3"
            placeholder="Training limitations or notes..."
            value={limitations}
            onChange={(event) => setLimitations(event.target.value)}
          />
          <button className="rounded-full bg-[var(--text)] px-5 py-3 text-sm font-bold text-[var(--primary-contrast)]" type="submit">
            {reportMutation.isPending ? "Reporting..." : "Report injury"}
          </button>
          <ErrorText error={reportMutation.error} />
        </form>

        <section className="grid gap-3">
          {(injuriesQuery.data?.injuries ?? []).map((injury) => (
            <article key={String(injury.id)} className="rounded-2xl border border-[var(--border)] bg-[var(--panel)] p-5">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="font-bold">
                    {String(injury.body_area)} · {String(injury.severity)}
                  </p>
                  <p className="text-sm text-[var(--muted)]">Status {String(injury.status)}</p>
                </div>
                {injury.status === "active" ? (
                  <button
                    className="rounded-full bg-[var(--primary)] px-4 py-2 text-sm font-bold text-[var(--primary-contrast)]"
                    type="button"
                    onClick={() => healMutation.mutate(String(injury.id))}
                  >
                    Mark healed
                  </button>
                ) : null}
              </div>
            </article>
          ))}
          <ErrorText error={healMutation.error} />
        </section>
      </div>
    </main>
  );
}

function ErrorText({ error }: { error: unknown }) {
  if (!(error instanceof Error)) return null;
  return <p className="text-sm font-semibold text-[var(--danger)]">{error.message}</p>;
}
