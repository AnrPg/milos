"use client";

import Link from "next/link";
import { useMemo, useState, type FormEvent } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { listPlatformOrganizations } from "@/api/platform-organizations";
import {
  PLATFORM_PLANS_KEY,
  PLATFORM_SUBSCRIPTIONS_KEY,
  assignPlatformPlan,
  createPlatformPlan,
  fetchPlatformPlans,
  fetchPlatformSubscriptions,
  updatePlatformPlan,
  type OrganizationSubscription,
  type PlanInput,
  type PlatformPlan,
  type SubscriptionStatus,
} from "@/api/platform-plans";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { Select } from "@/components/ui/Select";
import { DateInput } from "@/components/ui/DateInput";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const STATUSES: SubscriptionStatus[] = ["trialing", "active", "past_due", "cancelled", "comped"];
const inputClass = "min-h-10 w-full border-[1px] border-[var(--border)] bg-[var(--panel)] px-3 text-sm text-[var(--text)]";

/**
 * Platform console › Πλάνα (ADR-170): the catalog (names, limits, prices,
 * trials; a price stays «placeholder» until confirmed here) and the plan
 * every organization is on.
 */
export function PlatformPlansPage() {
  const t = useTranslations("SoloCoach");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const plans = useQuery({ queryKey: PLATFORM_PLANS_KEY, enabled: Boolean(token), queryFn: () => fetchPlatformPlans(token!) });
  const forbidden = plans.error instanceof ApiError && plans.error.status === 403;

  return (
    <main className="mx-auto w-full max-w-5xl px-4 py-8 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <Link href="/platform/organizations" className="text-sm text-[var(--text-soft)]">‹ {t("console.back")}</Link>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("console.title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("console.subtitle")}</p>
      </header>
      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("console.forbidden")}</p> : null}
      {token && plans.data ? (
        <>
          <section className="mt-6 flex flex-col gap-4" aria-label={t("console.plans")}>
            <h2 className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("console.plans")}</h2>
            {plans.data.plans.map((plan) => (
              <PlanEditor key={plan.code} token={token} plan={plan} />
            ))}
            <NewPlanForm token={token} />
          </section>
          <Subscriptions token={token} plans={plans.data.plans} />
        </>
      ) : null}
    </main>
  );
}

function centsToInput(cents: number | null | undefined) {
  return cents == null ? "" : (cents / 100).toFixed(2);
}

function inputToCents(value: string): number | null {
  const trimmed = value.trim().replace(",", ".");
  if (!trimmed) return null;
  const parsed = Math.round(Number(trimmed) * 100);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

/** A `<input type="date">` value as the end of that day, UTC. */
function endOfDayIso(date: string) {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day, 23, 59, 59)).toISOString();
}

function inputToLimit(value: string): number | null {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed >= 1 ? parsed : null;
}

function PlanEditor({ token, plan }: { token: string; plan: PlatformPlan }) {
  const t = useTranslations("SoloCoach");
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [form, setForm] = useState(() => ({
    name: plan.name,
    monthly: centsToInput(plan.monthly_price_cents),
    annual: centsToInput(plan.annual_price_cents),
    confirmed: plan.price_status === "confirmed",
    trialDays: String(plan.trial_days),
    staffSeats: plan.limits.staff_seats ? String(plan.limits.staff_seats) : "",
    activeClients: plan.limits.active_clients ? String(plan.limits.active_clients) : "",
    isDefault: plan.is_default,
    isPublic: plan.public,
    active: plan.active,
  }));
  const save = useMutation({
    mutationFn: () => {
      const limits: PlanInput["limits"] = {};
      const staff = inputToLimit(form.staffSeats);
      const clients = inputToLimit(form.activeClients);
      if (staff) limits.staff_seats = staff;
      if (clients) limits.active_clients = clients;
      return updatePlatformPlan(token, plan.code, {
        name: form.name,
        monthly_price_cents: inputToCents(form.monthly),
        annual_price_cents: inputToCents(form.annual),
        price_status: form.confirmed ? "confirmed" : "placeholder",
        trial_days: Number.parseInt(form.trialDays, 10) || 0,
        limits,
        is_default: form.isDefault,
        public: form.isPublic,
        active: form.active,
      });
    },
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: PLATFORM_PLANS_KEY }),
  });
  const set = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) => setForm((current) => ({ ...current, [key]: value }));

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        save.mutate();
      }}
      className="flex flex-col gap-3 border border-[var(--border)] p-4"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="font-semibold text-[var(--text)]">
          {plan.code} · {t(`console.audience.${plan.audience}`)}
        </p>
        {plan.price_status === "placeholder" ? (
          <span className="rounded-full px-3 py-1 text-xs font-bold" style={{ background: "color-mix(in srgb, var(--warning) 18%, transparent)", color: "var(--warning)" }}>
            {t("console.placeholder")}
          </span>
        ) : null}
      </div>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field label={t("console.name")}>
          <input className={inputClass} value={form.name} maxLength={80} onChange={(event) => set("name", event.target.value)} />
        </Field>
        <Field label={t("console.monthly", { currency: plan.currency })}>
          <input className={inputClass} inputMode="decimal" value={form.monthly} onChange={(event) => set("monthly", event.target.value)} />
        </Field>
        <Field label={t("console.annual", { currency: plan.currency })}>
          <input className={inputClass} inputMode="decimal" value={form.annual} onChange={(event) => set("annual", event.target.value)} />
        </Field>
        <Field label={t("console.trialDays")}>
          <input className={inputClass} inputMode="numeric" value={form.trialDays} onChange={(event) => set("trialDays", event.target.value)} />
        </Field>
        <Field label={t("plan.limit.staff_seats")} hint={t("console.unlimitedHint")}>
          <input className={inputClass} inputMode="numeric" value={form.staffSeats} onChange={(event) => set("staffSeats", event.target.value)} />
        </Field>
        <Field label={t("plan.limit.active_clients")} hint={t("console.unlimitedHint")}>
          <input className={inputClass} inputMode="numeric" value={form.activeClients} onChange={(event) => set("activeClients", event.target.value)} />
        </Field>
      </div>
      <div className="flex flex-wrap gap-4 text-sm text-[var(--text)]">
        <Check label={t("console.confirmed")} checked={form.confirmed} onChange={(value) => set("confirmed", value)} />
        <Check label={t("console.default")} checked={form.isDefault} onChange={(value) => set("isDefault", value)} />
        <Check label={t("console.public")} checked={form.isPublic} onChange={(value) => set("isPublic", value)} />
        <Check label={t("console.active")} checked={form.active} onChange={(value) => set("active", value)} />
      </div>
      {save.error ? <ErrorNotice>{localizeError(save.error, i18n)}</ErrorNotice> : null}
      <div>
        <button type="submit" disabled={save.isPending} className="bg-[var(--accent)] px-4 py-2 text-sm font-semibold text-[var(--primary-contrast)] disabled:opacity-50">
          {save.isSuccess && !save.isPending ? t("console.saved") : t("console.save")}
        </button>
      </div>
    </form>
  );
}

function NewPlanForm({ token }: { token: string }) {
  const t = useTranslations("SoloCoach");
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [audience, setAudience] = useState<"gym" | "coach">("coach");
  const create = useMutation({
    mutationFn: () => createPlatformPlan(token, { code: code.trim(), name: name.trim(), audience, active: true, public: false }),
    onSuccess: () => {
      setCode("");
      setName("");
      void queryClient.invalidateQueries({ queryKey: PLATFORM_PLANS_KEY });
    },
  });

  function submit(event: FormEvent) {
    event.preventDefault();
    if (code.trim() && name.trim()) create.mutate();
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-3 border border-dashed border-[var(--border)] p-4">
      <p className="font-semibold text-[var(--text)]">{t("console.newPlan")}</p>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field label={t("console.code")} hint={t("console.codeHint")}>
          <input className={inputClass} value={code} pattern="[a-z][a-z0-9_]{1,39}" onChange={(event) => setCode(event.target.value)} />
        </Field>
        <Field label={t("console.name")}>
          <input className={inputClass} value={name} maxLength={80} onChange={(event) => setName(event.target.value)} />
        </Field>
        <Field label={t("console.audienceLabel")}>
          <Select className={inputClass} value={audience} onValueChange={(value) => setAudience(value as "gym" | "coach")}>
            <option value="coach">{t("console.audience.coach")}</option>
            <option value="gym">{t("console.audience.gym")}</option>
          </Select>
        </Field>
      </div>
      {create.error ? <ErrorNotice>{localizeError(create.error, i18n)}</ErrorNotice> : null}
      <div>
        <button type="submit" disabled={create.isPending} className="border border-[var(--border)] px-4 py-2 text-sm font-semibold text-[var(--text)] disabled:opacity-50">
          {t("console.add")}
        </button>
      </div>
    </form>
  );
}

function Subscriptions({ token, plans }: { token: string; plans: PlatformPlan[] }) {
  const t = useTranslations("SoloCoach");
  const organizations = useQuery({ queryKey: ["platform", "organizations"], queryFn: () => listPlatformOrganizations(token) });
  const subscriptions = useQuery({ queryKey: PLATFORM_SUBSCRIPTIONS_KEY, queryFn: () => fetchPlatformSubscriptions(token) });
  const byOrganization = useMemo(
    () => new Map((subscriptions.data?.subscriptions ?? []).map((entry) => [entry.organization_id, entry])),
    [subscriptions.data],
  );

  return (
    <section className="mt-10 flex flex-col gap-3" aria-label={t("console.subscriptions")}>
      <h2 className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("console.subscriptions")}</h2>
      <ul className="flex flex-col divide-y divide-[var(--border)] border-y border-[var(--border)]">
        {(organizations.data?.organizations ?? []).map(({ organization }) => (
          <SubscriptionRow
            key={organization.id}
            token={token}
            organization={organization}
            subscription={byOrganization.get(organization.id) ?? null}
            plans={plans}
          />
        ))}
      </ul>
    </section>
  );
}

function SubscriptionRow({
  token,
  organization,
  subscription,
  plans,
}: {
  token: string;
  organization: { id: string; name: string; slug: string };
  subscription: OrganizationSubscription | null;
  plans: PlatformPlan[];
}) {
  const t = useTranslations("SoloCoach");
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [planCode, setPlanCode] = useState(subscription?.plan_code ?? plans[0]?.code ?? "");
  const [status, setStatus] = useState<SubscriptionStatus>(subscription?.stored_status ?? "active");
  const [trialEnds, setTrialEnds] = useState(subscription?.trial_ends_at?.slice(0, 10) ?? "");
  const [override, setOverride] = useState(centsToInput(subscription?.price_override_cents));
  const [notes, setNotes] = useState(subscription?.notes ?? "");
  const save = useMutation({
    mutationFn: () =>
      assignPlatformPlan(token, organization.id, {
        plan_code: planCode,
        status,
        trial_ends_at: status === "trialing" && trialEnds ? endOfDayIso(trialEnds) : null,
        price_override_cents: inputToCents(override),
        notes: notes.trim() || null,
      }),
    onSuccess: () => {
      setOpen(false);
      void queryClient.invalidateQueries({ queryKey: PLATFORM_SUBSCRIPTIONS_KEY });
    },
  });

  return (
    <li className="py-3">
      <button type="button" onClick={() => setOpen((value) => !value)} aria-expanded={open} className="flex w-full flex-wrap items-center gap-3 text-start">
        <span className="mr-auto font-semibold text-[var(--text)]">{organization.name}</span>
        <span className="text-sm text-[var(--text-soft)]">
          {subscription ? `${subscription.plan_code} · ${t(`plan.status.${subscription.status}`)}` : t("console.noPlan")}
        </span>
      </button>
      {open ? (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            save.mutate();
          }}
          className="mt-3 grid gap-3 sm:grid-cols-3"
        >
          <Field label={t("console.plan")}>
            <Select className={inputClass} value={planCode} onValueChange={(value) => setPlanCode(value)}>
              {plans.map((plan) => (
                <option key={plan.code} value={plan.code}>{plan.name} ({plan.code})</option>
              ))}
            </Select>
          </Field>
          <Field label={t("console.status")}>
            <Select className={inputClass} value={status} onValueChange={(value) => setStatus(value as SubscriptionStatus)}>
              {STATUSES.map((value) => (
                <option key={value} value={value}>{t(`plan.status.${value}`)}</option>
              ))}
            </Select>
          </Field>
          {status === "trialing" ? (
            <Field label={t("console.trialEnds")}>
              <DateInput className={inputClass} value={trialEnds} onValueChange={(value) => setTrialEnds(value)} />
            </Field>
          ) : null}
          <Field label={t("console.override")} hint={t("console.overrideHint")}>
            <input className={inputClass} inputMode="decimal" value={override} onChange={(event) => setOverride(event.target.value)} />
          </Field>
          <Field label={t("console.notes")}>
            <input className={inputClass} maxLength={1000} value={notes} onChange={(event) => setNotes(event.target.value)} />
          </Field>
          <div className="flex items-end">
            <button type="submit" disabled={save.isPending} className="bg-[var(--accent)] px-4 py-2 text-sm font-semibold text-[var(--primary-contrast)] disabled:opacity-50">
              {t("console.save")}
            </button>
          </div>
          {save.error ? <ErrorNotice className="sm:col-span-3">{localizeError(save.error, i18n)}</ErrorNotice> : null}
        </form>
      ) : null}
    </li>
  );
}

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1 text-sm">
      <span className="font-semibold text-[var(--text-soft)]">{label}</span>
      {children}
      {hint ? <span className="text-xs text-[var(--dim)]">{hint}</span> : null}
    </label>
  );
}

function Check({ label, checked, onChange }: { label: string; checked: boolean; onChange: (value: boolean) => void }) {
  return (
    <label className="flex items-center gap-2">
      <input type="checkbox" checked={checked} onChange={(event) => onChange(event.target.checked)} />
      {label}
    </label>
  );
}
