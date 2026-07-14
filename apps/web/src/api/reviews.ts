import { apiRequest } from "@/api/client";

export type ReviewRecord = Record<string, unknown>;

export async function fetchMyReviews(token: string) {
  return apiRequest<{ reviews: ReviewRecord[] }>("/reviews", { token });
}

export async function submitReview(token: string, body: ReviewRecord) {
  return apiRequest<{ review: ReviewRecord }>("/reviews", {
    method: "POST",
    token,
    body,
  });
}

export async function fetchAdminReviews(token: string, filters: Record<string, string> = {}) {
  const params = new URLSearchParams(filters);
  const suffix = params.toString() ? `?${params.toString()}` : "";
  return apiRequest<{ reviews: ReviewRecord[] }>(`/admin/reviews${suffix}`, { token });
}

export async function updateReviewStatus(token: string, reviewId: string, body: { status: string; tags?: string[] }) {
  return apiRequest<{ review: ReviewRecord }>(`/admin/reviews/${reviewId}/status`, {
    method: "PATCH",
    token,
    body,
  });
}
