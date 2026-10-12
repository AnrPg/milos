import { ApiError } from "@/api/client";

/**
 * When ending a membership is refused because the package's minimum commitment
 * is still running (ADR-097), returns the commitment end date; otherwise null.
 */
export function commitmentConflict(error: unknown): { endsOn: string | null } | null {
  if (!(error instanceof ApiError) || error.payload.code !== "package_commitment_active") return null;
  const endsOn = error.payload.params?.commitment_ends_on;
  return { endsOn: typeof endsOn === "string" ? endsOn.slice(0, 10) : null };
}
