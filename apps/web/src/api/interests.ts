import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/** «Τι κάνεις» (ADR-183): disciplines are box-vocabulary keys, level a Partners level. */
export type AccountInterests = components["schemas"]["AccountInterests"];
export type InterestLevel = NonNullable<AccountInterests["level"]>;

export const INTEREST_LEVELS: InterestLevel[] = ["beginner", "intermediate", "advanced"];

export async function fetchMyInterests(token: string) {
  const data = await apiRequest<components["schemas"]["AccountInterestsResponse"]>("/me/interests", { token });
  return data.interests;
}

export async function saveMyInterests(token: string, interests: AccountInterests) {
  const data = await apiRequest<components["schemas"]["AccountInterestsResponse"]>("/me/interests", {
    method: "PUT",
    token,
    body: interests,
  });
  return data.interests;
}
