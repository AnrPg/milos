type ExecutionCandidate = { id: string; status: string };
type ScheduleCandidate = {
  id: string;
  scheduled_at: string;
  current_user_booking?: { status: string } | null;
};
type AssignmentCandidate = {
  id: string;
  scheduled_for: string;
  execution_status?: string | null;
  my_athlete_status?: string | null;
};

type WorkoutCtaInput = {
  role: string | undefined;
  now: Date;
  executions: ExecutionCandidate[];
  scheduleSlots: ScheduleCandidate[];
  assignments: AssignmentCandidate[];
};

export type WorkoutCta = { href: string; label: "log" | "resume" };

const TWO_HOURS_MS = 2 * 60 * 60 * 1_000;

export function workoutCta(input: WorkoutCtaInput): WorkoutCta | null {
  const activeExecution = input.executions.find((execution) => execution.status !== "completed");
  if (activeExecution) {
    return { href: `/workouts/${activeExecution.id}/execute`, label: "resume" };
  }

  if (input.role === "member") {
    const bookedClass = input.scheduleSlots.find((slot) => {
      const distance = new Date(slot.scheduled_at).getTime() - input.now.getTime();
      return slot.current_user_booking?.status === "approved" && Math.abs(distance) <= TWO_HOURS_MS;
    });

    if (bookedClass) return { href: `/schedule?open_slot=${bookedClass.id}`, label: "log" };
  }

  if (input.role === "athlete") {
    const today = localDate(input.now);
    const dueAssignment = input.assignments.find(
      (assignment) =>
        assignment.scheduled_for === today &&
        assignment.execution_status !== "completed" &&
        assignment.my_athlete_status !== "rejected",
    );

    if (dueAssignment) return { href: "/my-workouts", label: "log" };
  }

  return null;
}

function localDate(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}
