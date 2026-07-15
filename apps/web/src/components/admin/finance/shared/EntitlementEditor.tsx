"use client";

export type EntitlementDraft = {
  channels: string[];
  capabilities: string[];
  classVisitLimit: string;
  classVisitPeriod: string;
  coachingTouchpointLimit: string;
  coachingTouchpointPeriod: string;
};

export const DEFAULT_ENTITLEMENT: EntitlementDraft = {
  channels: ["in_person"],
  capabilities: ["book_classes", "execute_class_workouts"],
  classVisitLimit: "unlimited",
  classVisitPeriod: "calendar_month",
  coachingTouchpointLimit: "0",
  coachingTouchpointPeriod: "calendar_month",
};

const CHANNELS = [
  ["in_person", "In-person classes"],
  ["workout_library", "Workout library"],
  ["personal_programming", "Personal programming"],
  ["coach_messaging", "Coach messaging"],
] as const;

const CAPABILITIES = [
  ["book_classes", "Book classes"],
  ["execute_class_workouts", "Execute class workouts"],
  ["execute_library_workouts", "Execute library workouts"],
  ["execute_assigned_workouts", "Execute assigned workouts"],
  ["receive_coaching_touchpoints", "Receive coaching touchpoints"],
] as const;

const PERIODS = [
  ["calendar_week", "Calendar week"],
  ["calendar_month", "Calendar month"],
  ["subscription_period", "Subscription period"],
] as const;

export function entitlementParams(draft: EntitlementDraft) {
  return {
    entitlement_version: 1,
    channels: draft.channels,
    capabilities: draft.capabilities,
    allowances: {
      class_visits: allowance(draft.classVisitLimit, draft.classVisitPeriod),
      coaching_touchpoints: allowance(
        draft.coachingTouchpointLimit,
        draft.coachingTouchpointPeriod,
      ),
    },
  };
}

export function entitlementDraft(params: unknown): EntitlementDraft {
  const value = (params ?? {}) as Record<string, unknown>;
  const allowances = (value.allowances ?? {}) as Record<string, Record<string, unknown>>;
  const visits = allowances.class_visits ?? {};
  const coaching = allowances.coaching_touchpoints ?? {};

  return {
    channels: Array.isArray(value.channels) ? value.channels.map(String) : [],
    capabilities: Array.isArray(value.capabilities) ? value.capabilities.map(String) : [],
    classVisitLimit: String(visits.limit ?? "unlimited"),
    classVisitPeriod: String(visits.period ?? "calendar_month"),
    coachingTouchpointLimit: String(coaching.limit ?? "0"),
    coachingTouchpointPeriod: String(coaching.period ?? "calendar_month"),
  };
}

function allowance(limit: string, period: string) {
  return {
    limit: limit.trim().toLowerCase() === "unlimited" ? "unlimited" : Number(limit),
    period,
    counted_kinds: [],
  };
}

export function EntitlementEditor({
  value,
  onChange,
}: {
  value: EntitlementDraft;
  onChange: (value: EntitlementDraft) => void;
}) {
  function toggle(key: "channels" | "capabilities", option: string) {
    const values = value[key];
    onChange({
      ...value,
      [key]: values.includes(option)
        ? values.filter((item) => item !== option)
        : [...values, option],
    });
  }

  return (
    <fieldset className="space-y-4 rounded-2xl p-4" style={{ border: "1px solid var(--border)" }}>
      <legend className="px-2 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--primary)" }}>
        Entitlements
      </legend>
      <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
        Channels describe what the package delivers. Capabilities describe what the user may do.
        Allowances define the measurable units and their reset boundary.
      </p>
      <ChoiceGroup label="Delivery channels" options={CHANNELS} selected={value.channels} onToggle={(item) => toggle("channels", item)} />
      <ChoiceGroup label="Capabilities" options={CAPABILITIES} selected={value.capabilities} onToggle={(item) => toggle("capabilities", item)} />
      <div className="grid gap-4 md:grid-cols-2">
        <AllowanceField
          label="Class visits"
          limit={value.classVisitLimit}
          period={value.classVisitPeriod}
          onLimit={(classVisitLimit) => onChange({ ...value, classVisitLimit })}
          onPeriod={(classVisitPeriod) => onChange({ ...value, classVisitPeriod })}
        />
        <AllowanceField
          label="Coaching touchpoints"
          limit={value.coachingTouchpointLimit}
          period={value.coachingTouchpointPeriod}
          onLimit={(coachingTouchpointLimit) => onChange({ ...value, coachingTouchpointLimit })}
          onPeriod={(coachingTouchpointPeriod) => onChange({ ...value, coachingTouchpointPeriod })}
        />
      </div>
    </fieldset>
  );
}

function ChoiceGroup({ label, options, selected, onToggle }: { label: string; options: ReadonlyArray<readonly [string, string]>; selected: string[]; onToggle: (item: string) => void }) {
  return (
    <div>
      <p className="mb-2 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{label}</p>
      <div className="grid gap-2 sm:grid-cols-2">
        {options.map(([key, text]) => (
          <label key={key} className="flex items-center gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
            <input type="checkbox" checked={selected.includes(key)} onChange={() => onToggle(key)} />
            {text}
          </label>
        ))}
      </div>
    </div>
  );
}

function AllowanceField({ label, limit, period, onLimit, onPeriod }: { label: string; limit: string; period: string; onLimit: (value: string) => void; onPeriod: (value: string) => void }) {
  return (
    <div className="space-y-2 rounded-xl p-3" style={{ background: "var(--bg-soft)" }}>
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{label}</p>
      <input
        aria-label={`${label} limit`}
        className="w-full rounded-lg px-3 py-2 text-sm"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        value={limit}
        onChange={(event) => onLimit(event.target.value)}
        placeholder="Number or unlimited"
      />
      <select
        aria-label={`${label} reset period`}
        className="w-full rounded-lg px-3 py-2 text-sm"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        value={period}
        onChange={(event) => onPeriod(event.target.value)}
      >
        {PERIODS.map(([key, text]) => <option key={key} value={key}>{text}</option>)}
      </select>
    </div>
  );
}
