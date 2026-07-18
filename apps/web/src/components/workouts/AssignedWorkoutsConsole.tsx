"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import {useUiLocale} from "@/i18n/use-ui-locale";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
import { fetchTimerSequence, startExecution, type SectionScore } from "@/api/executions";
import {
  deleteAssignedWorkout,
  fetchAssignedWorkoutWeek,
  listAthletes,
  requestWorkoutAssignment,
  rescheduleAssignment,
  updateAssignedWorkout,
  type AssignedWorkoutRecord,
  type AthleteOption,
} from "@/api/assigned-workouts";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";
import { ViewModeSelector } from "@/components/calendar/ViewModeSelector";
import { AssignedWorkoutPanel } from "@/components/workouts/AssignedWorkoutPanel";
import { QuickAssignModal } from "@/components/workouts/QuickAssignModal";
import { WorkoutEditModal } from "@/components/workouts/WorkoutEditModal";
import { addLocalDays, formatLocalDate, startOfLocalWeek } from "@/lib/local-date";
import { downloadIcsEvent } from "@/lib/ics";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { workoutTypeColor } from "@/lib/workout-colors";
import { useExecutionStore } from "@/stores/execution";
import { SemanticLabel } from "@/components/semantic-label";
import { LocalizedScore } from "@/components/localized-score";

type ViewMode = "3day" | "week" | "month";

function ScoreTooltip({ scores }: { scores: SectionScore[] }) {
  const i18n = useUiTranslations();
  if (scores.length === 0) return null;
  return (
    <div
      className="pointer-events-none absolute bottom-full start-1/2 z-50 mb-2 -translate-x-1/2 rounded-[1rem] px-3 py-2 shadow-[0_8px_32px_rgba(0,0,0,0.5)]"
      style={{
        background: "var(--panel)",
        border: "1px solid var(--border-strong)",
        minWidth: "140px",
        maxWidth: "220px",
      }}
    >
      <p className="mb-1.5 text-[9px] font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {i18n("scores126cb93")}
      </p>
      <div className="space-y-1">
        {scores.map((s, i) => (
          <div key={i} className="flex items-baseline justify-between gap-2">
            <span className="truncate text-[10px]" style={{ color: "var(--muted)" }}>
              {s.section_name ?? i18n("sectionf2c6b56") + (i + 1)}
            </span>
            <span className="shrink-0 text-[11px] font-semibold" style={{ color: "var(--success)" }}>
              <LocalizedScore value={s.value} scoreType={s.score_type} unit={s.unit} />
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function parseLocalDate(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
}

function formatShortDate(locale: string, isoDate: string) {
  return new Intl.DateTimeFormat(locale, { month: "short", day: "numeric" }).format(
    parseLocalDate(isoDate),
  );
}

function formatMonthLabel(locale: string, date: Date) {
  return new Intl.DateTimeFormat(locale, { month: "long", year: "numeric" }).format(date);
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
  const uiLocale = useUiLocale();
  const d = parseLocalDate(isoDate);
  const weekday = new Intl.DateTimeFormat(uiLocale, { weekday: compact ? "short" : "long" }).format(d);
  const month = new Intl.DateTimeFormat(uiLocale, { month: "short" }).format(d);
  const day = d.getDate();
  const isToday = isoDate === todayIso;

  if (compact) {
    return (
      <div className="text-center">
        <p className="text-[10px] font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{weekday}</p>
        <p className="text-base font-bold" style={{ color: isToday ? "var(--primary)" : "var(--text)" }}>{day}</p>
      </div>
    );
  }

  return (
    <div>
      <p className="text-base font-bold" style={{ color: "var(--text)" }}>{weekday}</p>
      <p className="mt-0.5 text-xs">
        <span style={{ color: "var(--dim)" }}>{month} </span>
        <span style={{ color: isToday ? "var(--primary)" : "var(--muted)" }}>{day}</span>
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
  const i18n = useUiTranslations();
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
        className="absolute end-2 top-2 z-10 select-none rounded p-1 text-base leading-none"
        style={{ color: "var(--dim)", cursor: "grab", touchAction: "none" }}
        {...listeners}
        {...attributes}
        role="button"
        tabIndex={-1}
        aria-label={i18n("dragToRescheduleb5f3f05")}
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
        outline: isOver ? "1px dashed color-mix(in srgb, var(--primary) 60%, transparent)" : "1px solid transparent",
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

  const isDone = assignment.execution_status === "completed";
  const hasScores = (assignment.execution_scores?.length ?? 0) > 0;

  return (
    <div className="group relative mt-0.5">
      <div
        ref={setNodeRef}
        className="truncate rounded px-1 py-0.5 text-[9px] font-semibold"
        style={{
          background: isDone
            ? "color-mix(in srgb, var(--success) 15%, transparent)"
            : `color-mix(in srgb, ${workoutTypeColor(assignment.workout.type)} 15%, transparent)`,
          color: isDone ? "var(--success)" : workoutTypeColor(assignment.workout.type),
          opacity: isDragging ? 0.3 : 1,
          cursor: disabled ? "default" : "grab",
          touchAction: "none",
        }}
        onClick={(e) => e.stopPropagation()}
        {...listeners}
        {...attributes}
      >
        {assignment.workout.is_team_workout ? "👥 " : ""}{assignment.workout.title}
        {isDone ? " ✓" : ""}
      </div>
      {isDone && hasScores ? (
        <div className="invisible absolute bottom-full start-1/2 z-50 mb-1 -translate-x-1/2 group-hover:visible">
          <ScoreTooltip scores={assignment.execution_scores!} />
        </div>
      ) : null}
    </div>
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
  const i18n = useUiTranslations();
  const { setNodeRef, isOver } = useDroppable({ id: date });

  return (
    <div
      ref={setNodeRef}
      className="min-h-[5.5rem] cursor-pointer rounded-xl p-1.5"
      style={{
        background: isOver
          ? "color-mix(in srgb, var(--primary) 10%, transparent)"
          : outsideMonth
            ? "transparent"
            : "var(--panel)",
        border: `1px solid ${isOver ? "var(--primary)" : isToday ? "var(--primary)" : outsideMonth ? "transparent" : "var(--border)"}`,
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
          background: isToday ? "var(--primary)" : "transparent",
          color: isToday ? "var(--primary-contrast)" : outsideMonth ? "var(--border-strong)" : "var(--text)",
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
        <p className="mt-0.5 text-[9px]" style={{ color: "var(--dim)" }}>
          +{assignments.length - 2} {i18n("moree7c95b4")}
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
        background: "var(--panel-muted)",
        border: "1px solid var(--primary)",
        width: 220,
        pointerEvents: "none",
      }}
    >
      <p className="text-[10px] font-semibold uppercase tracking-[0.18em]" style={{ color: workoutTypeColor(assignment.workout.type) }}>
        <SemanticLabel value={assignment.workout.type} />
      </p>
      <p className="mt-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
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
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
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
  const [requestingDate, setRequestingDate] = useState<string | null>(null);
  const [requestDate, setRequestDate] = useState("");
  const [requestNote, setRequestNote] = useState("");
  const [requestSaving, setRequestSaving] = useState(false);
  const [requestStatus, setRequestStatus] = useState<string | null>(null);
  const [requestError, setRequestError] = useState<string | null>(null);
  const [requestedDates, setRequestedDates] = useState<string[]>([]);

  const isAdmin = currentUser?.role === "admin";

  const openParamId = searchParams.get("open_assignment") ?? searchParams.get("open");
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
          ? localizeError(requestError, i18n)
          : i18n("couldNotLoadAssignedWorkouts4216f7d"),
      );
    } finally {
      setLoading(false);
    }
  }, [accessToken, i18n, signOut, weekStartsToFetch]);

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
      params.delete("open_assignment");
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
    if (openParamId || !openParamDate) return;

    const targetDate = new Date(openParamDate + "T00:00:00");
    if (isNaN(targetDate.getTime())) return;

    const frame = window.requestAnimationFrame(() => setRefDate(targetDate));
    return () => window.cancelAnimationFrame(frame);
  }, [openParamDate, openParamId]);

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
    if (viewMode === "month") return formatMonthLabel(uiLocale, refDate);
    return (formatShortDate(uiLocale, visibleDates[0])) + " – " + (formatShortDate(uiLocale, visibleDates[visibleDates.length - 1]));
  }, [refDate, uiLocale, viewMode, visibleDates]);

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

  function beginWorkoutRequest(date: string) {
    setRequestingDate(date);
    setRequestDate(date < todayIso ? todayIso : date);
    setRequestNote("");
    setRequestError(null);
    setRequestStatus(null);
  }

  function cancelWorkoutRequest() {
    setRequestingDate(null);
    setRequestDate("");
    setRequestNote("");
    setRequestError(null);
  }

  async function submitWorkoutRequest() {
    if (!tokens?.access_token || !requestDate) return;

    setRequestSaving(true);
    setRequestError(null);
    setRequestStatus(null);

    try {
      await requestWorkoutAssignment(tokens.access_token, requestDate, requestNote);
      setRequestedDates((current) =>
        current.includes(requestDate) ? current : [...current, requestDate],
      );
      setRequestStatus(i18n("requestSentFor0b1804b") + (requestDate) + ".");
      setRequestingDate(null);
      setRequestNote("");
    } catch (requestError) {
      setRequestError(
        requestError instanceof Error ? localizeError(requestError, i18n) : i18n("couldNotSendRequest3be3d2f"),
      );
    } finally {
      setRequestSaving(false);
    }
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
        requestError instanceof Error ? localizeError(requestError, i18n) : i18n("couldNotUpdateAssignmenta301a8e"),
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
        requestError instanceof Error ? localizeError(requestError, i18n) : i18n("couldNotDeleteAssignment3704beb"),
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
        requestError instanceof Error ? localizeError(requestError, i18n) : i18n("couldNotStartWorkoutExecution78f6030"),
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
      setError(i18n("cannotRescheduleAWorkoutToAPastDate49dd0f2"));
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
        setError(i18n("couldNotRescheduleWorkoute94cc0c"));
      }
    })();
  }

  function renderMonthView() {
    const currentMonthPrefix = formatLocalDate(startOfLocalMonth(refDate)).slice(0, 7);

    return (
      <section>
        <div className="mb-1 grid grid-cols-7 gap-1">
          {[i18n("mon24b2a09"), i18n("tue529541b"), i18n("wed23408b1"), i18n("thu3593ccd"), i18n("fribbd6e32"), i18n("sat6b782d4"), i18n("sun48c98ca")].map((label) => (
            <div
              key={label}
              className="py-1 text-center text-[10px] font-semibold uppercase tracking-[0.16em]"
              style={{ color: "var(--dim)" }}
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
                  background: "var(--panel)",
                  border: `1px solid ${isToday ? "var(--primary)" : "var(--border)"}`,
                  minHeight: "10rem",
                }}
              >
                <DayHeader isoDate={date} compact todayIso={todayIso} />
                <DroppableDay date={date} className="mt-3 space-y-1.5">
                  {dayAssignments.length === 0 ? (
                    <p className="text-[10px]" style={{ color: "var(--border-strong)" }}>—</p>
                  ) : null}
                  {dayAssignments.map((a) => {
                    const isWeekDone = a.execution_status === "completed" && date <= todayIso;
                    return (
                    <DraggableCard
                      key={a.id}
                      assignment={a}
                      disabled={isWeekDone}
                      className="group"
                      style={{ background: "var(--panel-muted)", border: `1px solid ${isWeekDone ? "color-mix(in srgb, var(--success) 25%, var(--border))" : "var(--border)"}`, borderRadius: "0.8rem", position: "relative" }}
                    >
                      {isWeekDone && (a.execution_scores?.length ?? 0) > 0 ? (
                        <div className="invisible absolute bottom-full start-1/2 z-50 mb-1.5 -translate-x-1/2 group-hover:visible">
                          <ScoreTooltip scores={a.execution_scores!} />
                        </div>
                      ) : null}
                      <div className="flex items-start gap-1">
                        <button
                          className="min-w-0 flex-1 truncate rounded-[0.8rem] px-2 py-1.5 text-start transition-opacity hover:opacity-80"
                          onClick={() => {
                            setLoading(true);
                            setError(null);
                            setRefDate(parseLocalDate(date));
                            setViewMode("3day");
                          }}
                          type="button"
                        >
                          <div className="flex items-center gap-1">
                            <p className="truncate text-[10px] font-semibold" style={{ color: isWeekDone ? "var(--success)" : "var(--text)" }}>
                              {a.workout.title}
                            </p>
                            {a.workout.is_team_workout ? (
                              <span className="shrink-0 rounded px-1 text-[8px] font-bold" style={{ background: "color-mix(in srgb, var(--warning) 20%, transparent)", color: "var(--warning)" }}>{i18n("tc2c53d6")}</span>
                            ) : null}
                          </div>
                          <p
                            className="text-[9px] uppercase tracking-[0.12em]"
                            style={{ color: workoutTypeColor(a.workout.type) }}
                          >
                            <SemanticLabel value={a.workout.type} />
                          </p>
                        </button>
                        <button
                          className="shrink-0 rounded px-1 py-1 text-[9px] font-bold leading-none transition-colors hover:opacity-80"
                          style={{ color: "var(--dim)" }}
                          onClick={(e) => {
                            e.stopPropagation();
                            downloadIcsEvent({ title: a.workout.title, date });
                          }}
                          title={i18n("addToCalendar4f05cd6")}
                          type="button"
                        >
                          {i18n("cal183eee3")}
                        </button>
                      </div>
                    </DraggableCard>
                  );
                  })}
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
                background: "var(--panel)",
                border: `1px solid ${isToday ? "var(--primary)" : "var(--border)"}`,
              }}
            >
              <DayHeader isoDate={date} compact={false} todayIso={todayIso} />

              <DroppableDay date={date} className="mt-5 space-y-3">
                {dayAssignments.length === 0 ? (
                  <div
                    className="rounded-[1.2rem] px-3 py-5 text-sm"
                    style={{ border: "1px dashed var(--border)", color: "var(--dim)" }}
                  >
                    <div className="flex flex-col gap-3">
                      <p>{i18n("noWorkoutAssigned9553f04")}</p>
                      {!isAdmin && date >= todayIso ? (
                        requestingDate === date ? (
                          <div className="space-y-2">
                            <input
                              className="w-full rounded-[0.8rem] px-3 py-2 text-xs outline-none"
                              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                              type="date"
                              min={todayIso}
                              value={requestDate}
                              onChange={(event) => setRequestDate(event.target.value)}
                            />
                            <textarea
                              className="min-h-16 w-full rounded-[0.8rem] px-3 py-2 text-xs outline-none"
                              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                              placeholder={i18n("optionalNote9873e59")}
                              value={requestNote}
                              onChange={(event) => setRequestNote(event.target.value)}
                              maxLength={500}
                            />
                            {requestError ? (
                              <p className="text-[11px]" style={{ color: "var(--primary-strong)" }}>{requestError}</p>
                            ) : null}
                            <div className="flex flex-wrap gap-2">
                              <button
                                className="rounded-full px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
                                style={{ background: "var(--border)", color: "var(--text-soft)", border: "1px solid var(--border-strong)" }}
                                disabled={requestSaving || !requestDate}
                                onClick={() => void submitWorkoutRequest()}
                                type="button"
                              >
                                {requestSaving ? i18n("sendingcf76551") : i18n("send9bc2575")}
                              </button>
                              <button
                                className="rounded-full px-3 py-1.5 text-xs font-semibold"
                                style={{ color: "var(--dim)" }}
                                onClick={cancelWorkoutRequest}
                                type="button"
                              >
                                {i18n("cancel77dfd21")}
                              </button>
                            </div>
                          </div>
                        ) : requestedDates.includes(date) ? (
                          <p className="text-[11px]" style={{ color: "var(--dim)" }}>
                            {i18n("requestSentab95f1c")}
                          </p>
                        ) : (
                          <button
                            className="w-fit rounded-full px-2.5 py-1 text-[11px] font-semibold transition-opacity hover:opacity-80"
                            style={{ background: "transparent", border: "1px solid var(--border-strong)", color: "var(--dim)" }}
                            onClick={() => beginWorkoutRequest(date)}
                            type="button"
                          >
                            {i18n("requestWorkout5ed523e")}
                          </button>
                        )
                      ) : null}
                    </div>
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
                    className="group relative rounded-[1.4rem] p-4"
                    style={{
                      background: "var(--panel-muted)",
                      border: `1px solid ${
                        isRejected
                          ? "color-mix(in srgb, var(--danger) 25%, var(--border))"
                          : isPastDone
                            ? "color-mix(in srgb, var(--success) 25%, var(--border))"
                            : "var(--border)"
                      }`,
                      opacity: isRejected ? 0.55 : 1,
                    }}
                  >
                    <button
                      className="w-full text-start"
                      onClick={() => setPanelAssignment(assignment)}
                      type="button"
                    >
                      <div className="flex items-center gap-2">
                        <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: isRejected ? "var(--dim)" : workoutTypeColor(assignment.workout.type) }}>
                          <SemanticLabel value={assignment.workout.type} />
                        </p>
                        {assignment.workout.is_team_workout ? (
                          <span className="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold" style={{ background: "color-mix(in srgb, var(--warning) 15%, transparent)", color: "var(--warning)", border: "1px solid color-mix(in srgb, var(--warning) 30%, transparent)" }}>
                            {i18n("team2188872")}
                          </span>
                        ) : null}
                      </div>
                      {isRejected ? (
                        <span className="mt-1 inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold" style={{ background: "color-mix(in srgb, var(--danger) 18%, transparent)", color: "var(--danger)" }}>
                          {i18n("rejectedByYou89c7171")}
                        </span>
                      ) : isPastDone ? (
                        <div className="relative mt-1 inline-block">
                          <span className="inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold" style={{ background: "color-mix(in srgb, var(--success) 15%, transparent)", color: "var(--success)" }}>
                            {i18n("donea821d15")}
                          </span>
                          {(assignment.execution_scores?.length ?? 0) > 0 ? (
                            <div className="invisible absolute bottom-full start-1/2 z-50 mb-1.5 -translate-x-1/2 group-hover:visible">
                              <ScoreTooltip scores={assignment.execution_scores!} />
                            </div>
                          ) : null}
                        </div>
                      ) : null}
                      <h2 className="mt-1.5 text-base font-semibold" style={{ color: isRejected ? "var(--dim)" : "var(--text)" }}>
                        {assignment.workout.title}
                      </h2>
                      <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
                        {assignment.workout.sections.length} {i18n("section20182fb")}{assignment.workout.sections.length !== 1 ? i18n("sa0f1490") : ""}
                        {" · "}
                        {assignment.workout.sections.reduce((n, s) => n + s.exercises.length, 0)} {i18n("exercises0ee6e81")}
                      </p>
                    </button>

                    {isAdmin ? (
                      <div className="mt-2.5 flex flex-wrap gap-1.5">
                        {(assignment.athletes ?? []).map((athlete) => (
                          <span
                            key={(assignment.id) + "-" + (athlete.id)}
                            className="rounded-full px-2 py-0.5 text-[10px] font-semibold"
                            style={{ background: "var(--primary)", color: "var(--bg)" }}
                          >
                            {athlete.nickname}
                          </span>
                        ))}
                      </div>
                    ) : null}

                    {assignment.admin_notes ? (
                      <p
                        className="mt-2.5 rounded-[1rem] px-3 py-2 text-xs"
                        style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", color: "var(--primary-strong)" }}
                      >
                        {assignment.admin_notes}
                      </p>
                    ) : null}

                    <div className="mt-2.5">
                      <button
                        className="rounded-full px-2.5 py-1 text-[10px] font-semibold transition-colors"
                        style={{ background: "var(--border)", color: "var(--dim)", border: "1px solid var(--border)" }}
                        onClick={(e) => {
                          e.stopPropagation();
                          downloadIcsEvent({ title: assignment.workout.title, date });
                        }}
                        type="button"
                      >
                        {i18n("addToCalendareee5400")}
                      </button>
                    </div>

                    {isAdmin ? (
                      <div className="mt-3 flex flex-wrap items-center gap-2">
                        <button
                          className="rounded-full px-3 py-1.5 text-xs font-semibold transition-colors"
                          style={{
                            background: "color-mix(in srgb, var(--primary) 12%, transparent)",
                            border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)",
                            color: "var(--primary)",
                          }}
                          onClick={() => beginEdit(assignment)}
                          type="button"
                        >
                          {i18n("edit5301648")}
                        </button>
                        <button
                          className="rounded-full px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
                          style={{
                            background: "color-mix(in srgb, var(--primary) 10%, transparent)",
                            border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)",
                            color: "var(--primary)",
                          }}
                          disabled={deletingId === assignment.id}
                          onClick={() => void removeAssignment(assignment.id)}
                          type="button"
                        >
                          {deletingId === assignment.id ? "…" : i18n("deletef6fdbe4")}
                        </button>
                        <button
                          className="rounded-full px-3 py-1.5 text-xs font-semibold transition-colors"
                          style={{
                            background: "color-mix(in srgb, var(--muted) 10%, transparent)",
                            border: "1px solid color-mix(in srgb, var(--muted) 20%, transparent)",
                            color: "var(--muted)",
                          }}
                          onClick={() => setEditWorkoutTarget(assignment)}
                          type="button"
                        >
                          {i18n("editWorkoutd299ce5")}
                        </button>
                      </div>
                    ) : null}

                    {isAdmin && editingId === assignment.id ? (
                      <div
                        className="mt-4 space-y-4 rounded-[1.2rem] p-4"
                        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                      >
                        <label className="block">
                          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                            {i18n("dateeb9a4bc")}
                          </span>
                          <input
                            className="mt-2 w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                            onChange={(event) => setEditScheduledFor(event.target.value)}
                            type="date"
                            value={editScheduledFor}
                          />
                        </label>

                        <label className="block">
                          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                            {i18n("athleteSearch22491bf")}
                          </span>
                          <input
                            className="mt-2 w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                            onChange={(event) => {
                              setAthletesLoading(true);
                              setEditQuery(event.target.value);
                            }}
                            placeholder={i18n("filterAthletes5e06f04")}
                            value={editQuery}
                          />
                        </label>

                        <div className="max-h-48 space-y-2 overflow-y-auto pe-1">
                          {athletes.map((athlete) => {
                            const selected = editAthleteIds.includes(athlete.id);
                            return (
                              <button
                                key={(assignment.id) + "-" + (athlete.id)}
                                className="flex w-full items-center justify-between rounded-[0.9rem] px-3 py-2 text-start text-sm transition-colors"
                                style={
                                  selected
                                    ? { background: "var(--primary)", color: "var(--bg)" }
                                    : { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }
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
                                  {selected ? i18n("selected9a976fc") : i18n("add61cc55a")}
                                </span>
                              </button>
                            );
                          })}
                          {!athletesLoading && athletes.length === 0 ? (
                            <p
                              className="rounded-[0.9rem] px-3 py-4 text-sm"
                              style={{ border: "1px dashed var(--border)", color: "var(--dim)" }}
                            >
                              {i18n("noAthletesMatchedThatSearchd4f2c56")}
                            </p>
                          ) : null}
                        </div>

                        <label className="block">
                          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                            {i18n("adminNotesdff73a2")}
                          </span>
                          <textarea
                            className="mt-2 min-h-24 w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                            onChange={(event) => setEditAdminNotes(event.target.value)}
                            value={editAdminNotes}
                          />
                        </label>

                        <div className="flex flex-wrap gap-2">
                          <button
                            className="rounded-full px-3 py-2 text-sm font-semibold disabled:opacity-50"
                            style={{ background: "var(--text)", color: "var(--bg)" }}
                            disabled={savingEdit || editAthleteIds.length === 0 || !editScheduledFor}
                            onClick={() => void saveEdit(assignment.id)}
                            type="button"
                          >
                            {savingEdit ? i18n("saving56a2285") : i18n("saveChanges179359b")}
                          </button>
                          <button
                            className="rounded-full px-3 py-2 text-sm font-medium transition-colors"
                            style={{ background: "var(--border)", color: "var(--text-soft)" }}
                            onClick={cancelEdit}
                            type="button"
                          >
                            {i18n("cancel77dfd21")}
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
    <main className="min-h-screen px-4 py-8 md:px-8 md:py-12" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-7xl space-y-6">
        <TransientHero
          collapsedTitle={pageTitle ?? (isAdmin ? i18n("workoutBoardc309600") : i18n("myWorkouts89fd2fd"))}
          label={i18n("workoutCalendarIntroduction1a3befd")}
          timeoutMs={3000}
        >
          <section className="rounded-[2rem] px-6 py-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-[var(--primary)]">
              {isAdmin ? i18n("personalCoaching6accdcd") : i18n("workoutCalendarf82cdf2")}
            </p>
            <h1 className="mt-1 text-2xl font-bold tracking-tight" style={{ color: "var(--text)" }}>
              {pageTitle ?? (isAdmin ? i18n("workoutBoardc309600") : i18n("myWorkouts89fd2fd"))}
            </h1>
          </section>
        </TransientHero>

        <section className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-col gap-5 xl:flex-row xl:items-center xl:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>
                {i18n("calendarWindow067b1fb")}
              </p>
              <h2 className="mt-1 text-xl font-bold tracking-tight" style={{ color: "var(--text)" }}>
                {periodLabel}
              </h2>
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <ViewModeSelector
                ariaLabel={i18n("calendarView2b4d458")}
                onChange={(mode) => {
                  setLoading(true);
                  setError(null);
                  setViewMode(mode);
                }}
                options={[
                  { value: "3day", label: i18n("message3d34f9efc"), accessibleLabel: i18n("threeDayView69e5393") },
                  { value: "week", label: i18n("message7dfd4a4c2"), accessibleLabel: i18n("weekView650551c") },
                  { value: "month", label: i18n("mo91e885d"), accessibleLabel: i18n("monthViewc8772b5") },
                ] satisfies Array<{ value: ViewMode; label: string; accessibleLabel: string }>}
                value={viewMode}
              />

              <div className="flex gap-2">
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                  onClick={() => navigate(-1)}
                  type="button"
                >
                  {i18n("preve96fea5")}
                </button>
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                  onClick={goToToday}
                  type="button"
                >
                  {i18n("today24345a1")}
                </button>
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                  onClick={() => navigate(1)}
                  type="button"
                >
                  {i18n("nextbc98198")}
                </button>
              </div>
            </div>
          </div>
        </section>


        {isAdmin ? (
          <section className="relative flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div className="flex min-w-0 flex-1 flex-wrap items-center gap-2">
              <div className="relative">
                <input
                  className="rounded-full px-4 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)", minWidth: "14rem" }}
                  placeholder={i18n("filterByAthletea7eb7e6")}
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
                    className="absolute start-0 top-full z-30 mt-1 w-64 rounded-[1rem] py-1 shadow-xl"
                    style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                  >
                    {filterAthletes.map((athlete) => {
                      const selected = filterAthleteIds.includes(athlete.id);
                      return (
                        <button
                          key={athlete.id}
                          className="flex w-full items-center gap-2 px-4 py-2 text-start text-sm transition-colors"
                          style={{ color: selected ? "var(--primary)" : "var(--text)" }}
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
                              background: selected ? "var(--primary)" : "var(--border)",
                              border: `1px solid ${selected ? "var(--primary)" : "var(--dim)"}`,
                            }}
                          >
                            {selected ? <span className="text-[10px] font-bold text-[var(--primary-contrast)]">✓</span> : null}
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
                        style={{ background: "color-mix(in srgb, var(--primary) 15%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 25%, transparent)", color: "var(--primary)" }}
                      >
                        {athlete.nickname}
                        <button
                          className="ms-0.5 opacity-70 hover:opacity-100"
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
                    style={{ background: "var(--border)", color: "var(--muted)" }}
                    onClick={() => { setFilterAthleteIds([]); setFilterQuery(""); }}
                    type="button"
                  >
                    {i18n("clearFilterb667d6f")}
                  </button>
                </>
              ) : null}
            </div>

            <button
              className="shrink-0 rounded-full px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              onClick={() => setShowQuickAssign(true)}
              type="button"
            >
              {i18n("assignWorkout3e28a99")}
            </button>
          </section>
        ) : null}

        {error ? (
          <section
            className="rounded-[1.8rem] px-5 py-4 text-sm"
            style={{
              background: "color-mix(in srgb, var(--primary) 10%, transparent)",
              border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)",
              color: "var(--primary-strong)",
            }}
          >
            {error}
          </section>
        ) : null}

        {!isAdmin && requestStatus ? (
          <section
            className="rounded-[1.2rem] px-4 py-3 text-xs"
            style={{ background: "color-mix(in srgb, var(--success) 8%, transparent)", border: "1px solid color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--success)" }}
          >
            {requestStatus}
          </section>
        ) : null}

        {loading ? (
          <section
            className="rounded-[1.8rem] px-5 py-4 text-sm"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--dim)" }}
          >
            {i18n("loading33ce417")}
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
            sourceLabel: i18n("assignmentOn11220d0") + (editWorkoutTarget.scheduled_for),
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
