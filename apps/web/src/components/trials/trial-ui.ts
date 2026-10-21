import { ApiError } from "@/api/client";

/** Error codes the trial endpoints answer with (ADR-144); each has a Trials.error_<code> message. */
export const TRIAL_ERROR_CODES = [
  "trials_disabled",
  "class_not_open_to_trials",
  "slot_in_past",
  "beyond_trial_horizon",
  "slot_full",
  "no_trial_seats",
  "weekly_trial_limit_reached",
  "already_member",
  "trial_for_first_timers_only",
  "trial_already_used",
  "trial_already_open",
  "invalid_trial_transition",
  "class_not_found",
  "package_not_found",
] as const;

type TrialErrorCode = (typeof TRIAL_ERROR_CODES)[number];

export function trialErrorKey(error: unknown): `error_${TrialErrorCode}` | "error_generic" {
  const code = error instanceof ApiError ? error.payload.code : undefined;
  return code && (TRIAL_ERROR_CODES as readonly string[]).includes(code) ? (`error_${code}` as `error_${TrialErrorCode}`) : "error_generic";
}

export function newOperationId() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) =>
        (Number(c) ^ (Math.random() * 16) >> (Number(c) / 4)).toString(16),
      );
}

/** Saves a text file on the device (the trial's calendar entry). */
export function downloadFile(name: string, type: string, content: string) {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
