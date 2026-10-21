import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

type MyReviewsResponse =
  operations["PaleeWeb.ReviewController.index"]["responses"][200]["content"]["application/json"];
type SubmitReviewResponse =
  operations["PaleeWeb.ReviewController.create"]["responses"][201]["content"]["application/json"];
type AdminReviewsResponse =
  operations["PaleeWeb.AdminReviewController.index"]["responses"][200]["content"]["application/json"];
type UpdateReviewResponse =
  operations["PaleeWeb.AdminReviewController.update_status"]["responses"][200]["content"]["application/json"];

export type ReviewRecord = MyReviewsResponse["reviews"][number];
export type SubmitReviewRequest =
  operations["PaleeWeb.ReviewController.create"]["requestBody"]["content"]["application/json"];
export type AdminReviewFilters = NonNullable<
  operations["PaleeWeb.AdminReviewController.index"]["parameters"]["query"]
>;
export type UpdateReviewStatusRequest =
  operations["PaleeWeb.AdminReviewController.update_status"]["requestBody"]["content"]["application/json"];

/** Query key of the member's own reviews (reviews page, Ροή, realtime sync). */
export const MY_REVIEWS_KEY = ["my", "reviews"] as const;

export async function fetchMyReviews(token: string) {
  return apiRequest<MyReviewsResponse>("/me/reviews", { token });
}

export async function submitReview(token: string, body: SubmitReviewRequest) {
  return apiRequest<SubmitReviewResponse>("/me/reviews", {
    method: "POST",
    token,
    body,
  });
}

export async function fetchAdminReviews(token: string, filters: AdminReviewFilters = {}) {
  const params = new URLSearchParams();
  Object.entries(filters).forEach(([key, value]) => {
    if (value !== undefined) params.set(key, String(value));
  });
  const suffix = params.toString() ? `?${params.toString()}` : "";
  return apiRequest<AdminReviewsResponse>(`/admin/reviews${suffix}`, { token });
}

export async function updateReviewStatus(
  token: string,
  reviewId: string,
  body: UpdateReviewStatusRequest,
) {
  return apiRequest<UpdateReviewResponse>(`/admin/reviews/${reviewId}/status`, {
    method: "PATCH",
    token,
    body,
  });
}
