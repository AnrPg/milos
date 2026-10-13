defmodule MilosTraining.Application.BackgroundUserScopeRLSTest do
  @moduledoc """
  TD-092 / ADR-131: background and system paths (Oban jobs, projections,
  cross-user maintenance) under real Row Level Security.

  Request paths are covered by `ConnCase` (ADR-119); these paths run outside a
  request, with no session scope at all, exactly like an Oban job in
  production. Fixtures are seeded as the superuser with `bypass_rls/1` and the
  session GUCs are cleared before the code under test runs as the
  RLS-enforcing runtime role, so a missing `RepoContext.run/2` shows up here as
  it would in production: empty reads or rejected writes.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.LogTrainingEntry

  alias MilosTraining.{
    Execution,
    Finance,
    Gamification,
    Organizations,
    Workouts
  }

  alias MilosTraining.Gamification.GamificationStore
  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  alias MilosTraining.Workers.{
    CoachingReplyOverdueJob,
    CorporateInvoicingJob,
    ExecutionAbandonmentSweepJob,
    InventoryDigestJob,
    MarkOverdueInvoicesJob,
    PackageExpiryReminderJob,
    PaymentReminderJob,
    ProcessWorkoutCompletionJob,
    ReconcileEntitlementReservationsJob,
    SubscriptionExpiryJob
  }

  describe "workout completion projection (ProcessWorkoutCompletionJob)" do
    setup do
      bypass_rls(fn ->
        owner = user_fixture()
        member = user_fixture()
        {:ok, gym} = Organizations.create_organization(%{name: "Projection Gym"})
        add!(gym, owner, :owner)
        add!(gym, member, :member)
        owner_ctx = tenant!(owner, gym)

        {:ok, _settings} =
          Gamification.with_tenant_context(owner_ctx, fn ->
            Gamification.update_settings(%{weekly_workout_target: 1, leaderboard_enabled: true})
          end)

        {:ok, challenge} =
          Gamification.with_tenant_context(owner_ctx, fn ->
            Gamification.create_seasonal_challenge(owner.id, %{
              title: "One and done",
              description: "Complete one workout",
              criteria_type: "workout_count",
              criteria_value: %{count: 1},
              badge_key: "challenge_one_and_done",
              badge_label: "One and done",
              starts_at: Date.utc_today(),
              ends_at: Date.add(Date.utc_today(), 7)
            })
          end)

        {:ok, workout} =
          Workouts.create_workout(owner_ctx, owner, %{
            title: "Projection Hero",
            type: :crossfit,
            sections: [
              %{
                name: "Main Piece",
                order: 1,
                scoreable: true,
                score_config: %{type: "time", unit: "sec", label: "Time"},
                exercises: [
                  %{name: "Burpees", order: 1, prescription_value: 21, prescription_unit: "reps"}
                ]
              }
            ]
          })

        section_id = workout.sections |> hd() |> Map.fetch!(:id)

        execution =
          RepoContext.run(%{organization_id: gym.id, user_id: member.id}, fn ->
            {:ok, execution} =
              Execution.start_execution(member.id, %{
                organization_id: gym.id,
                master_workout_id: workout.id,
                source: "self_selected",
                timezone: "UTC"
              })

            {:ok, completed} =
              Execution.complete_execution(execution.id, member.id, %{
                timezone: "UTC",
                section_scores: [%{section_id: section_id, value: 300, unit: "sec"}]
              })

            completed
          end)

        %{gym: gym, member: member, challenge: challenge, execution: execution}
      end)
    end

    test "the job projects stats, badges and challenge progress in the member's scope", ctx do
      clear_session!()

      assert :ok =
               ProcessWorkoutCompletionJob.perform(%Oban.Job{
                 args: %{"execution_id" => ctx.execution.id}
               })

      bypass_rls(fn ->
        stats = GamificationStore.get_user_stats(ctx.member.id)
        assert stats.total_workouts == 1

        badge_keys =
          ctx.member.id |> GamificationStore.list_user_achievements() |> Enum.map(& &1.badge_key)

        assert "workouts_1" in badge_keys
        assert "challenge_one_and_done" in badge_keys

        progress =
          Gamification.with_tenant_context(%{organization_id: ctx.gym.id}, fn ->
            Gamification.challenge_progress(ctx.member.id, ctx.challenge.id)
          end)

        assert progress.progress == 1
        assert progress.completed_at
      end)
    end

    test "a standalone training-log completion is projected in the member's scope", ctx do
      entry =
        bypass_rls(fn ->
          member_ctx = tenant!(ctx.member, ctx.gym)

          {:ok, entry, :created} =
            LogTrainingEntry.call(member_ctx, ctx.member, %{
              "source_type" => "freeform",
              "title" => "Park run",
              "performed_at" =>
                DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601(),
              "idempotency_key" => "rls-" <> Ecto.UUID.generate()
            })

          entry
        end)

      clear_session!()

      assert :ok =
               ProcessWorkoutCompletionJob.perform(%Oban.Job{
                 args: %{
                   "source" => "training_log",
                   "training_log_entry_id" => entry.id,
                   "organization_id" => ctx.gym.id,
                   "user_id" => ctx.member.id
                 }
               })

      # Both the finished execution and the logged entry count.
      assert %{total_workouts: 2} =
               bypass_rls(fn -> GamificationStore.get_user_stats(ctx.member.id) end)
    end
  end

  describe "per-tenant cron jobs" do
    test "a cron job reaches each active organization (MarkOverdueInvoicesJob)" do
      {context, invoice} =
        bypass_rls(fn ->
          owner = user_fixture()
          member = user_fixture()
          {:ok, gym} = Organizations.create_organization(%{name: "Cron Gym"})
          add!(gym, owner, :owner)
          context = tenant!(owner, gym)

          {:ok, membership} =
            Finance.upsert_membership(context, member.id, %{
              user_type_snapshot: "member",
              status: "active",
              signup_source: "direct"
            })

          {:ok, invoice} =
            Finance.create_invoice(context, membership.id, %{
              amount_cents: 5_000,
              description: "Cron overdue invoice",
              due_date: Date.add(Date.utc_today(), 7)
            })

          {:ok, _issued} = Finance.issue_invoice(context, invoice.id, %{})

          {:ok, _backdated} =
            Finance.update_invoice(context, invoice.id, %{
              due_date: Date.add(Date.utc_today(), -7)
            })

          {context, invoice}
        end)

      clear_session!()
      assert :ok = MarkOverdueInvoicesJob.perform(%Oban.Job{args: %{}})

      assert {:ok, %{status: "overdue"}} =
               bypass_rls(fn -> Finance.get_invoice(context, invoice.id) end)
    end

    test "every per-tenant cron worker runs under the runtime role without a session scope" do
      bypass_rls(fn ->
        owner = user_fixture()
        {:ok, gym} = Organizations.create_organization(%{name: "Smoke Gym"})
        add!(gym, owner, :owner)
      end)

      for worker <- [
            CoachingReplyOverdueJob,
            CorporateInvoicingJob,
            ExecutionAbandonmentSweepJob,
            InventoryDigestJob,
            MarkOverdueInvoicesJob,
            PackageExpiryReminderJob,
            PaymentReminderJob,
            ReconcileEntitlementReservationsJob,
            SubscriptionExpiryJob
          ] do
        clear_session!()
        assert :ok = worker.perform(%Oban.Job{args: %{}}), "#{inspect(worker)} failed"
      end
    end
  end

  describe "materialized view refresh as the runtime (non-owner) role" do
    test "the leaderboard refresh succeeds and reflects new opt-ins" do
      {gym, member} =
        bypass_rls(fn ->
          member = user_fixture()
          {:ok, gym} = Organizations.create_organization(%{name: "Refresh Gym"})
          add!(gym, member, :member)

          {:ok, true} =
            Gamification.with_tenant_context(%{organization_id: gym.id, user_id: member.id}, fn ->
              GamificationStore.set_leaderboard_opt_in(member.id, true)
            end)

          {gym, member}
        end)

      clear_session!()
      assert :ok = Gamification.refresh_leaderboard()

      leaderboard =
        Gamification.with_tenant_context(%{organization_id: gym.id, user_id: member.id}, fn ->
          Gamification.get_leaderboard("weekly", 5)
        end)

      assert Enum.any?(leaderboard, &(&1.user_id == member.id))
    end

    test "the coaching and finance aggregate refreshes succeed" do
      clear_session!()
      assert :ok = MilosTraining.Coaching.refresh_aggregates()
      assert :ok = MilosTraining.Finance.refresh_aggregates()
    end

    test "only the allow-listed views can be refreshed through the definer function" do
      assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
               Repo.query("SELECT milos_refresh_materialized_view('users')")
    end
  end

  defp add!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp tenant!(user, organization) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end
end
