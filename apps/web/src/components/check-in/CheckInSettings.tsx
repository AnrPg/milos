"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { CHECK_IN_RULES_KEY, fetchCheckInRules, updateCheckInRules, type MemberCodeMode } from "@/api/check-in";
import { useSession } from "@/components/session-provider";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { DEFAULT_RULES, modeChangeNeedsConfirm, ROTATION_CHOICES, validateRules, type RulesDraft } from "./check-in";
import { checkInErrorKey } from "./errors";

/**
 * Ρυθμίσεις › Check-in (ADR-155 §9): the window around a class, open gym,
 * the visitor's trial offer, the desk's «Check-in παρ' όλα αυτά», how fast
 * the door code turns, and whether personal codes rotate or stay the same
 * (only a code that stays the same can go in a Wallet). Going back to
 * rotating codes revokes every fixed code and card, so it asks first.
 */
export function CheckInSettings() {
  const t = useTranslations("CheckIn");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const rules = useQuery({ queryKey: CHECK_IN_RULES_KEY, enabled: Boolean(token), queryFn: () => fetchCheckInRules(token) });
  if (rules.isPending) return <p className="p-6 text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (rules.isError) return <p role="alert" className="p-6 text-sm" style={{ color: "var(--danger)" }}>{t(checkInErrorKey(rules.error))}</p>;
  const initial = { ...DEFAULT_RULES, ...Object.fromEntries(Object.entries(rules.data).filter(([, value]) => value !== undefined && value !== null)) } as RulesDraft;
  // Not keyed on the saved rules: saving updates `initial` (what a mode switch is measured
  // from) without throwing away the form and its «Αποθηκεύτηκε».
  return <Form token={token} initial={initial} />;
}

function Form({ token, initial }: { token: string; initial: RulesDraft }) {
  const t = useTranslations("CheckIn");
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<RulesDraft>(initial);
  const [saved, setSaved] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const errors = validateRules(draft);
  const set = <K extends keyof RulesDraft>(key: K, value: RulesDraft[K]) => {
    setSaved(false);
    setConfirming(false);
    setDraft((current) => ({ ...current, [key]: value }));
  };

  const save = useMutation({
    mutationFn: () => updateCheckInRules(token, draft),
    onSuccess: (data) => {
      queryClient.setQueryData(CHECK_IN_RULES_KEY, data);
      setSaved(true);
      setConfirming(false);
    },
  });

  function submit() {
    if (errors.length > 0) return;
    if (!confirming && modeChangeNeedsConfirm(initial.member_code_mode, draft.member_code_mode)) {
      setConfirming(true);
      return;
    }
    save.mutate();
  }

  const field = { background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" };

  return (
    <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
      <form
        className="mx-auto flex max-w-2xl flex-col gap-5 pb-36"
        noValidate
        onSubmit={(event) => {
          event.preventDefault();
          submit();
        }}
      >
        <header className="flex flex-col gap-1">
          <Link href={adminHref("/admin/settings", slug)} className="text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>
            ‹ {t("backToSettings")}
          </Link>
          <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("settingsTitle")}</h1>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("settingsIntro")}</p>
        </header>

        <Section title={t("windowTitle")} hint={t("windowHint")}>
          <MinutesRow
            label={t("windowBefore")}
            value={draft.window_before_minutes}
            invalid={errors.includes("window_before")}
            error={t("windowError")}
            onChange={(value) => set("window_before_minutes", value)}
            style={field}
          />
          <MinutesRow
            label={t("windowAfter")}
            value={draft.window_after_minutes}
            invalid={errors.includes("window_after")}
            error={t("windowError")}
            onChange={(value) => set("window_after_minutes", value)}
            style={field}
          />
        </Section>

        <Section title={t("rulesTitle")}>
          <Toggle label={t("openGymRequiresPackage")} hint={t("openGymRequiresPackageHint")} checked={draft.open_gym_requires_package} onChange={(value) => set("open_gym_requires_package", value)} />
          <Toggle label={t("visitorTrialOffer")} hint={t("visitorTrialOfferHint")} checked={draft.visitor_trial_offer} onChange={(value) => set("visitor_trial_offer", value)} />
          <Toggle label={t("deskOverride")} hint={t("deskOverrideHint")} checked={draft.desk_override} onChange={(value) => set("desk_override", value)} />
        </Section>

        <Section title={t("rotationTitle")} hint={t("rotationHint")}>
          <div role="radiogroup" aria-label={t("rotationTitle")} className="flex flex-wrap gap-2">
            {ROTATION_CHOICES.map((seconds) => (
              <label
                key={seconds}
                className="flex min-h-11 cursor-pointer items-center gap-2 rounded-full px-4 text-sm font-semibold"
                style={draft.door_rotation_seconds === seconds ? { background: "var(--text)", color: "var(--bg)" } : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
              >
                <input
                  type="radio"
                  name="door_rotation_seconds"
                  className="sr-only"
                  checked={draft.door_rotation_seconds === seconds}
                  onChange={() => set("door_rotation_seconds", seconds)}
                />
                {t("seconds", { count: seconds })}
              </label>
            ))}
          </div>
        </Section>

        <Section title={t("codeModeTitle")} hint={t("codeModeHint")}>
          {(["rotating", "static"] as MemberCodeMode[]).map((mode) => (
            <label
              key={mode}
              className="flex cursor-pointer items-start gap-3 rounded-2xl px-4 py-3"
              style={{ background: "var(--panel)", border: `1px solid ${draft.member_code_mode === mode ? "var(--primary)" : "var(--border)"}` }}
            >
              <input type="radio" name="member_code_mode" className="mt-1" checked={draft.member_code_mode === mode} onChange={() => set("member_code_mode", mode)} />
              <span className="flex flex-col">
                <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t(["codeMode", mode].join("_"))}</span>
                <span className="text-sm" style={{ color: "var(--text-soft)" }}>{t(["codeModeHint", mode].join("_"))}</span>
              </span>
            </label>
          ))}
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("codeModeWalletNote")}</p>
          {initial.member_code_mode === "rotating" && draft.member_code_mode === "static" ? (
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("codeModeToStatic")}</p>
          ) : null}
        </Section>

        <div className="sticky bottom-4 flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          {confirming ? (
            <div role="alertdialog" aria-labelledby="mode-confirm" className="flex flex-col gap-2" data-testid="mode-confirm">
              <p id="mode-confirm" className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("codeModeConfirm")}</p>
              <div className="flex flex-wrap gap-2">
                <button type="button" onClick={() => setConfirming(false)} className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
                  {t("keep")}
                </button>
                <button type="submit" disabled={save.isPending} className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold disabled:opacity-60" style={{ background: "var(--danger, #dc2626)", color: "#fff" }}>
                  {t("codeModeConfirmAction")}
                </button>
              </div>
            </div>
          ) : null}
          {save.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t(checkInErrorKey(save.error))}</p> : null}
          {saved ? <p role="status" className="text-sm" style={{ color: "var(--success)" }}>{t("saved")}</p> : null}
          {confirming ? null : (
            <button type="submit" disabled={save.isPending || errors.length > 0} className="min-h-12 rounded-2xl text-sm font-bold disabled:opacity-60" style={{ background: "var(--primary)", color: "var(--bg)" }}>
              {save.isPending ? t("saving") : t("save")}
            </button>
          )}
        </div>
      </form>
    </main>
  );
}

function Section({ title, hint, children }: { title: string; hint?: string; children: ReactNode }) {
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

function MinutesRow({
  label,
  value,
  invalid,
  error,
  onChange,
  style,
}: {
  label: string;
  value: number;
  invalid: boolean;
  error: string;
  onChange: (value: number) => void;
  style: React.CSSProperties;
}) {
  return (
    <label className="flex flex-col gap-1 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: `1px solid ${invalid ? "var(--danger)" : "var(--border)"}` }}>
      <span className="flex items-center justify-between gap-4">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{label}</span>
        <input
          type="number"
          inputMode="numeric"
          min={0}
          max={120}
          step={1}
          value={Number.isFinite(value) ? value : ""}
          aria-invalid={invalid}
          onChange={(event) => onChange(event.target.value.trim() === "" ? Number.NaN : Number(event.target.value))}
          className="min-h-11 w-24 rounded-2xl px-3 text-sm"
          style={style}
        />
      </span>
      {invalid ? <span className="text-xs" style={{ color: "var(--danger)" }}>{error}</span> : null}
    </label>
  );
}

/** The settings entry next to Δημόσια σελίδα, Δοκιμαστικά and Κοινότητα. */
export function CheckInSettingsLink() {
  const t = useTranslations("CheckIn");
  const slug = useOrganizationSlug();
  return (
    <Link
      href={adminHref("/admin/check-in/settings", slug)}
      className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <span className="flex flex-col">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("settingsTitle")}</span>
        <span className="text-sm" style={{ color: "var(--muted)" }}>{t("settingsNavHint")}</span>
      </span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
    </Link>
  );
}
