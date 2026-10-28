import { apiRequest } from "@/api/client";
import type { ScheduleSlot } from "@/api/schedule";

/**
 * ADR-224: the WOD of a whole day. A rule covers every class of the date
 * (`class_type_id` null; events only by their type) or one class type, and
 * every branch (`location_id` null) or one. Classes inherit it unless they
 * have their own WOD.
 */
export type DayWorkout = {
  id: string;
  /** The gym's own date, YYYY-MM-DD. */
  local_date: string;
  class_type_id: string | null;
  location_id: string | null;
  master_workout_id: string;
  workout: { id: string; title: string; type?: string | null } | null;
};

export type DayWorkoutRequest = {
  date: string;
  master_workout_id: string;
  /** Empty: every class of the day. */
  class_type_ids?: string[];
  location_id?: string | null;
  /** Also replace the WODs set on single classes in this scope. */
  replace_own?: boolean;
};

export type DayWorkoutClass = {
  id: string;
  name: string;
  scheduled_at: string;
  class_type_name?: string | null;
};

export type DayWorkoutPreview = {
  /** Classes that will take the day's WOD. */
  inherit: DayWorkoutClass[];
  /** Classes keeping a WOD of their own. */
  own: DayWorkoutClass[];
  /** Classes that already started; they keep their WOD. */
  started: DayWorkoutClass[];
};

export async function previewDayWorkout(token: string, request: DayWorkoutRequest) {
  return apiRequest<DayWorkoutPreview>("/admin/schedule/day-workouts/preview", {
    method: "POST",
    token,
    body: request,
  });
}

export async function setDayWorkout(token: string, request: DayWorkoutRequest) {
  return apiRequest<{ day_workouts: DayWorkout[]; changed_count: number }>("/admin/schedule/day-workouts", {
    method: "PUT",
    token,
    body: request,
  });
}

export async function removeDayWorkout(token: string, id: string) {
  return apiRequest<{ day_workout: DayWorkout; changed_count: number }>(`/admin/schedule/day-workouts/${id}`, {
    method: "DELETE",
    token,
  });
}

/** «Επαναφορά στο WOD ημέρας»: the class drops its own WOD for the day's. */
export async function followDayWorkout(token: string, slotId: string) {
  const response = await apiRequest<{ slot: ScheduleSlot }>(`/admin/schedule/slots/${slotId}/day-workout`, {
    method: "POST",
    token,
  });

  return response.slot;
}
