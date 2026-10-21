defmodule MilosTraining.Application.InsightsTest do
  @moduledoc """
  ADR-166 under real Row Level Security: the member's insights are computed
  from their own sessions, sleep and PRs, stored as their own rows, shown at
  most a few at a time, dismissed until the finding changes, switched off
  with their journal section, recomputed by the nightly run and forgotten
  when the wellness data behind them is erased.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{EraseMyWellness, GetMyInsights, NightlyInsights}
  alias MilosTraining.Execution.TrainingLogEntry
  alias MilosTraining.Identity.UserContext
  alias MilosTraining.Insights.Insight
  alias MilosTraining.Pantheon.{PRHistory, PRRecord}
  alias MilosTraining.Wellness.Entry
  alias MilosTraining.{Body, Insights, Organizations, Repo}

  @rested [1, 5, 9, 13, 30]
  @short [3, 7, 11, 15, 32]

  setup do
    fixtures =
      bypass_rls(fn ->
        box = org!("Insight Box")
        member = user_fixture()
        outsider = user_fixture()
        add!(box, member, :member)
        add!(box, outsider, :member)
        %{box: box, member: member, outsider: outsider}
      end)

    Map.merge(fixtures, %{
      member_ctx: UserContext.new(fixtures.member),
      outsider_ctx: UserContext.new(fixtures.outsider)
    })
  end

  defp day(offset), do: Date.add(Date.utc_today(), -offset)
  defp at(offset), do: DateTime.new!(day(offset), ~T[07:00:00.000000], "Etc/UTC")

  # Ten morning sessions over five weeks, each after a logged night: 8 h
  # before the "rested" ones, 6 h before the "short" ones; PRs on four
  # rested days and one short day.
  defp seed!(ctx) do
    bypass_rls(fn ->
      for offset <- @rested ++ @short do
        Repo.insert!(%TrainingLogEntry{
          user_id: ctx.member.id,
          organization_id: ctx.box.id,
          source_type: "freeform",
          title: "Session",
          performed_at_utc: at(offset),
          idempotency_key: Ecto.UUID.generate()
        })

        Repo.insert!(%Entry{
          user_id: ctx.member.id,
          kind: "sleep",
          occurred_at: at(offset),
          occurred_tz: "Etc/UTC",
          occurred_on: day(offset),
          value: %{"minutes" => if(offset in @rested, do: 480, else: 360), "nap" => false}
        })
      end

      record =
        Repo.insert!(%PRRecord{
          user_id: ctx.member.id,
          name: "Back Squat",
          current_score: Decimal.new(120),
          unit: "kg",
          beaten_on: day(1)
        })

      for offset <- Enum.take(@rested, 4) ++ Enum.take(@short, 1) do
        Repo.insert!(%PRHistory{
          pr_record_id: record.id,
          score: Decimal.new(100 + offset),
          beaten_on: day(offset)
        })
      end
    end)
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
        roles: [role],
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp stored(user),
    do: bypass_rls(fn -> Repo.all(from(i in Insight, where: i.user_id == ^user.id)) end)

  test "computed on first read, shown, dismissed until it changes, restored", ctx do
    seed!(ctx)

    assert {:ok, view} = GetMyInsights.call(ctx.member_ctx)
    assert view.state == "insights"
    assert view.min_weeks == 4 and view.window_weeks == 12 and view.max_shown == 3
    assert [insight] = view.insights
    assert insight.rule == "sleep_prs" and insight.variant == "more_after_goal"
    assert insight.params == %{"hours" => 7.0, "ratio" => 4.0}
    assert insight.weeks == 4
    assert view.data_weeks >= 4

    rows = stored(ctx.member)
    assert length(rows) == 5
    assert Enum.find(rows, &(&1.rule == "time_of_day")).status == "insufficient"

    # The rows are the member's alone.
    assert Insights.with_context(ctx.outsider_ctx, fn -> Insights.list(ctx.member.id) end) == []
    assert {:ok, %{state: "collecting", insights: []}} = GetMyInsights.call(ctx.outsider_ctx)

    # A second read within the day reads the stored rows.
    computed_at = hd(rows).computed_at
    assert {:ok, _} = GetMyInsights.call(ctx.member_ctx)
    assert hd(stored(ctx.member)).computed_at == computed_at

    assert {:ok, hidden} = GetMyInsights.dismiss(ctx.member_ctx, "sleep_prs")
    assert hidden.state == "all_hidden" and hidden.insights == [] and hidden.hidden_count == 1
    assert {:error, :not_found} = GetMyInsights.dismiss(ctx.member_ctx, "time_of_day")
    assert {:error, :not_found} = GetMyInsights.dismiss(ctx.member_ctx, "horoscope")
    assert {:error, :not_found} = GetMyInsights.dismiss(ctx.outsider_ctx, "sleep_prs")

    # The same finding on the next run stays hidden.
    assert :ok = NightlyInsights.compute(ctx.member.id, DateTime.add(DateTime.utc_now(), 60))
    assert {:ok, %{state: "all_hidden"}} = GetMyInsights.call(ctx.member_ctx)

    assert {:ok, restored} = GetMyInsights.restore(ctx.member_ctx)
    assert restored.state == "insights" and restored.hidden_count == 0
  end

  test "a journal section switched off produces nothing and clears its values", ctx do
    seed!(ctx)
    assert {:ok, %{state: "insights"}} = GetMyInsights.call(ctx.member_ctx)

    {:ok, _} =
      Body.put_settings(ctx.member_ctx, ctx.member.id, %{
        journal_sections: %{"body" => true, "wellness" => false, "cravings" => true}
      })

    assert {:ok, view} = GetMyInsights.call(ctx.member_ctx)
    assert view.insights == [] and view.state == "collecting"

    sleep = Enum.find(stored(ctx.member), &(&1.rule == "sleep_prs"))
    assert sleep.status == "off" and sleep.value == %{} and is_nil(sleep.fingerprint)
  end

  test "the nightly run reaches people with recent data only", ctx do
    seed!(ctx)
    now = DateTime.utc_now()

    assert {:ok, count} = NightlyInsights.call(now)
    assert count >= 1
    assert Enum.all?(stored(ctx.member), &(DateTime.compare(&1.computed_at, now) == :eq))
    assert stored(ctx.outsider) == []
  end

  test "erasing the wellness data forgets the insights", ctx do
    seed!(ctx)
    assert {:ok, %{state: "insights"}} = GetMyInsights.call(ctx.member_ctx)

    assert {:ok, _counts} = EraseMyWellness.call(ctx.member_ctx, %{"sections" => "wellness"})
    assert stored(ctx.member) == []
  end
end
