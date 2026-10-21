defmodule MilosTraining.Application.TrainingDepthTest do
  @moduledoc """
  ADR-165 under real Row Level Security: the member's Πρόοδος depth sections
  (coverage summary, qualities, load) across providers with the range and
  source filter, and a coach's view of a client built only from entries the
  client shares with that gym, for the client's own coach (or a head coach).
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{GetClientTrainingDepth, GetMyTrainingDepth}
  alias MilosTraining.Execution.{TrainingLogEntry, WorkoutExecution}
  alias MilosTraining.Identity.UserContext
  alias MilosTraining.Journal.GoalFeedback
  alias MilosTraining.{Coaching, Organizations, Repo}

  setup do
    fixtures =
      bypass_rls(fn ->
        box = org!("Box")
        other_gym = org!("Other")
        owner = user_fixture()
        coach = user_fixture()
        stranger_coach = user_fixture()
        member = user_fixture()
        outsider = user_fixture()
        add!(box, owner, :owner)
        add!(box, coach, :coach)
        add!(box, stranger_coach, :coach)
        add!(box, member, :member)
        add!(other_gym, owner, :owner)
        add!(other_gym, member, :member)
        add!(other_gym, outsider, :member)

        {:ok, _} =
          Coaching.start_relationship(%{organization_id: box.id}, %{
            coach_user_id: coach.id,
            client_user_id: member.id,
            origin: "assigned"
          })

        {:ok, owner_ctx} = Organizations.resolve_tenant_context(owner, box.slug)
        {:ok, coach_ctx} = Organizations.resolve_tenant_context(coach, box.slug)
        {:ok, stranger_ctx} = Organizations.resolve_tenant_context(stranger_coach, box.slug)

        squats = workout_fixture(owner, %{tenant_context: owner_ctx})

        %{
          box: box,
          other_gym: other_gym,
          member: member,
          outsider: outsider,
          owner_ctx: owner_ctx,
          coach_ctx: coach_ctx,
          stranger_ctx: stranger_ctx,
          squats: squats
        }
      end)

    Map.merge(fixtures, %{member_ctx: UserContext.new(fixtures.member)})
  end

  defp ago(days), do: DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

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

  defp felt!(org, entry, qualities) do
    bypass_rls(fn ->
      Repo.insert!(%GoalFeedback{
        user_id: entry.user_id,
        organization_id: org.id,
        entry_kind: "training_log",
        entry_id: entry.id,
        felt_muscles: ["quadriceps"],
        felt_qualities: qualities
      })
    end)
  end

  test "the member's sections across providers, with range and source filter", ctx do
    box_log =
      log!(ctx.member, ctx.box, %{
        performed_exercises: [%{"name" => "Back Squat", "sets" => 5}],
        perceived_effort: 7,
        duration_seconds: 3600
      })

    log!(ctx.member, ctx.other_gym, %{
      performed_exercises: [
        %{"name" => "Bench Press", "sets" => 4},
        %{"name" => "Pull-up", "sets" => 4}
      ],
      performed_at_utc: ago(9),
      perceived_effort: 6,
      duration_seconds: 3000
    })

    log!(ctx.member, ctx.box, %{
      performed_exercises: [%{"name" => "Deadlift", "sets" => 3}],
      performed_at_utc: ago(16),
      perceived_effort: 5,
      duration_seconds: 3600
    })

    # Older than 4 weeks: in 12w only, but it feeds the load chart.
    log!(ctx.member, ctx.box, %{
      performed_exercises: [%{"name" => "Back Squat", "sets" => 5}],
      performed_at_utc: ago(40),
      perceived_effort: 5,
      duration_seconds: 1800
    })

    # Someone else's training never counts.
    log!(ctx.outsider, ctx.other_gym, %{
      performed_exercises: [%{"name" => "Deadlift", "sets" => 9}]
    })

    felt!(ctx.box, box_log, ["strength"])

    assert {:ok, depth} = GetMyTrainingDepth.call(ctx.member_ctx, %{"range" => "4w"})
    assert depth.range == "4w" and depth.weeks == 4 and depth.sources == []
    assert depth.from == Date.add(Date.utc_today(), -27)
    assert depth.coverage.sessions == 3
    assert depth.coverage.felt_entries == 1
    assert depth.coverage.balance.push == 4.0 and depth.coverage.balance.pull == 4.0
    assert depth.coverage.balance.push_pull_ratio == 1.0
    assert "quadriceps" in Enum.map(depth.coverage.most, & &1.id)

    strength = Enum.find(depth.qualities.qualities, &(&1.id == "strength"))
    assert strength.score == 1.0 and strength.felt == 1
    assert depth.qualities.felt_entries == 1

    # Load: 420 in the last 7 days; 420 + 300 + 300 over three of the four
    # blocks of the 28 days, enough for a ratio: 420 / 255.
    assert depth.load.acute == 420 and depth.load.chronic == 255
    assert depth.load.rated_sessions == 3
    assert depth.load.sufficient and depth.load.ratio == 1.65
    assert depth.load.band == "well_above"
    assert Enum.sum(Enum.map(depth.load.weeks, & &1.load)) == 420 + 300 + 300 + 150

    assert {:ok, wide} = GetMyTrainingDepth.call(ctx.member_ctx, %{"range" => "12w"})
    assert wide.coverage.sessions == 4 and wide.weeks == 12

    assert {:ok, all} = GetMyTrainingDepth.call(ctx.member_ctx, %{})
    assert all.range == "all" and all.coverage.sessions == 4
    assert all.from == Date.add(Date.utc_today(), -40)

    assert {:ok, box_only} =
             GetMyTrainingDepth.call(ctx.member_ctx, %{"range" => "4w", "sources" => ctx.box.id})

    assert box_only.sources == [ctx.box.id]
    assert box_only.coverage.sessions == 2 and box_only.load.acute == 420
    assert box_only.coverage.balance.push == 0.0

    assert {:ok, other} =
             GetMyTrainingDepth.call(ctx.member_ctx, %{
               "range" => "4w",
               "sources" => ctx.other_gym.id
             })

    assert other.coverage.sessions == 1
    assert other.coverage.felt_entries == 0
    assert other.load.acute == 0

    assert {:error, _} = GetMyTrainingDepth.call(ctx.member_ctx, %{"range" => "2w"})
  end

  test "a coach sees only what the client shares with the gym", ctx do
    log!(ctx.member, ctx.box, %{
      performed_exercises: [%{"name" => "Back Squat", "sets" => 5}],
      perceived_effort: 7,
      duration_seconds: 3600
    })

    log!(ctx.member, ctx.box, %{
      performed_exercises: [%{"name" => "Bench Press", "sets" => 6}],
      journal_visibility: "private"
    })

    log!(ctx.member, ctx.other_gym, %{performed_exercises: [%{"name" => "Deadlift", "sets" => 9}]})

    bypass_rls(fn ->
      Repo.insert!(%WorkoutExecution{
        user_id: ctx.member.id,
        organization_id: ctx.box.id,
        master_workout_id: ctx.squats.id,
        status: :completed,
        started_at_utc: ago(2),
        completed_at_utc: ago(2),
        total_elapsed_ms: 1_200_000
      })
    end)

    assert {:ok, depth} = GetClientTrainingDepth.call(ctx.coach_ctx, ctx.member.id, %{})
    assert depth.range == "4w"
    # The shared log and the execution; never the private log; the other gym's
    # entry only when the member shares it with this gym.
    assert depth.coverage.sessions == 2
    ids = Enum.map(depth.coverage.most, & &1.id)
    refute "pectoralis-major" in ids
    refute Map.has_key?(depth, :sources)
    assert depth.coverage.balance.push == 0.0
    assert depth.load.acute == 420

    # A head coach (the owner) sees the same; another coach without the client does not.
    assert {:ok, owner_view} = GetClientTrainingDepth.call(ctx.owner_ctx, ctx.member.id, %{})
    assert owner_view.coverage.sessions == depth.coverage.sessions

    assert {:error, :not_your_client} =
             GetClientTrainingDepth.call(ctx.stranger_ctx, ctx.member.id, %{})

    # Not a member of this gym: not found; bad range: invalid.
    assert {:error, :not_found} = GetClientTrainingDepth.call(ctx.coach_ctx, ctx.outsider.id, %{})
    assert {:error, :not_found} = GetClientTrainingDepth.call(ctx.coach_ctx, "nope", %{})

    assert {:error, [range: _]} =
             GetClientTrainingDepth.call(ctx.coach_ctx, ctx.member.id, %{"range" => "2w"})
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
