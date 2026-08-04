import type { paths } from "@/api/generated/schema";
import { apiRequest } from "@/api/client";

export type OrganizationMembership =
  paths["/api/memberships"]["get"]["responses"]["200"]["content"]["application/json"][number];

export function fetchOrganizationMemberships(token: string) {
  return apiRequest<OrganizationMembership[]>("/memberships", { token });
}
