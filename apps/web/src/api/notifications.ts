import { apiRequest } from "@/api/client";
import type { components, operations } from "@/api/generated/schema";

export type NotificationsResponse =
  operations["PaleeWeb.NotificationController.index"]["responses"][200]["content"]["application/json"];

export type NotificationRecord = NotificationsResponse["notifications"][number];

export type PushNotificationConfig =
  operations["PaleeWeb.NotificationController.push_config"]["responses"][200]["content"]["application/json"];

export type PushSubscriptionPayload =
  NonNullable<
    operations["PaleeWeb.NotificationController.create_push_subscription"]["requestBody"]
  >["content"]["application/json"];

export type PushSubscriptionRecord =
  operations["PaleeWeb.NotificationController.create_push_subscription"]["responses"][201]["content"]["application/json"]["subscription"];

export type PushSubscriptionStatus =
  operations["PaleeWeb.NotificationController.push_subscription_status"]["responses"][200]["content"]["application/json"];

export type DeletePushSubscriptionPayload = {
  endpoint: string;
};

export async function fetchNotifications(
  token: string,
  params: {
    limit?: number;
    cursor?: string | null;
  } = {},
) {
  const search = new URLSearchParams();

  if (typeof params.limit === "number") {
    search.set("limit", String(params.limit));
  }

  if (params.cursor) {
    search.set("cursor", params.cursor);
  }

  const suffix = search.size > 0 ? `?${search.toString()}` : "";
  return apiRequest<NotificationsResponse>(`/notifications${suffix}`, { token });
}

export async function markAllNotificationsRead(token: string) {
  return apiRequest<{ marked_count: number }>("/notifications/read-all", {
    method: "POST",
    token,
  });
}

export async function markNotificationRead(token: string, notificationId: string) {
  return apiRequest<{ read: boolean }>(`/notifications/${notificationId}/read`, {
    method: "POST",
    token,
  });
}

export async function markNotificationClicked(token: string, notificationId: string, url?: string | null) {
  return apiRequest<{ clicked: boolean; read: boolean }>(`/notifications/${notificationId}/click`, {
    method: "POST",
    token,
    body: { url },
  });
}

export async function fetchPushNotificationConfig(token: string) {
  return apiRequest<PushNotificationConfig>("/notifications/push-config", { token });
}

export async function savePushSubscription(token: string, payload: PushSubscriptionPayload) {
  return apiRequest<{ subscription: PushSubscriptionRecord }>("/notifications/push-subscriptions", {
    method: "POST",
    token,
    body: payload,
  });
}

export async function fetchPushSubscriptionStatus(token: string, endpoint: string) {
  return apiRequest<PushSubscriptionStatus>("/notifications/push-subscriptions/status", {
    method: "POST",
    token,
    body: { endpoint },
  });
}

// ADR-171: push to the store apps (FCM on Android, APNs on iOS).
export type NativePushTokenPayload = NonNullable<
  operations["PaleeWeb.NotificationController.create_native_push_token"]["requestBody"]
>["content"]["application/json"];

export type NativePushTokenRecord =
  operations["PaleeWeb.NotificationController.create_native_push_token"]["responses"][201]["content"]["application/json"]["native_push_token"];

export async function registerNativePushToken(token: string, payload: NativePushTokenPayload) {
  return apiRequest<{ native_push_token: NativePushTokenRecord }>("/notifications/native-push-tokens", {
    method: "POST",
    token,
    body: payload,
  });
}

export async function unregisterNativePushToken(token: string, deviceToken: string) {
  return apiRequest<{ deleted: boolean }>("/notifications/native-push-tokens/unregister", {
    method: "POST",
    token,
    body: { token: deviceToken },
  });
}

export async function deletePushSubscription(token: string, payload: DeletePushSubscriptionPayload) {
  return apiRequest<{ deleted: boolean }>("/notifications/push-subscriptions", {
    method: "DELETE",
    token,
    body: payload,
  });
}

/**
 * ADR-199: per-category notification choices (Εγώ › Ρυθμίσεις ›
 * Ειδοποιήσεις). Each category lists the channels it reaches people on; a
 * locked one (account and payments) is always on.
 */
export type NotificationPreference = components["schemas"]["NotificationPreference"];
export type NotificationPreferenceList = components["schemas"]["NotificationPreferenceList"];
export type NotificationCategory = NotificationPreference["category"];
export type NotificationChannel = "in_app" | "push";

export const notificationPreferencesKey = (userId: string | null | undefined) =>
  ["notification-preferences", userId ?? null] as const;

export function fetchNotificationPreferences(token: string) {
  return apiRequest<NotificationPreferenceList>("/notifications/preferences", { token, scope: "account" });
}

export function updateNotificationPreference(
  token: string,
  category: NotificationCategory,
  change: Partial<Record<NotificationChannel, boolean>>,
) {
  return apiRequest<NotificationPreferenceList>(`/notifications/preferences/${encodeURIComponent(category)}`, {
    token,
    scope: "account",
    method: "PUT",
    body: change,
  });
}
