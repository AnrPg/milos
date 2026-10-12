import { beforeEach, describe, expect, it } from "vitest";

import { useWorkoutCreationStore } from "@/stores/workout-creation";
import {
  TIMER_CONFIG_CONTRACT,
  intervalPatternFromParams,
  normalizeFormatParams,
  paramsFromIntervalPattern,
  timerConfigParams,
  type SectionFormat,
} from "@/types/workout";

type TimerConfigPayload = { type: string } & Record<string, unknown>;

function timerConfigForNewSection(format: SectionFormat): TimerConfigPayload {
  const store = useWorkoutCreationStore.getState();
  store.resetDraft();
  store.addSection();
  const sectionId = useWorkoutCreationStore.getState().sections.at(-1)!.localId;
  useWorkoutCreationStore.getState().setFormat(sectionId, format);
  useWorkoutCreationStore.getState().addExercise(sectionId);

  const payload = useWorkoutCreationStore.getState().toApiPayload() as {
    sections: { timer_config: TimerConfigPayload }[];
  };
  return payload.sections.at(-1)!.timer_config;
}

describe("timer config contract", () => {
  beforeEach(() => {
    useWorkoutCreationStore.getState().resetDraft();
  });

  const formats = Object.keys(TIMER_CONFIG_CONTRACT) as SectionFormat[];

  it.each(formats)("a new %s section sends only backend fields, with every required one", (format) => {
    const { required, optional } = TIMER_CONFIG_CONTRACT[format];
    const { type, ...fields } = timerConfigForNewSection(format);

    expect(type).toBe(format);
    for (const key of Object.keys(fields)) {
      expect([...required, ...optional]).toContain(key);
    }
    for (const key of required) {
      const value = fields[key];
      expect(typeof value === "string" || (typeof value === "number" && value > 0)).toBe(true);
    }
  });

  it("drops unset optional values and editor-only keys", () => {
    expect(
      timerConfigParams("complex_emom", {
        duration_seconds: 600,
        interval_seconds: 60,
        max_windows: 0,
        minute_count: 2,
        interval_seconds_1: 90,
      }),
    ).toEqual({ duration_seconds: 600, interval_seconds: 60 });

    expect(timerConfigParams("pyramid", { time_cap_seconds: 0, peak_reps: 10, step_reps: 2 })).toEqual({
      peak_reps: 10,
      step_reps: 2,
    });
  });

  it("maps legacy editor keys to backend fields", () => {
    expect(normalizeFormatParams("death_by", { max_rounds: 20 })).toEqual({ ladder_cap: 20 });
    expect(normalizeFormatParams("hrr", { effort_cap_seconds: 45, hr_ceiling_bpm: 175 })).toEqual({
      effort_seconds: 45,
      hr_ceiling_bpm: 175,
    });
    expect(timerConfigParams("hrr", { effort_cap_seconds: 45, hr_ceiling_bpm: 175 })).toEqual({
      effort_seconds: 45,
    });
  });

  it("turns complex EMOM per-minute lengths into a backend interval pattern and back", () => {
    const params = { interval_seconds: 60, minute_count: 3, interval_seconds_2: 120 };

    expect(intervalPatternFromParams(params, 2)).toEqual([60, 120, 60]);
    expect(intervalPatternFromParams({ interval_seconds: 60 }, 3)).toBeNull();
    expect(paramsFromIntervalPattern([60, 120, 60])).toEqual({
      minute_count: 3,
      interval_seconds_1: 60,
      interval_seconds_2: 120,
      interval_seconds_3: 60,
    });
  });

  it("sends the complex EMOM pattern and the section rest with backend field names", () => {
    const store = useWorkoutCreationStore.getState();
    store.resetDraft();
    store.addSection();
    const sectionId = useWorkoutCreationStore.getState().sections.at(-1)!.localId;
    useWorkoutCreationStore.getState().setFormat(sectionId, "complex_emom");
    useWorkoutCreationStore.getState().setFormatParams(sectionId, {
      duration_seconds: 600,
      interval_seconds: 60,
      minute_count: 2,
      interval_seconds_2: 90,
    });
    useWorkoutCreationStore.getState().updateSection(sectionId, { restAfterSeconds: 120 });

    const section = (useWorkoutCreationStore.getState().toApiPayload() as {
      sections: Record<string, unknown>[];
    }).sections.at(-1)!;

    expect(section.timer_config).toMatchObject({ interval_pattern_seconds: [60, 90] });
    expect(section.timer_config).not.toHaveProperty("minute_count");
    expect(section.rest_before_next_section_seconds).toBe(120);
    expect(section).not.toHaveProperty("rest_after_seconds");
  });
});
