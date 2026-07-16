"use client";




import {useUiTranslations} from "@/i18n/ui";
import { useMutation, useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import {
  fetchAthletes,
  fetchAthleteDrillDown,
  writeAthleteNote,
  type AthleteDrillDown,
} from "@/api/admin";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";

function asRecord(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
}

function asList(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}

function DrillDownPanel({ drillDown }: { drillDown: AthleteDrillDown }) {
  const i18n = useUiTranslations();
  const d = asRecord(drillDown);
  const assignments = asList(d.assignments);
  const executions = asList(d.executions);
  const notes = asList(d.notes);
  const attention = asRecord(d.attention);
  const scores = asRecord(d.scores);

  return (
    <div className="space-y-4">
      {/* Scores / streak row */}
      <div className="grid grid-cols-3 gap-3">
        {[
          [i18n("streakac4792c"), String(asRecord(scores).streak_weeks ?? "—")],
          [i18n("completions1edd778"), String(asRecord(scores).total_completions ?? "—")],
          [i18n("assignments057d58c"), String(assignments.length)],
        ].map(([label, value]) => (
          <div key={label} className="rounded-[1.2rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            <p className="text-[10px] font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</p>
            <p className="mt-1.5 text-2xl font-black" style={{ color: "var(--text)" }}>{value}</p>
          </div>
        ))}
      </div>

      {/* Attention flags */}
      {Object.keys(attention).length > 0 ? (
        <div className="rounded-[1.4rem] p-4 space-y-1" style={{ background: "color-mix(in srgb, var(--primary) 8%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)" }}>
          <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--primary)" }}>{i18n("attentionFlags86e76f6")}</p>
          {Object.entries(attention).map(([key, val]) => val ? (
            <p key={key} className="text-xs" style={{ color: "var(--primary-strong)" }}>
              {key.replace(/_/g, " ")}: {String(val)}
            </p>
          ) : null)}
        </div>
      ) : null}

      {/* Recent executions */}
      {executions.length > 0 ? (
        <div className="space-y-2">
          <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("recentExecutionsa05fd99")}{executions.length})
          </p>
          <div className="max-h-48 space-y-1.5 overflow-auto">
            {executions.slice(0, 8).map((ex, i) => {
              const e = asRecord(ex);
              return (
                <div key={i} className="flex items-center justify-between gap-3 rounded-[1rem] px-3 py-2" style={{ background: "var(--panel-muted)" }}>
                  <span className="text-xs font-semibold" style={{ color: "var(--text)" }}>
                    {String(e.workout_title || e.status || i18n("execution6d525b7"))}
                  </span>
                  <span className="text-[10px]" style={{ color: "var(--dim)" }}>
                    {String(e.completed_at_utc || e.started_at_utc || "").slice(0, 10)}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      ) : null}

      {/* Coach notes */}
      {notes.length > 0 ? (
        <div className="space-y-2">
          <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("notesd1b1569")}{notes.length})
          </p>
          <div className="max-h-40 space-y-1.5 overflow-auto">
            {notes.map((n, i) => {
              const note = asRecord(n);
              return (
                <div key={i} className="rounded-[1rem] px-3 py-2" style={{ background: "var(--panel-muted)" }}>
                  <p className="text-xs" style={{ color: "var(--text-soft)" }}>{String(note.body || "")}</p>
                  <p className="mt-0.5 text-[10px]" style={{ color: "var(--dim)" }}>
                    {String(note.inserted_at || "").slice(0, 10)}
                  </p>
                </div>
              );
            })}
          </div>
        </div>
      ) : null}
    </div>
  );
}

export function AdminCoaching() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const [selectedAthleteId, setSelectedAthleteId] = useState("");
  const [noteBody, setNoteBody] = useState("");
  const [showDrillDown, setShowDrillDown] = useState(false);

  const athletesQuery = useQuery({
    queryKey: ["admin", "athletes"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => {
      if (!tokens?.access_token) throw new Error(i18n("authenticationRequired9e44e0b"));
      return fetchAthletes(tokens.access_token);
    },
  });

  const drillDownQuery = useQuery({
    queryKey: ["admin", "athlete-drill-down", selectedAthleteId],
    enabled: Boolean(tokens?.access_token && selectedAthleteId && showDrillDown),
    queryFn: async () => {
      if (!tokens?.access_token) throw new Error(i18n("authenticationRequired9e44e0b"));
      return fetchAthleteDrillDown(tokens.access_token, selectedAthleteId);
    },
  });

  const writeNote = useMutation({
    mutationFn: async () => {
      if (!tokens?.access_token || !selectedAthleteId) throw new Error(i18n("athleteSelectionRequired7fd21d5"));
      return writeAthleteNote(tokens.access_token, selectedAthleteId, noteBody);
    },
    onSuccess: () => {
      setNoteBody("");
    },
  });

  const athletes = athletesQuery.data?.athletes ?? [];
  const selectedAthlete = athletes.find((a) => a.id === selectedAthleteId);

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-8">
        <TransientHero label={i18n("coachingWorkspaceIntroductionb33101c")} timeoutMs={3000}>
        <section className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.28em] text-[var(--primary)]">{i18n("adminCoaching44254ed")}</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight md:text-4xl" style={{ color: "var(--text)" }}>
            {i18n("athleteCoachingWorkspaceae374b0")}
          </h1>
          <p className="mt-2 max-w-3xl text-sm leading-6" style={{ color: "var(--muted)" }}>
            {i18n("selectAnAthleteToViewTheirDrillDownc3ad98f")}
          </p>
          <Link
            className="mt-6 inline-flex rounded-full px-4 py-2 text-sm font-semibold"
            href="/admin"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
          >
            {i18n("backToAdminHome941355d")}
          </Link>
        </section>
        </TransientHero>

        <div className="grid gap-6 lg:grid-cols-[1fr_1.5fr]">
          {/* Athlete list */}
          <section className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>
              {i18n("athletesadb6fcf")}{athletes.length})
            </p>
            <div className="mt-4 space-y-2">
              {athletesQuery.isPending ? (
                <p className="text-sm" style={{ color: "var(--muted)" }}>{i18n("loadingAthletesbdd5068")}</p>
              ) : athletes.length === 0 ? (
                <p className="text-sm" style={{ color: "var(--muted)" }}>{i18n("noAthletesRegisteredYet9b65780")}</p>
              ) : (
                athletes.map((athlete) => (
                  <button
                    key={athlete.id}
                    className="w-full rounded-2xl border px-4 py-3 text-left transition-colors"
                    style={{
                      background: selectedAthleteId === athlete.id ? "color-mix(in srgb, var(--primary) 8%, transparent)" : "transparent",
                      borderColor: selectedAthleteId === athlete.id ? "color-mix(in srgb, var(--primary) 28%, transparent)" : "var(--border)",
                    }}
                    onClick={() => {
                      setSelectedAthleteId(athlete.id);
                      setShowDrillDown(false);
                    }}
                    type="button"
                  >
                    <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{athlete.nickname}</p>
                    <p className="mt-0.5 text-xs uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
                      {athlete.role}
                    </p>
                  </button>
                ))
              )}
            </div>
          </section>

          {/* Right panel: drill-down + note form */}
          <div className="space-y-6">
            {selectedAthlete ? (
              <>
                {/* Drill-down toggle */}
                <section className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                  <div className="flex items-center justify-between gap-4">
                    <div>
                      <p className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
                        {selectedAthlete.nickname}
                      </p>
                      <h2 className="mt-1 text-xl font-semibold" style={{ color: "var(--text)" }}>{i18n("athleteDrillDown0f0a44f")}</h2>
                    </div>
                    <button
                      className="rounded-full px-4 py-2 text-xs font-semibold transition-colors"
                      style={{
                        background: showDrillDown ? "var(--border)" : "color-mix(in srgb, var(--primary) 12%, transparent)",
                        color: showDrillDown ? "var(--dim)" : "var(--primary)",
                        border: showDrillDown ? "1px solid var(--border)" : "1px solid color-mix(in srgb, var(--primary) 25%, transparent)",
                      }}
                      onClick={() => setShowDrillDown((v) => !v)}
                      type="button"
                    >
                      {showDrillDown ? i18n("hide34d8b60") : i18n("loadDrillDown13990a6")}
                    </button>
                  </div>

                  {showDrillDown ? (
                    <div className="mt-5">
                      {drillDownQuery.isPending ? (
                        <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
                      ) : drillDownQuery.error instanceof Error ? (
                        <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{drillDownQuery.error.message}</p>
                      ) : drillDownQuery.data?.drill_down ? (
                        <DrillDownPanel drillDown={drillDownQuery.data.drill_down} />
                      ) : null}
                    </div>
                  ) : null}
                </section>

                {/* Note form */}
                <section className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                  <p className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
                    {i18n("coachingNotes5c7da9f")}
                  </p>
                  <h2 className="mt-1 text-xl font-semibold" style={{ color: "var(--text)" }}>
                    {i18n("sendNoteTof1db90e")} {selectedAthlete.nickname}
                  </h2>

                  <div className="mt-4 space-y-3">
                    <textarea
                      className="min-h-24 w-full rounded-2xl border px-4 py-3 text-sm"
                      style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                      placeholder={i18n("writeACoachingNotebd3ca38")}
                      value={noteBody}
                      onChange={(e) => setNoteBody(e.target.value)}
                    />
                    <div className="flex flex-wrap items-center gap-3">
                      <button
                        type="button"
                        className="rounded-full px-5 py-2.5 text-sm font-semibold disabled:opacity-50"
                        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                        disabled={noteBody.trim().length === 0 || writeNote.isPending}
                        onClick={() => void writeNote.mutateAsync()}
                      >
                        {writeNote.isPending ? i18n("sendingcf76551") : i18n("sendNote0bab5df")}
                      </button>
                      {writeNote.isSuccess ? (
                        <p className="text-sm" style={{ color: "var(--success)" }}>{i18n("noteSaved5311c22")}</p>
                      ) : null}
                      {writeNote.isError ? (
                        <p className="text-sm" style={{ color: "var(--primary)" }}>
                          {writeNote.error instanceof Error ? writeNote.error.message : i18n("unableToSaveNote8506e1a")}
                        </p>
                      ) : null}
                    </div>
                  </div>
                </section>
              </>
            ) : (
              <div className="flex items-center justify-center rounded-[2rem] p-12" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("selectAnAthleteToBegin2722ba1")}</p>
              </div>
            )}
          </div>
        </div>
      </div>
    </main>
  );
}
