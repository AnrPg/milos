import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

type MyReviewsResponse =
  operations["MilosTrainingWeb.ReviewController.index"]["responses"][200]["content"]["application/json"];
type SubmitReviewResponse =
  operations["MilosTrainingWeb.ReviewController.create"]["responses"][201]["content"]["application/json"];
type AdminReviewsResponse =
  operations["MilosTrainingWeb.AdminReviewController.index"]["responses"][200]["content"]["application/json"];
type UpdateReviewResponse =
  operations["MilosTrainingWeb.AdminReviewController.update_status"]["responses"][200]["content"]["application/json"];

export type ReviewRecord = MyReviewsResponse["reviews"][number];
export type SubmitReviewRequest =
  operations["MilosTrainingWeb.ReviewController.create"]["requestBody"]["content"]["application/json"];
export type AdminReviewFilters = NonNullable<
  operations["MilosTrainingWeb.AdminReviewController.index"]["parameters"]["query"]
>;
export type UpdateReviewStatusRequest =
  operations["MilosTrainingWeb.AdminReviewController.update_status"]["requestBody"]["content"]["application/json"];

export async function fetchMyReviews(token: string) {
  return apiRequest<MyReviewsResponse>("/reviews", { token });
}

export async function submitReview(token: string, body: SubmitReviewRequest) {
  return apiRequest<SubmitReviewResponse>("/reviews", {
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
