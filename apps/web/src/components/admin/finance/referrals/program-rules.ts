import type { FinanceRecord } from "@/api/finance";

/**
 * The rules a referral programme carries (ADR-156, board 11 Q4, Q6, Q7): the
 * friend's gift, when an invite counts, how long it holds, a yearly cap and
 * how rewards are approved. Form values are strings; `programRulesBody`
 * turns them into the API's fields (a credit gift in cents).
 */
export type ProgramRules = {
  friend_reward_type: "none" | "free_days" | "credit" | "custom";
  friend_reward_value: string;
  friend_reward_note: string;
  reward_note: string;
  qualifying_stage: "trial" | "paid";
  attribution_days: string;
  yearly_cap: string;
  approval: "manual" | "auto";
};

export const BLANK_RULES: ProgramRules = {
  friend_reward_type: "free_days",
  friend_reward_value: "7",
  friend_reward_note: "",
  reward_note: "",
  qualifying_stage: "paid",
  attribution_days: "30",
  yearly_cap: "",
  approval: "manual",
};

const GIFTS = ["none", "free_days", "credit", "custom"] as const;

export function rulesFromProgram(program: FinanceRecord | null | undefined): ProgramRules {
  if (!program) return BLANK_RULES;
  const text = (key: string, fallback: string) => {
    const value = program[key];
    return value === null || value === undefined ? fallback : String(value);
  };
  const gift = GIFTS.find((value) => value === program.friend_reward_type) ?? "none";
  const giftValue = Number(program.friend_reward_value ?? 0);
  return {
    friend_reward_type: gift,
    friend_reward_value: gift === "credit" ? String(giftValue / 100) : String(giftValue),
    friend_reward_note: text("friend_reward_note", ""),
    reward_note: text("reward_note", ""),
    qualifying_stage: program.qualifying_stage === "trial" ? "trial" : "paid",
    attribution_days: text("attribution_days", "30"),
    yearly_cap: text("yearly_cap", ""),
    approval: program.approval === "auto" ? "auto" : "manual",
  };
}

export function programRulesBody(rules: ProgramRules) {
  const value = Number(rules.friend_reward_value || 0);
  const cap = rules.yearly_cap.trim() === "" ? null : Math.trunc(Number(rules.yearly_cap));
  return {
    friend_reward_type: rules.friend_reward_type,
    friend_reward_value:
      rules.friend_reward_type === "credit"
        ? Math.round(value * 100)
        : rules.friend_reward_type === "free_days"
          ? Math.trunc(value)
          : 0,
    friend_reward_note: rules.friend_reward_type === "custom" ? rules.friend_reward_note.trim() || null : null,
    reward_note: rules.reward_note.trim() || null,
    qualifying_stage: rules.qualifying_stage,
    attribution_days: Math.trunc(Number(rules.attribution_days || 30)),
    yearly_cap: cap && cap > 0 ? cap : null,
    approval: rules.approval,
  };
}
