"use client";

import { useTranslations } from "next-intl";

import type { ProgramRules } from "./program-rules";
import { Select } from "@/components/ui/Select";
import { AdvancedDisclosure } from "@/components/settings/AdvancedSettings";

const inputStyle = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" };
const inputClass = "w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none";

/** The programme's two-sided rules in its create and edit panels (ADR-156). */
export function ProgramRulesFields({
  rules,
  rewardType,
  onChange,
}: {
  rules: ProgramRules;
  rewardType: string;
  onChange: (rules: ProgramRules) => void;
}) {
  const t = useTranslations("Referrals");
  const set = <K extends keyof ProgramRules>(key: K, value: ProgramRules[K]) => onChange({ ...rules, [key]: value });

  return (
    <div className="space-y-4">
      {rewardType === "manual" ? (
        <Field label={t("rules.rewardNote")}>
          <input className={inputClass} style={inputStyle} value={rules.reward_note} maxLength={200} onChange={(e) => set("reward_note", e.target.value)} />
        </Field>
      ) : null}

      <div className="grid gap-3 md:grid-cols-2">
        <Field label={t("rules.friendGift")}>
          <Select
            className={inputClass}
            style={inputStyle}
            value={rules.friend_reward_type}
            onValueChange={(value) => set("friend_reward_type", value as ProgramRules["friend_reward_type"])}
          >
            {(["free_days", "credit", "custom", "none"] as const).map((value) => (
              <option key={value} value={value}>{t(`rules.gift_${value}`)}</option>
            ))}
          </Select>
        </Field>
        {rules.friend_reward_type === "free_days" || rules.friend_reward_type === "credit" ? (
          <Field label={rules.friend_reward_type === "credit" ? t("rules.giftEuros") : t("rules.giftDays")}>
            <input
              className={inputClass}
              style={inputStyle}
              type="number"
              min={0}
              step={rules.friend_reward_type === "credit" ? "0.01" : "1"}
              value={rules.friend_reward_value}
              onChange={(e) => set("friend_reward_value", e.target.value)}
            />
          </Field>
        ) : rules.friend_reward_type === "custom" ? (
          <Field label={t("rules.giftNote")}>
            <input className={inputClass} style={inputStyle} value={rules.friend_reward_note} maxLength={200} onChange={(e) => set("friend_reward_note", e.target.value)} />
          </Field>
        ) : null}
      </div>

      {/* ADR-255: when an invite counts, how long it holds, the yearly cap and approval have good defaults. */}
      <AdvancedDisclosure count={4} testId="referral-rules-advanced">
        <div className="grid gap-3 md:grid-cols-2">
          <Field label={t("rules.counts")}>
            <Select className={inputClass} style={inputStyle} value={rules.qualifying_stage} onValueChange={(value) => set("qualifying_stage", value as ProgramRules["qualifying_stage"])}>
              <option value="paid">{t("rules.counts_paid")}</option>
              <option value="trial">{t("rules.counts_trial")}</option>
            </Select>
          </Field>
          <Field label={t("rules.approval")}>
            <Select className={inputClass} style={inputStyle} value={rules.approval} onValueChange={(value) => set("approval", value as ProgramRules["approval"])}>
              <option value="manual">{t("rules.approval_manual")}</option>
              <option value="auto">{t("rules.approval_auto")}</option>
            </Select>
          </Field>
          <Field label={t("rules.window")}>
            <input className={inputClass} style={inputStyle} type="number" min={7} max={365} value={rules.attribution_days} onChange={(e) => set("attribution_days", e.target.value)} />
          </Field>
          <Field label={t("rules.cap")}>
            <input
              className={inputClass}
              style={inputStyle}
              type="number"
              min={1}
              max={1000}
              placeholder={t("rules.capNone")}
              value={rules.yearly_cap}
              onChange={(e) => set("yearly_cap", e.target.value)}
            />
          </Field>
        </div>
        <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t("rules.hint")}</p>
      </AdvancedDisclosure>
    </div>
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
