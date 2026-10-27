import { ApiError } from "@/api/client";

/** ADR-211: this profile, or the account (login) with all its profiles. */
export type DeletionScope = "profile" | "login";

export type DeletionFailure = { key: string; values?: Record<string, string> };

/** What a refused deletion request says, as an `accountDeletion` message; null for anything else. */
export function deletionFailure(error: unknown): DeletionFailure | null {
  if (!(error instanceof ApiError)) return null;
  const payload = error.payload as Record<string, unknown>;

  switch (payload.code) {
    case "invalid_password":
      return { key: "errorPassword" };
    case "confirmation_mismatch":
      return { key: "errorConfirmation" };
    case "already_scheduled":
      return { key: "errorScheduled" };
    case "sole_owner": {
      const names = Array.isArray(payload.organizations)
        ? payload.organizations.filter((name): name is string => typeof name === "string")
        : [];
      return { key: "errorSoleOwner", values: { names: names.map((name) => `«${name}»`).join(", ") } };
    }
    default:
      return null;
  }
}

export type DeletionLinkFailure = "invalid" | "expired" | "other";

/** The confirmation and undo pages tell an expired link (410) from an unknown or used one (422). */
export function deletionLinkFailure(error: unknown): DeletionLinkFailure {
  if (!(error instanceof ApiError)) return "other";
  if (error.status === 410 || error.payload.code === "expired_deletion_link") return "expired";
  if (error.payload.code === "invalid_deletion_link") return "invalid";
  return "other";
}
