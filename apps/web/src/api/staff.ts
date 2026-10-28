import { apiRequest } from "@/api/client";
import type { TrainingGoal } from "@/api/gamification";
import type { operations, paths } from "@/api/generated/schema";

// ADR-098 staff work under /staff: form reviews, the reply queue, nutrition
// plans and appointments. Owners, admins and coaches share these routes.

type Json<T> = T extends { content: { "application/json": infer Body } } ? Body : never;

type FormReviewQueueResponse = Json<
  operations["PaleeWeb.CoachingExtrasController.form_review_queue"]["responses"][200]
>;
type CompleteFormReviewResponse = Json<
  operations["PaleeWeb.CoachingExtrasController.complete_form_review"]["responses"][200]
>;
type ReplyQueueResponse = Json<
  operations["PaleeWeb.CoachingExtrasController.reply_queue"]["responses"][200]
>;
type NutritionPlanResponse = Json<
  operations["PaleeWeb.CoachingExtrasController.nutrition_plan"]["responses"][200]
>;
type SlotsResponse = Json<operations["PaleeWeb.AppointmentsController.slots"]["responses"][200]>;
type SlotResponse = Json<operations["PaleeWeb.AppointmentsController.create_slot"]["responses"][201]>;
type BookingResponse = Json<
  operations["PaleeWeb.AppointmentsController.book_for_client"]["responses"][201]
>;
type StaffCancelResponse = Json<
  paths["/api/org/{organization_slug}/staff/appointments/{id}/cancel"]["post"]["responses"][200]
>;

export type FormReview = FormReviewQueueResponse["form_reviews"][number];
export type FormReviewStatus = FormReview["status"];
export type ReplyQueueItem = ReplyQueueResponse["replies"][number];
export type NutritionPlan = NonNullable<NutritionPlanResponse["nutrition_plan"]>;
export type NutritionPlanInput = NonNullable<
  operations["PaleeWeb.CoachingExtrasController.save_nutrition_plan"]["requestBody"]
>["content"]["application/json"];
export type AppointmentSlot = SlotsResponse["slots"][number];
export type AppointmentBooking = NonNullable<AppointmentSlot["bookings"]>[number];
export type AppointmentSlotInput = NonNullable<
  operations["PaleeWeb.AppointmentsController.create_slot"]["requestBody"]
>["content"]["application/json"];
export type AttendanceStatus = "attended" | "no_show";

export async function fetchFormReviewQueue(token: string, status?: FormReviewStatus) {
  const suffix = status ? `?status=${encodeURIComponent(status)}` : "";
  const response = await apiRequest<FormReviewQueueResponse>(`/staff/form-reviews${suffix}`, { token });
  return response.form_reviews;
}

export async function completeFormReview(token: string, id: string, feedback: string) {
  const response = await apiRequest<CompleteFormReviewResponse>(`/staff/form-reviews/${id}/review`, {
    method: "POST",
    token,
    body: { feedback },
  });
  return response.form_review;
}

export async function fetchReplyQueue(token: string) {
  const response = await apiRequest<ReplyQueueResponse>("/staff/reply-queue", { token });
  return response.replies;
}

export async function fetchClientNutritionPlan(token: string, userId: string) {
  const response = await apiRequest<NutritionPlanResponse>(`/staff/clients/${userId}/nutrition-plan`, { token });
  return response.nutrition_plan ?? null;
}

export async function saveClientNutritionPlan(token: string, userId: string, body: NutritionPlanInput) {
  const response = await apiRequest<NutritionPlanResponse>(`/staff/clients/${userId}/nutrition-plan`, {
    method: "PUT",
    token,
    body,
  });
  return response.nutrition_plan ?? null;
}

/** ADR-216: a client's weekly goal, for their coach or full-scope staff. */
export async function fetchClientTrainingGoal(token: string, userId: string): Promise<TrainingGoal> {
  const response = await apiRequest<{ goal: TrainingGoal }>(`/staff/clients/${userId}/training-goal`, { token });
  return response.goal;
}

export async function saveClientTrainingGoal(token: string, userId: string, weeklyWorkoutTarget: number): Promise<TrainingGoal> {
  const response = await apiRequest<{ goal: TrainingGoal }>(`/staff/clients/${userId}/training-goal`, {
    method: "PUT",
    token,
    body: { weekly_workout_target: weeklyWorkoutTarget },
  });
  return response.goal;
}

export async function fetchAppointmentSlots(
  token: string,
  filters: { from?: string; to?: string; coach_id?: string } = {},
) {
  const params = new URLSearchParams();
  Object.entries(filters).forEach(([key, value]) => {
    if (value) params.set(key, value);
  });
  const suffix = params.toString() ? `?${params.toString()}` : "";
  const response = await apiRequest<SlotsResponse>(`/staff/appointment-slots${suffix}`, { token });
  return response.slots;
}

export async function createAppointmentSlot(token: string, body: AppointmentSlotInput) {
  const response = await apiRequest<SlotResponse>("/staff/appointment-slots", {
    method: "POST",
    token,
    body,
  });
  return response.slot;
}

/** ADR-186 §8: one slot per branch in `location_ids`, created together (all or nothing). */
export async function createAppointmentSlotsAt(token: string, body: AppointmentSlotInput, locationIds: string[]) {
  const response = await apiRequest<SlotResponse & { slots?: SlotResponse["slot"][] }>("/staff/appointment-slots", {
    method: "POST",
    token,
    body: { ...body, location_id: null, location_ids: locationIds },
  });
  return response.slots ?? [response.slot];
}

export async function cancelAppointmentSlot(token: string, slotId: string) {
  const response = await apiRequest<SlotResponse>(`/staff/appointment-slots/${slotId}/cancel`, {
    method: "POST",
    token,
  });
  return response.slot;
}

export async function bookAppointmentForClient(token: string, slotId: string, userId: string) {
  const response = await apiRequest<BookingResponse>(`/staff/appointment-slots/${slotId}/bookings`, {
    method: "POST",
    token,
    body: { user_id: userId },
  });
  return response.appointment;
}

export async function recordAppointmentAttendance(token: string, bookingId: string, status: AttendanceStatus) {
  const response = await apiRequest<BookingResponse>(`/staff/appointments/${bookingId}/attendance`, {
    method: "POST",
    token,
    body: { status },
  });
  return response.appointment;
}

export async function cancelAppointmentBooking(token: string, bookingId: string) {
  const response = await apiRequest<StaffCancelResponse>(`/staff/appointments/${bookingId}/cancel`, {
    method: "POST",
    token,
  });
  return response.appointment;
}

type GymStaffResponse = Json<operations["PaleeWeb.StaffController.index"]["responses"][200]>;

/** One owner, admin or coach of this gym, with their role in this gym. */
export type StaffMember = GymStaffResponse["staff"][number];

export async function fetchGymStaff(token: string) {
  const response = await apiRequest<GymStaffResponse>("/staff/members", { token });
  return response.staff;
}
