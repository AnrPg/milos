import { apiRequest } from "@/api/client";
import type { SectionScore } from "@/api/executions";

export type AthleteOption = {
  id: string;
  nickname: string;
  role: string;
};

export type AssignedWorkoutPreview = {
  id: string;
  title: string;
  type: string;
  sections: Array<{
    id?: string;
    parent_section_id?: string | null;
    name: string;
    order: number;
    scoreable: boolean;
    score_config?: Record<string, unknown> | null;
    timer_config?: Record<string, unknown> | null;
    exercises: Array<{
      id?: string;
      name: string;
      sets?: number | null;
      prescription_value?: number | null;
      prescription_unit?: string | null;
      load_value?: number | null;
      load_mode?: string | null;
      superset_group_id?: string | null;
      hr_zone?: number | null;
      tempo?: string | null;
      rest_seconds?: number | null;
      cluster_rest_seconds?: number | null;
      rest_pause_seconds?: number | null;
      pacing?: number | null;
      interval_assignment?: number | null;
      order: number;
      variations?: Array<{
        id?: string;
        description?: string | null;
        sets?: number | null;
        prescription_value?: number | null;
        prescription_unit?: string | null;
        load_value?: number | null;
        load_mode?: string | null;
        excluded?: boolean;
        scale_level?: { id?: string; slug?: string; label?: string; sort_order?: number } | null;
      }>;
    }>;
  }>;
};

export type AssignedWorkoutRecord = {
  id: string;
  master_workout_id: string;
  scheduled_for: string;
  admin_notes?: string | null;
  athlete_ids?: string[];
  athletes?: AthleteOption[];
  workout: AssignedWorkoutPreview;
  my_athlete_status?: "accepted" | "rejected" | null;
  execution_status?: "completed" | null;
  execution_scores?: SectionScore[];
};

export type AssignedWorkoutWeek = {
  start_date: string;
  end_date: string;
  assignments: AssignedWorkoutRecord[];
};

export type AssignWorkoutPayload = {
  master_workout_id: string;
  athlete_ids: string[];
  scheduled_for: string;
  admin_notes?: string;
};

export type UpdateAssignedWorkoutPayload = {
  athlete_ids: string[];
  scheduled_for: string;
  admin_notes?: string;
};

export async function fetchAssignedWorkoutWeek(token: string, startDate?: string) {
  const search = new URLSearchParams();

  if (startDate) {
    search.set("start_date", startDate);
  }

  const suffix = search.toString() ? `?${search.toString()}` : "";
  return apiRequest<AssignedWorkoutWeek>(`/my-workouts${suffix}`, { token });
}

export async function assignWorkout(token: string, payload: AssignWorkoutPayload) {
  const response = await apiRequest<{ assignment: AssignedWorkoutRecord }>("/admin/assigned-workouts", {
    method: "POST",
    token,
    body: payload,
  });

  return response.assignment;
}

export async function updateAssignedWorkout(
  token: string,
  assignmentId: string,
  payload: UpdateAssignedWorkoutPayload,
) {
  const response = await apiRequest<{ assignment: AssignedWorkoutRecord }>(
    `/admin/assigned-workouts/${assignmentId}`,
    {
      method: "PATCH",
      token,
      body: payload,
    },
  );

  return response.assignment;
}

export async function deleteAssignedWorkout(token: string, assignmentId: string) {
  await apiRequest(`/admin/assigned-workouts/${assignmentId}`, {
    method: "DELETE",
    token,
  });
}

export async function rejectAssignment(token: string, assignmentId: string) {
  await apiRequest(`/my-workouts/assignments/${assignmentId}/reject`, {
    method: "PATCH",
    token,
  });
}

export type AssignmentMessage = {
  id: string;
  assigned_workout_id: string;
  sender_id: string;
  sender_nickname: string;
  body: string;
  inserted_at: string;
};

export async function fetchAssignmentMessages(
  token: string,
  assignmentId: string,
  isAdmin = false,
): Promise<AssignmentMessage[]> {
  const path = isAdmin
    ? `/admin/assigned-workouts/${assignmentId}/messages`
    : `/my-workouts/assignments/${assignmentId}/messages`;
  const data = await apiRequest<{ messages: AssignmentMessage[] }>(path, { token });
  return data.messages;
}

export async function postAssignmentMessage(
  token: string,
  assignmentId: string,
  body: string,
  isAdmin = false,
): Promise<AssignmentMessage> {
  const path = isAdmin
    ? `/admin/assigned-workouts/${assignmentId}/messages`
    : `/my-workouts/assignments/${assignmentId}/messages`;
  const data = await apiRequest<{ message: AssignmentMessage }>(path, {
    method: "POST",
    token,
    body: { body },
  });
  return data.message;
}

export async function rescheduleAssignment(
  token: string,
  assignmentId: string,
  scheduledFor: string,
): Promise<AssignedWorkoutRecord> {
  const response = await apiRequest<{ assignment: AssignedWorkoutRecord }>(
    `/my-workouts/assignments/${assignmentId}/reschedule`,
    { method: "PATCH", token, body: { scheduled_for: scheduledFor } },
  );
  return response.assignment;
}

export async function sendAssignmentMessage(token: string, assignmentId: string, body: string) {
  await apiRequest(`/my-workouts/assignments/${assignmentId}/message`, {
    method: "POST",
    token,
    body: { body },
  });
}

export async function listAthletes(token: string, query?: string) {
  const search = new URLSearchParams();

  if (query && query.trim()) {
    search.set("q", query.trim());
  }

  const suffix = search.toString() ? `?${search.toString()}` : "";
  const response = await apiRequest<{ athletes: AthleteOption[] }>(`/admin/athletes${suffix}`, { token });
  return response.athletes;
}
