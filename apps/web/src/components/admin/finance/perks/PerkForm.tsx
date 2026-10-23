"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useRef, useState, type ReactNode } from "react";

import { ApiError } from "@/api/client";
import { listAdminLocations } from "@/api/facility";
import { fetchFinancePackages } from "@/api/finance";
import { completeMediaUpload, requestMediaUpload, type MediaContentType } from "@/api/media";
import type { PerkBenefitType, PerkChannel, PerkMethod, StaffPerk, StaffPerkInput } from "@/api/perks";
import { AppliesToBranches } from "@/components/admin/AppliesToBranches";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { IntegerInput } from "@/components/integer-input";
import { PerkLogo } from "@/components/perks/PerkRows";
import { useAddPerkCodes, useSavePerk, useStepPerk } from "@/components/perks/use-perks";
import { useSession } from "@/components/session-provider";
import { DateInput, TimeInput } from "@/components/ui/DateInput";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import {
  canPublishPerk,
  codesHandedOut,
  draftFromPerk,
  emptyPerkDraft,
  normalizePerkCode,
  parsePerkCodes,
  perkDraftProblems,
  ruleSectionsSet,
  type PerkDraftProblem,
  type RuleSection,
} from "@/lib/perks/validity";
import { putPresigned } from "@/lib/presigned-upload";

const METHODS: PerkMethod[] = ["shared_code", "unique_code", "qr", "partner_link", "show_membership"];
const BENEFITS: PerkBenefitType[] = ["percent", "fixed_amount", "free_text"];
const WEEKDAYS = [1, 2, 3, 4, 5, 6, 7];
const LOGO_TYPES = ["image/png", "image/jpeg", "image/webp"];

const inputClass = "min-h-11 w-full rounded-2xl px-3 text-sm outline-none";
const inputStyle = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" } as const;

/**
 * Create or edit a partner perk (Οικονομικά › Προσφορές › Συνεργατών,
 * ADR-191). Up front only what every perk needs: the partner, the benefit,
 * how the store redeems it, and when it holds. Everything else sits in
 * collapsed «Περισσότεροι όροι» sections that say in one line what is set,
 * so any partner policy fits without a long form. A demo business may save
 * drafts but not publish.
 */
export function PerkForm({ perk, onClose }: { perk: StaffPerk | null; onClose: () => void }) {
  const t = useTranslations("PerksAdmin");
  const { membership } = useSelectedMembershipRole();
  const demo = membership?.organization.activation === "demo";
  const [draft, setDraft] = useState<StaffPerkInput>(() => (perk ? draftFromPerk(perk) : emptyPerkDraft()));
  const [codesText, setCodesText] = useState("");
  const [showProblems, setShowProblems] = useState(false);
  const save = useSavePerk();
  const step = useStepPerk();
  const addCodes = useAddPerkCodes();
  const pending = parsePerkCodes(codesText);
  const freeCodes = (perk?.codes?.free ?? 0) + pending.codes.length;
  const problems = perkDraftProblems(draft);
  const problem = (key: PerkDraftProblem) => (showProblems && problems.includes(key) ? t(`problem_${key}`) : null);
  const locked = Boolean(perk && perk.claims_count > 0);
  const busy = save.isPending || step.isPending || addCodes.isPending;
  const isLive = perk?.status === "published";

  function set<K extends keyof StaffPerkInput>(key: K, value: StaffPerkInput[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
  }

  function setRule<K extends keyof StaffPerkInput["rules"]>(key: K, value: StaffPerkInput["rules"][K]) {
    setDraft((current) => ({ ...current, rules: { ...current.rules, [key]: value } }));
  }

  async function submit(publish: boolean) {
    setShowProblems(true);
    if (problems.length > 0) return;
    if (publish && !canPublishPerk(draft, membership?.organization.activation, freeCodes)) return;
    const body: StaffPerkInput = {
      ...draft,
      partner_name: draft.partner_name.trim(),
      shared_code: draft.redemption_method === "shared_code" || draft.redemption_method === "partner_link" ? normalizePerkCode(draft.shared_code ?? "") : null,
      package_ids: draft.audience === "packages" ? draft.package_ids : [],
    };
    try {
      const saved = await save.mutateAsync({ id: perk?.id ?? null, body });
      if (draft.redemption_method === "unique_code" && pending.codes.length > 0) {
        await addCodes.mutateAsync({ id: saved.id, codes: pending.codes });
        setCodesText("");
      }
      if (publish && saved.status !== "published") await step.mutateAsync({ id: saved.id, step: "publish" });
      onClose();
    } catch {
      // The error shows under the buttons.
    }
  }

  const error = save.error ?? step.error ?? addCodes.error;
  const errorCode = error instanceof ApiError ? error.payload.code : null;

  return (
    <SidePanel
      title={perk ? perk.partner_name : t("newTitle")}
      subtitle={t("eyebrow")}
      onClose={onClose}
      footer={
        <div className="flex w-full flex-col gap-2">
          {demo ? <p className="text-xs" style={{ color: "var(--warning)" }}>{t("demoNote")}</p> : null}
          {error ? (
            <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
              {t(errorCode && ERROR_KEYS[errorCode] ? ERROR_KEYS[errorCode] : "saveFailed")}
            </p>
          ) : null}
          <div className="flex flex-wrap items-center gap-2">
            <span className="me-auto text-xs font-semibold" style={{ color: "var(--dim)" }}>{t(`status_${perk?.status ?? "draft"}`)}</span>
            {isLive ? (
              <button type="button" disabled={busy} onClick={() => perk && step.mutate({ id: perk.id, step: "pause" }, { onSuccess: onClose })} className="min-h-11 rounded-full px-4 text-sm font-semibold disabled:opacity-50" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
                {t("pause")}
              </button>
            ) : null}
            <button type="button" disabled={busy} onClick={() => void submit(false)} className="min-h-11 rounded-full px-4 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}>
              {isLive ? t("saveChanges") : t("saveDraft")}
            </button>
            {!isLive ? (
              <button
                type="button"
                disabled={busy || demo || (draft.redemption_method === "unique_code" && freeCodes === 0)}
                onClick={() => void submit(true)}
                className="min-h-11 rounded-full px-5 text-sm font-bold disabled:opacity-50"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                data-testid="perk-publish"
              >
                {t("publish")}
              </button>
            ) : null}
          </div>
        </div>
      }
    >
      {locked ? <p className="rounded-2xl px-4 py-3 text-xs" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}>{t("lockedNote")}</p> : null}

      <Card title={t("partner")}>
        <Field label={t("partnerName")} error={problem("partnerName")}>
          <input className={inputClass} style={inputStyle} value={draft.partner_name} onChange={(event) => set("partner_name", event.target.value)} maxLength={120} />
        </Field>
        <LogoField draft={draft} logoUrl={perk?.logo_url ?? null} onChange={(id) => set("logo_media_id", id)} />
        <Field label={t("partnerUrl")} hint={t("partnerUrlHint")} error={problem("partnerUrl")}>
          <input className={inputClass} style={inputStyle} value={draft.partner_url ?? ""} onChange={(event) => set("partner_url", event.target.value.trim() || null)} inputMode="url" placeholder="https://" />
        </Field>
      </Card>

      <Card title={t("benefit")}>
        <SegmentPicker
          ariaLabel={t("benefitType")}
          semantics="radiogroup"
          stretch
          value={draft.benefit_type}
          onChange={(value) => set("benefit_type", value)}
          options={BENEFITS.map((value) => ({ value, label: t(`benefit_${value}`), disabled: locked }))}
        />
        {draft.benefit_type !== "free_text" ? (
          <Field label={draft.benefit_type === "percent" ? t("percentLabel") : t("amountLabel")} error={draft.benefit_type === "percent" ? problem("percent") : problem("amount")}>
            {draft.benefit_type === "percent" ? (
              <IntegerInput className={inputClass} style={inputStyle} value={draft.benefit_value} onValueChange={(value) => set("benefit_value", value)} min={1} max={100} disabled={locked} />
            ) : (
              <MoneyInput cents={draft.benefit_value} onChange={(value) => set("benefit_value", value)} disabled={locked} />
            )}
          </Field>
        ) : null}
        <Field label={draft.benefit_type === "free_text" ? t("giftLabel") : t("onWhat")} hint={draft.benefit_type === "free_text" ? t("giftHint") : t("onWhatHint")} error={problem("benefitText")}>
          <input className={inputClass} style={inputStyle} value={draft.benefit_text ?? ""} onChange={(event) => set("benefit_text", event.target.value || null)} maxLength={200} disabled={locked} />
        </Field>
      </Card>

      <Card title={t("method")}>
        <div role="radiogroup" aria-label={t("method")} className="grid grid-cols-1 gap-2">
          {METHODS.map((method) => (
            <button
              key={method}
              type="button"
              role="radio"
              aria-checked={draft.redemption_method === method}
              disabled={locked && draft.redemption_method !== method}
              onClick={() => set("redemption_method", method)}
              className="flex flex-col items-start gap-0.5 rounded-2xl px-4 py-3 text-start disabled:opacity-40"
              style={{
                background: draft.redemption_method === method ? "color-mix(in srgb, var(--primary) 12%, var(--panel))" : "var(--panel)",
                border: `1px solid ${draft.redemption_method === method ? "var(--primary)" : "var(--border)"}`,
                color: "var(--text)",
              }}
              data-testid={`perk-method-${method}`}
            >
              <span className="text-sm font-bold">{t(`method_${method}`)}</span>
              <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t(`method_${method}_hint`)}</span>
            </button>
          ))}
        </div>
        {draft.redemption_method === "shared_code" || draft.redemption_method === "partner_link" ? (
          <Field label={t("sharedCode")} hint={draft.redemption_method === "partner_link" ? t("partnerLinkCodeHint") : t("sharedCodeHint")} error={problem("code")}>
            <input className={`${inputClass} font-mono`} style={inputStyle} value={draft.shared_code ?? ""} onChange={(event) => set("shared_code", event.target.value.toLocaleUpperCase("el"))} autoCapitalize="characters" disabled={locked} />
          </Field>
        ) : null}
        {draft.redemption_method === "partner_link" && !draft.partner_url ? <p className="text-xs" style={{ color: "var(--warning)" }}>{t("partnerLinkNeedsUrl")}</p> : null}
        {draft.redemption_method === "unique_code" ? <CodesPool perk={perk} text={codesText} onText={setCodesText} parsed={pending} /> : null}
      </Card>

      <Card title={t("validity")}>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label={t("validFrom")}>
            <DateInput className={inputClass} style={inputStyle} value={draft.valid_from ?? ""} onValueChange={(value) => set("valid_from", value || null)} placeholder={t("fromNow")} />
          </Field>
          <Field label={t("validUntil")} error={problem("dates")}>
            <DateInput className={inputClass} style={inputStyle} value={draft.valid_until ?? ""} onValueChange={(value) => set("valid_until", value || null)} min={draft.valid_from ?? undefined} placeholder={t("noEnd")} />
          </Field>
        </div>
      </Card>

      <MoreRules draft={draft} set={set} setRule={setRule} problem={problem} />
    </SidePanel>
  );
}

const ERROR_KEYS: Record<string, string> = {
  business_not_activated: "demoNote",
  perk_locked_after_claims: "lockedNote",
  perk_codes_required: "codesRequired",
  perk_ended: "endedError",
  perk_cap_below_claims: "capBelowClaims",
};

function Card({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-3 rounded-3xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>{title}</h3>
      {children}
    </section>
  );
}

function Field({ label, hint, error, children }: { label: string; hint?: string; error?: string | null; children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{label}</span>
      {children}
      {hint ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{hint}</span> : null}
      {error ? <span role="alert" className="text-xs font-semibold" style={{ color: "var(--danger)" }}>{error}</span> : null}
    </label>
  );
}

function Toggle({ label, hint, checked, onChange }: { label: string; hint?: string; checked: boolean; onChange: (value: boolean) => void }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className="flex min-h-12 w-full items-center justify-between gap-3 rounded-2xl px-4 py-2 text-start"
      style={{ background: "var(--panel)", border: `1px solid ${checked ? "var(--primary)" : "var(--border)"}`, color: "var(--text)" }}
    >
      <span className="flex flex-col">
        <span className="text-sm font-semibold">{label}</span>
        {hint ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{hint}</span> : null}
      </span>
      <span aria-hidden="true" className="relative inline-block h-6 w-11 shrink-0 rounded-full" style={{ background: checked ? "var(--primary)" : "var(--border)" }}>
        <span className="absolute top-0.5 h-5 w-5 rounded-full transition-all" style={{ background: "var(--panel)", insetInlineStart: checked ? "1.375rem" : "0.125rem" }} />
      </span>
    </button>
  );
}

/** An amount typed in the currency's units, kept as integer cents. */
function MoneyInput({ cents, onChange, disabled }: { cents: number | null; onChange: (cents: number | null) => void; disabled?: boolean }) {
  const locale = useUiLocale();
  const [text, setText] = useState(() => (cents === null ? "" : (cents / 100).toLocaleString(locale, { minimumFractionDigits: 2 })));
  return (
    <input
      className={inputClass}
      style={inputStyle}
      inputMode="decimal"
      value={text}
      disabled={disabled}
      onChange={(event) => {
        setText(event.target.value);
        const normalized = event.target.value.replace(/\s/g, "").replace(",", ".");
        const value = Number(normalized);
        onChange(normalized === "" || !Number.isFinite(value) ? null : Math.round(value * 100));
      }}
    />
  );
}

function LogoField({ draft, logoUrl, onChange }: { draft: StaffPerkInput; logoUrl: string | null; onChange: (id: string | null) => void }) {
  const t = useTranslations("PerksAdmin");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const input = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<string | null>(logoUrl);
  const [state, setState] = useState<"idle" | "uploading" | "failed">("idle");

  async function upload(file: File) {
    if (!LOGO_TYPES.includes(file.type) || file.size > 5 * 1024 * 1024) {
      setState("failed");
      return;
    }
    setState("uploading");
    try {
      // TODO(ADR-191): a `perk_logo` purpose; the post photo pipeline strips metadata and re-encodes meanwhile.
      const slot = await requestMediaUpload(token, { byte_size: file.size, content_type: file.type as MediaContentType, purpose: "post_photo" });
      await putPresigned(slot.upload_url, file, slot.required_headers);
      await completeMediaUpload(token, slot.media_id);
      setPreview(URL.createObjectURL(file));
      onChange(slot.media_id);
      setState("idle");
    } catch {
      setState("failed");
    }
  }

  return (
    <div className="flex items-center gap-3">
      <PerkLogo name={draft.partner_name || "?"} url={draft.logo_media_id || logoUrl ? preview : null} size={48} />
      <input ref={input} type="file" accept={LOGO_TYPES.join(",")} className="sr-only" onChange={(event) => { const file = event.target.files?.[0]; if (file) void upload(file); event.target.value = ""; }} />
      <button type="button" onClick={() => input.current?.click()} disabled={state === "uploading"} className="min-h-11 rounded-2xl px-4 text-sm font-semibold disabled:opacity-50" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
        {state === "uploading" ? t("logoUploading") : draft.logo_media_id ? t("logoChange") : t("logoAdd")}
      </button>
      {draft.logo_media_id ? (
        <button type="button" onClick={() => { onChange(null); setPreview(null); }} className="min-h-11 text-sm font-semibold" style={{ color: "var(--danger)" }}>
          {t("logoRemove")}
        </button>
      ) : null}
      {state === "failed" ? <span role="alert" className="text-xs" style={{ color: "var(--danger)" }}>{t("logoFailed")}</span> : null}
    </div>
  );
}

/** The pool of the partner's unique codes: paste or upload a CSV/TXT, top up later, see how many were handed out. */
function CodesPool({ perk, text, onText, parsed }: { perk: StaffPerk | null; text: string; onText: (text: string) => void; parsed: ReturnType<typeof parsePerkCodes> }) {
  const t = useTranslations("PerksAdmin");
  const file = useRef<HTMLInputElement>(null);
  const pool = perk?.codes ?? null;

  async function read(selected: File) {
    const content = await selected.text();
    onText(text ? `${text}\n${content}` : content);
  }

  return (
    <div className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
      {pool ? (
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }} data-testid="perk-codes-pool">
          {t("poolCounts", { handed: codesHandedOut(pool), total: pool.total, free: pool.free })}
        </p>
      ) : (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("poolEmpty")}</p>
      )}
      <Field label={pool && pool.total > 0 ? t("codesTopUp") : t("codesAdd")} hint={t("codesHint")}>
        <textarea className="min-h-28 w-full rounded-2xl p-3 font-mono text-sm outline-none" style={inputStyle} value={text} onChange={(event) => onText(event.target.value)} spellCheck={false} />
      </Field>
      <div className="flex flex-wrap items-center gap-2">
        <input ref={file} type="file" accept=".csv,.txt,text/csv,text/plain" className="sr-only" onChange={(event) => { const selected = event.target.files?.[0]; if (selected) void read(selected); event.target.value = ""; }} />
        <button type="button" onClick={() => file.current?.click()} className="min-h-11 rounded-2xl px-4 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)", background: "var(--panel)" }}>
          {t("codesUpload")}
        </button>
        {parsed.codes.length > 0 || parsed.duplicates > 0 || parsed.invalid > 0 ? (
          <span className="text-xs" style={{ color: "var(--text-soft)" }}>
            {t("codesParsed", { count: parsed.codes.length, duplicates: parsed.duplicates, invalid: parsed.invalid })}
          </span>
        ) : null}
        {parsed.tooMany ? <span className="text-xs" style={{ color: "var(--warning)" }}>{t("codesTooMany")}</span> : null}
      </div>
    </div>
  );
}

/** «Περισσότεροι όροι»: collapsed sections, each with a one-line summary once set. */
function MoreRules({
  draft,
  set,
  setRule,
  problem,
}: {
  draft: StaffPerkInput;
  set: <K extends keyof StaffPerkInput>(key: K, value: StaffPerkInput[K]) => void;
  setRule: <K extends keyof StaffPerkInput["rules"]>(key: K, value: StaffPerkInput["rules"][K]) => void;
  problem: (key: PerkDraftProblem) => string | null;
}) {
  const t = useTranslations("PerksAdmin");
  const tDays = useTranslations("PerksAdmin.weekday");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const filled = ruleSectionsSet(draft);
  const packages = useQuery({ queryKey: ["admin", "finance", "packages"], enabled: Boolean(token), queryFn: () => fetchFinancePackages(token) });
  const locations = useQuery({ queryKey: ["admin", "locations"], enabled: Boolean(token), queryFn: () => listAdminLocations(token) });
  const packageOptions = (packages.data?.packages ?? []).filter((item) => item?.id && item.active !== false);
  const { rules } = draft;
  const money = (cents: number) => new Intl.NumberFormat(locale, { style: "currency", currency: draft.currency }).format(cents / 100);

  const summaries: Record<RuleSection, string> = {
    limits: [
      draft.max_claims !== null ? t("sum_maxClaims", { count: draft.max_claims }) : null,
      t("sum_perMember", { count: draft.max_claims_per_member }),
      rules.min_spend_cents !== null ? t("sum_minSpend", { amount: money(rules.min_spend_cents) }) : null,
    ].filter(Boolean).join(" · "),
    when: [rules.weekdays.length > 0 ? rules.weekdays.map((day) => tDays(String(day))).join(", ") : null, rules.time_from && rules.time_until ? `${rules.time_from}–${rules.time_until}` : null].filter(Boolean).join(" · "),
    who: [
      draft.audience === "packages" ? t("sum_packages", { count: draft.package_ids.length }) : null,
      !draft.all_locations ? t("sum_branches", { count: draft.location_ids.length }) : null,
      rules.new_customers_only ? t("newCustomersOnly") : null,
    ].filter(Boolean).join(" · "),
    where: [rules.channel ? t(`channel_${rules.channel}`) : null, draft.partner_address?.trim() || null].filter(Boolean).join(" · "),
    terms: [draft.terms?.trim() ? t("sum_terms") : null, draft.box_benefits ? t("sum_disclosure") : null].filter(Boolean).join(" · "),
  };

  const sections: { id: RuleSection; title: string; body: ReactNode }[] = [
    {
      id: "limits",
      title: t("sec_limits"),
      body: (
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label={t("maxClaims")} hint={t("maxClaimsHint")} error={problem("maxClaims")}>
            <IntegerInput className={inputClass} style={inputStyle} value={draft.max_claims} onValueChange={(value) => set("max_claims", value)} min={1} placeholder={t("noLimit")} />
          </Field>
          <Field label={t("perMember")} error={problem("perMember")}>
            <IntegerInput className={inputClass} style={inputStyle} value={draft.max_claims_per_member} onValueChange={(value) => set("max_claims_per_member", value ?? 1)} min={1} max={1000} />
          </Field>
          <Field label={t("minSpend")} error={problem("minSpend")}>
            <MoneyInput cents={rules.min_spend_cents} onChange={(value) => setRule("min_spend_cents", value)} />
          </Field>
        </div>
      ),
    },
    {
      id: "when",
      title: t("sec_when"),
      body: (
        <div className="flex flex-col gap-3">
          <div role="group" aria-label={t("weekdays")} className="grid grid-cols-7 gap-1.5">
            {WEEKDAYS.map((day) => {
              const on = rules.weekdays.includes(day);
              return (
                <button key={day} type="button" aria-pressed={on} onClick={() => setRule("weekdays", on ? rules.weekdays.filter((item) => item !== day) : [...rules.weekdays, day].sort())} className="min-h-10 rounded-xl text-xs font-bold" style={{ background: on ? "var(--text)" : "var(--panel)", color: on ? "var(--bg)" : "var(--text)", border: "1px solid var(--border)" }}>
                  {tDays(String(day))}
                </button>
              );
            })}
          </div>
          <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("weekdaysHint")}</span>
          <div className="grid grid-cols-2 gap-3">
            <Field label={t("timeFrom")} error={problem("hours")}>
              <TimeInput className={inputClass} style={inputStyle} value={rules.time_from ?? ""} onValueChange={(value) => setRule("time_from", value || null)} step={900} />
            </Field>
            <Field label={t("timeUntil")}>
              <TimeInput className={inputClass} style={inputStyle} value={rules.time_until ?? ""} onValueChange={(value) => setRule("time_until", value || null)} step={900} />
            </Field>
          </div>
        </div>
      ),
    },
    {
      id: "who",
      title: t("sec_who"),
      body: (
        <div className="flex flex-col gap-3">
          <SegmentPicker
            ariaLabel={t("audience")}
            semantics="radiogroup"
            stretch
            value={draft.audience}
            onChange={(value) => set("audience", value)}
            options={[{ value: "all_clients", label: t("audience_all_clients") }, { value: "packages", label: t("audience_packages") }]}
          />
          {draft.audience === "packages" ? (
            <div className="flex flex-col gap-1.5">
              <div role="group" aria-label={t("audience_packages")} className="grid grid-cols-1 gap-1.5 sm:grid-cols-2">
                {packageOptions.map((item) => {
                  const id = String(item.id);
                  const on = draft.package_ids.includes(id);
                  return (
                    <button key={id} type="button" aria-pressed={on} onClick={() => set("package_ids", on ? draft.package_ids.filter((value) => value !== id) : [...draft.package_ids, id])} className="min-h-11 truncate rounded-xl px-3 text-start text-sm font-semibold" style={{ background: on ? "color-mix(in srgb, var(--primary) 12%, var(--panel))" : "var(--panel)", border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`, color: "var(--text)" }}>
                      {String(item.name ?? "")}
                    </button>
                  );
                })}
              </div>
              <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("packagesHint")}</span>
              {problem("packages") ? <span role="alert" className="text-xs font-semibold" style={{ color: "var(--danger)" }}>{problem("packages")}</span> : null}
            </div>
          ) : null}
          <AppliesToBranches
            kind="covering"
            locations={locations.data}
            value={draft.all_locations ? "all" : draft.location_ids}
            onChange={(scope) => {
              set("all_locations", scope === "all");
              set("location_ids", scope === "all" ? [] : scope);
            }}
          />
          {problem("branches") ? <span role="alert" className="text-xs font-semibold" style={{ color: "var(--danger)" }}>{problem("branches")}</span> : null}
          <Toggle label={t("newCustomersOnly")} hint={t("newCustomersOnlyHint")} checked={rules.new_customers_only} onChange={(value) => setRule("new_customers_only", value)} />
        </div>
      ),
    },
    {
      id: "where",
      title: t("sec_where"),
      body: (
        <div className="flex flex-col gap-3">
          <SegmentPicker
            ariaLabel={t("channel")}
            semantics="radiogroup"
            stretch
            value={rules.channel ?? "any"}
            onChange={(value) => setRule("channel", value === "any" ? null : (value as PerkChannel))}
            options={[
              { value: "any", label: t("channel_any") },
              { value: "in_store", label: t("channel_in_store") },
              { value: "online", label: t("channel_online") },
            ]}
          />
          <Field label={t("partnerAddress")} hint={t("partnerAddressHint")}>
            <input className={inputClass} style={inputStyle} value={draft.partner_address ?? ""} onChange={(event) => set("partner_address", event.target.value || null)} maxLength={300} />
          </Field>
        </div>
      ),
    },
    {
      id: "terms",
      title: t("sec_terms"),
      body: (
        <div className="flex flex-col gap-3">
          <Field label={t("terms")} hint={t("termsHint")}>
            <textarea className="min-h-24 w-full rounded-2xl p-3 text-sm outline-none" style={inputStyle} value={draft.terms ?? ""} onChange={(event) => set("terms", event.target.value || null)} maxLength={4000} />
          </Field>
          <Toggle label={t("boxBenefits")} hint={t("boxBenefitsHint")} checked={draft.box_benefits} onChange={(value) => set("box_benefits", value)} />
        </div>
      ),
    },
  ];

  return (
    <section className="flex flex-col gap-2">
      <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("moreRules")}</h3>
      {sections.map((section) => (
        <details key={section.id} className="rounded-2xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} open={section.id === "who" && Boolean(problem("packages") || problem("branches"))}>
          <summary className="flex min-h-12 cursor-pointer list-none items-center justify-between gap-3 px-4 py-2">
            <span className="flex min-w-0 flex-col">
              <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{section.title}</span>
              <span className="truncate text-xs" style={{ color: filled[section.id] ? "var(--primary-strong)" : "var(--dim)" }}>
                {filled[section.id] && summaries[section.id] ? summaries[section.id] : t("notSet")}
              </span>
            </span>
            <span aria-hidden="true" style={{ color: "var(--dim)" }}>▾</span>
          </summary>
          <div className="px-4 pb-4">{section.body}</div>
        </details>
      ))}
    </section>
  );
}
