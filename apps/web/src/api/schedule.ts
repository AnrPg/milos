import { apiRequest } from "@/api/client";
import type { paths } from "@/api/generated/schema";

type ScheduleQuery = NonNullable<
  paths["/api/schedule"]["get"]["parameters"]["query"]
>;
export type TrainingType = "crossfit" | "strength" | "gymnastics" | "aerobics" | "flexibility" | "recovery";

export type WorkoutPreviewExercise = {
  id: string;
  name: string;
  sets?: number | null;
  prescription_value?: number | null;
  prescription_unit?: string | null;
  load_value?: number | null;
  load_mode?: string | null;
  order: number;
  superset_group_id?: string | null;
  hr_zone?: number | null;
  tempo?: string | null;
  rest_seconds?: number | null;
  cluster_rest_seconds?: number | null;
  rest_pause_seconds?: number | null;
  pacing?: number | null;
  interval_assignment?: number | null;
  variations?: Array<{
    id?: string;
    description?: string | null;
    exercise_name_override?: string | null;
    sets?: number | null;
    prescription_value?: number | null;
    prescription_unit?: string | null;
    load_value?: number | null;
    load_mode?: string | null;
    excluded?: boolean;
    scale_level?: { id?: string; slug?: string; label?: string; sort_order?: number } | null;
  }>;
};

export type WorkoutPreviewSection = {
  id: string;
  name: string;
  order?: number;
  scoreable?: boolean;
  score_config?: Record<string, unknown> | null;
  timer_config?: Record<string, unknown> | null;
  exercises: WorkoutPreviewExercise[];
};

export type WorkoutPreview = {
  id: string;
  title: string;
  type: string;
  sections: WorkoutPreviewSection[];
};

export type ScheduleBooking = {
  id: string;
  user_id: string;
  user_nickname?: string | null;
  status: "pending" | "approved" | "rejected" | "cancelled";
  admin_message?: string | null;
  inserted_at: string;
};

export type ScheduleSlot = {
  id: string;
  master_workout_id: string;
  scheduled_at: string;
  training_type: TrainingType;
  capacity: number;
  auto_approve: boolean;
  booking_timeout_minutes: number;
  approved_booking_count: number;
  spots_remaining: number;
  workout: WorkoutPreview | null;
  current_user_booking?: ScheduleBooking | null;
  bookings: ScheduleBooking[];
};

export type ScheduleWindow = {
  start_date: string;
  end_date: string;
  days: number;
  slots: ScheduleSlot[];
};

export type ScheduleSlotPayload = {
  master_workout_id: string;
  training_type: TrainingType;
  scheduled_at: string;
  capacity: number;
  auto_approve: boolean;
  booking_timeout_minutes: number;
};

export async function fetchSchedule(
  token: string,
  params: {
    startAt: NonNullable<ScheduleQuery["start_at"]>;
    endAt: NonNullable<ScheduleQuery["end_at"]>;
    days: NonNullable<ScheduleQuery["days"]>;
    trainingType: TrainingType | null;
  },
) {
  const search = new URLSearchParams({
    start_at: params.startAt,
    end_at: params.endAt,
    days: String(params.days),
  });

  if (params.trainingType) {
    search.set("training_type", params.trainingType);
  }

  return apiRequest<ScheduleWindow>(`/schedule?${search.toString()}`, { token });
}

export async function createBooking(token: string, slotId: string) {
  const response = await apiRequest<{ booking: ScheduleBooking }>("/bookings", {
    method: "POST",
    token,
    body: { slot_id: slotId },
  });

  return response.booking;
}

export async function createScheduleSlot(token: string, payload: ScheduleSlotPayload) {
  const response = await apiRequest<{ slot: ScheduleSlot }>("/admin/schedule/slots", {
    method: "POST",
    token,
    body: payload,
  });

  return response.slot;
}

export async function updateScheduleSlot(token: string, slotId: string, payload: ScheduleSlotPayload) {
  const response = await apiRequest<{ slot: ScheduleSlot }>(`/admin/schedule/slots/${slotId}`, {
    method: "PATCH",
    token,
    body: payload,
  });

  return response.slot;
}

export async function deleteScheduleSlot(token: string, slotId: string) {
  await apiRequest<unknown>(`/admin/schedule/slots/${slotId}`, {
    method: "DELETE",
    token,
  });
}

export async function approveBooking(token: string, bookingId: string, adminMessage?: string) {
  const response = await apiRequest<{ booking: ScheduleBooking }>(`/admin/bookings/${bookingId}/approve`, {
    method: "PATCH",
    token,
    body: adminMessage ? { admin_message: adminMessage } : {},
  });

  return response.booking;
}

export async function rejectBooking(token: string, bookingId: string, adminMessage?: string) {
  const response = await apiRequest<{ booking: ScheduleBooking }>(`/admin/bookings/${bookingId}/reject`, {
    method: "PATCH",
    token,
    body: adminMessage ? { admin_message: adminMessage } : {},
  });

  return response.booking;
}

export async function cancelBooking(token: string, bookingId: string) {
  await apiRequest(`/bookings/${bookingId}`, {
    method: "DELETE",
    token,
  });
}

export async function sendSlotMessage(token: string, slotId: string, body: string) {
  await apiRequest(`/schedule/slots/${slotId}/message`, {
    method: "POST",
    token,
    body: { body },
  });
}
