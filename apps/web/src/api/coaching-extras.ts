import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

type FormReviewsResponse =
  paths["/api/org/{organization_slug}/me/form-reviews"]["get"]["responses"][200]["content"]["application/json"];
type NutritionPlanResponse =
  paths["/api/org/{organization_slug}/me/nutrition-plan"]["get"]["responses"][200]["content"]["application/json"];

export type FormReview = FormReviewsResponse["form_reviews"][number];
export type NutritionPlan = NonNullable<NutritionPlanResponse["nutrition_plan"]>;
export type SubmitFormReviewParams = NonNullable<
  paths["/api/org/{organization_slug}/me/form-reviews"]["post"]["requestBody"]
>["content"]["application/json"];

export async function fetchMyFormReviews(token: string): Promise<FormReview[]> {
  const data = await apiRequest<FormReviewsResponse>("/me/form-reviews", { token });
  return data.form_reviews;
}

/** Submitting reserves one `form_reviews` unit (ADR-098). */
export async function submitFormReview(
  token: string,
  params: SubmitFormReviewParams,
): Promise<FormReview> {
  const data = await apiRequest<{ form_review: FormReview }>("/me/form-reviews", {
    method: "POST",
    token,
    body: params,
  });
  return data.form_review;
}

/** Withdrawing an open review gives the unit back. */
export async function withdrawFormReview(token: string, id: string): Promise<FormReview> {
  const data = await apiRequest<{ form_review: FormReview }>(
    `/me/form-reviews/${encodeURIComponent(id)}/withdraw`,
    { method: "POST", token },
  );
  return data.form_review;
}

export async function fetchMyNutritionPlan(token: string): Promise<NutritionPlan | null> {
  const data = await apiRequest<NutritionPlanResponse>("/me/nutrition-plan", { token });
  return data.nutrition_plan ?? null;
}
