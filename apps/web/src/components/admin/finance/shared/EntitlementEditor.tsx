"use client";






import {useUiTranslations} from "@/i18n/ui";
import { SemanticLabel } from "@/components/semantic-label";

const BLOCKED_CHANNELS = new Set(["workout_library"]);
const BLOCKED_CAPABILITIES = new Set([
  "execute_library_workouts",
  "receive_coaching_touchpoints",
]);

export type EntitlementDraft = {
  channels: string[];
  capabilities: string[];
  classVisitLimit: string;
  classVisitPeriod: string;
  coachingTouchpointLimit: string;
  coachingTouchpointPeriod: string;
};

export function sanitizeEntitlementDraft(draft: EntitlementDraft): EntitlementDraft {
  return {
    ...draft,
    channels: draft.channels.filter((channel) => !BLOCKED_CHANNELS.has(channel)),
    capabilities: draft.capabilities.filter((capability) => !BLOCKED_CAPABILITIES.has(capability)),
  };
}

export const DEFAULT_ENTITLEMENT: EntitlementDraft = {
  channels: ["in_person"],
  capabilities: ["book_classes", "execute_class_workouts"],
  classVisitLimit: "unlimited",
  classVisitPeriod: "calendar_month",
  coachingTouchpointLimit: "0",
  coachingTouchpointPeriod: "calendar_month",
};

export function entitlementParams(draft: EntitlementDraft) {
  const sanitized = sanitizeEntitlementDraft(draft);
  const allowances: Record<string, ReturnType<typeof allowance>> = {
    class_visits: allowance(sanitized.classVisitLimit, sanitized.classVisitPeriod),
  };

  if (sanitized.capabilities.includes("receive_coaching_touchpoints")) {
    allowances.coaching_touchpoints = allowance(
      sanitized.coachingTouchpointLimit,
      sanitized.coachingTouchpointPeriod,
    );
  }

  return {
    entitlement_version: 1,
    channels: sanitized.channels,
    capabilities: sanitized.capabilities,
    allowances,
  };
}

export function entitlementDraft(params: unknown): EntitlementDraft {
  const value = (params ?? {}) as Record<string, unknown>;
  const allowances = (value.allowances ?? {}) as Record<string, Record<string, unknown>>;
  const visits = allowances.class_visits ?? {};
  const coaching = allowances.coaching_touchpoints ?? {};

  return sanitizeEntitlementDraft({
    channels: Array.isArray(value.channels) ? value.channels.map(String) : [],
    capabilities: Array.isArray(value.capabilities) ? value.capabilities.map(String) : [],
    classVisitLimit: String(visits.limit ?? "unlimited"),
    classVisitPeriod: String(visits.period ?? "calendar_month"),
    coachingTouchpointLimit: String(coaching.limit ?? "0"),
    coachingTouchpointPeriod: String(coaching.period ?? "calendar_month"),
  });
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
  const i18n = useUiTranslations();

  const CAPABILITIES = [
    { key: "book_classes", text: i18n("bookClasses0d3cc7b") },
    { key: "execute_class_workouts", text: i18n("executeClassWorkouts842686e") },
    {
      key: "execute_library_workouts",
      text: i18n("executeLibraryWorkouts6a80faa"),
      disabledReason: i18n("workoutOptionsUnavailable3c866ef"),
    },
    { key: "execute_assigned_workouts", text: i18n("executeAssignedWorkouts8b32393") },
    {
      key: "receive_coaching_touchpoints",
      text: i18n("receiveCoachingTouchpointscadf91e"),
      disabledReason: i18n("workoutOptionsUnavailable3c866ef"),
    },
  ] as const;

  const CHANNELS = [
    { key: "in_person", text: i18n("inPersonClasses867d7ae") },
    {
      key: "workout_library",
      text: i18n("workoutLibrarya039091"),
      disabledReason: i18n("workoutOptionsUnavailable3c866ef"),
    },
    { key: "personal_programming", text: i18n("personalProgramming0517f6d") },
    { key: "coach_messaging", text: i18n("coachMessagingf3902dc") },
  ] as const;
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
        {i18n("entitlements7de7578")}
      </legend>
      <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
        {i18n("channelsDescribeWhatThePackageDeliversCapabilitiesDescribe99a636b")}
      </p>
      <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
        {i18n("coachMessagingEnablesTheCoachingCommunicationChannelOrdinary9919f8f")}
      </p>
      <ChoiceGroup label={i18n("deliveryChannelsc3e34c4")} options={CHANNELS} selected={value.channels} onToggle={(item) => toggle("channels", item)} />
      <ChoiceGroup label={i18n("capabilitiesca09c54")} options={CAPABILITIES} selected={value.capabilities} onToggle={(item) => toggle("capabilities", item)} />
      <div className="grid gap-4 md:grid-cols-2">
        <AllowanceField
          label={i18n("classVisits142b3b0")}
          limit={value.classVisitLimit}
          period={value.classVisitPeriod}
          onLimit={(classVisitLimit) => onChange({ ...value, classVisitLimit })}
          onPeriod={(classVisitPeriod) => onChange({ ...value, classVisitPeriod })}
        />
        {value.capabilities.includes("receive_coaching_touchpoints") ? (
          <AllowanceField
            label={i18n("coachingTouchpoints23bfcb6")}
            limit={value.coachingTouchpointLimit}
            period={value.coachingTouchpointPeriod}
            onLimit={(coachingTouchpointLimit) => onChange({ ...value, coachingTouchpointLimit })}
            onPeriod={(coachingTouchpointPeriod) => onChange({ ...value, coachingTouchpointPeriod })}
          />
        ) : null}
      </div>
    </fieldset>
  );
}

type ChoiceOption = {
  key: string;
  text: string;
  disabledReason?: string;
};

function ChoiceGroup({ label, options, selected, onToggle }: { label: string; options: ReadonlyArray<ChoiceOption>; selected: string[]; onToggle: (item: string) => void }) {
  return (
    <div>
      <p className="mb-2 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{label}</p>
      <div className="grid gap-2 sm:grid-cols-2">
        {options.map(({ key, text, disabledReason }) => (
          <label
            key={key}
            className="flex items-center gap-2 rounded-lg px-2 py-1 text-sm"
            style={{
              color: disabledReason ? "var(--dim)" : "var(--text-soft)",
              background: disabledReason ? "color-mix(in srgb, var(--border) 55%, transparent)" : "transparent",
              opacity: disabledReason ? 0.62 : 1,
              cursor: disabledReason ? "not-allowed" : "pointer",
            }}
            title={disabledReason}
          >
            <input
              type="checkbox"
              checked={!disabledReason && selected.includes(key)}
              disabled={Boolean(disabledReason)}
              onChange={() => onToggle(key)}
            />
            <span className="min-w-0 flex-1">{text}</span>
            {disabledReason ? (
              <span className="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em]" style={{ background: "var(--border)", color: "var(--dim)" }}>
                <SemanticLabel value="blocked" />
              </span>
            ) : null}
          </label>
        ))}
      </div>
    </div>
  );
}

function AllowanceField({ label, limit, period, onLimit, onPeriod }: { label: string; limit: string; period: string; onLimit: (value: string) => void; onPeriod: (value: string) => void }) {
  const i18n = useUiTranslations();
  const PERIODS = [
      ["calendar_week", i18n("calendarWeek154e2bc")],
      ["calendar_month", i18n("calendarMonth1622c7f")],
      ["subscription_period", i18n("subscriptionPeriod22e7508")],
    ] as const;
  return (
    <div className="space-y-2 rounded-xl p-3" style={{ background: "var(--bg-soft)" }}>
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{label}</p>
      <input
        aria-label={i18n("allowanceLimitLabel", {label})}
        className="w-full rounded-lg px-3 py-2 text-sm"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        value={limit}
        onChange={(event) => onLimit(event.target.value)}
        placeholder={i18n("numberOrUnlimitedcc5e462")}
      />
      <select
        aria-label={(label) + i18n("resetPeriod98cb89c")}
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
