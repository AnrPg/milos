"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";

import { createPromotionCampaign, fetchPromotionCampaigns, type FinanceRecord } from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { CampaignPanel } from "@/components/admin/finance/panels/CampaignPanel";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

const BLANK = { name: "", description: "", starts_on: "", ends_on: "", active: true };

export function PromotionsTab() {
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
    queryKey: ["admin", "finance", "promotions"],
    enabled: Boolean(token),
    queryFn: () => fetchPromotionCampaigns(token),
  });

  const campaigns = campaignsQuery.data?.promotion_campaigns ?? [];
  const openCampaign = campaigns.find((c) => field(c, "id") === openCampaignId) ?? null;

  const [form, setForm] = useState(BLANK);

  const createMutation = useMutation({
    mutationFn: () =>
      createPromotionCampaign(token, {
        ...form,
        starts_on: form.starts_on || null,
        ends_on: form.ends_on || null,
      }),
    onSuccess: async () => {
      setForm(BLANK);
      setParam("new", null);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "promotions"] });
    },
  });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
          {campaigns.length} campaign{campaigns.length !== 1 ? "s" : ""}
        </p>
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
          onClick={() => setParam("new", "true")}
          type="button"
        >
          + New campaign
        </button>
      </div>

      <div className="rounded-[2rem] overflow-hidden" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {campaignsQuery.isLoading ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>Loading…</p>
        ) : campaigns.length === 0 ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>No campaigns yet.</p>
        ) : (
          campaigns.map((c, i) => (
            <button
              key={field(c, "id")}
              className="flex w-full items-center justify-between gap-4 px-6 py-4 text-left transition-opacity hover:opacity-80"
              style={{ borderBottom: i < campaigns.length - 1 ? "1px solid var(--border)" : "none" }}
              onClick={() => setParam("campaign", field(c, "id"))}
              type="button"
            >
              <div>
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{field(c, "name")}</p>
                <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
                  {field(c, "starts_on") || "No start"} → {field(c, "ends_on") || "No end"}
                </p>
              </div>
              <div className="flex items-center gap-3">
                <span
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={
                    c.active !== false
                      ? { background: "color-mix(in srgb, var(--success) 12%, transparent)", color: "var(--success)" }
                      : { background: "var(--border)", color: "var(--dim)" }
                  }
                >
                  {c.active !== false ? "Active" : "Inactive"}
                </span>
                <span style={{ color: "var(--dim)" }}>→</span>
              </div>
            </button>
          ))
        )}
      </div>

      {openCampaign ? (
        <CampaignPanel campaign={openCampaign} onClose={() => setParam("campaign", null)} />
      ) : null}

      {showNew ? (
        <SidePanel
          title="New campaign"
          subtitle="Promotions"
          onClose={() => setParam("new", null)}
          footer={
            <div className="flex gap-3">
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--text)", color: "var(--bg)" }}
                disabled={createMutation.isPending || !form.name}
                onClick={() => createMutation.mutate()}
                type="button"
              >
                {createMutation.isPending ? "Creating…" : "Create campaign"}
              </button>
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                onClick={() => setParam("new", null)}
                type="button"
              >
                Cancel
              </button>
            </div>
          }
        >
          <div className="space-y-4">
            <PanelField label="Campaign name">
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
              />
            </PanelField>
            <PanelField label="Description">
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={form.description}
                onChange={(e) => setForm({ ...form, description: e.target.value })}
              />
            </PanelField>
            <div className="grid gap-3 md:grid-cols-2">
              <PanelField label="Starts on">
                <input
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  type="date"
                  value={form.starts_on}
                  onChange={(e) => setForm({ ...form, starts_on: e.target.value })}
                />
              </PanelField>
              <PanelField label="Ends on">
                <input
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  type="date"
                  value={form.ends_on}
                  onChange={(e) => setForm({ ...form, ends_on: e.target.value })}
                />
              </PanelField>
            </div>
            <label className="flex items-center gap-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              <input
                type="checkbox"
                checked={form.active}
                onChange={(e) => setForm({ ...form, active: e.target.checked })}
              />
              Active
            </label>
            {createMutation.error instanceof Error && (
              <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{createMutation.error.message}</p>
            )}
          </div>
        </SidePanel>
      ) : null}
    </div>
  );
}

function PanelField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</span>
      {children}
    </label>
  );
}
