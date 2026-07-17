import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";
import type { EffectiveEntitlement } from "@/api/my-finance";

export type AllowanceExtensionRequest = NonNullable<
  paths["/api/admin/users/{id}/allowance-extensions"]["post"]["requestBody"]
>["content"]["application/json"];

export type AdminUserDirectoryEntry = {
  id: string;
  nickname: string;
  avatar_url: string | null;
  role: "member" | "athlete" | "admin";
  account_status: string;
  joined_at: string | null;
  finance_status: string | null;
  attention_count: number;
};

export type AdminUserProfileShell = {
  identity: Pick<AdminUserDirectoryEntry, "id" | "nickname" | "avatar_url" | "role" | "joined_at">;
  account_status: string;
  available_sections: string[];
  attention: Array<Record<string, unknown>>;
  operational_links: Record<string, string>;
};

export type AdminUserFinance = {
  user_id: string;
  available: boolean;
  summary: null | {
    credit_balance: number;
    current_status: Record<string, unknown>;
    package_relationship: Record<string, unknown>;
    outstanding_items: Array<Record<string, unknown>>;
    effective_entitlement: EffectiveEntitlement | null;
  };
  drill_down: Record<string, unknown> | null;
  operational_links: Record<string, string>;
};

export type AdminUserExecution = {
  id: string;
  workout_title: string;
  workout_type: string | null;
  source: string;
  status: string;
  started_at_utc: string | null;
  completed_at_utc: string | null;
  total_elapsed_ms: number;
  section_scores: Array<Record<string, unknown>>;
};

export type AdminUserTraining = {
  user_id: string;
  executions: AdminUserExecution[];
  scores: Array<Record<string, unknown>>;
  class_participation: AdminUserExecution[];
  assigned_workouts: Array<Record<string, unknown>>;
  summary: { execution_count: number; completed_count: number; scored_section_count: number };
};

export type AdminUserPR = {
  id: string;
  name: string;
  current_score: number | string;
  unit: string;
  higher_is_better: boolean;
  beaten_on: string;
  supporting_metrics?: Record<string, string | number>;
  notes?: string | null;
  updated_at?: string | null;
};

export type AdminUserIncident = {
  id: string;
  body_area: string;
  severity: string;
  status: string;
  training_limitations: string | null;
  started_on: string | null;
};

export type AdminUserMessageThread = {
  id: string;
  context_type: string;
  message_count: number;
  latest_message: null | { body: string; inserted_at: string; sender_id: string };
};

export function fetchAdminUsers(token: string, params: { q?: string; role?: string } = {}) {
  const query = new URLSearchParams();
  if (params.q) query.set("q", params.q);
  if (params.role) query.set("role", params.role);
  query.set("limit", "50");

  return apiRequest<{
    users: AdminUserDirectoryEntry[];
    meta: { total: number; limit: number; offset: number; has_more: boolean };
  }>(`/admin/users?${query.toString()}`, { token });
}

export function fetchAdminUserProfile(token: string, userId: string) {
  return apiRequest<{ user: AdminUserProfileShell }>(`/admin/users/${userId}`, { token });
}

export function fetchAdminUserFinance(token: string, userId: string) {
  return apiRequest<AdminUserFinance>(`/admin/users/${userId}/finance`, { token });
}

export function fetchAdminUserTraining(token: string, userId: string) {
  return apiRequest<AdminUserTraining>(`/admin/users/${userId}/training-history`, { token });
}

export function fetchAdminUserPRs(token: string, userId: string) {
  return apiRequest<{ user_id: string; prs: AdminUserPR[] }>(`/admin/users/${userId}/prs`, { token });
}

export function fetchAdminUserIncidents(token: string, userId: string) {
  return apiRequest<{ user_id: string; incidents: AdminUserIncident[]; summary: { total: number; active: number } }>(`/admin/users/${userId}/incidents`, { token });
}

export function fetchAdminUserMessages(token: string, userId: string) {
  return apiRequest<{ user_id: string; threads: AdminUserMessageThread[]; summary: { thread_count: number; unread_thread_count: number }; operational_links: Record<string, string> }>(`/admin/users/${userId}/messages`, { token });
}

export function fetchAdminUserCoachingContext(token: string, userId: string) {
  return apiRequest<{ user_id: string; available: boolean; drill_down: Record<string, unknown> | null }>(`/admin/users/${userId}/coaching-context`, { token });
}

export function updateAdminUserRole(token: string, userId: string, role: AdminUserDirectoryEntry["role"]) {
  return apiRequest<Pick<AdminUserDirectoryEntry, "id" | "nickname" | "role">>(`/admin/users/${userId}/role`, {
    token,
    method: "PATCH",
    body: { role },
  });
}

export function deleteAdminUser(token: string, userId: string) {
  return apiRequest<void>(`/admin/users/${userId}`, { token, method: "DELETE" });
}

export function grantAdminUserAllowance(
  token: string,
  userId: string,
  body: AllowanceExtensionRequest,
) {
  return apiRequest<{ entry: Record<string, unknown>; entitlement: EffectiveEntitlement }>(
    `/admin/users/${userId}/allowance-extensions`,
    { token, method: "POST", body },
  );
}

export function revokeAdminUserAllowance(token: string, userId: string, entryId: string, reason: string) {
  return apiRequest<{ entry: Record<string, unknown>; entitlement: EffectiveEntitlement }>(
    `/admin/users/${userId}/allowance-extensions/${entryId}/revoke`,
    { token, method: "POST", body: { reason } },
  );
}
