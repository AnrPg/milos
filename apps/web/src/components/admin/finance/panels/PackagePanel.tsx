"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { SemanticLabel } from "@/components/semantic-label";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  fetchFinanceMembers,
  fetchFinancePackage,
  retireFinancePackage,
  updateFinancePackage,
  type FinanceRecord,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { BasicsStep, IncludedStep } from "@/components/admin/finance/packages/PackageWizard";
import { AdvancedSettings, LockStrip, MemberPreview, PackageContractDetails, previewContext, useT } from "@/components/admin/finance/packages/package-ui";
import { usePackageAuthoring } from "@/components/admin/finance/packages/use-package-authoring";
import {
  applyLocks,
  changedFields,
  draftFromPackage,
  draftIssues,
  findType,
  resetAll,
  toPackageRequest,
  typeLabelKey,
  wizardSteps,
  type PackageDraft,
} from "@/components/admin/finance/packages/package-catalog";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

export function PackagePanel({
  packageId,
  packages,
  onClose,
  onDuplicate,
}: {
  packageId: string;
  packages: FinanceRecord[];
  onClose: () => void;
  onDuplicate: (draft: PackageDraft) => void;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const t = useT();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();

  const packageQuery = useQuery({
    queryKey: ["admin", "finance", "package", packageId],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackage(token, packageId),
  });

  const pkg = packageQuery.data?.package ?? null;
  const { catalog, classTypes, locations } = usePackageAuthoring(token);

  const [form, setForm] = useState<FinanceRecord | null>(null);
  const [draft, setDraft] = useState<PackageDraft | null>(null);
  const [attempted, setAttempted] = useState(false);
  const [showReconciliation, setShowReconciliation] = useState(false);
  const [replacements, setReplacements] = useState<Record<string, string>>({});
  const editing = form !== null;
  const retiring = Boolean(editing && pkg?.active !== false && form?.active === false);

  const impactQuery = useQuery({
    queryKey: ["admin", "finance", "package-retirement-impact", packageId],
    enabled: Boolean(token && retiring),
    queryFn: () => fetchFinanceMembers(token, { limit: "5000" }),
  });

  const affectedMembers = (impactQuery.data?.members ?? []).filter((member) => {
    const subscription = member.active_package_subscription as FinanceRecord | null | undefined;
    return field(subscription, "membership_package_id") === packageId;
  });
  const affectedByRole = affectedMembers.reduce<Record<string, number>>((counts, member) => {
    const membership = member.membership as FinanceRecord | null | undefined;
    const role = field(membership, "user_type_snapshot") || field(member, "identity_role");
    if (role) counts[role] = (counts[role] ?? 0) + 1;
    return counts;
  }, {});
  const affectedRoles = Object.keys(affectedByRole);
  const replacementOptions = packages.filter((candidate) => candidate.active !== false && field(candidate, "id") !== packageId);

  const type = catalog && draft ? findType(catalog, draft.packageType) : undefined;

  function startEdit() {
    if (!pkg || !catalog) return;
    setForm({ active: pkg.active !== false });
    setDraft(draftFromPackage(catalog, pkg));
    setAttempted(false);
  }

  function cancelEdit() {
    setForm(null);
    setDraft(null);
    setShowReconciliation(false);
  }

  function setField(key: string, value: unknown) {
    setDraft((previous) => {
      if (!previous || !catalog) return previous;
      const current = findType(catalog, previous.packageType);
      const fields = { ...previous.fields, [key]: value };
      return { ...previous, fields: current ? applyLocks(current, fields) : fields };
    });
  }

  const updateMutation = useMutation({
    mutationFn: () => {
      if (!form || !draft || !catalog) throw new Error(i18n("noForm2807394"));
      return updateFinancePackage(token, packageId, {
        ...toPackageRequest(catalog, draft),
        active: form.active !== false,
      });
    },
    onSuccess: async () => {
      setForm(null);
      setDraft(null);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "package", packageId] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] });
    },
  });

  const retireMutation = useMutation({
    mutationFn: () => retireFinancePackage(token, packageId, replacements),
    onSuccess: async () => {
      setShowReconciliation(false);
      setReplacements({});
      setForm(null);
      setDraft(null);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["admin", "finance", "package", packageId] }),
        queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] }),
        queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] }),
      ]);
    },
  });

  function saveChanges() {
    setAttempted(true);
    if (draft && draftIssues(draft).length > 0) return;
    if (retiring && !impactQuery.isSuccess) return;

    if (retiring && affectedMembers.length > 0) {
      setShowReconciliation(true);
      return;
    }

    updateMutation.mutate();
  }

  return (
    <SidePanel
      title={pkg ? field(pkg, "name", field(pkg, "code")) : i18n("package7431e3d")}
      subtitle={i18n("membershipPackage4602237")}
      onClose={onClose}
      width="md:max-w-[680px]"
      footer={
        editing ? (
          <div className="flex gap-3">
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              disabled={updateMutation.isPending || retireMutation.isPending || (retiring && !impactQuery.isSuccess)}
              onClick={saveChanges}
              type="button"
            >
              {updateMutation.isPending || (retiring && impactQuery.isFetching) ? i18n("checking820d600") : i18n("saveChanges179359b")}
            </button>
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              onClick={cancelEdit}
              type="button"
            >
              {i18n("cancel77dfd21")}
            </button>
          </div>
        ) : (
          <div className="flex flex-wrap gap-3">
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              disabled={!catalog}
              onClick={startEdit}
              type="button"
            >
              {i18n("editPackage77c0543")}
            </button>
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ color: "var(--primary)" }}
              disabled={!catalog || !pkg}
              onClick={() => {
                if (!catalog || !pkg) return;
                const copy = draftFromPackage(catalog, pkg);
                onDuplicate({ ...copy, name: t("pkgCopyName", { name: copy.name }) });
              }}
              type="button"
            >
              {t("pkgDuplicate")}
            </button>
          </div>
        )
      }
    >
      {packageQuery.isLoading ? (
        <p style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
      ) : !pkg ? (
        <p style={{ color: "var(--primary-strong)" }}>{i18n("packageNotFound764673f")}</p>
      ) : editing && form && draft && catalog && type ? (
        <div className="space-y-6">
          <p className="rounded-2xl px-4 py-3 text-sm" style={{ background: "color-mix(in srgb, var(--primary) 8%, transparent)", color: "var(--text-soft)" }}>
            {t("pkgEditSnapshotNotice")}
          </p>
          <div className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)" }}>
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("pkgStep_type")}: {t(typeLabelKey(draft.packageType))}</span>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t("pkgTypeChangeHint")}</span>
          </div>
          <section className="space-y-4">
            <h3 className="text-base font-semibold" style={{ color: "var(--text)" }}>{t("pkgStep_basics")}</h3>
            <BasicsStep draft={draft} catalog={catalog} attempted={attempted} issues={draftIssues(draft)} onChange={(next) => setDraft({ ...next, fields: applyLocks(type, next.fields) })} packages={packages} locale={uiLocale} />
          </section>
          {wizardSteps(draft.packageType).includes("included") ? (
            <section className="space-y-4">
              <h3 className="text-base font-semibold" style={{ color: "var(--text)" }}>{t("pkgStep_included")}</h3>
              <IncludedStep draft={draft} catalog={catalog} attempted={attempted} issues={draftIssues(draft)} onField={setField} classTypes={classTypes} />
            </section>
          ) : null}
          <details className="rounded-2xl" style={{ border: "1px solid var(--border)" }}>
            <summary className="cursor-pointer px-4 py-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
              ⚙ {t("pkgAdvancedSettings")}{changedFields(catalog, draft).length > 0 ? ` · ${changedFields(catalog, draft).length}` : ""}
            </summary>
            <div className="px-4 pb-4">
              <AdvancedSettings
                catalog={catalog}
                type={type}
                draft={draft}
                context={{ classTypes, packages, locations }}
                changedCount={changedFields(catalog, draft).length}
                onFieldChange={setField}
                onResetAll={() => setDraft(resetAll(catalog, draft))}
              />
            </div>
          </details>
          <MemberPreview draft={draft} classTypes={classTypes} compact {...previewContext(catalog, draft, packages)} />
          <label className="flex items-center gap-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            <input
              type="checkbox"
              checked={form.active !== false}
              onChange={(e) => {
                setForm({ ...form, active: e.target.checked });
                if (e.target.checked) setShowReconciliation(false);
              }}
            />
            {i18n("activea733b80")}
          </label>
          {updateMutation.error instanceof Error && (
            <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{localizeError(updateMutation.error, i18n)}</p>
          )}
          {impactQuery.isError ? (
            <p className="text-sm" style={{ color: "var(--danger)" }}>{i18n("couldNotCheckCurrentSubscribersThePackageWilldd8ac35")}</p>
          ) : null}
        </div>
      ) : (
        <div className="space-y-4">
          {catalog ? <MemberPreview draft={draftFromPackage(catalog, pkg)} classTypes={classTypes} {...previewContext(catalog, draftFromPackage(catalog, pkg), packages)} /> : null}
          <div className="grid gap-4 sm:grid-cols-2">
            <Stat label={t("pkgStep_type")} value={t(typeLabelKey(field(pkg, "package_type", "membership")))} />
            <Stat label={i18n("codeadac693")} value={field(pkg, "code")} />
            <Stat label={i18n("billingPeriodda59f5a")} value={t(`pkgBilling_${field(pkg, "billing_period", "monthly")}`)} />
            <Stat label={i18n("basePrice708f3d8")} value={money(uiLocale, pkg.base_price_cents)} />
            <Stat label={i18n("statusbae7d5b")} value={pkg.active !== false ? i18n("activea733b80") : i18n("inactive09af574")} />
            <Stat label={t("pkgAdvancedSettings")} value={Array.isArray(pkg.changed_fields) && pkg.changed_fields.length > 0 ? t("pkgChangesFromSuggested", { count: pkg.changed_fields.length }) : t("pkgNoChangesFromSuggested")} />
          </div>
          {catalog ? <PackageContractDetails catalog={catalog} draft={draftFromPackage(catalog, pkg)} packages={packages} /> : null}
          {Array.isArray(pkg.tags) && (pkg.tags as string[]).length > 0 && (
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.18em] mb-2" style={{ color: "var(--dim)" }}>{i18n("tags848eed0")}</p>
              <div className="flex flex-wrap gap-2">
                {(pkg.tags as string[]).map((tag) => (
                  <span key={tag} className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }}>{tag}</span>
                ))}
              </div>
            </div>
          )}
          {catalog && findType(catalog, field(pkg, "package_type", "membership")) ? (
            <div className="pt-6">
              <LockStrip type={findType(catalog, field(pkg, "package_type", "membership"))!} />
            </div>
          ) : null}
        </div>
      )}
      {showReconciliation ? (
        <div className="fixed inset-0 z-[90] grid place-items-center bg-[var(--scrim)] p-4" role="dialog" aria-modal="true" aria-labelledby="package-retirement-title">
          <div className="w-full max-w-lg rounded-[1.75rem] p-6 shadow-2xl" style={{ background: "var(--bg)", border: "1px solid var(--border-strong)" }}>
            <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--warning)" }}>{i18n("requiredReconciliationd3a0ead")}</p>
            <h3 id="package-retirement-title" className="mt-2 text-xl font-semibold" style={{ color: "var(--text)" }}>{i18n("moveCurrentSubscribersBeforeRetiringThisPackage8116b72")}</h3>
            <p className="mt-2 text-sm leading-6" style={{ color: "var(--dim)" }}>
              {i18n("packageSubscribersRequireReplacement", {count: affectedMembers.length})}
            </p>
            <div className="mt-5 space-y-3">
              {affectedRoles.map((role) => (
                <label key={role} className="block space-y-1">
                  <span className="text-xs font-semibold capitalize" style={{ color: "var(--text-soft)" }}><SemanticLabel value={role} /> {i18n("replacement898d79a")} {i18n("userCount", { count: affectedByRole[role] })}</span>
                  <select
                    className="w-full rounded-xl px-3 py-2 text-sm"
                    style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                    value={replacements[role] ?? ""}
                    onChange={(event) => setReplacements((current) => ({ ...current, [role]: event.target.value }))}
                  >
                    <option value="">{i18n("selectReplacement2a95f76")}</option>
                    {replacementOptions.map((candidate) => (
                      <option key={field(candidate, "id")} value={field(candidate, "id")}>
                        {field(candidate, "name", field(candidate, "code"))}
                      </option>
                    ))}
                  </select>
                </label>
              ))}
            </div>
            {replacementOptions.length === 0 ? <p className="mt-3 text-sm" style={{ color: "var(--danger)" }}>{i18n("createAnotherActivePackageBeforeRetiringThisOne619ea88")}</p> : null}
            {retireMutation.error instanceof Error ? <p className="mt-3 text-sm" style={{ color: "var(--danger)" }}>{localizeError(retireMutation.error, i18n)}</p> : null}
            <div className="mt-6 flex flex-wrap gap-3">
              <button
                type="button"
                className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-40"
                style={{ background: "var(--primary)", color: "var(--bg)" }}
                disabled={retireMutation.isPending || affectedRoles.some((role) => !replacements[role])}
                onClick={() => retireMutation.mutate()}
              >
                {retireMutation.isPending ? i18n("reconciling4bfc2e9") : i18n("reassignAndRetirec6fc878")}
              </button>
              <button type="button" className="rounded-full px-5 py-2 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={() => setShowReconciliation(false)}>
                {i18n("keepPackageActivef655e90")}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </SidePanel>
  );
}

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</p>
      <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{value || "—"}</p>
    </div>
  );
}
