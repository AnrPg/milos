"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchFinancePackages } from "@/api/finance";
import { listAdminClassTypes } from "@/api/schedule";
import { fetchTrialPolicy, TRIAL_POLICY_KEY, updateTrialPolicy, type TrialPolicy } from "@/api/trials";
import { useSession } from "@/components/session-provider";
import { trialErrorKey } from "@/components/trials/trial-ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { Select } from "@/components/ui/Select";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { BackLink } from "@/components/ui/BackLink";

type Draft = {
  enabled: boolean;
  approval: "auto" | "manual";
  weekly_limit: number | null;
  per_person_limit: number;
  seats_per_class: number;
  class_type_ids: string[];
  horizon_days: number | null;
  first_timers_only: boolean;
  no_show_consumes: boolean;
  bring_note: string | null;
  conversion_package_id: string | null;
};

const DEFAULTS: Draft = {
  enabled: false,
  approval: "auto",
  weekly_limit: null,
  per_person_limit: 1,
  seats_per_class: 2,
  class_type_ids: [],
  horizon_days: null,
  first_timers_only: false,
  no_show_consumes: false,
  bring_note: null,
  conversion_package_id: null,
};

/**
 * The owner's trial rules (board 6 Q3): off until turned on; approval,
 * limits, which class types, how far ahead, who may come, «Τι να φέρεις»
 * and the package offered to people who want to join. The week's count
 * shows what the limits mean in practice.
 */
export function TrialSettings() {
  const t = useTranslations("Trials");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const policy = useQuery({ queryKey: TRIAL_POLICY_KEY, enabled: Boolean(token), queryFn: () => fetchTrialPolicy(token) });
  if (policy.isPending) return <p className="p-6 text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (policy.isError) return <div className="p-6"><ErrorNotice>{t(trialErrorKey(policy.error))}</ErrorNotice></div>;
  return <Form token={token} initial={{ ...DEFAULTS, ...stripNulls(policy.data.policy) }} thisWeek={policy.data.this_week} />;
}

function stripNulls(policy: TrialPolicy): Partial<Draft> {
  return Object.fromEntries(Object.entries(policy).filter(([, value]) => value !== undefined)) as Partial<Draft>;
}

function Form({ token, initial, thisWeek }: { token: string; initial: Draft; thisWeek: number }) {
  const t = useTranslations("Trials");
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<Draft>(initial);
  const [saved, setSaved] = useState(false);
  const set = <K extends keyof Draft>(key: K, value: Draft[K]) => {
    setSaved(false);
    setDraft((current) => ({ ...current, [key]: value }));
  };

  const classTypes = useQuery({ queryKey: ["admin", "class-types"], queryFn: () => listAdminClassTypes(token) });
  const packages = useQuery({ queryKey: ["admin", "finance", "packages"], queryFn: () => fetchFinancePackages(token) });
  const activeTypes = (classTypes.data ?? []).filter((type) => !type.archived_at);
  const activePackages = (packages.data?.packages ?? []).filter((pkg) => pkg.active !== false) as Array<{ id: string; name: string }>;

  const save = useMutation({
    mutationFn: () => updateTrialPolicy(token, { ...draft, bring_note: draft.bring_note?.trim() || null } as TrialPolicy),
    onSuccess: (data) => {
      queryClient.setQueryData(TRIAL_POLICY_KEY, data);
      setSaved(true);
    },
  });

  const input = "min-h-11 w-24 rounded-2xl px-3 text-sm";
  const field = { background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" };
  const disabled = !draft.enabled;

  return (
    <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
      <form
        className="mx-auto flex max-w-2xl flex-col gap-5 pb-36"
        onSubmit={(event) => {
          event.preventDefault();
          save.mutate();
        }}
      >
        <header className="flex flex-col gap-1">
          <BackLink href={adminHref("/admin/trials", slug)} className="text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>{t("queueTitle")}</BackLink>
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("settingsTitle")}</h1>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("settingsIntro")}</p>
        </header>

        <Toggle label={t("enabledLabel")} hint={t("enabledHint")} checked={draft.enabled} onChange={(value) => set("enabled", value)} />

        <fieldset disabled={disabled} className="flex flex-col gap-5 disabled:opacity-55">
          <Section title={t("approvalTitle")}>
            {(["auto", "manual"] as const).map((value) => (
              <label key={value} className="flex items-start gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: `1px solid ${draft.approval === value ? "var(--primary)" : "var(--border)"}` }}>
                <input type="radio" name="approval" checked={draft.approval === value} onChange={() => set("approval", value)} className="mt-1" />
                <span className="flex flex-col">
                  <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t(`approval_${value}`)}</span>
                  <span className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`approvalHint_${value}`)}</span>
                </span>
              </label>
            ))}
          </Section>

          <Section title={t("limitsTitle")}>
            <NumberRow label={t("seatsPerClass")} value={draft.seats_per_class} min={1} max={50} onChange={(value) => set("seats_per_class", value ?? 1)} className={input} style={field} />
            <NumberRow label={t("weeklyLimit")} hint={t("weeklyLimitHint", { count: thisWeek })} value={draft.weekly_limit} min={1} max={500} onChange={(value) => set("weekly_limit", value)} className={input} style={field} />
            <NumberRow label={t("perPersonLimit")} value={draft.per_person_limit} min={1} max={10} onChange={(value) => set("per_person_limit", value ?? 1)} className={input} style={field} />
            <NumberRow label={t("horizonDays")} hint={t("horizonHint")} value={draft.horizon_days} min={1} max={90} onChange={(value) => set("horizon_days", value)} className={input} style={field} />
          </Section>

          <Section title={t("classTypesTitle")} hint={t("classTypesHint")}>
            <div className="flex flex-wrap gap-2">
              {activeTypes.map((type) => {
                const on = (draft.class_type_ids ?? []).includes(type.id);
                return (
                  <button
                    key={type.id}
                    type="button"
                    aria-pressed={on}
                    onClick={() =>
                      set("class_type_ids", on ? (draft.class_type_ids ?? []).filter((id) => id !== type.id) : [...(draft.class_type_ids ?? []), type.id])
                    }
                    className="min-h-10 rounded-full px-4 text-sm font-semibold"
                    style={on ? { background: "var(--text)", color: "var(--bg)" } : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                  >
                    {type.name}
                  </button>
                );
              })}
            </div>
          </Section>

          <Section title={t("whoTitle")}>
            <Toggle label={t("firstTimersOnly")} hint={t("firstTimersHint")} checked={draft.first_timers_only} onChange={(value) => set("first_timers_only", value)} />
            <Toggle label={t("noShowConsumes")} hint={t("noShowHint")} checked={draft.no_show_consumes} onChange={(value) => set("no_show_consumes", value)} />
          </Section>

          <Section title={t("bringTitle")} hint={t("bringHint")}>
            <textarea
              value={draft.bring_note ?? ""}
              maxLength={600}
              rows={4}
              onChange={(event) => set("bring_note", event.target.value)}
              placeholder={t("bringPlaceholder")}
              className="rounded-2xl px-3.5 py-2.5 text-sm"
              style={field}
            />
          </Section>

          <Section title={t("conversionTitle")} hint={t("conversionHint")}>
            <Select
              value={draft.conversion_package_id ?? ""}
              onValueChange={(value) => set("conversion_package_id", value || null)}
              className="min-h-11 rounded-2xl px-3 text-sm"
              style={field}
            >
              <option value="">{t("conversionNone")}</option>
              {activePackages.map((pkg) => (
                <option key={pkg.id} value={pkg.id}>{pkg.name}</option>
              ))}
            </Select>
          </Section>
        </fieldset>

        <div className="sticky bottom-4 flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          {save.isError ? <ErrorNotice>{t(trialErrorKey(save.error))}</ErrorNotice> : null}
          {saved ? <p role="status" className="text-sm" style={{ color: "var(--success)" }}>{t("saved")}</p> : null}
          <button type="submit" disabled={save.isPending} className="min-h-12 rounded-2xl text-sm font-bold disabled:opacity-60" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {save.isPending ? t("saving") : t("save")}
          </button>
        </div>
      </form>
    </main>
  );
}

function Section({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-2">
      <h2 className="text-sm font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{title}</h2>
      {hint ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{hint}</p> : null}
      {children}
    </section>
  );
}

function Toggle({ label, hint, checked, onChange }: { label: string; hint?: string; checked: boolean; onChange: (value: boolean) => void }) {
  return (
    <label className="flex items-start justify-between gap-4 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <span className="flex flex-col">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{label}</span>
        {hint ? <span className="text-sm" style={{ color: "var(--text-soft)" }}>{hint}</span> : null}
      </span>
      <input type="checkbox" role="switch" checked={checked} onChange={(event) => onChange(event.target.checked)} className="mt-1 h-5 w-5 shrink-0" />
    </label>
  );
}

function NumberRow({
  label,
  hint,
  value,
  min,
  max,
  onChange,
  className,
  style,
}: {
  label: string;
  hint?: string;
  value: number | null;
  min: number;
  max: number;
  onChange: (value: number | null) => void;
  className: string;
  style: React.CSSProperties;
}) {
  return (
    <label className="flex items-center justify-between gap-4 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <span className="flex flex-col">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{label}</span>
        {hint ? <span className="text-sm" style={{ color: "var(--text-soft)" }}>{hint}</span> : null}
      </span>
      <input
        type="number"
        inputMode="numeric"
        min={min}
        max={max}
        value={value ?? ""}
        onChange={(event) => onChange(event.target.value.trim() === "" ? null : Math.min(max, Math.max(min, Math.floor(Number(event.target.value)))))}
        className={className}
        style={style}
      />
    </label>
  );
}
