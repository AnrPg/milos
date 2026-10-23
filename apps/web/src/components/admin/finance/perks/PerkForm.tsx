"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useRef, useState, type ReactNode } from "react";

import { ApiError } from "@/api/client";
import { listAdminLocations } from "@/api/facility";
import { STAFF_GROUPS_KEY, fetchStaffGroups } from "@/api/admin-community";
import { fetchFinancePackages } from "@/api/finance";
import type { PerkBenefitType, PerkChannel, PerkMethod, PerkPeriod, StaffPerk } from "@/api/perks";
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
  LINK_CODE_PLACEHOLDER,
  canPublishPerk,
  codesHandedOut,
  draftFromPerk,
  emptyPerkDraft,
  methodNeedsCode,
  parsePerkCodes,
  perkDraftProblems,
  ruleSectionsSet,
  toPerkInput,
  type DraftWindow,
  type PerkDraft,
  type PerkDraftProblem,
  type RuleSection,
} from "@/lib/perks/validity";
import { uploadBoxPhoto } from "@/lib/box-photo-upload";

// Partner-issued first (the default), then the Palee QR, as the API lists them.
const METHODS: PerkMethod[] = ["shared_code", "code_pool", "personal_qr", "partner_link", "show_membership"];
const BENEFITS: PerkBenefitType[] = ["percent", "fixed_amount", "free_item", "buy_x_get_y", "free_text"];
const PERIODS: PerkPeriod[] = ["day", "week", "month"];
const WEEKDAYS = [1, 2, 3, 4, 5, 6, 7];
const MAX_WINDOWS = 14;
const LOGO_TYPES = ["image/png", "image/jpeg", "image/webp"];

const inputClass = "min-h-11 w-full rounded-2xl px-3 text-sm outline-none";
const inputStyle = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" } as const;

type SetDraft = <K extends keyof PerkDraft>(key: K, value: PerkDraft[K]) => void;
type Problem = (key: PerkDraftProblem) => string | null;

/**
 * Create or edit a partner perk (Οικονομικά › Προσφορές › Συνεργατών,
 * ADR-191). Up front only what every perk needs: the partner, the benefit,
 * how the store redeems it, and when it holds. Everything else (limits,
 * weekly windows, who, where, terms) sits in collapsed «Περισσότεροι όροι»
 * sections that say in one line what is set, so any partner policy fits
 * without a long form. A demo business may save drafts but not publish.
 * Once members claimed it, a change makes a new version; their claims keep
 * the terms they agreed to.
 */
export function PerkForm({ perk, onClose }: { perk: StaffPerk | null; onClose: () => void }) {
  const t = useTranslations("PerksAdmin");
  const { membership } = useSelectedMembershipRole();
  const demo = membership?.organization.activation === "demo";
  const [draft, setDraft] = useState<PerkDraft>(() => (perk ? draftFromPerk(perk) : emptyPerkDraft()));
  const [codesText, setCodesText] = useState("");
  const [showProblems, setShowProblems] = useState(false);
  const save = useSavePerk();
  const step = useStepPerk();
  const addCodes = useAddPerkCodes();
  const pending = parsePerkCodes(codesText);
  const freeCodes = (perk?.codes?.free ?? 0) + pending.codes.length;
  const problems = perkDraftProblems(draft);
  const problem: Problem = (key) => (showProblems && problems.includes(key) ? t(`problem_${key}`) : null);
  const busy = save.isPending || step.isPending || addCodes.isPending;
  const isLive = perk?.status === "published";

  const set: SetDraft = (key, value) => setDraft((current) => ({ ...current, [key]: value }));

  async function submit(publish: boolean) {
    setShowProblems(true);
    if (problems.length > 0) return;
    if (publish && !canPublishPerk(draft, membership?.organization.activation, freeCodes)) return;
    try {
      const saved = await save.mutateAsync({ id: perk?.id ?? null, body: toPerkInput(draft) });
      if (draft.redemption_method === "code_pool" && pending.codes.length > 0) {
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
  const needsCode = methodNeedsCode(draft.redemption_method, draft.link_url);

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
                disabled={busy || demo || (draft.redemption_method === "code_pool" && freeCodes === 0)}
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
      {perk && perk.claims_count > 0 ? <p className="rounded-2xl px-4 py-3 text-xs" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}>{t("versionNote")}</p> : null}

      <Card title={t("partner")}>
        <Field label={t("partnerName")} error={problem("partnerName")}>
          <input className={inputClass} style={inputStyle} value={draft.partner_name} onChange={(event) => set("partner_name", event.target.value)} maxLength={120} />
        </Field>
        <LogoField draft={draft} logoUrl={perk?.logo_url ?? null} onChange={(id) => set("logo_media_id", id)} />
        <Field label={t("partnerUrl")} hint={t("partnerUrlHint")} error={problem("partnerUrl")}>
          <input className={inputClass} style={inputStyle} value={draft.partner_url ?? ""} onChange={(event) => set("partner_url", event.target.value.trim() || null)} inputMode="url" placeholder="https://" maxLength={500} />
        </Field>
      </Card>

      <Card title={t("benefit")}>
        <SegmentPicker
          ariaLabel={t("benefitType")}
          semantics="radiogroup"
          stretch
          value={draft.benefit_type}
          onChange={(value) => set("benefit_type", value)}
          options={BENEFITS.map((value) => ({ value, label: t(`benefit_${value}`) }))}
        />
        <BenefitFields draft={draft} set={set} problem={problem} />
      </Card>

      <Card title={t("method")}>
        <div role="radiogroup" aria-label={t("method")} className="grid grid-cols-1 gap-2">
          {METHODS.map((method) => (
            <button
              key={method}
              type="button"
              role="radio"
              aria-checked={draft.redemption_method === method}
              onClick={() => set("redemption_method", method)}
              className="flex flex-col items-start gap-0.5 rounded-2xl px-4 py-3 text-start"
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
        {draft.redemption_method === "partner_link" ? (
          <Field label={t("linkUrl")} hint={t("linkUrlHint", { placeholder: LINK_CODE_PLACEHOLDER })} error={problem("linkUrl")}>
            <input className={inputClass} style={inputStyle} value={draft.link_url ?? ""} onChange={(event) => set("link_url", event.target.value.trim() || null)} inputMode="url" placeholder="https://" maxLength={1000} />
          </Field>
        ) : null}
        {needsCode ? (
          <Field label={t("sharedCode")} hint={draft.redemption_method === "partner_link" ? t("partnerLinkCodeHint") : t("sharedCodeHint")} error={problem("code")}>
            <input className={`${inputClass} font-mono`} style={inputStyle} value={draft.shared_code ?? ""} onChange={(event) => set("shared_code", event.target.value.toLocaleUpperCase("el"))} autoCapitalize="characters" maxLength={64} />
          </Field>
        ) : null}
        {draft.redemption_method === "code_pool" ? (
          <CodesPool perk={perk} text={codesText} onText={setCodesText} parsed={pending} threshold={draft.low_pool_threshold} onThreshold={(value) => set("low_pool_threshold", value)} />
        ) : null}
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

      <MoreRules draft={draft} set={set} problem={problem} />
    </SidePanel>
  );
}

const ERROR_KEYS: Record<string, string> = {
  business_not_activated: "demoNote",
  perk_codes_required: "codesRequired",
  perk_ended: "endedError",
  perk_read_only: "endedError",
  perk_cap_below_claims: "capBelowClaims",
  invalid_perk_codes: "problem_code",
  invalid_perk_packages: "problem_packages",
  invalid_perk_groups: "problem_groups",
};

/** The fields the chosen benefit needs (`Palee.Perks.Benefit`). */
function BenefitFields({ draft, set, problem }: { draft: PerkDraft; set: SetDraft; problem: Problem }) {
  const t = useTranslations("PerksAdmin");
  const type = draft.benefit_type;
  return (
    <>
      {type === "percent" ? (
        <Field label={t("percentLabel")} error={problem("percent")}>
          <IntegerInput className={inputClass} style={inputStyle} value={draft.percent} onValueChange={(value) => set("percent", value)} min={1} max={100} />
        </Field>
      ) : null}
      {type === "fixed_amount" ? (
        <Field label={t("amountLabel")} error={problem("amount")}>
          <MoneyInput cents={draft.amount_cents} onChange={(value) => set("amount_cents", value)} />
        </Field>
      ) : null}
      {type === "buy_x_get_y" ? (
        <div className="grid grid-cols-2 gap-3">
          <Field label={t("buyQuantity")} error={problem("quantities")}>
            <IntegerInput className={inputClass} style={inputStyle} value={draft.buy_quantity} onValueChange={(value) => set("buy_quantity", value)} min={1} max={100} />
          </Field>
          <Field label={t("getQuantity")}>
            <IntegerInput className={inputClass} style={inputStyle} value={draft.get_quantity} onValueChange={(value) => set("get_quantity", value)} min={1} max={100} />
          </Field>
        </div>
      ) : null}
      {type === "free_item" || type === "buy_x_get_y" ? (
        <Field label={t("itemLabel")} hint={type === "free_item" ? t("itemHint") : t("itemOptionalHint")} error={problem("item")}>
          <input className={inputClass} style={inputStyle} value={draft.item ?? ""} onChange={(event) => set("item", event.target.value || null)} maxLength={120} />
        </Field>
      ) : null}
      <Field
        label={type === "free_text" ? t("giftLabel") : t("onWhat")}
        hint={type === "free_text" ? t("giftHint") : t("onWhatHint")}
        error={problem("benefitText")}
      >
        <input className={inputClass} style={inputStyle} value={draft.text ?? ""} onChange={(event) => set("text", event.target.value || null)} maxLength={200} />
      </Field>
    </>
  );
}

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

function LogoField({ draft, logoUrl, onChange }: { draft: PerkDraft; logoUrl: string | null; onChange: (id: string | null) => void }) {
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
      // The API takes "a ready box_photo upload of the business" (PerkCreate.logo_media_id);
      // the box photo pipeline re-encodes it in the browser, which drops EXIF.
      const media = await uploadBoxPhoto(token, file);
      setPreview(media.url ?? URL.createObjectURL(file));
      onChange(media.id);
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

/** The partner's code pool: paste or upload a CSV/TXT, top up later, see how many were handed out. */
function CodesPool({
  perk,
  text,
  onText,
  parsed,
  threshold,
  onThreshold,
}: {
  perk: StaffPerk | null;
  text: string;
  onText: (text: string) => void;
  parsed: ReturnType<typeof parsePerkCodes>;
  threshold: number | null;
  onThreshold: (value: number | null) => void;
}) {
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
        <p className="text-sm font-semibold" style={{ color: pool.low ? "var(--warning)" : "var(--text)" }} data-testid="perk-codes-pool">
          {t("poolCounts", { handed: codesHandedOut(pool), total: pool.total, free: pool.free })}
          {pool.low ? ` · ${t("poolLow")}` : ""}
        </p>
      ) : (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("poolEmpty")}</p>
      )}
      <Field label={pool && pool.total > 0 ? t("codesTopUp") : t("codesAdd")} hint={t("codesHint")}>
        <textarea className="min-h-28 w-full rounded-2xl p-3 font-mono text-sm outline-none" style={inputStyle} value={text} onChange={(event) => onText(event.target.value)} spellCheck={false} data-testid="perk-codes-input" />
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
      <Field label={t("lowPoolThreshold")} hint={t("lowPoolHint")}>
        <IntegerInput className={inputClass} style={inputStyle} value={threshold} onValueChange={onThreshold} min={0} placeholder="10" />
      </Field>
    </div>
  );
}

/** One weekly window: the days and the hours. */
function WindowRow({ index, window, onChange, onRemove }: { index: number; window: DraftWindow; onChange: (window: DraftWindow) => void; onRemove: () => void }) {
  const t = useTranslations("PerksAdmin");
  const tDays = useTranslations("PerksAdmin.weekday");
  return (
    <div className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("windowN", { n: index + 1 })}</span>
        <button type="button" onClick={onRemove} className="min-h-11 px-2 text-xs font-bold" style={{ color: "var(--danger)" }}>{t("removeWindow")}</button>
      </div>
      <div role="group" aria-label={t("weekdays")} className="grid grid-cols-7 gap-1.5">
        {WEEKDAYS.map((day) => {
          const on = window.weekdays.includes(day);
          return (
            <button
              key={day}
              type="button"
              aria-pressed={on}
              onClick={() => onChange({ ...window, weekdays: on ? window.weekdays.filter((item) => item !== day) : [...window.weekdays, day].sort() })}
              className="min-h-10 rounded-xl text-xs font-bold"
              style={{ background: on ? "var(--text)" : "var(--panel)", color: on ? "var(--bg)" : "var(--text)", border: "1px solid var(--border)" }}
            >
              {tDays(String(day))}
            </button>
          );
        })}
      </div>
      <div className="grid grid-cols-2 gap-3">
        <Field label={t("timeFrom")}>
          <TimeInput className={inputClass} style={inputStyle} value={window.from} onValueChange={(value) => onChange({ ...window, from: value })} step={900} />
        </Field>
        <Field label={t("timeUntil")}>
          <TimeInput className={inputClass} style={inputStyle} value={window.until} onValueChange={(value) => onChange({ ...window, until: value })} step={900} />
        </Field>
      </div>
    </div>
  );
}

/** «Περισσότεροι όροι»: collapsed sections, each with a one-line summary once set. */
function MoreRules({ draft, set, problem }: { draft: PerkDraft; set: SetDraft; problem: Problem }) {
  const t = useTranslations("PerksAdmin");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const filled = ruleSectionsSet(draft);
  const packages = useQuery({ queryKey: ["admin", "finance", "packages"], enabled: Boolean(token), queryFn: () => fetchFinancePackages(token) });
  const locations = useQuery({ queryKey: ["admin", "locations"], enabled: Boolean(token), queryFn: () => listAdminLocations(token) });
  const packageOptions = (packages.data?.packages ?? []).filter((item) => item?.id && item.active !== false);
  // Club groups (Κοινότητα): the live ones, plus any already chosen that has since been archived.
  const groups = useQuery({ queryKey: STAFF_GROUPS_KEY, enabled: Boolean(token), queryFn: () => fetchStaffGroups(token) });
  const groupOptions = [
    ...(groups.data?.live ?? []),
    ...(groups.data?.archived ?? []).filter((group) => draft.group_ids.includes(group.id)),
  ];
  const money = (cents: number) => new Intl.NumberFormat(locale, { style: "currency", currency: draft.currency }).format(cents / 100);
  const windows = draft.windows;
  const setWindows = (next: DraftWindow[]) => set("windows", next);

  const summaries: Record<RuleSection, string> = {
    limits: [
      draft.max_claims !== null ? t("sum_maxClaims", { count: draft.max_claims }) : null,
      t("sum_perMember", { count: draft.max_per_member }),
      draft.period && (draft.max_per_period || draft.max_per_member_per_period) ? t(`sum_period_${draft.period}`, { count: draft.max_per_member_per_period ?? draft.max_per_period ?? 0 }) : null,
      draft.min_spend_cents !== null ? t("sum_minSpend", { amount: money(draft.min_spend_cents) }) : null,
      draft.benefit_type === "percent" && draft.max_discount_cents !== null ? t("sum_maxDiscount", { amount: money(draft.max_discount_cents) }) : null,
    ].filter(Boolean).join(" · "),
    when: windows.length > 0 ? t("sum_windows", { count: windows.length }) : "",
    who: [
      draft.audience === "packages" ? t("sum_packages", { count: draft.package_ids.length }) : null,
      draft.groups_only ? t("sum_groups", { count: draft.group_ids.length }) : null,
      !draft.all_locations ? t("sum_branches", { count: draft.location_ids.length }) : null,
      draft.min_tenure_days !== null ? t("sum_minTenure", { count: draft.min_tenure_days }) : null,
    ].filter(Boolean).join(" · "),
    where: [draft.channel ? t(`channel_${draft.channel}`) : null, draft.partner_address?.trim() || null].filter(Boolean).join(" · "),
    terms: [draft.terms?.trim() ? t("sum_terms") : null, draft.stacking?.trim() ? t("sum_stacking") : null, draft.instructions?.trim() ? t("sum_instructions") : null].filter(Boolean).join(" · "),
  };

  const sections: { id: RuleSection; title: string; body: ReactNode; open: boolean }[] = [
    {
      id: "limits",
      title: t("sec_limits"),
      open: Boolean(problem("maxClaims") || problem("perMember") || problem("period") || problem("minSpend") || problem("maxDiscount")),
      body: (
        <div className="flex flex-col gap-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label={t("maxClaims")} hint={t("maxClaimsHint")} error={problem("maxClaims")}>
              <IntegerInput className={inputClass} style={inputStyle} value={draft.max_claims} onValueChange={(value) => set("max_claims", value)} min={1} placeholder={t("noLimit")} />
            </Field>
            <Field label={t("perMember")} error={problem("perMember")}>
              <IntegerInput className={inputClass} style={inputStyle} value={draft.max_per_member} onValueChange={(value) => set("max_per_member", value ?? 1)} min={1} max={1000} />
            </Field>
          </div>
          <SegmentPicker
            ariaLabel={t("period")}
            semantics="radiogroup"
            stretch
            value={draft.period ?? "none"}
            onChange={(value) => set("period", value === "none" ? null : (value as PerkPeriod))}
            options={[{ value: "none", label: t("period_none") }, ...PERIODS.map((value) => ({ value, label: t(`period_${value}`) }))]}
          />
          {draft.period ? (
            <div className="grid gap-3 sm:grid-cols-2">
              <Field label={t("maxPerPeriod")} error={problem("period")}>
                <IntegerInput className={inputClass} style={inputStyle} value={draft.max_per_period} onValueChange={(value) => set("max_per_period", value)} min={1} placeholder={t("noLimit")} />
              </Field>
              <Field label={t("maxPerMemberPerPeriod")}>
                <IntegerInput className={inputClass} style={inputStyle} value={draft.max_per_member_per_period} onValueChange={(value) => set("max_per_member_per_period", value)} min={1} placeholder={t("noLimit")} />
              </Field>
            </div>
          ) : null}
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label={t("minSpend")} error={problem("minSpend")}>
              <MoneyInput cents={draft.min_spend_cents} onChange={(value) => set("min_spend_cents", value)} />
            </Field>
            {draft.benefit_type === "percent" ? (
              <Field label={t("maxDiscount")} error={problem("maxDiscount")}>
                <MoneyInput cents={draft.max_discount_cents} onChange={(value) => set("max_discount_cents", value)} />
              </Field>
            ) : null}
          </div>
        </div>
      ),
    },
    {
      id: "when",
      title: t("sec_when"),
      open: Boolean(problem("windows")),
      body: (
        <div className="flex flex-col gap-3">
          <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("windowsHint")}</span>
          {windows.map((window, index) => (
            <WindowRow
              key={index}
              index={index}
              window={window}
              onChange={(next) => setWindows(windows.map((item, at) => (at === index ? next : item)))}
              onRemove={() => setWindows(windows.filter((_, at) => at !== index))}
            />
          ))}
          {problem("windows") ? <span role="alert" className="text-xs font-semibold" style={{ color: "var(--danger)" }}>{problem("windows")}</span> : null}
          {windows.length < MAX_WINDOWS ? (
            <button type="button" onClick={() => setWindows([...windows, { weekdays: [], from: "", until: "" }])} className="min-h-11 self-start rounded-2xl px-4 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
              {t("addWindow")}
            </button>
          ) : null}
        </div>
      ),
    },
    {
      id: "who",
      title: t("sec_who"),
      open: Boolean(problem("packages") || problem("groups") || problem("branches") || problem("tenure")),
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
          <SegmentPicker
            ariaLabel={t("groupsAudience")}
            semantics="radiogroup"
            stretch
            value={draft.groups_only ? "groups" : "any"}
            onChange={(value) => set("groups_only", value === "groups")}
            options={[{ value: "any", label: t("groups_any") }, { value: "groups", label: t("groups_only") }]}
          />
          {draft.groups_only ? (
            <div className="flex flex-col gap-1.5">
              {groupOptions.length === 0 ? (
                <span className="text-xs" style={{ color: "var(--text-soft)" }}>{groups.isLoading ? t("groupsLoading") : t("groupsEmpty")}</span>
              ) : (
                <div role="group" aria-label={t("groups_only")} className="grid grid-cols-1 gap-1.5 sm:grid-cols-2" data-testid="perk-groups">
                  {groupOptions.map((group) => {
                    const on = draft.group_ids.includes(group.id);
                    return (
                      <button key={group.id} type="button" aria-pressed={on} onClick={() => set("group_ids", on ? draft.group_ids.filter((value) => value !== group.id) : [...draft.group_ids, group.id])} className="flex min-h-11 items-center justify-between gap-2 rounded-xl px-3 text-start text-sm font-semibold" style={{ background: on ? "color-mix(in srgb, var(--primary) 12%, var(--panel))" : "var(--panel)", border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`, color: "var(--text)" }}>
                        <span className="truncate">{group.name}</span>
                        <span className="shrink-0 text-xs font-normal" style={{ color: "var(--dim)" }}>{t("groupMembers", { count: group.member_count })}</span>
                      </button>
                    );
                  })}
                </div>
              )}
              <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("groupsHint")}</span>
              {problem("groups") ? <span role="alert" className="text-xs font-semibold" style={{ color: "var(--danger)" }}>{problem("groups")}</span> : null}
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
          <Field label={t("minTenure")} hint={t("minTenureHint")} error={problem("tenure")}>
            <IntegerInput className={inputClass} style={inputStyle} value={draft.min_tenure_days} onValueChange={(value) => set("min_tenure_days", value)} min={1} placeholder={t("noLimit")} />
          </Field>
        </div>
      ),
    },
    {
      id: "where",
      title: t("sec_where"),
      open: false,
      body: (
        <div className="flex flex-col gap-3">
          <SegmentPicker
            ariaLabel={t("channel")}
            semantics="radiogroup"
            stretch
            value={draft.channel ?? "both"}
            onChange={(value) => set("channel", value === "both" ? null : (value as PerkChannel))}
            options={[
              { value: "both", label: t("channel_both") },
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
      open: false,
      body: (
        <div className="flex flex-col gap-3">
          <Field label={t("terms")} hint={t("termsHint")}>
            <textarea className="min-h-24 w-full rounded-2xl p-3 text-sm outline-none" style={inputStyle} value={draft.terms ?? ""} onChange={(event) => set("terms", event.target.value || null)} maxLength={4000} />
          </Field>
          <Field label={t("stacking")} hint={t("stackingHint")}>
            <input className={inputClass} style={inputStyle} value={draft.stacking ?? ""} onChange={(event) => set("stacking", event.target.value || null)} maxLength={1000} />
          </Field>
          <Field label={t("instructions")} hint={t("instructionsHint")}>
            <input className={inputClass} style={inputStyle} value={draft.instructions ?? ""} onChange={(event) => set("instructions", event.target.value || null)} maxLength={500} />
          </Field>
        </div>
      ),
    },
  ];

  return (
    <section className="flex flex-col gap-2">
      <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("moreRules")}</h3>
      {sections.map((section) => (
        <details key={section.id} className="rounded-2xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} open={section.open || undefined}>
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
