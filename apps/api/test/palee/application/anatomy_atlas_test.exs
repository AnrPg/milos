defmodule Palee.Application.AnatomyAtlasTest do
  @moduledoc """
  ADR-164 under real Row Level Security: the member's atlas counts their own
  completed executions and logged entries at every provider in the range
  (never voided entries, unfinished executions, older work or another
  member's), resolves performed exercises to the catalog, and counts felt
  feedback; the node exercises list the gym's tagged videos.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures

  alias Palee.Application.{GetMyAtlas, ListAtlasNodeExercises}
  alias Palee.Content.Video
  alias Palee.Execution.{TrainingLogEntry, WorkoutExecution}
  alias Palee.Identity.UserContext
  alias Palee.Journal.GoalFeedback
  alias Palee.{Organizations, Repo}

  setup do
    fixtures =
      bypass_rls(fn ->
        box = org!("Box")
        coach = org!("Coach")
        box_owner = user_fixture()
        coach_owner = user_fixture()
        member = user_fixture()
        other = user_fixture()
        add!(box, box_owner, :owner)
        add!(coach, coach_owner, :owner)
        add!(box, member, :member)
        add!(coach, member, :member)
        add!(box, other, :member)

        {:ok, box_staff} = Organizations.resolve_tenant_context(box_owner, box.slug)
        {:ok, coach_staff} = Organizations.resolve_tenant_context(coach_owner, coach.slug)

        squats = workout_fixture(box_owner, %{tenant_context: box_staff})

        deadlifts =
          workout_fixture(coach_owner, %{
            tenant_context: coach_staff,
            sections: [
              %{
                name: "Strength",
                order: 1,
                scoreable: false,
                exercises: [
                  %{
                    name: "Deadlift",
                    order: 1,
                    sets: 5,
                    prescription_value: 3,
                    prescription_unit: "reps"
                  }
                ]
              }
            ]
          })

        %{
          box: box,
          coach: coach,
          member: member,
          other: other,
          box_staff: box_staff,
          squats: squats,
          deadlifts: deadlifts
        }
      end)

    Map.merge(fixtures, %{member_ctx: UserContext.new(fixtures.member)})
  end

  defp ago(days), do: DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

  defp execution!(user, org, workout, attrs) do
    bypass_rls(fn ->
      Repo.insert!(
        struct(
          %WorkoutExecution{
            user_id: user.id,
            organization_id: org.id,
            master_workout_id: workout.id,
            status: :completed,
            started_at_utc: ago(2),
            completed_at_utc: ago(2)
          },
          attrs
        )
      )
    end)
  end

  defp log!(user, org, attrs) do
    bypass_rls(fn ->
      Repo.insert!(
        struct(
          %TrainingLogEntry{
            user_id: user.id,
            organization_id: org.id,
            source_type: "freeform",
            title: "Session",
            performed_at_utc: ago(1),
            idempotency_key: Ecto.UUID.generate()
          },
          attrs
        )
      )
    end)
  end

  defp felt!(org, kind, entry, muscles) do
    bypass_rls(fn ->
      Repo.insert!(%GoalFeedback{
        user_id: entry.user_id,
        organization_id: org.id,
        entry_kind: kind,
        entry_id: entry.id,
        felt_muscles: muscles,
        felt_qualities: []
      })
    end)
  end

  test "counts the member's own work at every provider in the range", ctx do
    at_box = execution!(ctx.member, ctx.box, ctx.squats, %{})
    execution!(ctx.member, ctx.coach, ctx.deadlifts, %{completed_at_utc: ago(3)})

    execution!(ctx.member, ctx.box, ctx.squats, %{
      started_at_utc: ago(40),
      completed_at_utc: ago(40)
    })

    execution!(ctx.member, ctx.box, ctx.squats, %{status: :active, completed_at_utc: nil})
    execution!(ctx.other, ctx.box, ctx.deadlifts, %{})

    log!(ctx.member, ctx.box, %{
      performed_exercises: [%{"name" => "Back Squats", "sets" => 4}, %{"name" => "Yoga flow"}]
    })

    voided =
      log!(ctx.member, ctx.box, %{
        status: "voided",
        voided_at: DateTime.utc_now(),
        performed_exercises: [%{"name" => "Deadlift", "sets" => 10}]
      })

    log!(ctx.member, ctx.box, %{
      source_type: "library_workout",
      source_reference_id: ctx.squats.id,
      master_workout_id: ctx.squats.id
    })

    felt!(ctx.box, "execution", at_box, ["quadriceps"])
    felt!(ctx.box, "training_log", voided, ["hamstrings"])

    assert {:ok, atlas} = GetMyAtlas.call(ctx.member_ctx, %{"range" => "4w"})
    nodes = Map.new(atlas.nodes, &{&1.id, &1})

    assert atlas.range == "4w" and atlas.weeks == 4
    assert atlas.to == Date.utc_today()
    assert atlas.from == Date.add(Date.utc_today(), -27)
    assert atlas.sessions == 4
    assert atlas.exercises == %{recognized: 4, unrecognized: 1}
    assert atlas.felt_entries == 1
    assert atlas.thresholds == %{medium: 3.0, high: 8.0}

    # Air squats 3 + deadlift secondary 2.5 + back squats 4 + logged squats 3.
    assert nodes["quadriceps"].sets == 12.5
    assert nodes["quadriceps"].level == "medium"
    assert nodes["quadriceps"].felt == 1
    # Deadlift primary 5 + back squat secondary 2; nothing from the voided entry.
    assert nodes["hamstrings"].sets == 7.0
    assert nodes["hamstrings"].felt == 0
    assert nodes["hamstrings"].level == "low"

    assert {:ok, week} = GetMyAtlas.call(ctx.member_ctx, %{"range" => "1w"})
    assert week.sessions == 4
    assert Enum.find(week.nodes, &(&1.id == "quadriceps")).level == "high"
  end

  test "an athlete with nothing in the range gets an empty atlas", ctx do
    assert {:ok, atlas} = GetMyAtlas.call(ctx.member_ctx, %{})
    assert atlas.range == "4w"
    assert atlas.sessions == 0 and atlas.nodes == []
    assert {:error, :invalid_range} = GetMyAtlas.call(ctx.member_ctx, %{"range" => "6m"})
  end

  test "node exercises carry the gym's published videos that name them", ctx do
    bypass_rls(fn ->
      for {title, tags, published} <- [
            {"Romanian Deadlift", [], true},
            {"Hinge basics", ["deadlift", "mobility"], true},
            {"Draft deadlift", ["deadlift"], false}
          ] do
        Repo.insert!(%Video{
          organization_id: ctx.box.id,
          title: title,
          video_url: "https://videos.example/#{System.unique_integer([:positive])}",
          tags: tags,
          published_at: if(published, do: DateTime.utc_now())
        })
      end
    end)

    assert {:ok, result} = ListAtlasNodeExercises.call(ctx.box_staff, nil, "hamstrings")
    assert result.node_id == "hamstrings" and result.videos_included
    by_ref = Map.new(result.exercises, &{&1.exercise_ref, &1})

    assert [%{title: "Romanian Deadlift"}] = by_ref["romanian-deadlift"].videos
    assert [%{title: "Hinge basics"}] = by_ref["deadlift"].videos
    assert by_ref["deadlift"].label == "Deadlift" and by_ref["deadlift"].role == "primary"
    assert by_ref["back-squat"].role == "secondary"

    # Primary first; within a role, exercises with a video first.
    [first, second | _] = result.exercises
    assert first.videos != [] and second.videos != []

    assert Enum.all?(
             Enum.take_while(result.exercises, &(&1.role == "primary")),
             &is_binary(&1.label)
           )

    assert {:error, :not_found} = ListAtlasNodeExercises.call(ctx.box_staff, nil, "spleen")
  end

  defp org!(name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    organization
  end

  defp add!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        roles: if(role == :owner, do: [:owner, :coach], else: [role]),
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end
end
