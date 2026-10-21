defmodule Palee.Workouts.MultiFormatWorkoutTest do
  @moduledoc """
  A workout is a concatenation of sections with independent formats. This
  covers the whole path for one assistant answer: contract check against the
  per-format schemas → normalization → persistence → timer sequence.
  """
  use Palee.DataCase, async: false

  alias Palee.{Execution, Identity, Organizations, Repo, Workouts}
  alias Palee.Workouts.Domain.FreeTextAnalysis
  alias Palee.Workouts.Domain.WorkoutAssistant.Contract

  @source """
  Warm-up: 20 air squats
  EMOM 12: min 1 12 cal row, min 2 10 burpees, min 3 8 power cleans 60kg
  Tabata air squats
  Rest 2'
  21-15-9 thrusters 43kg / pull-ups, cap 10
  """

  @answer %{
    "workout" => %{"title" => "Chained formats", "type" => "crossfit"},
    "sections" => [
      %{
        "name" => "Warm-up",
        "format" => "untimed",
        "exercises" => [%{"name" => "Air squat", "reps" => 20}]
      },
      %{
        "name" => "EMOM 12",
        "format" => "complex_emom",
        "timer" => %{"duration_seconds" => 720, "interval_seconds" => 60},
        "score" => "rounds",
        "exercises" => [
          %{"name" => "Row", "calories" => 12, "interval_assignment" => 1},
          %{"name" => "Burpee", "reps" => 10, "interval_assignment" => 2},
          %{"name" => "Power clean", "reps" => 8, "load_kg" => 60, "interval_assignment" => 3}
        ]
      },
      %{
        "name" => "Tabata",
        "format" => "tabata",
        "timer" => %{"work_seconds" => 20, "rest_seconds" => 10, "rounds" => 8},
        "exercises" => [%{"name" => "Air squat"}]
      },
      %{
        "name" => "Rest",
        "format" => "rest",
        "timer" => %{"duration_seconds" => 120},
        "exercises" => []
      },
      %{
        "name" => "21-15-9",
        "format" => "ladder_descending",
        "timer" => %{
          "start_reps" => 21,
          "step_reps" => 6,
          "min_reps" => 9,
          "time_cap_seconds" => 600
        },
        "score" => "time",
        "exercises" => [%{"name" => "Thruster", "load_kg" => 43}, %{"name" => "Pull-up"}]
      }
    ],
    "issues" => [],
    "missing_fields" => []
  }

  test "different sections keep separate formats from analysis to execution" do
    assert Contract.check(@answer, @source) == []

    %{"workout" => canonical} = FreeTextAnalysis.normalize(@answer, @source)

    assert Enum.map(canonical["sections"], & &1["timer_config"]["type"]) ==
             ~w(untimed complex_emom tabata rest ladder_descending)

    emom = Enum.at(canonical["sections"], 1)
    assert emom["scoreable"] == true
    assert emom["score_config"] == %{"type" => "rounds"}
    assert Enum.map(emom["exercises"], & &1["interval_assignment"]) == [1, 2, 3]

    admin = create_admin!()

    # Published exactly like the free-text editor does (draft → publish).
    {:ok, draft} = Workouts.create_draft(admin)

    params = %{
      "title" => canonical["title"],
      "type" => canonical["type"],
      "authoring_mode" => "free_text",
      "free_text_body" => @source,
      "expected_source_revision" => draft.dsl_source_revision,
      "sections" =>
        Enum.map(canonical["sections"], fn section ->
          section
          |> compact()
          |> Map.update!("exercises", fn exercises -> Enum.map(exercises, &compact/1) end)
        end)
    }

    assert {:ok, created} = Workouts.publish_workout(draft.id, params)

    workout =
      Workouts.get_workout(
        %{organization_id: created.organization_id, user_id: admin.id},
        created.id
      )

    assert Enum.map(workout.sections, &(&1.timer_config["type"] || &1.timer_config[:type])) ==
             ~w(untimed complex_emom tabata rest ladder_descending)

    segments = Execution.build_timer_sequence(workout)
    by_format = Enum.group_by(segments, & &1.format)

    assert [%{kind: :no_timer}] = by_format["untimed"]

    # 12 one-minute windows; the three slots repeat in order (row, burpee, clean).
    emom_segments = by_format["complex_emom"]
    assert length(emom_segments) == 12
    assert Enum.all?(emom_segments, &(&1.duration_seconds == 60 and &1.scoreable))

    assert emom_segments |> Enum.map(fn s -> hd(s.exercises).name end) |> Enum.take(6) ==
             ["Row", "Burpee", "Power clean", "Row", "Burpee", "Power clean"]

    # 8 work intervals with a rest between each (no trailing rest).
    tabata = by_format["tabata"]
    assert length(tabata) == 15
    assert tabata |> Enum.take(2) |> Enum.map(& &1.duration_seconds) == [20, 10]

    assert [%{kind: :countdown, duration_seconds: 120}] = by_format["rest"]
    assert [%{kind: :countup, scoreable: true}] = by_format["ladder_descending"]

    assert Enum.map(segments, & &1.format) |> Enum.dedup() ==
             ~w(untimed complex_emom tabata rest ladder_descending)
  end

  defp compact(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()

  defp create_admin! do
    {:ok, user} =
      Identity.register(%{
        nickname: "multi_format_#{System.unique_integer([:positive])}",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, admin} = Identity.update_role(user, :admin)
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", admin.id])
    admin
  end
end
