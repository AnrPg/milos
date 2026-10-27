import { ApiError } from "@/api/client";

export type SignOutLinkFailure = "expired" | "used" | "invalid" | "other";

/** ADR-208: why a "sign out everywhere" link did not work, from the API's answer. */
export function signOutLinkFailure(error: unknown): SignOutLinkFailure {
  if (!(error instanceof ApiError)) return "other";
  const code = error.payload.code;
  if (code === "expired_link") return "expired";
  if (code === "used_link") return "used";
  if (code === "invalid_link") return "invalid";
  return "other";
}
