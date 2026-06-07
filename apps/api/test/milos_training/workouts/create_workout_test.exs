defmodule MilosTraining.Workouts.CreateWorkoutTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Identity
  alias MilosTraining.Workouts

  describe "create_workout/1" do
    test "creates a workout tree with variations tied to configured scale levels" do
      {:ok, admin} =
        Identity.register(%{
          nickname: "coach_workouts",
          password: "S3cur3P@ss!",
          role: :member
        })

      {:ok, admin} = Identity.update_role(admin, :admin)

      {:ok, _levels} =
        Workouts.replace_scale_levels([
          %{slug: "scaled", label: "Scaled", sort_order: 1},
          %{slug: "rx", label: "Rx", sort_order: 2},
          %{slug: "competition", label: "Competition", sort_order: 3}
        ])

      params = %{
        title: "Friday Grinder",
        type: "crossfit",
        sections: [
          %{
            name: "Main Set",
            order: 1,
            scoreable: true,
            score_config: %{type: "time", unit: "min", label: "Finish time"},
            timer_config: %{type: "for_time"},
            exercises: [
              %{
                name: "Thrusters",
                sets: 3,
                prescription_value: 12,
                prescription_unit: "reps",
                order: 1,
                variations: [
                  %{scale_level_slug: "scaled", prescription_value: 10, load_value: 40},
                  %{scale_level_slug: "competition", prescription_value: 15, load_value: 60}
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, workout} = Workouts.create_workout(admin, params)
      assert workout.title == "Friday Grinder"
      assert workout.status == "published"
      assert Enum.map(workout.available_scale_levels, & &1.slug) == ["scaled", "competition"]

      [section] = workout.sections
      [exercise] = section.exercises

      assert exercise.name == "Thrusters"
      assert exercise.prescription_value == 12
      assert Enum.map(exercise.variations, & &1.scale_level.slug) == ["scaled", "competition"]
    end

    test "normalizes section and exercise order from list position" do
      admin = create_admin!("admin_order_normalization")

      {:ok, _levels} =
        Workouts.replace_scale_levels([
          %{slug: "scaled", label: "Scaled", sort_order: 1}
        ])

      params = %{
        title: "Ordering Check",
        type: "strength",
        sections: [
          %{
            name: "Second in payload",
            order: 99,
            exercises: [
              %{name: "B", order: 45, variations: []},
              %{name: "A", order: 12, variations: []}
            ]
          },
          %{
            name: "Third in payload",
            order: 42,
            exercises: [
              %{name: "C", order: 7, variations: []}
            ]
          }
        ]
      }

      assert {:ok, workout} = Workouts.create_workout(admin, params)

      assert Enum.map(workout.sections, &{&1.name, &1.order}) == [
               {"Second in payload", 1},
               {"Third in payload", 2}
             ]

      assert Enum.map(Enum.at(workout.sections, 0).exercises, &{&1.name, &1.order}) == [
               {"B", 1},
               {"A", 2}
             ]
    end

    test "rejects blank variations that do not override any field" do
      admin = create_admin!("admin_blank_variation")

      {:ok, _levels} =
        Workouts.replace_scale_levels([
          %{slug: "scaled", label: "Scaled", sort_order: 1}
        ])

      params = %{
        title: "Invalid Variation",
        type: "crossfit",
        sections: [
          %{
            name: "Main Set",
            order: 1,
            exercises: [
              %{
                name: "Air Squats",
                order: 1,
                variations: [
                  %{scale_level_slug: "scaled"}
                ]
              }
            ]
          }
        ]
      }

      assert {:error, changeset} = Workouts.create_workout(admin, params)
      assert errors_on(changeset).sections != %{}
    end

    test "rejects incomplete timer configs for timer types that require numeric fields" do
      admin = create_admin!("admin_timer_validation")

      {:ok, _levels} =
        Workouts.replace_scale_levels([
          %{slug: "scaled", label: "Scaled", sort_order: 1}
        ])

      params = %{
        title: "Broken Timer",
        type: "crossfit",
        sections: [
          %{
            name: "EMOM Block",
            order: 1,
            timer_config: %{type: "emom", rounds: 5},
            exercises: [
              %{name: "Burpees", order: 1, variations: []}
            ]
          }
        ]
      }

      assert {:error, changeset} = Workouts.create_workout(admin, params)
      assert errors_on(changeset).sections != %{}
    end
  end

  describe "replace_scale_levels/1" do
    test "allows swapping existing sort orders without unique collisions" do
      {:ok, _levels} =
        Workouts.replace_scale_levels([
          %{slug: "scaled", label: "Scaled", sort_order: 1},
          %{slug: "rx", label: "Rx", sort_order: 2}
        ])

      assert {:ok, updated_levels} =
               Workouts.replace_scale_levels([
                 %{slug: "scaled", label: "Scaled", sort_order: 2},
                 %{slug: "rx", label: "Rx", sort_order: 1}
               ])

      assert Enum.map(updated_levels, &{&1.slug, &1.sort_order}) == [{"rx", 1}, {"scaled", 2}]
    end
  end

  defp create_admin!(nickname) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!",
        role: :member
      })

    {:ok, admin} = Identity.update_role(user, :admin)
    admin
  end
end
