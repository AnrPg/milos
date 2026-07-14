import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

export type NotificationsResponse =
  operations["MilosTrainingWeb.NotificationController.index"]["responses"][200]["content"]["application/json"];

export type NotificationRecord = NotificationsResponse["notifications"][number];

export type PushNotificationConfig =
  operations["MilosTrainingWeb.NotificationController.push_config"]["responses"][200]["content"]["application/json"];

export type PushSubscriptionPayload =
  NonNullable<
    operations["MilosTrainingWeb.NotificationController.create_push_subscription"]["requestBody"]
  >["content"]["application/json"];

export type PushSubscriptionRecord =
  operations["MilosTrainingWeb.NotificationController.create_push_subscription"]["responses"][201]["content"]["application/json"]["subscription"];

export type PushSubscriptionStatus =
  operations["MilosTrainingWeb.NotificationController.push_subscription_status"]["responses"][200]["content"]["application/json"];

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

export async function deletePushSubscription(token: string, payload: DeletePushSubscriptionPayload) {
  return apiRequest<{ deleted: boolean }>("/notifications/push-subscriptions", {
    method: "DELETE",
    token,
    body: payload,
  });
}
