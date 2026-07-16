"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { adminMarkInjuryHealed, adminReportInjury, fetchAdminInjuries } from "@/api/wellbeing";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";

export function AdminWellbeing() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [offset, setOffset] = useState(0);
  const pageSize = 25;
  const [form, setForm] = useState({
    user_id: "",
    body_area: "knee",
    severity: "mild",
    started_on: "",
    description: "",
    training_limitations: "",
    visibility: "user_and_admin",
  });

  const injuriesQuery = useQuery({
    queryKey: ["admin", "wellbeing", "injuries", offset],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () =>
      fetchAdminInjuries(tokens!.access_token, { limit: String(pageSize), offset: String(offset) }),
  });

  const injuries = injuriesQuery.data?.injuries ?? [];
  const refreshInjuries = () => queryClient.invalidateQueries({ queryKey: ["admin", "wellbeing", "injuries"] });

  const reportMutation = useMutation({
    mutationFn: async () => {
      if (!tokens?.access_token || !form.user_id.trim()) return null;

      return adminReportInjury(tokens.access_token, form.user_id.trim(), {
        body_area: form.body_area,
        severity: form.severity,
        started_on: form.started_on || undefined,
        description: form.description || undefined,
        training_limitations: form.training_limitations || undefined,
        visibility: form.visibility,
      });
    },
    onSuccess: () => {
      setForm((current) => ({
        ...current,
        body_area: "knee",
        severity: "mild",
        started_on: "",
        description: "",
        training_limitations: "",
        visibility: "user_and_admin",
      }));
      void refreshInjuries();
    },
  });

  const healMutation = useMutation({
    mutationFn: async (injuryId: string) => {
      if (!tokens?.access_token) return null;
      return adminMarkInjuryHealed(tokens.access_token, injuryId);
    },
    onSuccess: () => {
      void refreshInjuries();
    },
  });

  return (
    <main className="min-h-screen bg-[var(--bg)] px-6 py-10 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-5xl space-y-6">
        <TransientHero label={i18n("wellbeingAdministrationIntroductionf721cc4")} timeoutMs={3000}>
        <section className="rounded-[2rem] border border-[color:var(--border)] bg-[var(--panel)] p-5">
          <p className="text-xs font-bold uppercase tracking-[0.24em] text-[var(--primary)]">{i18n("wellbeingAdminef7f328")}</p>
          <h1 className="mt-2 text-3xl font-black">{i18n("injuryAndLimitationHistory76a0775")}</h1>
          <p className="mt-3 text-sm leading-6 text-[var(--muted)]">
            {i18n("staffCanSeeInjuryStatusBodyAreaTags5ea970b")}
          </p>
        </section>
        </TransientHero>

        <section className="rounded-[2rem] border border-[color:var(--border)] bg-[var(--panel)] p-6">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)]">{i18n("reportInjuryea0dc21")}</p>
              <h2 className="mt-2 text-2xl font-black">{i18n("createAStaffManagedReport8d86448")}</h2>
            </div>
          </div>
          <form
            className="mt-5 grid gap-3 md:grid-cols-2"
            onSubmit={(event) => {
              event.preventDefault();
              reportMutation.mutate();
            }}
          >
            <Field
              label={i18n("memberAthleteUserIde2ce583")}
              value={form.user_id}
              onChange={(user_id) => setForm({ ...form, user_id })}
              required
            />
            <Field
              label={i18n("bodyAreaa785bb3")}
              value={form.body_area}
              onChange={(body_area) => setForm({ ...form, body_area })}
              required
            />
            <SelectField
              label={i18n("severityde314fa")}
              value={form.severity}
              options={["mild", "moderate", "severe"]}
              onChange={(severity) => setForm({ ...form, severity })}
            />
            <SelectField
              label={i18n("visibility7d9ff4f")}
              value={form.visibility}
              options={["user_and_admin", "admin_only"]}
              onChange={(visibility) => setForm({ ...form, visibility })}
            />
            <Field
              label={i18n("startedOn9bbd73f")}
              type="date"
              value={form.started_on}
              onChange={(started_on) => setForm({ ...form, started_on })}
            />
            <Field
              label={i18n("description55f8ebc")}
              value={form.description}
              onChange={(description) => setForm({ ...form, description })}
            />
            <label className="md:col-span-2">
              <span className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--muted)]">
                {i18n("trainingLimitationsec788e9")}
              </span>
              <textarea
                className="mt-2 min-h-24 w-full rounded-2xl border border-[color:var(--border)] bg-[var(--panel-muted)] px-4 py-3 text-sm outline-none"
                value={form.training_limitations}
                onChange={(event) => setForm({ ...form, training_limitations: event.target.value })}
              />
            </label>
            <div className="md:col-span-2">
              <button
                className="rounded-full bg-[var(--primary)] px-5 py-3 text-sm font-bold text-[var(--primary-contrast)] disabled:opacity-50"
                disabled={reportMutation.isPending || !form.user_id.trim()}
                type="submit"
              >
                {reportMutation.isPending ? i18n("savingae7e887") : i18n("saveInjuryReport0a1caa0")}
              </button>
              {reportMutation.error ? (
                <p className="mt-3 text-sm font-semibold text-[var(--danger)]">{i18n("couldNotSaveInjuryReport5ec35fc")}</p>
              ) : null}
            </div>
          </form>
        </section>

        <section className="grid gap-4">
          {injuries.length === 0 ? <p className="rounded-2xl bg-[var(--panel)] p-5 text-sm">{i18n("noInjuryReportsYet11437b3")}</p> : null}
          {injuries.map((injury) => (
            <article key={String(injury.id)} className="rounded-[1.5rem] border border-[color:var(--border)] bg-[var(--panel)] p-5">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="font-bold">
                    {String(injury.body_area)} · {String(injury.severity)}
                  </p>
                  <p className="text-sm text-[var(--muted)]">
                    {i18n("statusbae7d5b")} {String(injury.status)} {i18n("userefbb4ac")} {String(injury.user_id)} · {String(injury.visibility)}
                  </p>
                </div>
                {injury.status === "active" ? (
                  <button
                    className="rounded-full border border-[color:var(--border)] px-4 py-2 text-xs font-bold text-[var(--primary)] disabled:opacity-50"
                    disabled={healMutation.isPending}
                    onClick={() => healMutation.mutate(String(injury.id))}
                    type="button"
                  >
                    {i18n("markHealed65e6ef9")}
                  </button>
                ) : null}
              </div>
              {injury.training_limitations ? (
                <p className="mt-3 text-sm leading-6">{String(injury.training_limitations)}</p>
              ) : null}
            </article>
          ))}
        </section>
        <div className="flex items-center justify-between">
          <button
            className="rounded-full border border-[color:var(--border)] px-4 py-2 text-sm font-bold text-[var(--primary)] disabled:opacity-40"
            disabled={offset === 0}
            type="button"
            onClick={() => setOffset(Math.max(offset - pageSize, 0))}
          >
            {i18n("previous50f9428")}
          </button>
          <button
            className="rounded-full border border-[color:var(--border)] px-4 py-2 text-sm font-bold text-[var(--primary)] disabled:opacity-40"
            disabled={injuries.length < pageSize}
            type="button"
            onClick={() => setOffset(offset + pageSize)}
          >
            {i18n("nextbc98198")}
          </button>
        </div>
      </div>
    </main>
  );
}

function Field({
  label,
  value,
  onChange,
  required = false,
  type = "text",
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  type?: string;
}) {
  
  return (
    <label>
      <span className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--muted)]">{label}</span>
      <input
        className="mt-2 w-full rounded-2xl border border-[color:var(--border)] bg-[var(--panel-muted)] px-4 py-3 text-sm outline-none"
        required={required}
        type={type}
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </label>
  );
}

function SelectField({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: string[];
  onChange: (value: string) => void;
}) {
  return (
    <label>
      <span className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--muted)]">{label}</span>
      <select
        className="mt-2 w-full rounded-2xl border border-[color:var(--border)] bg-[var(--panel-muted)] px-4 py-3 text-sm outline-none"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        {options.map((option) => (
          <option key={option} value={option}>
            {option.replace(/_/g, " ")}
          </option>
        ))}
      </select>
    </label>
  );
}
