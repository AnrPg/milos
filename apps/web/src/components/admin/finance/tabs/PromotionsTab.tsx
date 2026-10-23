"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";

import { createPromotionCampaign, fetchPromotionCampaigns, type FinanceRecord } from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { CampaignPanel } from "@/components/admin/finance/panels/CampaignPanel";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { SPARK_ACTIVE_STYLE, SPARK_CREATE_STYLE } from "@/lib/spark";
import { DateInput } from "@/components/ui/DateInput";
import { listAdminLocations } from "@/api/facility";
import { AppliesToBranches, defaultAppliesTo, showsAppliesTo } from "@/components/admin/AppliesToBranches";
import { membershipLocationScope, toLocationScope, type LocationScope, type LocationScopePayload } from "@/lib/location-scope";
import { BranchCoverageBadge } from "@/components/admin/BranchFilter";
import type { FacilityLocation } from "@/api/facility";
import { useSelectedMembershipRole } from "@/lib/membership-role";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

const BLANK = { name: "", description: "", starts_on: "", ends_on: "", active: true };

/** `locationIds`: the page branch filter (ADR-186 §7); promotions valid there or everywhere show. */
export function PromotionsTab({ locationIds }: { locationIds?: string } = {}) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const router = useRouter();
  const searchParams = useSearchParams();

  const openCampaignId = searchParams.get("campaign");
  const showNew = searchParams.get("new") === "true";

  const setParam = useCallback(
    (key: string, value: string | null) => {
      const params = new URLSearchParams(searchParams.toString());
      if (value === null) params.delete(key);
      else params.set(key, value);
      router.replace(`?${params.toString()}`, { scroll: false });
    },
    [router, searchParams],
  );

  const campaignsQuery = useQuery({
    queryKey: ["admin", "finance", "promotions", ...(locationIds ? [locationIds] : [])],
    enabled: Boolean(token),
    queryFn: () => fetchPromotionCampaigns(token, locationIds),
  });

  const campaigns = campaignsQuery.data?.promotion_campaigns ?? [];
  const activeCampaigns = campaigns.filter((campaign) => campaign.active !== false);
  const inactiveCampaigns = campaigns.filter((campaign) => campaign.active === false);
  const openCampaign = campaigns.find((c) => field(c, "id") === openCampaignId) ?? null;

  const [form, setForm] = useState(BLANK);
  // ADR-186 §8: «Ισχύει για» — one promotion valid at the chosen branches.
  const { membership } = useSelectedMembershipRole();
  const everywhere = membershipLocationScope(membership) === "all";
  const locationsQuery = useQuery({
    queryKey: ["admin", "locations"],
    enabled: Boolean(token),
    queryFn: () => listAdminLocations(token),
  });
  const manyBranches = showsAppliesTo(locationsQuery.data);
  const [branchDraft, setBranchDraft] = useState<LocationScope | null>(null);
  // A new promotion defaults to the page filter, when one is set (§8).
  const pageFilter = locationIds ? locationIds.split(",") : [];
  const branches: LocationScope =
    branchDraft ??
    (pageFilter.length > 0
      ? defaultAppliesTo(locationsQuery.data, pageFilter)
      : everywhere
        ? "all"
        : defaultAppliesTo(locationsQuery.data));

  const createMutation = useMutation({
    mutationFn: () =>
      createPromotionCampaign(token, {
        ...form,
        starts_on: form.starts_on || null,
        ends_on: form.ends_on || null,
        ...(manyBranches
          ? branches === "all"
            ? { all_locations: true }
            : { all_locations: false, location_ids: branches }
          : {}),
      }),
    onSuccess: async () => {
      setForm(BLANK);
      setBranchDraft(null);
      setParam("new", null);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "promotions"] });
    },
  });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
          {i18n("activeCampaignCount", {count: activeCampaigns.length})}
        </p>
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={SPARK_CREATE_STYLE}
          onClick={() => setParam("new", "true")}
          type="button"
        >
          {i18n("newCampaignb18ba62")}
        </button>
      </div>

      <div className="rounded-[2rem] overflow-hidden" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {campaignsQuery.isLoading ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
        ) : activeCampaigns.length === 0 ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{i18n("noActiveCampaignse543337")}</p>
        ) : (
          <CampaignRows campaigns={activeCampaigns} locations={locationsQuery.data} onOpen={(id) => setParam("campaign", id)} />
        )}
      </div>

      {inactiveCampaigns.length > 0 ? (
        <details className="overflow-hidden rounded-2xl" style={{ border: "1px solid var(--border)" }}>
          <summary className="cursor-pointer px-5 py-3 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("archivedPromotions314dfb3")} {inactiveCampaigns.length}
          </summary>
          <div style={{ background: "var(--panel)", borderTop: "1px solid var(--border)" }}>
            <CampaignRows campaigns={inactiveCampaigns} locations={locationsQuery.data} onOpen={(id) => setParam("campaign", id)} />
          </div>
        </details>
      ) : null}

      {openCampaign ? (
        <CampaignPanel campaign={openCampaign} onClose={() => setParam("campaign", null)} />
      ) : null}

      {showNew ? (
        <SidePanel
          title={i18n("newCampaignaaf9a8a")}
          subtitle={i18n("promotions086e09b")}
          onClose={() => setParam("new", null)}
          footer={
            <div className="flex gap-3">
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--text)", color: "var(--bg)" }}
                disabled={createMutation.isPending || !form.name || (manyBranches && branches !== "all" && branches.length === 0)}
                onClick={() => createMutation.mutate()}
                type="button"
              >
                {createMutation.isPending ? i18n("creating94d7d8e") : i18n("createCampaign59812bb")}
              </button>
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                onClick={() => setParam("new", null)}
                type="button"
              >
                {i18n("cancel77dfd21")}
              </button>
            </div>
          }
        >
          <div className="space-y-4">
            <PanelField label={i18n("campaignNameaa5d0e7")}>
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
              />
            </PanelField>
            <PanelField label={i18n("description55f8ebc")}>
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={form.description}
                onChange={(e) => setForm({ ...form, description: e.target.value })}
              />
            </PanelField>
            <div className="grid gap-3 md:grid-cols-2">
              <PanelField label={i18n("startsOn6d888f7")}>
                <DateInput
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  value={form.starts_on}
                  onValueChange={(value) => setForm({ ...form, starts_on: value })}
                />
              </PanelField>
              <PanelField label={i18n("endsOn5c262f3")}>
                <DateInput
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  value={form.ends_on}
                  onValueChange={(value) => setForm({ ...form, ends_on: value })}
                />
              </PanelField>
            </div>
            <label className="flex items-center gap-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              <input
                type="checkbox"
                checked={form.active}
                onChange={(e) => setForm({ ...form, active: e.target.checked })}
              />
              {i18n("activea733b80")}
            </label>
            <AppliesToBranches kind="covering" locations={locationsQuery.data} value={branches} onChange={setBranchDraft} />
            {createMutation.error instanceof Error && (
              <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{localizeError(createMutation.error, i18n)}</p>
            )}
          </div>
        </SidePanel>
      ) : null}
    </div>
  );
}

function CampaignRows({
  campaigns,
  locations,
  onOpen,
}: {
  campaigns: FinanceRecord[];
  locations: FacilityLocation[] | null | undefined;
  onOpen: (id: string) => void;
}) {
  const i18n = useUiTranslations();
  return campaigns.map((campaign, index) => (
    <button
      key={field(campaign, "id")}
      className="flex w-full items-center justify-between gap-4 px-6 py-4 text-start transition-opacity hover:opacity-80"
      style={{ borderBottom: index < campaigns.length - 1 ? "1px solid var(--border)" : "none" }}
      onClick={() => onOpen(field(campaign, "id"))}
      type="button"
    >
      <div>
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{field(campaign, "name")}</p>
        <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
          {field(campaign, "starts_on") || i18n("noStartc3324f8")} → {field(campaign, "ends_on") || i18n("noEnd5d1bd95")}
        </p>
      </div>
      <div className="flex items-center gap-3">
        <BranchCoverageBadge
          target={toLocationScope(campaign.location_scope as LocationScopePayload | null | undefined)}
          locations={locations}
        />
        <span className="rounded-full px-3 py-1 text-xs font-semibold" style={campaign.active === false ? { background: "var(--border)", color: "var(--dim)" } : SPARK_ACTIVE_STYLE}>
          {campaign.active === false ? i18n("inactive09af574") : i18n("activea733b80")}
        </span>
        <span style={{ color: "var(--dim)" }}>→</span>
      </div>
    </button>
  ));
}

function PanelField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</span>
      {children}
    </label>
  );
}
