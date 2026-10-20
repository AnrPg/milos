import type {
  ReferralGift,
  ReferralInvite,
  ReferralProgramTerms,
  ReferralRewardStatus,
  ReferralStage,
  StaffReferralInvite,
} from "@/api/referrals";

/**
 * Pure helpers for «Φέρε φίλο» (ADR-156): the words for the offer, a friend's
 * step and the member's reward, and the links a member shares.
 */

export type Translate = (key: string, values?: Record<string, string | number>) => string;

export function money(locale: string, cents: number, currency = "EUR") {
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency,
    minimumFractionDigits: cents % 100 === 0 ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(cents / 100);
}

/** What the friend gets: «7 μέρες δωρεάν», «20 € πίστωση» or the box's own words. */
export function giftText(gift: ReferralGift | null | undefined, t: Translate, locale: string) {
  if (!gift) return null;
  switch (gift.type) {
    case "free_days":
      return t("gift.freeDays", { days: gift.value });
    case "credit":
      return t("gift.credit", { amount: money(locale, gift.value) });
    case "custom":
      return gift.note?.trim() || null;
    default:
      return null;
  }
}

type RewardTerms = Pick<ReferralProgramTerms["reward"], "type" | "value" | "note">;

/** What the member gets: «20 € πίστωση», «−15% στην ανανέωση», «1 μήνας δωρεάν» or the box's words. */
export function rewardText(reward: RewardTerms | null | undefined, t: Translate, locale: string) {
  if (!reward) return null;
  switch (reward.type) {
    case "credit":
      return t("reward.credit", { amount: money(locale, reward.value) });
    case "discount":
      return t("reward.discount", { percent: reward.value });
    case "free_period":
      return t("reward.freePeriod", { days: reward.value });
    case "manual":
      return reward.note?.trim() || t("reward.manual");
    default:
      return null;
  }
}

/** When the member earns it, in the programme's words. */
export function qualifyingText(program: Pick<ReferralProgramTerms, "qualifying_stage">, t: Translate) {
  return program.qualifying_stage === "trial" ? t("when.trial") : t("when.paid");
}

export const STAGES: ReferralStage[] = ["signed_up", "event", "trial", "joined", "paid"];

export function stageText(stage: ReferralStage, t: Translate) {
  return t(`stage.${stage}`);
}

export type Tone = "ok" | "accent" | "neutral" | "muted";

/** The pill on a friend's row: the reward once there is one, else the step. */
export function invitePill(invite: Pick<ReferralInvite, "stage" | "status" | "reward">, t: Translate): { label: string; tone: Tone } {
  const status = invite.reward?.status;
  if (invite.status === "expired") return { label: t("status.expired"), tone: "muted" };
  if (invite.status === "void") return { label: t("status.void"), tone: "muted" };
  if (status && status !== "upcoming" && status !== "none") return { label: rewardStatusText(status, t), tone: rewardTone(status) };
  return { label: stageText(invite.stage, t), tone: invite.stage === "signed_up" ? "neutral" : "accent" };
}

export function rewardStatusText(status: ReferralRewardStatus, t: Translate) {
  return t(`rewardStatus.${status}`);
}

function rewardTone(status: ReferralRewardStatus): Tone {
  if (status === "given" || status === "approved") return "ok";
  if (status === "pending") return "accent";
  return "muted";
}

/** The link a member shares; the QR carries `?via=qr`, an event invite `?event=<id>`. */
export function inviteUrl(origin: string, code: string, options: { via?: "qr"; eventId?: string } = {}) {
  const url = new URL(`/r/${encodeURIComponent(code)}`, origin);
  if (options.eventId) url.searchParams.set("event", options.eventId);
  else if (options.via) url.searchParams.set("via", options.via);
  return url.toString();
}

/** Staff's queue: invites that wait for a decision first, then the newest. */
export function sortForStaff(invites: StaffReferralInvite[]) {
  const waiting = (invite: StaffReferralInvite) => (invite.reward?.status === "pending" ? 0 : 1);
  return [...invites].sort(
    (a, b) => waiting(a) - waiting(b) || b.attributed_at.localeCompare(a.attributed_at),
  );
}

/** The steps a friend reached, oldest first, for staff's detail panel. */
export function reachedSteps(invite: Pick<StaffReferralInvite, "attributed_at" | "steps">) {
  const steps: Array<{ stage: ReferralStage; at: string }> = [{ stage: "signed_up", at: invite.attributed_at }];
  const at = invite.steps;
  if (at.event_at) steps.push({ stage: "event", at: at.event_at });
  if (at.trial_at) steps.push({ stage: "trial", at: at.trial_at });
  if (at.joined_at) steps.push({ stage: "joined", at: at.joined_at });
  if (at.paid_at) steps.push({ stage: "paid", at: at.paid_at });
  return steps;
}
