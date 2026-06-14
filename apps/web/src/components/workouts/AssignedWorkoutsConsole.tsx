"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  TouchSensor,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragStartEvent,
} from "@dnd-kit/core";

import { ApiError } from "@/api/client";
import { fetchTimerSequence, startExecution } from "@/api/executions";
import {
  deleteAssignedWorkout,
  fetchAssignedWorkoutWeek,
  listAthletes,
  rescheduleAssignment,
  updateAssignedWorkout,
  type AssignedWorkoutRecord,
  type AthleteOption,
} from "@/api/assigned-workouts";
import { useSession } from "@/components/session-provider";
import { AssignedWorkoutPanel } from "@/components/workouts/AssignedWorkoutPanel";
import { QuickAssignModal } from "@/components/workouts/QuickAssignModal";
import { WorkoutEditModal } from "@/components/workouts/WorkoutEditModal";
import { addLocalDays, formatLocalDate, startOfLocalWeek } from "@/lib/local-date";
import { downloadIcsEvent } from "@/lib/ics";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { workoutTypeColor } from "@/lib/workout-colors";
import { useExecutionStore } from "@/stores/execution";

type ViewMode = "3day" | "week" | "month";

function parseLocalDate(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
}

function formatShortDate(isoDate: string) {
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(
    parseLocalDate(isoDate),
  );
}

function formatMonthLabel(date: Date) {
  return new Intl.DateTimeFormat(undefined, { month: "long", year: "numeric" }).format(date);
}

function startOfLocalMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function addMonths(date: Date, n: number): Date {
  return new Date(date.getFullYear(), date.getMonth() + n, 1);
}

function generateMonthGrid(refDate: Date): string[] {
  const gridStart = startOfLocalWeek(startOfLocalMonth(refDate));
  return Array.from({ length: 42 }, (_, i) => formatLocalDate(addLocalDays(gridStart, i)));
}

function monthGridMondays(refDate: Date): string[] {
  const gridStart = startOfLocalWeek(startOfLocalMonth(refDate));
  return Array.from({ length: 6 }, (_, i) => formatLocalDate(addLocalDays(gridStart, i * 7)));
}

function DayHeader({ isoDate, compact, todayIso }: { isoDate: string; compact: boolean; todayIso: string }) {
  const d = parseLocalDate(isoDate);
  const weekday = new Intl.DateTimeFormat(undefined, { weekday: compact ? "short" : "long" }).format(d);
  const month = new Intl.DateTimeFormat(undefined, { month: "short" }).format(d);
  const day = d.getDate();
  const isToday = isoDate === todayIso;

  if (compact) {
    return (
      <div className="text-center">
        <p className="text-[10px] font-semibold uppercase tracking-[0.16em]" style={{ color: "#55556a" }}>{weekday}</p>
        <p className="text-base font-bold" style={{ color: isToday ? "#d95d39" : "#F0EDF8" }}>{day}</p>
      </div>
    );
  }

  return (
    <div>
      <p className="text-base font-bold" style={{ color: "#F0EDF8" }}>{weekday}</p>
      <p className="mt-0.5 text-xs">
        <span style={{ color: "#55556a" }}>{month} </span>
        <span style={{ color: isToday ? "#d95d39" : "#8888aa" }}>{day}</span>
      </p>
    </div>
  );
}

// ─── DnD sub-components ───────────────────────────────────────────────────────

function DraggableCard({
  assignment,
  disabled = false,
  className,
  style,
  children,
}: {
  assignment: AssignedWorkoutRecord;
  disabled?: boolean;
  className?: string;
  style?: React.CSSProperties;
  children: React.ReactNode;
}) {
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, isDragging } = useDraggable({
    id: assignment.id,
    data: { assignment },
    disabled,
  });

  return (
    <div
      ref={setNodeRef}
      className={className}
      style={{ ...style, opacity: isDragging ? 0.3 : 1, position: "relative" }}
    >
      <span
        ref={(el) => setActivatorNodeRef(el)}
        className="absolute right-2 top-2 z-10 select-none rounded p-1 text-base leading-none"
        style={{ color: "#3a3a55", cursor: "grab", touchAction: "none" }}
        {...listeners}
        {...attributes}
        role="button"
        tabIndex={-1}
        aria-label="Drag to reschedule"
      >
        ⠿
      </span>
      {children}
    </div>
  );
}

function DroppableDay({
  date,
  className,
  children,
}: {
  date: string;
  className?: string;
  children: React.ReactNode;
}) {
  const { setNodeRef, isOver } = useDroppable({ id: date });
  return (
    <div
      ref={setNodeRef}
      className={className}
      style={{
        outline: isOver ? "1px dashed rgba(217,93,57,0.6)" : "1px solid transparent",
        borderRadius: "0.8rem",
        transition: "outline-color 0.1s",
      }}
    >
      {children}
    </div>
  );
}

function DraggableMonthChip({
  assignment,
  disabled = false,
}: {
  assignment: AssignedWorkoutRecord;
  disabled?: boolean;
}) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: assignment.id,
    data: { assignment },
    disabled,
  });

  return (
    <p
      ref={setNodeRef}
      className="mt-0.5 truncate rounded px-1 py-0.5 text-[9px] font-semibold"
      style={{
        background: `${workoutTypeColor(assignment.workout.type)}26`,
        color: workoutTypeColor(assignment.workout.type),
        opacity: isDragging ? 0.3 : 1,
        cursor: "grab",
        touchAction: "none",
      }}
      onClick={(e) => e.stopPropagation()}
      {...listeners}
      {...attributes}
    >
      {assignment.workout.is_team_workout ? "👥 " : ""}{assignment.workout.title}
    </p>
  );
}

function DroppableMonthCell({
  date,
  isToday,
  outsideMonth,
  dayNum,
  assignments,
  onNavigate,
  todayIso,
}: {
  date: string;
  isToday: boolean;
  outsideMonth: boolean;
  dayNum: number;
  assignments: AssignedWorkoutRecord[];
  onNavigate: () => void;
  todayIso: string;
}) {
  const { setNodeRef, isOver } = useDroppable({ id: date });

  return (
    <div
      ref={setNodeRef}
      className="min-h-[5.5rem] cursor-pointer rounded-xl p-1.5"
      style={{
        background: isOver
          ? "rgba(217,93,57,0.1)"
          : outsideMonth
            ? "transparent"
            : "#111118",
        border: `1px solid ${isOver ? "#d95d39" : isToday ? "#d95d39" : outsideMonth ? "transparent" : "#1a1a28"}`,
        transition: "background 0.1s, border-color 0.1s",
      }}
      onClick={onNavigate}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") onNavigate(); }}
    >
      <span
        className="flex h-5 w-5 items-center justify-center rounded-full text-xs font-bold"
        style={{
          background: isToday ? "#d95d39" : "transparent",
          color: isToday ? "#fff" : outsideMonth ? "#2a2a3a" : "#F0EDF8",
        }}
      >
        {dayNum}
      </span>
      {assignments.slice(0, 2).map((a) => (
        <DraggableMonthChip
          key={a.id}
          assignment={a}
          disabled={a.execution_status === "completed" && date <= todayIso}
        />
      ))}
      {assignments.length > 2 ? (
        <p className="mt-0.5 text-[9px]" style={{ color: "#55556a" }}>
          +{assignments.length - 2} more
        </p>
      ) : null}
    </div>
  );
}

function DragGhostCard({ assignment }: { assignment: AssignedWorkoutRecord }) {
  return (
    <div
      className="rounded-[1.4rem] p-4 shadow-xl"
      style={{
        background: "#0d0d18",
        border: "1px solid #d95d39",
        width: 220,
        pointerEvents: "none",
      }}
    >
      <p className="text-[10px] font-semibold uppercase tracking-[0.18em]" style={{ color: workoutTypeColor(assignment.workout.type) }}>
        {assignment.workout.type}
      </p>
      <p className="mt-1 truncate text-sm font-semibold" style={{ color: "#F0EDF8" }}>
        {assignment.workout.title}
      </p>
    </div>
  );
}

// ─── Main component ───────────────────────────────────────────────────────────

export function AssignedWorkoutsConsole({
  initialOpenAssignmentId = null,
  pageTitle,
}: {
  initialOpenAssignmentId?: string | null;
  pageTitle?: string;
} = {}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { currentUser, tokens, signOut } = useSession();
  const initExecution = useExecutionStore((state) => state.initExecution);
  const [refDate, setRefDate] = useState<Date>(() => new Date());
  const [viewMode, setViewMode] = useState<ViewMode>("3day");
  const [allAssignments, setAllAssignments] = useState<AssignedWorkoutRecord[]>([]);
  const [athletes, setAthletes] = useState<AthleteOption[]>([]);
  const [panelAssignment, setPanelAssignment] = useState<AssignedWorkoutRecord | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editScheduledFor, setEditScheduledFor] = useState("");
  const [editAdminNotes, setEditAdminNotes] = useState("");
  const [editAthleteIds, setEditAthleteIds] = useState<string[]>([]);
  const [editQuery, setEditQuery] = useState("");
  const [athletesLoading, setAthletesLoading] = useState(false);
  const [savingEdit, setSavingEdit] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [launchingId, setLaunchingId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeAssignment, setActiveAssignment] = useState<AssignedWorkoutRecord | null>(null);
  const [editWorkoutTarget, setEditWorkoutTarget] = useState<AssignedWorkoutRecord | null>(null);
  const [filterAthleteIds, setFilterAthleteIds] = useState<string[]>([]);
  const [filterQuery, setFilterQuery] = useState("");
  const [filterAthletes, setFilterAthletes] = useState<AthleteOption[]>([]);
  const [filterDropdownOpen, setFilterDropdownOpen] = useState(false);
  const [showQuickAssign, setShowQuickAssign] = useState(false);

  const isAdmin = currentUser?.role === "admin";

  const openParamId = searchParams.get("open");
  const openParamDate = searchParams.get("date");
  const autoOpenedRef = useRef<string | null>(null);
  const initialOpenHandledRef = useRef(false);

  const [todayIso, setTodayIso] = useState(() => formatLocalDate(new Date()));
  useEffect(() => {
    const now = new Date();
    const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    const timerId = window.setTimeout(
      () => setTodayIso(formatLocalDate(new Date())),
      tomorrow.getTime() - now.getTime(),
    );
    return () => window.clearTimeout(timerId);
  }, [todayIso]);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 250, tolerance: 5 } }),
  );

  const weekStartsToFetch = useMemo(() => {
    if (viewMode === "month") return monthGridMondays(refDate);
    return [formatLocalDate(startOfLocalWeek(refDate))];
  }, [refDate, viewMode]);

  const accessToken = tokens?.access_token;

  const loadAssignments = useCallback(async () => {
    if (!accessToken) return;

    setLoading(true);
    setError(null);

    try {
      const results = await Promise.all(
        weekStartsToFetch.map((weekStart) =>
          fetchAssignedWorkoutWeek(accessToken, weekStart),
        ),
      );

      const seen = new Set<string>();
      const merged: AssignedWorkoutRecord[] = [];

      for (const result of results) {
        for (const assignment of result.assignments) {
          if (!seen.has(assignment.id)) {
            seen.add(assignment.id);
            merged.push(assignment);
          }
        }
      }

      setAllAssignments(merged);
    } catch (requestError) {
      if (
        requestError instanceof ApiError &&
        (requestError.status === 401 || requestError.status === 403)
      ) {
        signOut();
        return;
      }

      setError(
        requestError instanceof Error
          ? requestError.message
          : "Could not load assigned workouts.",
      );
    } finally {
      setLoading(false);
    }
  }, [accessToken, signOut, weekStartsToFetch]);

  useEffect(() => {
    queueMicrotask(() => {
      void loadAssignments();
    });
  }, [loadAssignments]);

  useEffect(() => {
    function handleUserSync(event: Event) {
      const detail = (event as CustomEvent<UserSyncDetail>).detail;

      if (!detail?.scopes.includes("assigned_workouts")) {
        return;
      }

      void loadAssignments();
    }

    window.addEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);

    return () => {
      window.removeEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);
    };
  }, [loadAssignments]);

  useEffect(() => {
    if (!isAdmin || !tokens?.access_token || !editingId) return;

    let cancelled = false;
    const timeoutId = window.setTimeout(() => {
      void listAthletes(tokens.access_token!, editQuery)
        .then((nextAthletes) => {
          if (!cancelled) setAthletes(nextAthletes);
        })
        .catch(() => {
          if (!cancelled) setAthletes([]);
        })
        .finally(() => {
          if (!cancelled) setAthletesLoading(false);
        });
    }, 150);

    return () => {
      cancelled = true;
      window.clearTimeout(timeoutId);
    };
  }, [editQuery, editingId, isAdmin, tokens?.access_token]);

  useEffect(() => {
    if (!isAdmin || !tokens?.access_token || !filterDropdownOpen) return;

    let cancelled = false;
    const timeoutId = window.setTimeout(() => {
      void listAthletes(tokens.access_token!, filterQuery)
        .then((result) => { if (!cancelled) setFilterAthletes(result); })
        .catch(() => { if (!cancelled) setFilterAthletes([]); });
    }, 200);

    return () => {
      cancelled = true;
      window.clearTimeout(timeoutId);
    };
  }, [filterQuery, filterDropdownOpen, isAdmin, tokens?.access_token]);

  useEffect(() => {
    if (!openParamId || autoOpenedRef.current === openParamId) return;

    const target = allAssignments.find((a) => a.id === openParamId);
    if (target) {
      autoOpenedRef.current = openParamId;
      const frame = window.requestAnimationFrame(() => setPanelAssignment(target));
      const params = new URLSearchParams(searchParams.toString());
      params.delete("open");
      params.delete("date");
      router.replace(`?${params.toString()}`, { scroll: false });
      return () => window.cancelAnimationFrame(frame);
    }

    // Assignment not in loaded week — navigate to the week containing the target date
    if (!loading && openParamDate) {
      const targetDate = new Date(openParamDate + "T00:00:00");
      if (!isNaN(targetDate.getTime())) {
        autoOpenedRef.current = openParamId;
        const frame = window.requestAnimationFrame(() => setRefDate(targetDate));

        return () => window.cancelAnimationFrame(frame);
      }
    }
  }, [openParamId, openParamDate, loading, allAssignments, searchParams, router]);

  useEffect(() => {
    if (!initialOpenAssignmentId || initialOpenHandledRef.current || allAssignments.length === 0) return;
    const assignment = allAssignments.find((a) => a.id === initialOpenAssignmentId);
    if (assignment) {
      initialOpenHandledRef.current = true;
      const frame = window.requestAnimationFrame(() => setPanelAssignment(assignment));

      return () => window.cancelAnimationFrame(frame);
    }
  }, [initialOpenAssignmentId, allAssignments]);

  const visibleDates = useMemo(() => {
    if (viewMode === "3day") {
      return Array.from({ length: 3 }, (_, i) => formatLocalDate(addLocalDays(refDate, i)));
    }
    if (viewMode === "week") {
      const weekStart = startOfLocalWeek(refDate);
      return Array.from({ length: 7 }, (_, i) => formatLocalDate(addLocalDays(weekStart, i)));
    }
    return generateMonthGrid(refDate);
  }, [refDate, viewMode]);

  const filteredAssignments = useMemo(() => {
    if (!isAdmin || filterAthleteIds.length === 0) return allAssignments;
    return allAssignments.filter((a) =>
      (a.athlete_ids ?? []).some((id) => filterAthleteIds.includes(id)),
    );
  }, [allAssignments, filterAthleteIds, isAdmin]);

  const assignmentMap = useMemo(() => {
    const map: Record<string, AssignedWorkoutRecord[]> = {};
    for (const date of visibleDates) map[date] = [];
    for (const a of filteredAssignments) {
      if (map[a.scheduled_for]) map[a.scheduled_for].push(a);
    }
    return map;
  }, [filteredAssignments, visibleDates]);

  const periodLabel = useMemo(() => {
    if (viewMode === "month") return formatMonthLabel(refDate);
    return `${formatShortDate(visibleDates[0])} – ${formatShortDate(visibleDates[visibleDates.length - 1])}`;
  }, [refDate, viewMode, visibleDates]);

  function navigate(direction: 1 | -1) {
    setLoading(true);
    setError(null);
    setRefDate((current) => {
      if (viewMode === "3day") return addLocalDays(current, direction * 3);
      if (viewMode === "week") return addLocalDays(current, direction * 7);
      return addMonths(current, direction);
    });
  }

  function goToToday() {
    setLoading(true);
    setError(null);
    setRefDate(new Date());
  }

  function beginEdit(assignment: AssignedWorkoutRecord) {
    setEditingId(assignment.id);
    setEditScheduledFor(assignment.scheduled_for);
    setEditAdminNotes(assignment.admin_notes ?? "");
    setEditAthleteIds(assignment.athlete_ids ?? []);
    setAthletes(assignment.athletes ?? []);
    setAthletesLoading(true);
    setEditQuery("");
    setError(null);
  }

  function cancelEdit() {
    setEditingId(null);
    setEditScheduledFor("");
    setEditAdminNotes("");
    setEditAthleteIds([]);
    setEditQuery("");
  }

  async function saveEdit(assignmentId: string) {
    if (!tokens?.access_token) return;
    setSavingEdit(true);
    setError(null);
    try {
      const existingAssignment = allAssignments.find((a) => a.id === assignmentId) ?? null;
      const updatedAssignment = await updateAssignedWorkout(tokens.access_token, assignmentId, {
        scheduled_for: editScheduledFor,
        athlete_ids: editAthleteIds,
        admin_notes: editAdminNotes.trim() || undefined,
      });

      const athletePool = [...(existingAssignment?.athletes ?? []), ...athletes].filter(
        (athlete, index, collection) =>
          collection.findIndex((c) => c.id === athlete.id) === index,
      );

      const hydratedAssignment = {
        ...updatedAssignment,
        athlete_ids: editAthleteIds,
        athletes: athletePool.filter((a) => editAthleteIds.includes(a.id)),
      };

      setAllAssignments((current) =>
        current.map((a) => (a.id === assignmentId ? hydratedAssignment : a)),
      );
      cancelEdit();
    } catch (requestError) {
      setError(
        requestError instanceof Error ? requestError.message : "Could not update assignment.",
      );
    } finally {
      setSavingEdit(false);
    }
  }

  async function removeAssignment(assignmentId: string) {
    if (!tokens?.access_token) return;
    setDeletingId(assignmentId);
    setError(null);
    try {
      await deleteAssignedWorkout(tokens.access_token, assignmentId);
      setAllAssignments((current) => current.filter((a) => a.id !== assignmentId));
      if (editingId === assignmentId) cancelEdit();
    } catch (requestError) {
      setError(
        requestError instanceof Error ? requestError.message : "Could not delete assignment.",
      );
    } finally {
      setDeletingId(null);
    }
  }

  async function executeAssignedWorkout(assignment: AssignedWorkoutRecord) {
    if (!tokens?.access_token || launchingId) return;

    setLaunchingId(assignment.id);
    setError(null);

    try {
      const execution = await startExecution(tokens.access_token, {
        master_workout_id: assignment.workout.id,
        source: "assigned",
        source_reference_id: assignment.id,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      });

      const segments = await fetchTimerSequence(tokens.access_token, assignment.workout.id, {
        source: "assigned",
        sourceReferenceId: assignment.id,
      });

      initExecution({
        executionId: execution.id,
        workoutId: assignment.workout.id,
        scaleSlug: null,
        segments,
        checkedExerciseIds: execution.checked_exercise_ids,
        sectionScores: execution.section_scores,
        exerciseNotes: execution.exercise_notes,
        currentSegmentIndex: execution.current_segment_index,
        status: execution.status,
        segmentStartedAt: execution.segment_started_at_utc
          ? Date.parse(execution.segment_started_at_utc)
          : null,
        pausedElapsed: execution.paused_elapsed_ms,
        totalElapsedMs: execution.total_elapsed_ms,
        sectionElapsedMs: execution.section_elapsed_ms,
        segmentCycleCounts: execution.segment_cycle_counts,
        resumeCountdownEndsAt: execution.resume_countdown_ends_at_utc
          ? Date.parse(execution.resume_countdown_ends_at_utc)
          : null,
      });

      router.push(`/workouts/${execution.id}/execute`);
    } catch (requestError) {
      if (
        requestError instanceof ApiError &&
        (requestError.status === 401 || requestError.status === 403)
      ) {
        signOut();
        return;
      }

      setError(
        requestError instanceof Error ? requestError.message : "Could not start workout execution.",
      );
    } finally {
      setLaunchingId(null);
    }
  }

  function handleDragStart({ active }: DragStartEvent) {
    const assignment = allAssignments.find((a) => a.id === active.id);
    setActiveAssignment(assignment ?? null);
  }

  function handleDragEnd({ active, over }: DragEndEvent) {
    setActiveAssignment(null);
    if (!over || !tokens?.access_token) return;

    const newDate = over.id as string;
    const assignment = allAssignments.find((a) => a.id === active.id);
    if (!assignment || assignment.scheduled_for === newDate) return;

    if (newDate < todayIso) {
      setError("Cannot reschedule a workout to a past date.");
      return;
    }

    setAllAssignments((current) =>
      current.map((a) => (a.id === assignment.id ? { ...a, scheduled_for: newDate } : a)),
    );

    void (async () => {
      try {
        if (isAdmin) {
          await updateAssignedWorkout(tokens.access_token!, assignment.id, {
            scheduled_for: newDate,
            athlete_ids: assignment.athlete_ids ?? [],
            admin_notes: assignment.admin_notes ?? undefined,
          });
        } else {
          const updated = await rescheduleAssignment(tokens.access_token!, assignment.id, newDate);
          setAllAssignments((current) =>
            current.map((a) => (a.id === updated.id ? updated : a)),
          );
        }
      } catch {
        setAllAssignments((current) =>
          current.map((a) => (a.id === assignment.id ? assignment : a)),
        );
        setError("Could not reschedule workout.");
      }
    })();
  }

  function renderMonthView() {
    const currentMonthPrefix = formatLocalDate(startOfLocalMonth(refDate)).slice(0, 7);

    return (
      <section>
        <div className="mb-1 grid grid-cols-7 gap-1">
          {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((label) => (
            <div
              key={label}
              className="py-1 text-center text-[10px] font-semibold uppercase tracking-[0.16em]"
              style={{ color: "#55556a" }}
            >
              {label}
            </div>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-1">
          {visibleDates.map((date) => {
            const dayAssignments = assignmentMap[date] ?? [];
            const outsideMonth = !date.startsWith(currentMonthPrefix);
            const isToday = date === todayIso;
            const dayNum = parseInt(date.split("-")[2], 10);

            return (
              <DroppableMonthCell
                key={date}
                date={date}
                isToday={isToday}
                outsideMonth={outsideMonth}
                dayNum={dayNum}
                assignments={dayAssignments}
                todayIso={todayIso}
                onNavigate={() => {
                  setLoading(true);
                  setError(null);
                  setRefDate(parseLocalDate(date));
                  setViewMode("3day");
                }}
              />
            );
          })}
        </div>
      </section>
    );
  }

  function renderWeekView() {
    return (
      <section className="overflow-x-auto pb-2">
        <div className="grid min-w-[48rem] grid-cols-7 gap-2">
          {visibleDates.map((date) => {
            const dayAssignments = assignmentMap[date] ?? [];
            const isToday = date === todayIso;

            return (
              <div
                key={date}
                className="rounded-[1.4rem] p-3"
                style={{
                  background: "#111118",
                  border: `1px solid ${isToday ? "#d95d39" : "#1a1a28"}`,
                  minHeight: "10rem",
                }}
              >
                <DayHeader isoDate={date} compact todayIso={todayIso} />
                <DroppableDay date={date} className="mt-3 space-y-1.5">
                  {dayAssignments.length === 0 ? (
                    <p className="text-[10px]" style={{ color: "#2a2a3a" }}>—</p>
                  ) : null}
                  {dayAssignments.map((a) => (
                    <DraggableCard
                      key={a.id}
                      assignment={a}
                      disabled={a.execution_status === "completed" && date <= todayIso}
                      style={{ background: "#0d0d18", border: "1px solid #1a1a28", borderRadius: "0.8rem" }}
                    >
                      <div className="flex items-start gap-1">
                        <button
                          className="min-w-0 flex-1 truncate rounded-[0.8rem] px-2 py-1.5 text-left transition-opacity hover:opacity-80"
                          onClick={() => {
                            setLoading(true);
                            setError(null);
                            setRefDate(parseLocalDate(date));
                            setViewMode("3day");
                          }}
                          type="button"
                        >
                          <div className="flex items-center gap-1">
                            <p className="truncate text-[10px] font-semibold" style={{ color: "#F0EDF8" }}>
                              {a.workout.title}
                            </p>
                            {a.workout.is_team_workout ? (
                              <span className="shrink-0 rounded px-1 text-[8px] font-bold" style={{ background: "rgba(251,191,36,0.2)", color: "#fbbf24" }}>T</span>
                            ) : null}
                          </div>
                          <p
                            className="text-[9px] uppercase tracking-[0.12em]"
                            style={{ color: workoutTypeColor(a.workout.type) }}
                          >
                            {a.workout.type}
                          </p>
                        </button>
                        <button
                          className="shrink-0 rounded px-1 py-1 text-[9px] font-bold leading-none transition-colors hover:opacity-80"
                          style={{ color: "#3a3a55" }}
                          onClick={(e) => {
                            e.stopPropagation();
                            downloadIcsEvent({ title: a.workout.title, date });
                          }}
                          title="Add to calendar"
                          type="button"
                        >
                          +cal
                        </button>
                      </div>
                    </DraggableCard>
                  ))}
                </DroppableDay>
              </div>
            );
          })}
        </div>
      </section>
    );
  }

  function renderThreeDayView() {
    return (
      <section className="grid gap-4 md:grid-cols-3">
        {visibleDates.map((date) => {
          const dayAssignments = assignmentMap[date] ?? [];
          const isToday = date === todayIso;

          return (
            <article
              key={date}
              className="rounded-[1.8rem] p-5"
              style={{
                background: "#111118",
                border: `1px solid ${isToday ? "#d95d39" : "#1a1a28"}`,
              }}
            >
              <DayHeader isoDate={date} compact={false} todayIso={todayIso} />

              <DroppableDay date={date} className="mt-5 space-y-3">
                {dayAssignments.length === 0 ? (
                  <div
                    className="rounded-[1.2rem] px-3 py-5 text-sm"
                    style={{ border: "1px dashed #1a1a28", color: "#3a3a55" }}
                  >
                    No workout assigned.
                  </div>
                ) : null}

                {dayAssignments.map((assignment) => {
                  const isRejected = assignment.my_athlete_status === "rejected";
                  const isDone = assignment.execution_status === "completed";
                  const isPastDone = isDone && date <= todayIso;
                  return (
                  <DraggableCard
                    key={assignment.id}
                    assignment={assignment}
                    disabled={isPastDone}
                    className="rounded-[1.4rem] p-4"
                    style={{
                      background: "#0d0d18",
                      border: `1px solid ${isRejected ? "#2a1a1a" : isPastDone ? "#1a2a1a" : "#1a1a28"}`,
                      opacity: isRejected ? 0.55 : 1,
                    }}
                  >
                    <button
                      className="w-full text-left"
                      onClick={() => setPanelAssignment(assignment)}
                      type="button"
                    >
                      <div className="flex items-center gap-2">
                        <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: isRejected ? "#55556a" : workoutTypeColor(assignment.workout.type) }}>
                          {assignment.workout.type}
                        </p>
                        {assignment.workout.is_team_workout ? (
                          <span className="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold" style={{ background: "rgba(251,191,36,0.15)", color: "#fbbf24", border: "1px solid rgba(251,191,36,0.3)" }}>
                            Team
                          </span>
                        ) : null}
                      </div>
                      {isRejected ? (
                        <span className="mt-1 inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold" style={{ background: "rgba(100,30,30,0.4)", color: "#e07a5f" }}>
                          Rejected by you
                        </span>
                      ) : isPastDone ? (
                        <span className="mt-1 inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold" style={{ background: "rgba(16,185,129,0.15)", color: "#34d399" }}>
                          Done ✓
                        </span>
                      ) : null}
                      <h2 className="mt-1.5 text-base font-semibold" style={{ color: isRejected ? "#55556a" : "#F0EDF8" }}>
                        {assignment.workout.title}
                      </h2>
                      <p className="mt-1 text-xs" style={{ color: "#8888aa" }}>
                        {assignment.workout.sections.length} section{assignment.workout.sections.length !== 1 ? "s" : ""}
                        {" · "}
                        {assignment.workout.sections.reduce((n, s) => n + s.exercises.length, 0)} exercises
                      </p>
                    </button>

                    {isAdmin ? (
                      <div className="mt-2.5 flex flex-wrap gap-1.5">
                        {(assignment.athletes ?? []).map((athlete) => (
                          <span
                            key={`${assignment.id}-${athlete.id}`}
                            className="rounded-full px-2 py-0.5 text-[10px] font-semibold"
                            style={{ background: "#9c799c", color: "#0A0A0F" }}
                          >
                            {athlete.nickname}
                          </span>
                        ))}
                      </div>
                    ) : null}

                    {assignment.admin_notes ? (
                      <p
                        className="mt-2.5 rounded-[1rem] px-3 py-2 text-xs"
                        style={{ background: "rgba(217,93,57,0.1)", color: "#e07a5f" }}
                      >
                        {assignment.admin_notes}
                      </p>
                    ) : null}

                    <div className="mt-2.5">
                      <button
                        className="rounded-full px-2.5 py-1 text-[10px] font-semibold transition-colors"
                        style={{ background: "#1a1a28", color: "#55556a", border: "1px solid #1e1e2e" }}
                        onClick={(e) => {
                          e.stopPropagation();
                          downloadIcsEvent({ title: assignment.workout.title, date });
                        }}
                        type="button"
                      >
                        + Add to calendar
                      </button>
                    </div>

                    {isAdmin ? (
                      <div className="mt-3 flex flex-wrap items-center gap-2">
                        <button
                          className="rounded-full px-3 py-1.5 text-xs font-semibold transition-colors"
                          style={{
                            background: "rgba(156,121,156,0.12)",
                            border: "1px solid rgba(156,121,156,0.2)",
                            color: "#9c799c",
                          }}
                          onClick={() => beginEdit(assignment)}
                          type="button"
                        >
                          Edit
                        </button>
                        <button
                          className="rounded-full px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
                          style={{
                            background: "rgba(217,93,57,0.1)",
                            border: "1px solid rgba(217,93,57,0.2)",
                            color: "#d95d39",
                          }}
                          disabled={deletingId === assignment.id}
                          onClick={() => void removeAssignment(assignment.id)}
                          type="button"
                        >
                          {deletingId === assignment.id ? "…" : "Delete"}
                        </button>
                        <button
                          className="rounded-full px-3 py-1.5 text-xs font-semibold transition-colors"
                          style={{
                            background: "rgba(136,136,170,0.1)",
                            border: "1px solid rgba(136,136,170,0.2)",
                            color: "#8888aa",
                          }}
                          onClick={() => setEditWorkoutTarget(assignment)}
                          type="button"
                        >
                          Edit workout
                        </button>
                      </div>
                    ) : null}

                    {isAdmin && editingId === assignment.id ? (
                      <div
                        className="mt-4 space-y-4 rounded-[1.2rem] p-4"
                        style={{ background: "#111118", border: "1px solid #1e1e2e" }}
                      >
                        <label className="block">
                          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                            Date
                          </span>
                          <input
                            className="mt-2 w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                            style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                            onChange={(event) => setEditScheduledFor(event.target.value)}
                            type="date"
                            value={editScheduledFor}
                          />
                        </label>

                        <label className="block">
                          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                            Athlete search
                          </span>
                          <input
                            className="mt-2 w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                            style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                            onChange={(event) => {
                              setAthletesLoading(true);
                              setEditQuery(event.target.value);
                            }}
                            placeholder="Filter athletes"
                            value={editQuery}
                          />
                        </label>

                        <div className="max-h-48 space-y-2 overflow-y-auto pr-1">
                          {athletes.map((athlete) => {
                            const selected = editAthleteIds.includes(athlete.id);
                            return (
                              <button
                                key={`${assignment.id}-${athlete.id}`}
                                className="flex w-full items-center justify-between rounded-[0.9rem] px-3 py-2 text-left text-sm transition-colors"
                                style={
                                  selected
                                    ? { background: "#9c799c", color: "#0A0A0F" }
                                    : { background: "#0d0d18", border: "1px solid #1a1a28", color: "#c0c0d8" }
                                }
                                onClick={() =>
                                  setEditAthleteIds((current) =>
                                    current.includes(athlete.id)
                                      ? current.filter((id) => id !== athlete.id)
                                      : [...current, athlete.id],
                                  )
                                }
                                type="button"
                              >
                                <span>{athlete.nickname}</span>
                                <span className="text-[11px] uppercase tracking-[0.18em]">
                                  {selected ? "Selected" : "Add"}
                                </span>
                              </button>
                            );
                          })}
                          {!athletesLoading && athletes.length === 0 ? (
                            <p
                              className="rounded-[0.9rem] px-3 py-4 text-sm"
                              style={{ border: "1px dashed #1a1a28", color: "#3a3a55" }}
                            >
                              No athletes matched that search.
                            </p>
                          ) : null}
                        </div>

                        <label className="block">
                          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                            Admin notes
                          </span>
                          <textarea
                            className="mt-2 min-h-24 w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                            style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                            onChange={(event) => setEditAdminNotes(event.target.value)}
                            value={editAdminNotes}
                          />
                        </label>

                        <div className="flex flex-wrap gap-2">
                          <button
                            className="rounded-full px-3 py-2 text-sm font-semibold disabled:opacity-50"
                            style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                            disabled={savingEdit || editAthleteIds.length === 0 || !editScheduledFor}
                            onClick={() => void saveEdit(assignment.id)}
                            type="button"
                          >
                            {savingEdit ? "Saving…" : "Save changes"}
                          </button>
                          <button
                            className="rounded-full px-3 py-2 text-sm font-medium transition-colors"
                            style={{ background: "#1a1a28", color: "#c0c0d8" }}
                            onClick={cancelEdit}
                            type="button"
                          >
                            Cancel
                          </button>
                        </div>
                      </div>
                    ) : null}
                  </DraggableCard>
                  );
                })}
              </DroppableDay>
            </article>
          );
        })}
      </section>
    );
  }

  return (
    <main className="min-h-screen px-4 py-8 md:px-8 md:py-12" style={{ background: "#0A0A0F" }}>
      <div className="mx-auto max-w-7xl space-y-6">
        <section
          className="flex flex-col gap-4 rounded-[2rem] px-6 py-5 sm:flex-row sm:items-center sm:justify-between"
          style={{ background: "#111118", border: "1px solid #1a1a28" }}
        >
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.28em] text-[#d95d39]">
              {pageTitle ?? (isAdmin ? "Workout Board" : "My Workouts")}
            </p>
            <h1 className="mt-1 text-2xl font-bold tracking-tight" style={{ color: "#F0EDF8" }}>
              {periodLabel}
            </h1>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <div className="flex rounded-full p-0.5" style={{ background: "#1a1a28" }}>
              {(["3day", "week", "month"] as ViewMode[]).map((mode) => (
                <button
                  key={mode}
                  className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
                  style={
                    viewMode === mode
                      ? { background: "#F0EDF8", color: "#0A0A0F" }
                      : { color: "#55556a" }
                  }
                  onClick={() => {
                    setLoading(true);
                    setError(null);
                    setViewMode(mode);
                  }}
                  type="button"
                >
                  {mode === "3day" ? "3d" : mode === "week" ? "7d" : "Mo"}
                </button>
              ))}
            </div>

            <button
              className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
              style={{ background: "#1a1a28", color: "#c0c0d8" }}
              onClick={() => navigate(-1)}
              type="button"
            >
              ←
            </button>
            <button
              className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
              style={{ background: "#1a1a28", color: "#c0c0d8" }}
              onClick={goToToday}
              type="button"
            >
              Today
            </button>
            <button
              className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
              style={{ background: "#1a1a28", color: "#c0c0d8" }}
              onClick={() => navigate(1)}
              type="button"
            >
              →
            </button>
          </div>
        </section>


        {isAdmin ? (
          <section className="relative flex flex-wrap items-center gap-2">
            <div className="relative">
              <input
                className="rounded-full px-4 py-2 text-sm outline-none"
                style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8", minWidth: "14rem" }}
                placeholder="Filter by athlete…"
                value={filterQuery}
                onFocus={() => setFilterDropdownOpen(true)}
                onBlur={() => window.setTimeout(() => setFilterDropdownOpen(false), 150)}
                onChange={(e) => {
                  setFilterQuery(e.target.value);
                  setFilterDropdownOpen(true);
                }}
              />
              {filterDropdownOpen && filterAthletes.length > 0 ? (
                <div
                  className="absolute left-0 top-full z-30 mt-1 w-64 rounded-[1rem] py-1 shadow-xl"
                  style={{ background: "#111118", border: "1px solid #1a1a28" }}
                >
                  {filterAthletes.map((athlete) => {
                    const selected = filterAthleteIds.includes(athlete.id);
                    return (
                      <button
                        key={athlete.id}
                        className="flex w-full items-center gap-2 px-4 py-2 text-left text-sm transition-colors"
                        style={{ color: selected ? "#d95d39" : "#F0EDF8" }}
                        onMouseDown={(e) => e.preventDefault()}
                        onClick={() => {
                          setFilterAthleteIds((current) =>
                            selected ? current.filter((id) => id !== athlete.id) : [...current, athlete.id],
                          );
                        }}
                        type="button"
                      >
                        <span
                          className="flex h-4 w-4 shrink-0 items-center justify-center rounded"
                          style={{
                            background: selected ? "#d95d39" : "#1a1a28",
                            border: `1px solid ${selected ? "#d95d39" : "#3a3a55"}`,
                          }}
                        >
                          {selected ? <span className="text-[10px] font-bold text-white">✓</span> : null}
                        </span>
                        {athlete.nickname}
                      </button>
                    );
                  })}
                </div>
              ) : null}
            </div>

            {filterAthleteIds.length > 0 ? (
              <>
                {filterAthleteIds.map((id) => {
                  const athlete = filterAthletes.find((a) => a.id === id) ?? allAssignments
                    .flatMap((a) => a.athletes ?? [])
                    .find((a) => a.id === id);
                  return athlete ? (
                    <span
                      key={id}
                      className="flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold"
                      style={{ background: "rgba(217,93,57,0.15)", border: "1px solid rgba(217,93,57,0.25)", color: "#d95d39" }}
                    >
                      {athlete.nickname}
                      <button
                        className="ml-0.5 opacity-70 hover:opacity-100"
                        onClick={() => setFilterAthleteIds((c) => c.filter((fid) => fid !== id))}
                        type="button"
                      >
                        ✕
                      </button>
                    </span>
                  ) : null;
                })}
                <button
                  className="rounded-full px-3 py-1 text-xs font-semibold transition-colors"
                  style={{ background: "#1a1a28", color: "#8888aa" }}
                  onClick={() => { setFilterAthleteIds([]); setFilterQuery(""); }}
                  type="button"
                >
                  Clear filter
                </button>
              </>
            ) : null}
          </section>
        ) : null}

        {error ? (
          <section
            className="rounded-[1.8rem] px-5 py-4 text-sm"
            style={{
              background: "rgba(217,93,57,0.1)",
              border: "1px solid rgba(217,93,57,0.2)",
              color: "#e07a5f",
            }}
          >
            {error}
          </section>
        ) : null}

        {loading ? (
          <section
            className="rounded-[1.8rem] px-5 py-4 text-sm"
            style={{ background: "#111118", border: "1px solid #1a1a28", color: "#55556a" }}
          >
            Loading…
          </section>
        ) : null}

        <DndContext
          sensors={sensors}
          onDragStart={handleDragStart}
          onDragEnd={handleDragEnd}
        >
          {!loading
            ? viewMode === "month"
              ? renderMonthView()
              : viewMode === "week"
                ? renderWeekView()
                : renderThreeDayView()
            : null}
          <DragOverlay>
            {activeAssignment ? <DragGhostCard assignment={activeAssignment} /> : null}
          </DragOverlay>
        </DndContext>

        {isAdmin && !loading ? (
          <section
            className="rounded-[1.8rem] p-6"
            style={{ background: "#111118", border: "1px solid #1a1a28" }}
          >
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>
                  Assign workout
                </p>
                <p className="mt-2 text-xl font-semibold" style={{ color: "#F0EDF8" }}>
                  Assign a workout to one or more athletes.
                </p>
              </div>
              <div className="flex flex-wrap gap-2">
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "#d95d39", color: "#fff" }}
                  onClick={() => setShowQuickAssign(true)}
                  type="button"
                >
                  Assign workout
                </button>
                <Link
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "#1a1a28", color: "#c0c0d8" }}
                  href="/admin/workouts"
                >
                  Workout library
                </Link>
              </div>
            </div>
          </section>
        ) : null}
      </div>

      {panelAssignment && tokens?.access_token ? (
        <AssignedWorkoutPanel
          key={panelAssignment.id}
          assignment={panelAssignment}
          isAdmin={isAdmin}
          accessToken={tokens.access_token}
          onClose={() => setPanelAssignment(null)}
          onStartWorkout={(assignment) => void executeAssignedWorkout(assignment)}
          onRejected={(rejectedId) =>
            setAllAssignments((current) =>
              current.map((a) =>
                a.id === rejectedId ? { ...a, my_athlete_status: "rejected" as const } : a
              )
            )
          }
          onDeleted={(deletedId) => {
            setAllAssignments((current) => current.filter((a) => a.id !== deletedId));
            setPanelAssignment(null);
          }}
          onEditWorkout={(assignment) => {
            setPanelAssignment(null);
            setEditWorkoutTarget(assignment);
          }}
          onRescheduled={(updated) => {
            setAllAssignments((current) =>
              current.map((a) => (a.id === updated.id ? updated : a)),
            );
          }}
          launching={launchingId === panelAssignment.id}
        />
      ) : null}

      {editWorkoutTarget && tokens?.access_token ? (
        <WorkoutEditModal
          workoutId={editWorkoutTarget.workout.id}
          workoutTitle={editWorkoutTarget.workout.title}
          accessToken={tokens.access_token}
          context={{
            kind: "assignment",
            sourceId: editWorkoutTarget.id,
            sourceLabel: `assignment on ${editWorkoutTarget.scheduled_for}`,
          }}
          onClose={() => setEditWorkoutTarget(null)}
        />
      ) : null}

      {showQuickAssign && tokens?.access_token ? (
        <QuickAssignModal
          accessToken={tokens.access_token}
          defaultDate={todayIso}
          onClose={() => setShowQuickAssign(false)}
          onAssigned={() => {
            setShowQuickAssign(false);
            void loadAssignments();
          }}
        />
      ) : null}
    </main>
  );
}
