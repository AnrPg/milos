import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Home-screen widgets (ADR-173): the store app asks for a token its widgets
 * use on their own (`/api/widget/*`, read by the native code, never here)
 * and revokes it on sign-out.
 */
export type WidgetToken = components["schemas"]["WidgetToken"];
export type WidgetPlatform = components["schemas"]["WidgetTokenRequest"]["platform"];

export function issueWidgetToken(token: string, platform: WidgetPlatform, replacesId?: string | null) {
  return apiRequest<WidgetToken>("/me/widget-tokens", {
    method: "POST",
    token,
    body: { platform, replaces_id: replacesId ?? null },
  });
}

export function revokeWidgetToken(token: string, id: string) {
  return apiRequest<void>(`/me/widget-tokens/${encodeURIComponent(id)}`, { method: "DELETE", token });
}
