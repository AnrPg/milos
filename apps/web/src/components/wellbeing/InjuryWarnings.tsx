"use client";

// ADR-114 injury-aware workout safety warnings. Self-contained and
// non-blocking: these components only inform. They never disable an
// assignment, booking or "Start workout" action, and a failed load simply
// renders a quiet notice.

import { useMutation, useQuery } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";

import {
  acknowledgeAthleteInjuryWarnings,
  acknowledgeMyInjuryWarnings,
  evaluateAthleteInjuryWarnings,
  fetchMyWorkoutInjuryWarnings,
  fetchSlotInjuryWarnings,
  type AthleteInjuryWarningEntry,
  type InjuryWarning,
  type InjuryWarningLevel,
  type SelfInjuryWarningSurface,
  type StaffInjuryWarningSurface,
} from "@/api/injury-warnings";
import { SemanticLabel } from "@/components/semantic-label";
import { useUiTranslations } from "@/i18n/ui";
import { affectedExercises, selectionKey, warnedAthletes } from "@/lib/injury-warnings";

export type StaffInjuryWarningApi = {
  evaluate: typeof evaluateAthleteInjuryWarnings;
  acknowledge: typeof acknowledgeAthleteInjuryWarnings;
};

export type SelfInjuryWarningApi = {
  fetch: typeof fetchMyWorkoutInjuryWarnings;
  acknowledge: typeof acknowledgeMyInjuryWarnings;
};

const defaultStaffApi: StaffInjuryWarningApi = {
  evaluate: evaluateAthleteInjuryWarnings,
  acknowledge: acknowledgeAthleteInjuryWarnings,
};

const defaultSelfApi: SelfInjuryWarningApi = {
  fetch: fetchMyWorkoutInjuryWarnings,
  acknowledge: acknowledgeMyInjuryWarnings,
};

function levelColor(level: InjuryWarningLevel) {
  return level === "avoid" ? "var(--danger)" : "var(--warning)";
}

export function InjuryWarningBadge({ level }: { level: InjuryWarningLevel }) {
  const i18n = useUiTranslations();
  if (level === "none") return null;

  return (
    <span
      className="inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.14em]"
      style={{
        background: `color-mix(in srgb, ${levelColor(level)} 16%, transparent)`,
        color: levelColor(level),
      }}
      data-testid="injury-warning-badge"
    >
      {level === "avoid" ? i18n("injuryWarningLevelAvoid") : i18n("injuryWarningLevelCaution")}
    </span>
  );
}

export function InjuryWarningDetails({
  warnings,
  showProvenance = false,
}: {
  warnings: InjuryWarning[];
  showProvenance?: boolean;
}) {
  const i18n = useUiTranslations();

  return (
    <ul className="space-y-2">
      {warnings.map((warning) => {
        const exercises = affectedExercises(warning);
        return (
          <li
            key={warning.injury_id}
            className="rounded-[0.9rem] px-3 py-2 text-xs"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
          >
            <div className="flex flex-wrap items-center gap-2">
              <InjuryWarningBadge level={warning.level} />
              <span className="font-semibold" style={{ color: "var(--text)" }}>
                <bdi>{warning.body_area}</bdi>
              </span>
              <span style={{ color: "var(--dim)" }}>
                <SemanticLabel value={warning.severity} />
              </span>
              {showProvenance && warning.provenance === "personal" ? (
                <span style={{ color: "var(--dim)" }}>{i18n("injuryWarningPersonal")}</span>
              ) : null}
            </div>
            {exercises.avoid.length > 0 ? (
              <p className="mt-1">{i18n("injuryWarningAvoidExercises", { names: exercises.avoid.join(", ") })}</p>
            ) : null}
            {exercises.caution.length > 0 ? (
              <p className="mt-1">{i18n("injuryWarningCautionExercises", { names: exercises.caution.join(", ") })}</p>
            ) : null}
            {warning.exercises.length === 0 ? <p className="mt-1">{i18n("injuryWarningUnmappedArea")}</p> : null}
            {warning.training_limitations ? (
              <p className="mt-1" style={{ color: "var(--muted)" }}>
                {i18n("injuryWarningLimitations", { text: warning.training_limitations })}
              </p>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

function PanelFrame({
  level,
  title,
  intro,
  children,
}: {
  level: InjuryWarningLevel;
  title: string;
  intro: string;
  children: ReactNode;
}) {
  return (
    <section
      className="rounded-[1.2rem] p-4"
      style={{
        background: `color-mix(in srgb, ${levelColor(level)} 7%, var(--panel))`,
        border: `1px solid color-mix(in srgb, ${levelColor(level)} 30%, var(--border))`,
      }}
      role="status"
      aria-live="polite"
    >
      <div className="flex flex-wrap items-center gap-2">
        <InjuryWarningBadge level={level} />
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {title}
        </p>
      </div>
      <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
        {intro}
      </p>
      <div className="mt-3 space-y-3">{children}</div>
    </section>
  );
}

function AcknowledgeButton({
  acknowledged,
  pending,
  onClick,
}: {
  acknowledged: boolean;
  pending: boolean;
  onClick: () => void;
}) {
  const i18n = useUiTranslations();

  if (acknowledged) {
    return (
      <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
        {i18n("injuryWarningAcknowledged")}
      </p>
    );
  }

  return (
    <button
      className="rounded-full px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
      style={{ background: "var(--border)", color: "var(--text-soft)" }}
      disabled={pending}
      onClick={onClick}
      type="button"
    >
      {i18n("injuryWarningAcknowledge")}
    </button>
  );
}

function StaffWarningsList({
  athletes,
  nameFor,
}: {
  athletes: AthleteInjuryWarningEntry[];
  nameFor: (userId: string) => string;
}) {
  return (
    <>
      {warnedAthletes(athletes, nameFor).map((athlete) => (
        <div key={athlete.user_id} className="space-y-2">
          <div className="flex items-center gap-2">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
              <bdi>{athlete.name}</bdi>
            </span>
            <InjuryWarningBadge level={athlete.level} />
          </div>
          <InjuryWarningDetails warnings={athlete.warnings} />
        </div>
      ))}
    </>
  );
}

/**
 * Staff panel for the assign-workout flow: re-evaluates whenever the
 * selection changes. Renders nothing while no selected person is warned.
 */
export function AthleteInjuryWarningsPanel({
  accessToken,
  workoutId,
  userIds,
  surface,
  nameFor,
  sourceContextId,
  api = defaultStaffApi,
}: {
  accessToken: string;
  workoutId: string;
  userIds: string[];
  surface: StaffInjuryWarningSurface;
  nameFor: (userId: string) => string;
  sourceContextId?: string;
  api?: StaffInjuryWarningApi;
}) {
  const i18n = useUiTranslations();
  const key = selectionKey(userIds);
  const [acknowledgedKey, setAcknowledgedKey] = useState<string | null>(null);
  const body = {
    workout_id: workoutId,
    user_ids: key ? key.split(",") : [],
    surface,
    source_context_id: sourceContextId ?? null,
  };

  const query = useQuery({
    queryKey: ["injury-warnings", "staff", workoutId, surface, key],
    queryFn: () => api.evaluate(accessToken, body),
    enabled: Boolean(accessToken && workoutId && key),
    staleTime: 30_000,
  });

  const acknowledge = useMutation({
    mutationFn: () => api.acknowledge(accessToken, body),
    onSuccess: () => setAcknowledgedKey(key),
  });

  if (!key) return null;
  if (query.isError) {
    return (
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {i18n("injuryWarningLoadFailed")}
      </p>
    );
  }
  if (!query.data || query.data.level === "none") return null;

  return (
    <PanelFrame level={query.data.level} title={i18n("injuryWarningStaffTitle")} intro={i18n("injuryWarningStaffIntro")}>
      <StaffWarningsList athletes={query.data.athletes} nameFor={nameFor} />
      <AcknowledgeButton
        acknowledged={acknowledgedKey === key}
        pending={acknowledge.isPending}
        onClick={() => acknowledge.mutate()}
      />
    </PanelFrame>
  );
}

/** Class roster data: one request per open slot, shared by badges and the panel. */
export function useSlotInjuryWarnings(accessToken: string, slotId: string, enabled: boolean, fetcher = fetchSlotInjuryWarnings) {
  return useQuery({
    queryKey: ["injury-warnings", "slot", slotId],
    queryFn: () => fetcher(accessToken, slotId),
    enabled: Boolean(enabled && accessToken && slotId),
    staleTime: 30_000,
  });
}

/** Staff panel for the class slot roster (booked members). */
export function RosterInjuryWarningsPanel({
  accessToken,
  slotId,
  workoutId,
  athletes,
  level,
  nameFor,
  acknowledgeFn = acknowledgeAthleteInjuryWarnings,
}: {
  accessToken: string;
  slotId: string;
  workoutId: string | null | undefined;
  athletes: AthleteInjuryWarningEntry[];
  level: InjuryWarningLevel;
  nameFor: (userId: string) => string;
  acknowledgeFn?: typeof acknowledgeAthleteInjuryWarnings;
}) {
  const i18n = useUiTranslations();
  const [acknowledged, setAcknowledged] = useState(false);
  const acknowledge = useMutation({
    mutationFn: () =>
      acknowledgeFn(accessToken, {
        workout_id: workoutId ?? "",
        user_ids: athletes.filter((athlete) => athlete.level !== "none").map((athlete) => athlete.user_id),
        surface: "class_roster",
        source_context_id: slotId,
      }),
    onSuccess: () => setAcknowledged(true),
  });

  if (level === "none" || !workoutId) return null;

  return (
    <PanelFrame level={level} title={i18n("injuryWarningStaffTitle")} intro={i18n("injuryWarningRosterIntro")}>
      <StaffWarningsList athletes={athletes} nameFor={nameFor} />
      <AcknowledgeButton acknowledged={acknowledged} pending={acknowledge.isPending} onClick={() => acknowledge.mutate()} />
    </PanelFrame>
  );
}

/**
 * The athlete/member's own warnings for a workout they are about to start
 * (assignment detail, class detail). Includes their personal injuries.
 */
export function MyInjuryWarningsPanel({
  accessToken,
  workoutId,
  surface,
  sourceContextId,
  api = defaultSelfApi,
}: {
  accessToken: string;
  workoutId: string;
  surface: SelfInjuryWarningSurface;
  sourceContextId?: string;
  api?: SelfInjuryWarningApi;
}) {
  const i18n = useUiTranslations();
  const [acknowledged, setAcknowledged] = useState(false);
  const options = { surface, source_context_id: sourceContextId ?? null };

  const query = useQuery({
    queryKey: ["injury-warnings", "self", workoutId, surface, sourceContextId ?? null],
    queryFn: () => api.fetch(accessToken, workoutId, options),
    enabled: Boolean(accessToken && workoutId),
    staleTime: 60_000,
  });

  const acknowledge = useMutation({
    mutationFn: () => api.acknowledge(accessToken, workoutId, options),
    onSuccess: () => setAcknowledged(true),
  });

  if (query.isError) {
    return (
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {i18n("injuryWarningLoadFailed")}
      </p>
    );
  }
  if (!query.data || query.data.level === "none") return null;

  return (
    <PanelFrame level={query.data.level} title={i18n("injuryWarningSelfTitle")} intro={i18n("injuryWarningSelfIntro")}>
      <InjuryWarningDetails warnings={query.data.warnings} showProvenance />
      <AcknowledgeButton acknowledged={acknowledged} pending={acknowledge.isPending} onClick={() => acknowledge.mutate()} />
    </PanelFrame>
  );
}
