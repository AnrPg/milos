import { apiRequest } from "@/api/client";
import type { TimerSegment } from "@/api/executions";
import type { WorkoutBody } from "@/api/workouts";
import type { FreeTextTimerPreset } from "@/lib/free-text-timer";

export type ClassTimerStatus = "ready" | "running" | "paused" | "finished";

export type ClassTimerState = {
  status: ClassTimerStatus;
  current_segment_index: number;
  /** May be in the future: the get-ready countdown before the segment starts. */
  segment_started_at_utc: string | null;
  paused_elapsed_ms: number;
  duration_adjustments: Record<string, unknown>;
  timer_preset: FreeTextTimerPreset | null;
  lock_version: number;
  updated_at?: string | null;
};

export type ClassTimerPayload = {
  class: { id: string; name: string; scheduled_at: string; duration_minutes: number };
  workout: {
    id: string;
    title: string;
    authoring_mode?: string | null;
    free_text_body?: string | null;
    /** ADR-224: the WOD as written; each segment's `section_id` points at one of its sections. */
    body?: WorkoutBody | null;
  } | null;
  segments: TimerSegment[];
  timer: ClassTimerState;
  server_now: string;
};

export type ClassTimerCommand =
  | { command: "start"; countdown_seconds?: number }
  | { command: "pause" | "resume" | "next" | "previous" | "reset" | "finish" }
  | { command: "jump"; index: number }
  | { command: "adjust"; delta_seconds: number }
  | { command: "configure"; timer_preset: FreeTextTimerPreset | null };

export function fetchClassTimer(token: string, slotId: string) {
  return apiRequest<ClassTimerPayload>(`/class-timers/${slotId}`, { token });
}

export function sendClassTimerCommand(
  token: string,
  slotId: string,
  command: ClassTimerCommand,
  expectedVersion: number,
) {
  return apiRequest<ClassTimerPayload>(`/class-timers/${slotId}/commands`, {
    method: "POST",
    token,
    body: { ...command, expected_version: expectedVersion },
  });
}
