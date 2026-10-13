import type { AssignedWorkoutPreview } from "@/api/assigned-workouts";
import { apiRequest } from "@/api/client";
import type { operations, paths } from "@/api/generated/schema";

type CreateBookingRequest = NonNullable<
  operations["MilosTrainingWeb.ScheduleController.create_booking"]["requestBody"]
>["content"]["application/json"];
type ResolveBookingRequest = NonNullable<
  operations["MilosTrainingWeb.AdminScheduleController.approve_booking"]["requestBody"]
>["content"]["application/json"];

type ScheduleQuery = NonNullable<
  paths["/api/org/{organization_slug}/schedule"]["get"]["parameters"]["query"]
>;
export type ClassTypeRecord = {
  id: string;
  name: string;
  slug: string;
  sort_order: number;
  archived_at: string | null;
  inserted_at?: string;
  updated_at?: string;
  future_classes_reassigned?: number;
  /** Visits one booking uses (1..10, ADR-097). */
  credit_cost?: number;
  kind?: "class" | "event";
};

export type ScheduleLocation = {
  id: string;
  name: string;
  address: string | null;
  archived_at: string | null;
};

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
  authoring_mode?: "structured" | "quick_text" | "free_text";
  free_text_body?: string | null;
  free_text_document?: Record<string, unknown> | null;
  sections: WorkoutPreviewSection[];
};

export type ScheduleBooking = {
  id: string;
  user_id: string;
  user_nickname?: string | null;
  status: "pending" | "approved" | "rejected" | "cancelled" | "waitlisted";
  admin_message?: string | null;
  inserted_at: string;
  /** Set on a guest booking made on the member's guest passes (ADR-097). */
  guest_name?: string | null;
  entitlement_allowance?: string | null;
  waitlist_priority?: number | null;
  /** 1-based place in the queue, only while waitlisted. */
  waitlist_position?: number | null;
};

export type ScheduleSlot = {
  id: string;
  master_workout_id: string;
  class_series_id?: string | null;
  name: string;
  duration_minutes: number;
  scheduled_at: string;
  class_type_id: string;
  class_type: ClassTypeRecord;
  capacity: number;
  auto_approve: boolean;
  booking_timeout_minutes: number;
  approved_booking_count: number;
  spots_remaining: number;
  workout: WorkoutPreview | null;
  current_user_booking?: ScheduleBooking | null;
  /** The member's own guest booking for this class, if any. */
  current_user_guest?: ScheduleBooking | null;
  location_id?: string | null;
  waitlist_count?: number;
  bookings: ScheduleBooking[];
  /** ADR-125: the acting member's own version of this class (members only). */
  my_version?: MemberClassVersion | null;
  /** ADR-125: every member's version of this class (staff only). */
  member_versions?: StaffMemberClassVersion[];
};

export type MemberClassVersion = {
  assignment_id: string;
  master_workout_id: string;
  scheduled_for: string;
  status?: "accepted" | null;
  execution_status?: "completed" | null;
  workout: AssignedWorkoutPreview;
};

export type StaffMemberClassVersion = {
  assignment_id: string;
  user_id: string;
  user_nickname?: string | null;
  master_workout_id: string;
  workout_title?: string | null;
};

export type ScheduleWindow = {
  start_date: string;
  end_date: string;
  days: number;
  class_types: ClassTypeRecord[];
  slots: ScheduleSlot[];
  locations?: ScheduleLocation[];
};

export type ScheduleSlotPayload = {
  master_workout_id: string;
  class_type_id: string;
  name: string;
  duration_minutes: number;
  scheduled_at: string;
  capacity: number;
  auto_approve: boolean;
  booking_timeout_minutes: number;
  /** Optional gym location (ADR-097); null for single-site gyms. */
  location_id?: string | null;
};

export async function fetchSchedule(
  token: string,
  params: {
    startAt: NonNullable<ScheduleQuery["start_at"]>;
    endAt: NonNullable<ScheduleQuery["end_at"]>;
    days: NonNullable<ScheduleQuery["days"]>;
    classTypeIds: string[];
  },
) {
  const search = new URLSearchParams({
    start_at: params.startAt,
    end_at: params.endAt,
    days: String(params.days),
  });

  params.classTypeIds.forEach((id) => search.append("class_type_ids[]", id));

  return apiRequest<ScheduleWindow>(`/schedule?${search.toString()}`, { token });
}

export async function listAdminClassTypes(token: string) {
  const response = await apiRequest<{ class_types: ClassTypeRecord[] }>("/admin/class-types", { token });
  return response.class_types;
}

export type ClassTypePayload = {
  name: string;
  sort_order?: number;
  credit_cost?: number;
  kind?: "class" | "event";
};

export async function createClassType(token: string, payload: ClassTypePayload) {
  const response = await apiRequest<{ class_type: ClassTypeRecord }>("/admin/class-types", {
    method: "POST",
    token,
    body: payload,
  });
  return response.class_type;
}

export async function updateClassType(
  token: string,
  id: string,
  payload: ClassTypePayload,
) {
  const response = await apiRequest<{ class_type: ClassTypeRecord }>(`/admin/class-types/${id}`, {
    method: "PATCH",
    token,
    body: payload,
  });
  return response.class_type;
}

export async function archiveClassType(token: string, id: string, replacementClassTypeId?: string) {
  const search = new URLSearchParams();
  if (replacementClassTypeId) search.set("replacement_class_type_id", replacementClassTypeId);
  const suffix = search.size > 0 ? `?${search.toString()}` : "";
  const response = await apiRequest<{ class_type: ClassTypeRecord }>(`/admin/class-types/${id}${suffix}`, {
    method: "DELETE",
    token,
  });
  return response.class_type;
}

/**
 * Offline-replay options (ADR-120). `clientOperationId` makes the command
 * idempotent on the server; `organizationSlug` pins a replay to the tenant
 * the user acted in, even if they switched organizations meanwhile.
 */
export type CommandReplayOptions = {
  clientOperationId?: string;
  organizationSlug?: string | null;
};

function pinnedPath(path: string, options?: CommandReplayOptions) {
  return options?.organizationSlug ? `/org/${options.organizationSlug}${path}` : path;
}

export async function createBooking(token: string, slotId: string, options?: CommandReplayOptions) {
  const body: CreateBookingRequest = { slot_id: slotId };
  if (options?.clientOperationId) body.client_operation_id = options.clientOperationId;

  const response = await apiRequest<{ booking: ScheduleBooking }>(pinnedPath("/bookings", options), {
    method: "POST",
    token,
    body,
  });

  return response.booking;
}

export async function joinWaitlist(token: string, slotId: string) {
  const response = await apiRequest<{ booking: ScheduleBooking }>("/bookings/waitlist", {
    method: "POST",
    token,
    body: { slot_id: slotId },
  });

  return response.booking;
}

export async function createGuestBooking(token: string, slotId: string, guestName: string) {
  const response = await apiRequest<{ booking: ScheduleBooking }>("/bookings/guests", {
    method: "POST",
    token,
    body: { slot_id: slotId, guest_name: guestName },
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

export async function createScheduleSeries(
  token: string,
  payload: {
    class_type_id: string;
    name: string;
    duration_minutes: number;
    timezone: string;
    starts_on: string;
    ends_on: string | null;
    local_start_time: string;
    weekdays: number[];
    excluded_dates: string[];
    capacity: number;
    auto_approve: boolean;
    booking_timeout_minutes: number;
    location_id?: string | null;
  },
) {
  return apiRequest<{ series: { id: string; occurrence_count: number } }>(
    "/admin/schedule/slots/series",
    { method: "POST", token, body: payload },
  );
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

export async function approveBooking(
  token: string,
  bookingId: string,
  adminMessage?: string,
  options?: CommandReplayOptions,
) {
  const response = await apiRequest<{ booking: ScheduleBooking }>(
    pinnedPath(`/admin/bookings/${bookingId}/approve`, options),
    { method: "PATCH", token, body: resolutionBody(adminMessage, options) },
  );

  return response.booking;
}

export async function rejectBooking(
  token: string,
  bookingId: string,
  adminMessage?: string,
  options?: CommandReplayOptions,
) {
  const response = await apiRequest<{ booking: ScheduleBooking }>(
    pinnedPath(`/admin/bookings/${bookingId}/reject`, options),
    { method: "PATCH", token, body: resolutionBody(adminMessage, options) },
  );

  return response.booking;
}

function resolutionBody(adminMessage: string | undefined, options?: CommandReplayOptions) {
  const body: ResolveBookingRequest = {};
  if (adminMessage) body.admin_message = adminMessage;
  if (options?.clientOperationId) body.client_operation_id = options.clientOperationId;
  return body;
}

/** Withdraws a booking, a guest booking or a waitlist place. `late_cancellation`
 * is true when the visit was still counted because of the cancellation cutoff. */
export async function cancelBooking(token: string, bookingId: string) {
  const response = await apiRequest<{ ok?: boolean; late_cancellation?: boolean } | null>(
    `/bookings/${bookingId}`,
    { method: "DELETE", token },
  );

  return { lateCancellation: response?.late_cancellation === true };
}

export async function sendSlotMessage(token: string, slotId: string, body: string) {
  await apiRequest(`/schedule/slots/${slotId}/message`, {
    method: "POST",
    token,
    body: { body },
  });
}
