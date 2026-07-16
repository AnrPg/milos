"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  createPromotionCode,
  fetchPromotionCodes,
  type FinanceRecord,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

const BLANK_CODE_FORM = {
  code: "",
  discount_type: "percent",
  discount_value: "10",
  max_redemptions: "",
  active: true,
};

export function CampaignPanel({
  campaign,
  onClose,
}: {
  campaign: FinanceRecord;
  onClose: () => void;
}) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const campaignId = field(campaign, "id");

  const codesQuery = useQuery({
    queryKey: ["admin", "finance", "promotion-codes", campaignId],
    enabled: Boolean(token && campaignId),
    queryFn: () => fetchPromotionCodes(token, campaignId),
  });

  const codes = codesQuery.data?.promotion_codes ?? [];
  const [codeForm, setCodeForm] = useState(BLANK_CODE_FORM);
  const [showCodeForm, setShowCodeForm] = useState(false);

  const createCodeMutation = useMutation({
    mutationFn: () =>
      createPromotionCode(token, campaignId, {
        code: codeForm.code,
        discount_type: codeForm.discount_type,
        discount_value: Number(codeForm.discount_value || 0),
        max_redemptions: codeForm.max_redemptions ? Number(codeForm.max_redemptions) : null,
        active: codeForm.active,
      }),
    onSuccess: async () => {
      setCodeForm(BLANK_CODE_FORM);
      setShowCodeForm(false);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "promotion-codes", campaignId] });
    },
  });

  return (
    <SidePanel
      title={field(campaign, "name")}
      subtitle={i18n("campaign69390e1")}
      onClose={onClose}
    >
      {/* Campaign info */}
      <div className="space-y-3 rounded-[1.5rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
        {field(campaign, "description") && (
          <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>{field(campaign, "description")}</p>
        )}
        <div className="flex flex-wrap gap-4 text-xs">
          <span style={{ color: "var(--dim)" }}>
            {i18n("starts83eef1d")} <span style={{ color: "var(--text-soft)" }}>{field(campaign, "starts_on") || "—"}</span>
          </span>
          <span style={{ color: "var(--dim)" }}>
            {i18n("ends06e9778")} <span style={{ color: "var(--text-soft)" }}>{field(campaign, "ends_on") || "—"}</span>
          </span>
          <span
            className="rounded-full px-3 py-1 font-semibold"
            style={
              campaign.active !== false
                ? { background: "color-mix(in srgb, var(--success) 12%, transparent)", color: "var(--success)" }
                : { background: "var(--border)", color: "var(--dim)" }
            }
          >
            {campaign.active !== false ? i18n("activea733b80") : i18n("inactive09af574")}
          </span>
        </div>
      </div>

      {/* Codes section */}
      <div>
        <div className="flex items-center justify-between gap-4 mb-3">
          <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("promoCodes13b7ca0")}{codes.length})
          </p>
          <button
            className="rounded-full px-3 py-1 text-xs font-semibold"
            style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
            onClick={() => setShowCodeForm((v) => !v)}
            type="button"
          >
            {showCodeForm ? i18n("cancel77dfd21") : i18n("newCodeb1a906d")}
          </button>
        </div>

        {showCodeForm && (
          <div className="mb-4 space-y-3 rounded-[1.5rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            <PanelField label={i18n("codeadac693")}>
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={codeForm.code}
                onChange={(e) => setCodeForm({ ...codeForm, code: e.target.value })}
              />
            </PanelField>
            <div className="grid gap-3 md:grid-cols-2">
              <PanelField label={i18n("discountTypec5137dd")}>
                <select
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  value={codeForm.discount_type}
                  onChange={(e) => setCodeForm({ ...codeForm, discount_type: e.target.value })}
                >
                  {["percent", "fixed_amount", "free_period", "manual"].map((v) => (
                    <option key={v} value={v}>{v}</option>
                  ))}
                </select>
              </PanelField>
              <PanelField label={i18n("discountValuecfbd2d5")}>
                <input
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  type="number"
                  value={codeForm.discount_value}
                  onChange={(e) => setCodeForm({ ...codeForm, discount_value: e.target.value })}
                />
              </PanelField>
            </div>
            <PanelField label={i18n("maxRedemptionsOptional9c39e71")}>
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                type="number"
                value={codeForm.max_redemptions}
                onChange={(e) => setCodeForm({ ...codeForm, max_redemptions: e.target.value })}
              />
            </PanelField>
            <label className="flex items-center gap-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              <input
                type="checkbox"
                checked={codeForm.active}
                onChange={(e) => setCodeForm({ ...codeForm, active: e.target.checked })}
              />
              {i18n("activea733b80")}
            </label>
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              disabled={createCodeMutation.isPending || !codeForm.code}
              onClick={() => createCodeMutation.mutate()}
              type="button"
            >
              {createCodeMutation.isPending ? i18n("creating94d7d8e") : i18n("createCodecdeaf88")}
            </button>
            {createCodeMutation.error instanceof Error && (
              <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{createCodeMutation.error.message}</p>
            )}
          </div>
        )}

        {codesQuery.isLoading ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loadingCodes328cf85")}</p>
        ) : codes.length === 0 ? (
          <p className="rounded-[1.2rem] px-4 py-4 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
            {i18n("noCodesYetbe15d6c")}
          </p>
        ) : (
          <div className="space-y-2">
            {codes.map((code) => (
              <div key={field(code, "id")} className="rounded-[1.2rem] px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                <div className="flex items-center justify-between gap-4">
                  <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{field(code, "code")}</p>
                  <span
                    className="rounded-full px-3 py-1 text-xs font-semibold"
                    style={
                      code.active !== false
                        ? { background: "color-mix(in srgb, var(--success) 12%, transparent)", color: "var(--success)" }
                        : { background: "var(--border)", color: "var(--dim)" }
                    }
                  >
                    {code.active !== false ? i18n("activea733b80") : i18n("inactive09af574")}
                  </span>
                </div>
                <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
                  {field(code, "discount_type")} · {field(code, "discount_value")}
                  {code.max_redemptions ? i18n("max8004fdc") + (field(code, "max_redemptions")) + " uses" : ""}
                </p>
              </div>
            ))}
          </div>
        )}
      </div>
    </SidePanel>
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
