"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
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
import {
  EntitlementEditor,
  entitlementDraft,
  entitlementParams,
  type EntitlementDraft,
} from "@/components/admin/finance/shared/EntitlementEditor";

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
}: {
  packageId: string;
  packages: FinanceRecord[];
  onClose: () => void;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();

  const packageQuery = useQuery({
    queryKey: ["admin", "finance", "package", packageId],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackage(token, packageId),
  });

  const pkg = packageQuery.data?.package ?? null;

  const [form, setForm] = useState<FinanceRecord | null>(null);
  const [entitlement, setEntitlement] = useState<EntitlementDraft | null>(null);
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

  function startEdit() {
    if (!pkg) return;
    setForm({
      name: field(pkg, "name"),
      description: field(pkg, "description"),
      family: field(pkg, "family"),
      billing_period: field(pkg, "billing_period"),
      base_price_cents: pkg.base_price_cents ?? 0,
      tags: Array.isArray(pkg.tags) ? (pkg.tags as string[]).join(", ") : "",
      active: pkg.active !== false,
    });
    setEntitlement(entitlementDraft(pkg.params));
  }

  const updateMutation = useMutation({
    mutationFn: () => {
      if (!form) throw new Error(i18n("noForm2807394"));
      const tags = typeof form.tags === "string"
        ? (form.tags as string).split(",").map((t) => t.trim()).filter(Boolean)
        : [];
      if (!entitlement) throw new Error(i18n("noEntitlementContract1f18377"));
      return updateFinancePackage(token, packageId, {
        ...form,
        tags,
        params: entitlementParams(entitlement),
      });
    },
    onSuccess: async () => {
      setForm(null);
      setEntitlement(null);
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
      setEntitlement(null);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["admin", "finance", "package", packageId] }),
        queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] }),
        queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] }),
      ]);
    },
  });

  function saveChanges() {
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
              onClick={() => { setForm(null); setEntitlement(null); setShowReconciliation(false); }}
              type="button"
            >
              {i18n("cancel77dfd21")}
            </button>
          </div>
        ) : (
          <button
            className="rounded-full px-5 py-2 text-sm font-semibold"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            onClick={startEdit}
            type="button"
          >
            {i18n("editPackage77c0543")}
          </button>
        )
      }
    >
      {packageQuery.isLoading ? (
        <p style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
      ) : !pkg ? (
        <p style={{ color: "var(--primary-strong)" }}>{i18n("packageNotFound764673f")}</p>
      ) : editing && form ? (
        <div className="space-y-4">
          <Field label={i18n("name709a232")}>
            <input
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={String(form.name ?? "")}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
            />
          </Field>
          <Field label={i18n("description55f8ebc")}>
            <input
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={String(form.description ?? "")}
              onChange={(e) => setForm({ ...form, description: e.target.value })}
            />
          </Field>
          <div className="grid gap-4 md:grid-cols-2">
            <Field label={i18n("family4efb6cb")}>
              <select
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={String(form.family ?? "")}
                onChange={(e) => setForm({ ...form, family: e.target.value })}
              >
                {["unlimited", "limited-visits", "personal-programming", "hybrid"].map((v) => (
                  <option key={v} value={v}>{v}</option>
                ))}
              </select>
            </Field>
            <Field label={i18n("billingPeriodda59f5a")}>
              <select
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={String(form.billing_period ?? "")}
                onChange={(e) => setForm({ ...form, billing_period: e.target.value })}
              >
                {["monthly", "quarterly", "annual", "custom"].map((v) => (
                  <option key={v} value={v}>{v}</option>
                ))}
              </select>
            </Field>
          </div>
          <Field label={i18n("basePriceEuree0693f")}>
            <input
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              type="number"
              value={Number(form.base_price_cents ?? 0) / 100}
              onChange={(e) => setForm({ ...form, base_price_cents: Math.round(Number(e.target.value) * 100) })}
            />
          </Field>
          <Field label={i18n("tagsCommaSeparated32bf672")}>
            <input
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={String(form.tags ?? "")}
              onChange={(e) => setForm({ ...form, tags: e.target.value })}
            />
          </Field>
          {entitlement ? <EntitlementEditor value={entitlement} onChange={setEntitlement} /> : null}
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
            <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{updateMutation.error.message}</p>
          )}
          {impactQuery.isError ? (
            <p className="text-sm" style={{ color: "var(--danger)" }}>{i18n("couldNotCheckCurrentSubscribersThePackageWilldd8ac35")}</p>
          ) : null}
        </div>
      ) : (
        <div className="space-y-4">
          <Stat label={i18n("codeadac693")} value={field(pkg, "code")} />
          <Stat label={i18n("name709a232")} value={field(pkg, "name")} />
          <Stat label={i18n("family4efb6cb")} value={field(pkg, "family")} />
          <Stat label={i18n("billingPeriodda59f5a")} value={field(pkg, "billing_period")} />
          <Stat label={i18n("basePrice708f3d8")} value={money(uiLocale, pkg.base_price_cents)} />
          <Stat label={i18n("statusbae7d5b")} value={pkg.active !== false ? i18n("activea733b80") : i18n("inactive09af574")} />
          <EntitlementSummary params={pkg.params} />
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
        </div>
      )}
      {showReconciliation ? (
        <div className="fixed inset-0 z-[90] grid place-items-center bg-black/70 p-4" role="dialog" aria-modal="true" aria-labelledby="package-retirement-title">
          <div className="w-full max-w-lg rounded-[1.75rem] p-6 shadow-2xl" style={{ background: "var(--bg)", border: "1px solid var(--border-strong)" }}>
            <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--warning)" }}>{i18n("requiredReconciliationd3a0ead")}</p>
            <h3 id="package-retirement-title" className="mt-2 text-xl font-semibold" style={{ color: "var(--text)" }}>{i18n("moveCurrentSubscribersBeforeRetiringThisPackage8116b72")}</h3>
            <p className="mt-2 text-sm leading-6" style={{ color: "var(--dim)" }}>
              {affectedMembers.length} {i18n("currentSubscriber5f16e61")}{affectedMembers.length === 1 ? " is" : i18n("sAre81c69ca")} {i18n("usingThisPackageChooseAnActiveReplacementFor1114469")}
            </p>
            <div className="mt-5 space-y-3">
              {affectedRoles.map((role) => (
                <label key={role} className="block space-y-1">
                  <span className="text-xs font-semibold capitalize" style={{ color: "var(--text-soft)" }}>{role} {i18n("replacement898d79a")} {affectedByRole[role]} {i18n("user12dea96")}{affectedByRole[role] === 1 ? "" : i18n("sa0f1490")}</span>
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
            {retireMutation.error instanceof Error ? <p className="mt-3 text-sm" style={{ color: "var(--danger)" }}>{retireMutation.error.message}</p> : null}
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

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</span>
      {children}
    </label>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</p>
      <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{value || "—"}</p>
    </div>
  );
}

function EntitlementSummary({ params }: { params: unknown }) {
  const i18n = useUiTranslations();
  const draft = entitlementDraft(params);
  return (
    <div className="space-y-2 rounded-xl p-4" style={{ background: "var(--bg-soft)" }}>
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("entitlements7de7578")}</p>
      <p className="text-sm"><strong>{i18n("channelsb727b80")}</strong> {draft.channels.join(", ") || i18n("none6eef664")}</p>
      <p className="text-sm"><strong>{i18n("capabilities92761fd")}</strong> {draft.capabilities.join(", ") || i18n("none6eef664")}</p>
      <p className="text-sm"><strong>{i18n("classVisits6c6fff6")}</strong> {draft.classVisitLimit} / {draft.classVisitPeriod.replaceAll("_", " ")}</p>
      {draft.capabilities.includes("receive_coaching_touchpoints") ? (
        <p className="text-sm"><strong>{i18n("coachingTouchpoints4a9fb40")}</strong> {draft.coachingTouchpointLimit} / {draft.coachingTouchpointPeriod.replaceAll("_", " ")}</p>
      ) : null}
    </div>
  );
}
