"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";

import { createFinancePackage, type FinanceRecord } from "@/api/finance";
import type { ClassTypeRecord } from "@/api/schedule";
import { localizeError, type UiTranslator } from "@/i18n/presentation";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { ApiError } from "@/api/client";
import {
  AdvancedSettings,
  DurationControl,
  FieldShell,
  LockStrip,
  MemberPreview,
  QuotaControl,
  ClassTypeScope,
  Segmented,
  Stepper,
  Toggle,
  VALIDITY_PRESETS,
  money,
  useT,
  type FieldContext,
} from "./package-ui";
import {
  anyServiceIncluded,
  applyLocks,
  changeBillingPeriod,
  changedFields,
  draftIssues,
  fieldLabelKey,
  findType,
  isFieldLocked,
  monthlyEquivalentCents,
  moduleEnabled,
  newDraft,
  perVisitCents,
  priceCents,
  resetAll,
  selectableTypes,
  sectionLabelKey,
  switchType,
  toPackageRequest,
  typeLabelKey,
  wizardSteps,
  type DurationValue,
  type PackageCatalog,
  type PackageDraft,
  type QuotaValue,
} from "./package-catalog";

const STORAGE_KEY = "milos.package-wizard.draft.v1";
const TYPE_ICONS: Record<string, string> = {
  membership: "🔁",
  class_pack: "🎟️",
  drop_in: "🎫",
  trial: "✨",
  pt_pack: "🏋️",
  add_on: "➕",
  shared: "👥",
  corporate: "🏢",
};
const ARIA_CURRENT_STEP = "step" as const;
const TYPE_ORDER = ["membership", "class_pack", "drop_in", "trial", "pt_pack", "add_on", "shared", "corporate"];

type StoredWizard = { step: number; draft: PackageDraft };

function readStored(): StoredWizard | null {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as StoredWizard) : null;
  } catch {
    return null;
  }
}

function writeStored(value: StoredWizard | null) {
  try {
    if (value) window.localStorage.setItem(STORAGE_KEY, JSON.stringify(value));
    else window.localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Draft persistence is a convenience; the wizard works without storage.
  }
}

export function PackageWizard({
  catalog,
  token,
  classTypes,
  packages,
  initialDraft,
  onClose,
  onCreated,
}: {
  catalog: PackageCatalog;
  token: string;
  classTypes: ClassTypeRecord[];
  packages: FinanceRecord[];
  initialDraft?: PackageDraft;
  onClose: () => void;
  onCreated: (pkg: FinanceRecord) => void;
}) {
  const t = useT();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<PackageDraft | null>(initialDraft ?? null);
  const [stepIndex, setStepIndex] = useState(initialDraft ? 1 : 0);
  // The wizard only mounts after a user action, so storage is read on first render.
  const [resumable, setResumable] = useState<StoredWizard | null>(() => (initialDraft ? null : readStored()));
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [attempted, setAttempted] = useState(false);
  const headingRef = useRef<HTMLHeadingElement>(null);
  const context: FieldContext = { classTypes, packages };

  useEffect(() => {
    if (draft) writeStored({ step: stepIndex, draft });
  }, [draft, stepIndex]);

  useEffect(() => {
    headingRef.current?.focus();
  }, [stepIndex, showAdvanced]);

  const type = draft ? findType(catalog, draft.packageType) : undefined;
  const steps = wizardSteps(draft?.packageType ?? "membership");
  const step = steps[Math.min(stepIndex, steps.length - 1)];
  const changed = draft ? changedFields(catalog, draft) : [];
  const issues = draft ? draftIssues(draft) : [];
  const stepIssues = issues.filter((issue) =>
    step === "basics" ? ["name", "price", "terms.validity"].includes(issue.field) : step === "included" ? !["name", "price"].includes(issue.field) : true,
  );

  const createMutation = useMutation({
    mutationFn: () => createFinancePackage(token, toPackageRequest(catalog, draft as PackageDraft)),
    onSuccess: async (response) => {
      writeStored(null);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] });
      onCreated(response.package as FinanceRecord);
    },
  });

  function update(next: PackageDraft) {
    setDraft(type ? { ...next, fields: applyLocks(type, next.fields) } : next);
  }

  // Functional update so several field changes in one handler compose.
  function setField(key: string, value: unknown) {
    setDraft((previous) => {
      if (!previous) return previous;
      const current = findType(catalog, previous.packageType);
      const fields = { ...previous.fields, [key]: value };
      return { ...previous, fields: current ? applyLocks(current, fields) : fields };
    });
  }

  function chooseType(typeKey: string) {
    setDraft(draft ? switchType(catalog, draft, typeKey) : newDraft(catalog, typeKey));
  }

  function next() {
    setAttempted(true);
    if (step === "type" && !draft) return;
    if (stepIssues.length > 0 && step !== "type") return;
    setAttempted(false);
    setStepIndex((index) => Math.min(index + 1, steps.length - 1));
  }

  function back() {
    setAttempted(false);
    setStepIndex((index) => Math.max(index - 1, 0));
  }

  function close() {
    onClose();
  }

  const serverError =
    createMutation.error instanceof ApiError
      ? (createMutation.error.payload.params as { field?: string } | undefined)?.field
      : undefined;

  const nextLabel = steps[stepIndex + 1] ? t(`pkgContinueTo_${steps[stepIndex + 1]}`) : "";

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <ol className="flex flex-wrap gap-2 px-6 pt-5" aria-label={t("pkgWizardProgress")}>
        {steps.map((name, index) => {
          const state = index < stepIndex ? "done" : index === stepIndex ? "current" : "todo";
          return (
            <li
              key={name}
              aria-current={state === "current" ? ARIA_CURRENT_STEP : undefined}
              className="flex items-center gap-2 rounded-full px-3 py-1.5 text-xs font-semibold"
              style={{
                background: state === "current" ? "var(--text)" : "var(--bg-soft)",
                color: state === "current" ? "var(--bg)" : state === "done" ? "var(--success)" : "var(--dim)",
                border: "1px solid var(--border)",
              }}
            >
              <span aria-hidden="true">{state === "done" ? "✓" : index + 1}</span>
              {t(`pkgStep_${name}`)}
            </li>
          );
        })}
      </ol>

      <div className="flex-1 overflow-y-auto px-6 py-5">
        <h3 ref={headingRef} tabIndex={-1} className="text-lg font-semibold outline-none" style={{ color: "var(--text)" }}>
          {showAdvanced ? t("pkgAdvancedSettings") : t(`pkgStepTitle_${step}`)}
        </h3>
        {!showAdvanced ? <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>{t(`pkgStepIntro_${step}`)}</p> : null}

        {resumable && !draft && step === "type" ? (
          <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-2xl p-4" style={{ background: "color-mix(in srgb, var(--primary) 8%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 30%, transparent)" }}>
            <p className="text-sm" style={{ color: "var(--text)" }}>
              {t("pkgResumeDraft", { name: resumable.draft.name || t("pkgUntitled") })}
            </p>
            <div className="flex gap-2">
              <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--text)", color: "var(--bg)" }} onClick={() => { setDraft(resumable.draft); setStepIndex(resumable.step); setResumable(null); }}>
                {t("pkgResumeContinue")}
              </button>
              <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={() => { writeStored(null); setResumable(null); }}>
                {t("pkgResumeDiscard")}
              </button>
            </div>
          </div>
        ) : null}

        <div className="mt-5 space-y-6">
          {showAdvanced && draft && type ? (
            <AdvancedSettings
              catalog={catalog}
              type={type}
              draft={draft}
              context={context}
              changedCount={changed.length}
              onFieldChange={setField}
              onResetAll={() => setDraft(resetAll(catalog, draft))}
            />
          ) : null}

          {!showAdvanced && step === "type" ? (
            <TypeStep catalog={catalog} selected={draft?.packageType} onSelect={chooseType} />
          ) : null}

          {!showAdvanced && step === "basics" && draft && type ? (
            <BasicsStep draft={draft} catalog={catalog} attempted={attempted} issues={stepIssues} onChange={update} packages={packages} locale={locale} />
          ) : null}

          {!showAdvanced && step === "included" && draft && type ? (
            <IncludedStep draft={draft} catalog={catalog} attempted={attempted} issues={stepIssues} onField={setField} classTypes={classTypes} />
          ) : null}

          {!showAdvanced && step === "review" && draft && type ? (
            <ReviewStep
              catalog={catalog}
              draft={draft}
              changed={changed}
              classTypes={classTypes}
              onEdit={(target) => setStepIndex(steps.indexOf(target))}
              onAdvanced={() => setShowAdvanced(true)}
            />
          ) : null}

          {!showAdvanced && draft && step !== "type" && step !== "review" ? <MemberPreview draft={draft} classTypes={classTypes} compact /> : null}

          {createMutation.error ? (
            <p role="alert" className="rounded-xl px-3 py-2 text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--danger) 10%, transparent)", color: "var(--danger)" }}>
              {localizeError(createMutation.error, t)}
              {serverError ? ` (${t(fieldLabelKey(serverError.split(".").slice(0, 2).join(".")))})` : ""}
            </p>
          ) : null}
        </div>
      </div>

      <div className="sticky bottom-0 flex flex-wrap items-center justify-between gap-3 px-6 py-4" style={{ background: "var(--bg)", borderTop: "1px solid var(--border)" }}>
        <div className="flex gap-2">
          {showAdvanced ? (
            <button type="button" className="min-h-[2.75rem] rounded-full px-5 text-sm font-semibold" style={{ background: "var(--text)", color: "var(--bg)" }} onClick={() => setShowAdvanced(false)}>
              {t("pkgAdvancedDone")}
            </button>
          ) : stepIndex > 0 ? (
            <button type="button" className="min-h-[2.75rem] rounded-full px-5 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={back}>
              ← {t("pkgBack")}
            </button>
          ) : (
            <button type="button" className="min-h-[2.75rem] rounded-full px-5 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={close}>
              {t("pkgCancel")}
            </button>
          )}
          {!showAdvanced && draft && (step === "basics" || step === "included") ? (
            <button type="button" className="min-h-[2.75rem] rounded-full px-4 text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setShowAdvanced(true)}>
              ⚙ {t("pkgAdvancedSettings")}{changed.length > 0 ? ` · ${changed.length}` : ""}
            </button>
          ) : null}
        </div>
        {!showAdvanced ? (
          step === "review" ? (
            <button
              type="button"
              className="min-h-[2.75rem] rounded-full px-6 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "white" }}
              disabled={createMutation.isPending || issues.length > 0}
              onClick={() => createMutation.mutate()}
            >
              {createMutation.isPending ? t("pkgCreating") : t("pkgCreate")}
            </button>
          ) : (
            <button
              type="button"
              className="min-h-[2.75rem] rounded-full px-6 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              disabled={step === "type" && !draft}
              onClick={next}
            >
              {nextLabel} →
            </button>
          )
        ) : null}
      </div>
    </div>
  );
}

function TypeStep({ catalog, selected, onSelect }: { catalog: PackageCatalog; selected?: string; onSelect: (key: string) => void }) {
  const t = useT();
  const types = selectableTypes(catalog).sort((a, b) => TYPE_ORDER.indexOf(a.key) - TYPE_ORDER.indexOf(b.key));
  return (
    <div role="radiogroup" aria-label={t("pkgStepTitle_type")} className="grid gap-3 sm:grid-cols-2">
      {types.map((type) => {
        const on = selected === type.key;
        return (
          <button
            key={type.key}
            type="button"
            role="radio"
            aria-checked={on}
            onClick={() => onSelect(type.key)}
            className="flex min-h-[7rem] flex-col items-start gap-1 rounded-2xl p-4 text-start"
            style={{
              background: on ? "color-mix(in srgb, var(--primary) 10%, var(--panel))" : "var(--panel)",
              border: `2px solid ${on ? "var(--primary)" : "var(--border)"}`,
            }}
          >
            <span className="text-2xl" aria-hidden="true">{TYPE_ICONS[type.key]}</span>
            <span className="text-base font-semibold" style={{ color: "var(--text)" }}>{t(typeLabelKey(type.key))}</span>
            <span className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`${typeLabelKey(type.key)}Hint`)}</span>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t(`${typeLabelKey(type.key)}Example`)}</span>
          </button>
        );
      })}
    </div>
  );
}

function issueFor(issues: Array<{ field: string; message: string }>, field: string, attempted: boolean, t: UiTranslator) {
  const issue = issues.find((candidate) => candidate.field === field);
  return attempted && issue ? t(issue.message) : undefined;
}

export function BasicsStep({
  draft,
  catalog,
  attempted,
  issues,
  onChange,
  packages,
  locale,
}: {
  draft: PackageDraft;
  catalog: PackageCatalog;
  attempted: boolean;
  issues: Array<{ field: string; message: string }>;
  onChange: (draft: PackageDraft) => void;
  packages: FinanceRecord[];
  locale: string;
}) {
  const t = useT();
  const type = findType(catalog, draft.packageType);
  if (!type) return null;
  const cents = priceCents(draft.price);
  const monthly = monthlyEquivalentCents(draft.billingPeriod, cents);
  const perVisit = perVisitCents(draft);
  const visits = draft.fields["group_classes.visits"] as QuotaValue;
  const suffix = draft.packageType === "membership" ? t(`pkgPriceSuffix_${draft.billingPeriod}`) : t("pkgPriceSuffixTotal");
  const setField = (key: string, value: unknown) => onChange({ ...draft, fields: { ...draft.fields, [key]: value } });

  return (
    <div className="space-y-5">
      <LockStrip type={type} />
      <FieldShell label={t("pkgName")} htmlFor="pkg-name" error={issueFor(issues, "name", attempted, t)}>
        <input
          id="pkg-name"
          className="h-11 w-full rounded-[0.9rem] px-3 text-sm outline-none"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          maxLength={60}
          placeholder={t(`${typeLabelKey(draft.packageType)}NameExample`)}
          value={draft.name}
          onChange={(event) => onChange({ ...draft, name: event.target.value })}
        />
      </FieldShell>
      <FieldShell label={`${t("pkgDescription")} · ${t("pkgOptional")}`} htmlFor="pkg-description" hint={t("pkgDescriptionHint", { count: 280 - draft.description.length })}>
        <textarea
          id="pkg-description"
          rows={2}
          maxLength={280}
          className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          value={draft.description}
          onChange={(event) => onChange({ ...draft, description: event.target.value })}
        />
      </FieldShell>

      {type.billing_model === "recurring" ? (
        <FieldShell label={t("pkgBillingPeriod")} hint={draft.billingPeriod === "custom" ? t("pkgBillingPeriodCustomHint") : undefined}>
          <Segmented
            label={t("pkgBillingPeriod")}
            value={draft.billingPeriod}
            options={type.billing_periods.map((period) => ({ value: period, label: t(`pkgBilling_${period}`) }))}
            onChange={(period) => onChange(changeBillingPeriod(type, draft, period))}
          />
        </FieldShell>
      ) : null}

      {draft.packageType === "class_pack" ? (
        <FieldShell label={t("pkgVisitsCount")} error={issueFor(issues, "group_classes.visits", attempted, t)}>
          <Stepper label={t("pkgVisitsCount")} value={typeof visits.limit === "number" ? visits.limit : 10} min={1} onChange={(limit) => setField("group_classes.visits", { ...visits, limit })} suffix={t("pkgVisits")} />
        </FieldShell>
      ) : null}

      {type.billing_model === "one_off" ? (
        <FieldShell label={t(draft.packageType === "trial" ? "pkgDuration" : "pkgValidity")} hint={t("pkgValidityHint")} error={issueFor(issues, "terms.validity", attempted, t)}>
          <DurationControl
            label={t("pkgValidity")}
            value={(draft.fields["terms.validity"] as DurationValue | null) ?? null}
            presets={VALIDITY_PRESETS[draft.packageType] ?? VALIDITY_PRESETS.class_pack}
            onChange={(value) => setField("terms.validity", value)}
          />
        </FieldShell>
      ) : null}

      <FieldShell
        label={t("pkgPrice")}
        htmlFor="pkg-price"
        error={issueFor(issues, "price", attempted, t)}
        hint={monthly !== null ? t("pkgMonthlyEquivalent", { amount: money(locale, monthly) }) : perVisit !== null ? t("pkgPerVisit", { amount: money(locale, perVisit) }) : undefined}
      >
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold" style={{ color: "var(--dim)" }}>€</span>
          <input
            id="pkg-price"
            inputMode="decimal"
            className="h-11 w-full max-w-[10rem] rounded-[0.9rem] px-3 text-sm outline-none"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
            value={draft.price}
            onChange={(event) => onChange({ ...draft, price: event.target.value.replace(/[^\d.,]/g, "") })}
          />
          <span className="text-sm" style={{ color: "var(--dim)" }}>{suffix}</span>
        </div>
      </FieldShell>

      {draft.packageType === "trial" ? (
        <>
          <FieldShell label={t("pkgFieldTermsNewMembersOnly")} hint={t("pkgFieldTermsNewMembersOnlyHint")}>
            <div className="flex items-center justify-between gap-3 rounded-xl px-3 py-2" style={{ background: "var(--bg-soft)" }}>
              <span className="text-sm" style={{ color: "var(--text-soft)" }}>{draft.fields["terms.new_members_only"] ? t("pkgYes") : t("pkgNo")}</span>
              <Toggle label={t("pkgFieldTermsNewMembersOnly")} checked={draft.fields["terms.new_members_only"] === true} onChange={(value) => setField("terms.new_members_only", value)} />
            </div>
          </FieldShell>
          <FieldShell label={`${t("pkgFieldTermsConversionPackageId")} · ${t("pkgOptional")}`} htmlFor="pkg-conversion" hint={t("pkgFieldTermsConversionPackageIdHint")}>
            <select
              id="pkg-conversion"
              className="h-11 w-full rounded-[0.9rem] px-3 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={typeof draft.fields["terms.conversion_package_id"] === "string" ? String(draft.fields["terms.conversion_package_id"]) : ""}
              onChange={(event) => setField("terms.conversion_package_id", event.target.value || null)}
            >
              <option value="">{t("pkgNone")}</option>
              {packages.filter((pkg) => pkg.active !== false && pkg.package_type === "membership").map((pkg) => (
                <option key={String(pkg.id)} value={String(pkg.id)}>{String(pkg.name)}</option>
              ))}
            </select>
          </FieldShell>
        </>
      ) : null}
    </div>
  );
}

export function IncludedStep({
  draft,
  catalog,
  attempted,
  issues,
  onField,
  classTypes,
}: {
  draft: PackageDraft;
  catalog: PackageCatalog;
  attempted: boolean;
  issues: Array<{ field: string; message: string }>;
  onField: (key: string, value: unknown) => void;
  classTypes: ClassTypeRecord[];
}) {
  const t = useT();
  const type = findType(catalog, draft.packageType);
  if (!type) return null;
  const classesLocked = isFieldLocked(type, "group_classes.included");
  const showClasses = moduleEnabled(catalog, "group_classes") || draft.fields["group_classes.included"] === true;
  const showCoaching = moduleEnabled(catalog, "online_coaching") || draft.fields["online_coaching.included"] === true;
  const visits = draft.fields["group_classes.visits"] as QuotaValue;
  const serviceError = !anyServiceIncluded(draft.fields) && attempted ? t("pkgErrorServiceRequired") : undefined;
  const coachingError = issueFor(issues, "online_coaching.included", attempted, t);

  return (
    <div className="space-y-4">
      {showClasses ? (
        <ServiceCard
          title={t(sectionLabelKey("group_classes"))}
          description={t("pkgServiceGroupClassesHint")}
          checked={draft.fields["group_classes.included"] === true}
          locked={classesLocked}
          onToggle={(value) => onField("group_classes.included", value)}
        >
          {draft.packageType !== "class_pack" && draft.packageType !== "drop_in" ? (
            <FieldShell label={t("pkgFieldGroupClassesVisits")} error={issueFor(issues, "group_classes.visits", attempted, t)}>
              <QuotaControl type={type} fieldKey="group_classes.visits" value={visits} onChange={(value) => onField("group_classes.visits", value)} label={t("pkgFieldGroupClassesVisits")} unitLabel={t("pkgVisits")} />
            </FieldShell>
          ) : null}
          <FieldShell label={t("pkgFieldGroupClassesClassTypes")} hint={t("pkgFieldGroupClassesClassTypesHint")}>
            <ClassTypeScope value={draft.fields["group_classes.class_types"]} classTypes={classTypes} onChange={(value) => {
              const limits = (draft.fields["group_classes.class_type_limits"] as Array<{ id: string }>) ?? [];
              onField("group_classes.class_types", value);
              if (Array.isArray(value)) onField("group_classes.class_type_limits", limits.filter((limit) => value.includes(limit.id)));
            }} />
          </FieldShell>
        </ServiceCard>
      ) : null}

      {showCoaching ? (
        <ServiceCard
          title={t(sectionLabelKey("online_coaching"))}
          description={t("pkgServiceOnlineCoachingHint")}
          checked={draft.fields["online_coaching.included"] === true}
          locked={false}
          onToggle={(value) => onField("online_coaching.included", value)}
          error={coachingError}
        >
          {(["online_coaching.assigned_programming", "online_coaching.messaging"] as const).map((key) => (
            <label key={key} className="flex min-h-[2.75rem] items-center gap-3 rounded-xl px-3" style={{ background: "var(--bg-soft)" }}>
              <input type="checkbox" className="h-5 w-5" checked={draft.fields[key] === true} onChange={(event) => onField(key, event.target.checked)} />
              <span className="text-sm" style={{ color: "var(--text)" }}>{t(fieldLabelKey(key))}</span>
            </label>
          ))}
        </ServiceCard>
      ) : null}

      {serviceError ? <p role="alert" className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{serviceError}</p> : null}
    </div>
  );
}

function ServiceCard({
  title,
  description,
  checked,
  locked,
  onToggle,
  children,
  error,
}: {
  title: string;
  description: string;
  checked: boolean;
  locked: boolean;
  onToggle: (value: boolean) => void;
  children: React.ReactNode;
  error?: string;
}) {
  const t = useT();
  return (
    <fieldset className="rounded-2xl" style={{ border: `1px solid ${checked ? "var(--primary)" : "var(--border)"}`, background: "var(--panel)" }}>
      <legend className="sr-only">{title}</legend>
      <div className="flex items-start justify-between gap-4 p-4">
        <div>
          <p className="text-base font-semibold" style={{ color: "var(--text)" }}>{title}</p>
          <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>{description}</p>
        </div>
        {locked ? (
          <span className="rounded-full px-3 py-1 text-xs font-semibold" title={t("pkgLockReasonTypeService")} style={{ background: "var(--bg-soft)", color: "var(--text-soft)" }}>🔒 {t("pkgIncluded")}</span>
        ) : (
          <Toggle label={title} checked={checked} onChange={onToggle} />
        )}
      </div>
      {checked ? <div className="space-y-5 px-4 pb-4">{children}</div> : null}
      {error ? <p role="alert" className="px-4 pb-4 text-xs font-semibold" style={{ color: "var(--danger)" }}>{error}</p> : null}
    </fieldset>
  );
}

function ReviewStep({
  catalog,
  draft,
  changed,
  classTypes,
  onEdit,
  onAdvanced,
}: {
  catalog: PackageCatalog;
  draft: PackageDraft;
  changed: string[];
  classTypes: ClassTypeRecord[];
  onEdit: (step: "type" | "basics" | "included" | "review") => void;
  onAdvanced: () => void;
}) {
  const t = useT();
  const type = findType(catalog, draft.packageType);
  const steps = wizardSteps(draft.packageType);
  const issues = draftIssues(draft);
  const rows = useMemo(
    () => [
      { step: "type" as const, label: t("pkgStep_type"), value: t(typeLabelKey(draft.packageType)) },
      { step: "basics" as const, label: t("pkgStep_basics"), value: [draft.name || t("pkgUntitled"), draft.packageType === "membership" ? t(`pkgBilling_${draft.billingPeriod}`) : null].filter(Boolean).join(" · ") },
      ...(steps.includes("included")
        ? [{ step: "included" as const, label: t("pkgStep_included"), value: [draft.fields["group_classes.included"] ? t(sectionLabelKey("group_classes")) : null, draft.fields["online_coaching.included"] ? t(sectionLabelKey("online_coaching")) : null].filter(Boolean).join(" · ") }]
        : []),
    ],
    [draft, steps, t],
  );

  return (
    <div className="space-y-5">
      <MemberPreview draft={draft} classTypes={classTypes} />
      <dl className="divide-y rounded-2xl" style={{ border: "1px solid var(--border)", background: "var(--panel)" }}>
        {rows.map((row) => (
          <div key={row.step} className="flex items-center justify-between gap-3 px-4 py-3" style={{ borderColor: "var(--border)" }}>
            <div>
              <dt className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{row.label}</dt>
              <dd className="text-sm" style={{ color: "var(--text)" }}>{row.value}</dd>
            </div>
            <button type="button" className="rounded-full px-3 py-2 text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => onEdit(row.step)}>
              {t("pkgChange")}
            </button>
          </div>
        ))}
        <div className="flex items-center justify-between gap-3 px-4 py-3" style={{ borderColor: "var(--border)" }}>
          <div>
            <dt className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("pkgAdvancedSettings")}</dt>
            <dd className="text-sm" style={{ color: "var(--text)" }}>
              {changed.length === 0 ? t("pkgNoChangesFromSuggested") : t("pkgChangesFromSuggested", { count: changed.length })}
            </dd>
            {changed.length > 0 ? (
              <ul className="mt-1 list-disc ps-5 text-xs" style={{ color: "var(--dim)" }}>
                {changed.map((key) => <li key={key}>{t(fieldLabelKey(key))}</li>)}
              </ul>
            ) : null}
          </div>
          <button type="button" className="rounded-full px-3 py-2 text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={onAdvanced}>
            {t("pkgChange")}
          </button>
        </div>
      </dl>
      {type ? <LockStrip type={type} /> : null}
      {issues.length > 0 ? (
        <ul role="alert" className="space-y-1 rounded-2xl p-4 text-sm" style={{ background: "color-mix(in srgb, var(--danger) 8%, transparent)", color: "var(--danger)" }}>
          {issues.map((issue) => <li key={issue.field}>{t(issue.message)}</li>)}
        </ul>
      ) : null}
    </div>
  );
}
