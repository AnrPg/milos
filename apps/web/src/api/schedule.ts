import type { AssignedWorkoutPreview } from "@/api/assigned-workouts";
import type { WorkoutContentEntry } from "@/components/workouts/WorkoutContent";
import { apiRequest } from "@/api/client";
import type { operations, paths } from "@/api/generated/schema";

type CreateBookingRequest = NonNullable<
  operations["PaleeWeb.ScheduleController.create_booking"]["requestBody"]
>["content"]["application/json"];
type ResolveBookingRequest = NonNullable<
  operations["PaleeWeb.AdminScheduleController.approve_booking"]["requestBody"]
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
  /** Who the class suits (Phase 2 Επίπεδο filter). */
  level?: ClassLevel;
  /** Groups the class is for; empty means everyone (Κοινό filter). */
  audiences?: ClassAudience[];
};

export const CLASS_LEVELS = ["beginner", "all_levels", "advanced"] as const;
export type ClassLevel = (typeof CLASS_LEVELS)[number];
export const CLASS_AUDIENCES = ["women_only", "teens", "kids", "over_40", "seniors", "prenatal_postnatal", "adaptive"] as const;
export type ClassAudience = (typeof CLASS_AUDIENCES)[number];
export const WORKOUT_FOCUSES = [
  "strength",
  "endurance",
  "gymnastics",
  "olympic_lifting",
  "mobility",
  "legs",
  "core",
  "upper_body",
] as const;
export type WorkoutFocus = (typeof WORKOUT_FOCUSES)[number];

export type ScheduleCoach = { id: string; nickname: string; avatar_url: string | null };

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
  content?: WorkoutContentEntry[];
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
  content?: WorkoutContentEntry[];
  exercises: WorkoutPreviewExercise[];
};

export type WorkoutPreview = {
  id: string;
  title: string;
  type: string;
  authoring_mode?: "structured" | "quick_text" | "free_text" | "sectioned_text";
  free_text_body?: string | null;
  free_text_document?: Record<string, unknown> | null;
  /** Οδηγίες and the rest of the workout's content (ADR-140 §4). */
  content?: WorkoutContentEntry[];
  sections: WorkoutPreviewSection[];
  /** What the workout trains, read from its movements. */
  focus?: WorkoutFocus[];
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
  /** "trial" for a visitor's trial class (ADR-144); otherwise a regular booking. */
  kind?: string | null;
  entitlement_allowance?: string | null;
  waitlist_priority?: number | null;
  /** 1-based place in the queue, only while waitlisted. */
  waitlist_position?: number | null;
  /** The member's own attendance on this class (TD-105), e.g. "attended". */
  attendance_status?: string | null;
  /** When the member may check themselves in (own booking only). */
  check_in_opens_at?: string | null;
  check_in_closes_at?: string | null;
};

export type FriendGoing = { id: string; nickname?: string | null; avatar_url?: string | null };

/**
 * ADR-176: "linked" has its WOD; "missing" is the incomplete badge (a draft,
 * or a series class from 00:00 on its day); "awaiting" is a series class on
 * an earlier day.
 */
export type ClassWorkoutStatus = "linked" | "awaiting" | "missing";

export type ScheduleSlot = {
  id: string;
  /** Null until a WOD is linked (ADR-176). */
  master_workout_id: string | null;
  /** False for a draft: no WOD and not in a series, so members can't see it. */
  published?: boolean;
  workout_status?: ClassWorkoutStatus;
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
  /** ADR-202: the room or area of the branch the class is held in. */
  space_id?: string | null;
  space?: { id: string; name: string } | null;
  /** Staff only: another class shares the space at an overlapping time (a warning). */
  space_overlap?: boolean;
  /** Staff only: the space was made unavailable for this class's time. */
  space_unavailable?: boolean;
  coach_user_id?: string | null;
  /** Members only: whether their package includes this class, visits aside. */
  covered_by_package?: boolean;
  /** Members only: until when withdrawing is free; null when no cutoff applies. */
  cancel_free_until?: string | null;
  /** Members only: people you follow who share their bookings and are going (ADR-142 decision 12). */
  friends_going?: FriendGoing[];
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
  coaches?: ScheduleCoach[];
};

export type ScheduleSlotPayload = {
  /** Optional (ADR-176): a standalone class without one stays a draft. */
  master_workout_id: string | null;
  class_type_id: string;
  name: string;
  duration_minutes: number;
  scheduled_at: string;
  capacity: number;
  auto_approve: boolean;
  booking_timeout_minutes: number;
  /** Optional gym location (ADR-097); null for single-site gyms. */
  location_id?: string | null;
  /** Optional space of the branch (ADR-202). */
  space_id?: string | null;
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
  level?: ClassLevel;
  audiences?: ClassAudience[];
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

/** Self check-in to a booked class, inside its window (TD-105). */
export async function checkInToClass(token: string, bookingId: string) {
  const response = await apiRequest<{ attendance: { scheduled_class_id: string; status: string; marked_at: string } }>(
    `/bookings/${encodeURIComponent(bookingId)}/check-in`,
    { method: "POST", token },
  );
  return response.attendance;
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

/**
 * ADR-186 §8: one class per branch in `location_ids`, created together (all
 * or nothing).
 */
export async function createScheduleSlotsAt(token: string, payload: ScheduleSlotPayload, locationIds: string[]) {
  const response = await apiRequest<{ slot: ScheduleSlot; slots: ScheduleSlot[] }>("/admin/schedule/slots", {
    method: "POST",
    token,
    body: { ...payload, location_id: null, location_ids: locationIds },
  });

  return response.slots ?? [response.slot];
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
    /** ADR-202: the space every class of the series is held in. */
    space_id?: string | null;
    /** ADR-186 §8: one series per branch, created together. */
    location_ids?: string[];
    /** Optional (ADR-176): each occurrence can get its own WOD later. */
    master_workout_id?: string | null;
  },
) {
  type CreatedSeries = { id: string; occurrence_count: number; location_id?: string | null };
  return apiRequest<{ series: CreatedSeries; series_list?: CreatedSeries[] }>(
    "/admin/schedule/slots/series",
    { method: "POST", token, body: payload },
  );
}

/**
 * ADR-200: how far an edit to one class of a series goes. Dates are on the
 * gym's clock, both inclusive.
 */
export type SeriesEditScope =
  | { scope: "this" }
  | { scope: "all" }
  | { scope: "range"; from: string; to: string };

export async function updateScheduleSlot(
  token: string,
  slotId: string,
  payload: ScheduleSlotPayload,
  seriesScope: SeriesEditScope = { scope: "this" },
) {
  const response = await apiRequest<{ slot: ScheduleSlot; updated_count: number }>(`/admin/schedule/slots/${slotId}`, {
    method: "PATCH",
    token,
    body: {
      ...payload,
      series_scope: seriesScope.scope,
      ...(seriesScope.scope === "range" ? { range_from: seriesScope.from, range_to: seriesScope.to } : {}),
    },
  });

  return { slot: response.slot, updatedCount: response.updated_count ?? 1 };
}

/** ADR-176: links a WOD to a class; publishes a draft. */
export async function linkScheduleSlotWorkout(token: string, slotId: string, workoutId: string) {
  const response = await apiRequest<{ slot: ScheduleSlot }>(`/admin/schedule/slots/${slotId}/workout`, {
    method: "PUT",
    token,
    body: { master_workout_id: workoutId },
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
