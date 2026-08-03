import { beforeEach, describe, expect, it } from "vitest";

import { useWorkoutCreationStore } from "@/stores/workout-creation";

describe("workout creation draft hydration", () => {
  beforeEach(() => useWorkoutCreationStore.getState().resetDraft());

  it("hydrates grouped exercises with the group-owned set count", () => {
    useWorkoutCreationStore.getState().loadFromDraftData({
      title: "Group demo",
      type: "strength",
      draft_data: {
        authoring_mode: "quick_text",
        dsl_source: "[workout]...[/workout]",
      },
      sections: [
        {
          name: "Main Work",
          timer_config: { type: "untimed" },
          exercises: [
            {
              name: "Pull-up",
              sets: 1,
              prescription_value: 8,
              superset_group_id: "group-1",
              group_config: { sets: 3 },
            },
            {
              name: "Push-up",
              sets: 1,
              prescription_value: 12,
              superset_group_id: "group-1",
              group_config: { sets: 3 },
            },
          ],
        },
      ],
    });

    expect(useWorkoutCreationStore.getState().sections[0].exercises.map(({ sets }) => sets)).toEqual([
      3,
      3,
    ]);
  });
});
