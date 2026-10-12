import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";

import type { AthleteInjuryWarnings, InjuryWarning, MyWorkoutInjuryWarnings } from "@/api/injury-warnings";
import {
  AthleteInjuryWarningsPanel,
  InjuryWarningBadge,
  MyInjuryWarningsPanel,
  RosterInjuryWarningsPanel,
} from "@/components/wellbeing/InjuryWarnings";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${Object.values(values).join("|")}` : key,
}));

vi.mock("@/components/semantic-label", () => ({
  SemanticLabel: ({ value }: { value: unknown }) => <span>{String(value)}</span>,
}));

function wrapper({ children }: { children: ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

function warning(overrides: Partial<InjuryWarning> = {}): InjuryWarning {
  return {
    injury_id: "injury-1",
    user_id: "user-1",
    body_area: "knee",
    regions: ["knee"],
    severity: "moderate",
    level: "avoid",
    provenance: "organization",
    training_limitations: "No deep squats",
    tags: [],
    exercises: [
      { name: "Back Squat", exercise_ref: "back-squat", level: "avoid", patterns: ["squat"], match: "catalog" },
      { name: "Run", exercise_ref: "run", level: "caution", patterns: ["running"], match: "catalog" },
    ],
    ...overrides,
  };
}

describe("InjuryWarningBadge", () => {
  it("renders nothing for no warning and a labelled badge otherwise", () => {
    const { container, rerender } = render(<InjuryWarningBadge level="none" />);
    expect(container).toBeEmptyDOMElement();

    rerender(<InjuryWarningBadge level="avoid" />);
    expect(screen.getByText("injuryWarningLevelAvoid")).toBeInTheDocument();

    rerender(<InjuryWarningBadge level="caution" />);
    expect(screen.getByText("injuryWarningLevelCaution")).toBeInTheDocument();
  });
});

describe("AthleteInjuryWarningsPanel", () => {
  const result: AthleteInjuryWarnings = {
    workout_id: "workout-1",
    level: "avoid",
    athletes: [
      { user_id: "user-1", level: "avoid", warnings: [warning()] },
      { user_id: "user-2", level: "none", warnings: [] },
    ],
  };

  it("evaluates the selection and lists only warned athletes with their exercises", async () => {
    const api = {
      evaluate: vi.fn().mockResolvedValue(result),
      acknowledge: vi.fn().mockResolvedValue({ acknowledged_count: 1 }),
    };

    render(
      <AthleteInjuryWarningsPanel
        accessToken="token"
        workoutId="workout-1"
        userIds={["user-2", "user-1"]}
        surface="assign_dialog"
        nameFor={(id) => (id === "user-1" ? "Ana" : "Bo")}
        api={api}
      />,
      { wrapper },
    );

    expect(await screen.findByText("Ana")).toBeInTheDocument();
    expect(screen.queryByText("Bo")).not.toBeInTheDocument();
    expect(screen.getByText("injuryWarningAvoidExercises:Back Squat")).toBeInTheDocument();
    expect(screen.getByText("injuryWarningCautionExercises:Run")).toBeInTheDocument();
    expect(screen.getByText("injuryWarningLimitations:No deep squats")).toBeInTheDocument();
    expect(api.evaluate).toHaveBeenCalledWith("token", {
      workout_id: "workout-1",
      user_ids: ["user-1", "user-2"],
      surface: "assign_dialog",
      source_context_id: null,
    });

    fireEvent.click(screen.getByRole("button", { name: "injuryWarningAcknowledge" }));
    expect(await screen.findByText("injuryWarningAcknowledged")).toBeInTheDocument();
    expect(api.acknowledge).toHaveBeenCalledTimes(1);
  });

  it("stays silent when nobody is warned or nothing is selected", async () => {
    const api = {
      evaluate: vi.fn().mockResolvedValue({ workout_id: "workout-1", level: "none", athletes: [] }),
      acknowledge: vi.fn(),
    };

    const { container } = render(
      <AthleteInjuryWarningsPanel
        accessToken="token"
        workoutId="workout-1"
        userIds={[]}
        surface="assign_dialog"
        nameFor={(id) => id}
        api={api}
      />,
      { wrapper },
    );

    expect(container).toBeEmptyDOMElement();
    expect(api.evaluate).not.toHaveBeenCalled();
  });

  it("shows a quiet notice instead of blocking when loading fails", async () => {
    const api = { evaluate: vi.fn().mockRejectedValue(new Error("boom")), acknowledge: vi.fn() };

    render(
      <AthleteInjuryWarningsPanel
        accessToken="token"
        workoutId="workout-1"
        userIds={["user-1"]}
        surface="assign_dialog"
        nameFor={(id) => id}
        api={api}
      />,
      { wrapper },
    );

    expect(await screen.findByText("injuryWarningLoadFailed")).toBeInTheDocument();
    expect(screen.queryByRole("button")).not.toBeInTheDocument();
  });
});

describe("RosterInjuryWarningsPanel", () => {
  it("acknowledges only warned booked members for the slot", async () => {
    const acknowledgeFn = vi.fn().mockResolvedValue({ acknowledged_count: 1 });

    render(
      <RosterInjuryWarningsPanel
        accessToken="token"
        slotId="slot-1"
        workoutId="workout-1"
        level="avoid"
        athletes={[
          { user_id: "user-1", level: "avoid", warnings: [warning()] },
          { user_id: "user-2", level: "none", warnings: [] },
        ]}
        nameFor={() => "Ana"}
        acknowledgeFn={acknowledgeFn}
      />,
      { wrapper },
    );

    fireEvent.click(screen.getByRole("button", { name: "injuryWarningAcknowledge" }));

    await waitFor(() =>
      expect(acknowledgeFn).toHaveBeenCalledWith("token", {
        workout_id: "workout-1",
        user_ids: ["user-1"],
        surface: "class_roster",
        source_context_id: "slot-1",
      }),
    );
  });
});

describe("MyInjuryWarningsPanel", () => {
  it("shows own warnings including personal ones and acknowledges", async () => {
    const result: MyWorkoutInjuryWarnings = {
      workout_id: "workout-1",
      level: "caution",
      warnings: [warning({ level: "caution", provenance: "personal", exercises: [], training_limitations: null })],
    };
    const api = {
      fetch: vi.fn().mockResolvedValue(result),
      acknowledge: vi.fn().mockResolvedValue({ level: "caution", warning_count: 1 }),
    };

    render(
      <MyInjuryWarningsPanel
        accessToken="token"
        workoutId="workout-1"
        surface="assignment_detail"
        sourceContextId="assignment-1"
        api={api}
      />,
      { wrapper },
    );

    expect(await screen.findByText("injuryWarningSelfTitle")).toBeInTheDocument();
    expect(screen.getByText("injuryWarningPersonal")).toBeInTheDocument();
    expect(screen.getByText("injuryWarningUnmappedArea")).toBeInTheDocument();
    expect(api.fetch).toHaveBeenCalledWith("token", "workout-1", {
      surface: "assignment_detail",
      source_context_id: "assignment-1",
    });

    fireEvent.click(screen.getByRole("button", { name: "injuryWarningAcknowledge" }));
    expect(await screen.findByText("injuryWarningAcknowledged")).toBeInTheDocument();
  });

  it("renders nothing without warnings", async () => {
    const api = {
      fetch: vi.fn().mockResolvedValue({ workout_id: "workout-1", level: "none", warnings: [] }),
      acknowledge: vi.fn(),
    };

    const { container } = render(
      <MyInjuryWarningsPanel accessToken="token" workoutId="workout-1" surface="pre_start" api={api} />,
      { wrapper },
    );

    await waitFor(() => expect(api.fetch).toHaveBeenCalled());
    expect(container).toBeEmptyDOMElement();
  });
});
