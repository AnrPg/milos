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

  alias MilosTraining.Application.{
    AdminMemberSearchDocuments,
    AdminRecordAttendance,
    AssignWorkout,
    DeleteWorkout,
    LogTrainingEntry,
    ResolveBooking,
    SubmitBooking,
    WithdrawBooking
  }

  alias MilosTraining.{
    Execution,
    Finance,
    Gamification,
    Notifications,
    Organizations,
    Scheduling,
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
    ReconcileBookingReleaseJob,
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

  describe "class-visit entitlement reconciliation" do
    setup do
      bypass_rls(fn ->
        owner = user_fixture()
        member = user_fixture()
        {:ok, gym} = Organizations.create_organization(%{name: "Visits Gym"})
        add!(gym, owner, :owner)
        add!(gym, member, :member)
        owner_ctx = tenant!(owner, gym)
        member_ctx = tenant!(member, gym)

        {:ok, _settings} =
          Finance.update_finance_settings(owner_ctx, %{
            entitlement_enforcement_mode: "enforce_managed",
            entitlement_timezone: "Europe/Athens"
          })

        {:ok, package} =
          Finance.create_package(owner_ctx, %{
            name: "One visit #{System.unique_integer([:positive])}",
            package_type: "class_pack",
            fields: %{
              "group_classes.visits" => %{"limit" => 1, "period" => "subscription_period"},
              "booking.no_show_penalty_waived" => true
            }
          })

        {:ok, membership} =
          Finance.upsert_membership(owner_ctx, member.id, %{
            user_type_snapshot: "member",
            status: "active",
            signup_source: "direct"
          })

        {:ok, _subscription} =
          Finance.assign_package(owner_ctx, membership.id, package.id, %{})

        {:ok, class_type} =
          Scheduling.create_class_type(owner_ctx, %{
            name: "Visits type",
            slug: "visits-type-#{System.unique_integer([:positive])}",
            sort_order: 1
          })

        workout = workout_fixture(owner, %{tenant_context: owner_ctx})

        slot = fn attrs ->
          slot_fixture(
            workout,
            Map.merge(
              %{tenant_context: owner_ctx, class_type_id: class_type.id, auto_approve: true},
              attrs
            )
          )
        end

        %{owner: owner, member: member, owner_ctx: owner_ctx, member_ctx: member_ctx, slot: slot}
      end)
    end

    test "withdrawing on time returns the visit and clears the staff's pending notice", ctx do
      booking = book!(ctx, ctx.slot.(%{auto_approve: false}))

      {:ok, _notification} =
        bypass_rls(fn ->
          Notifications.create_notification(%{
            user_id: ctx.owner.id,
            organization_id: ctx.owner_ctx.organization_id,
            type: :booking_pending,
            payload: %{"booking_id" => booking.id}
          })
        end)

      clear_session!()

      assert {:ok, %{late_cancellation: false}} =
               WithdrawBooking.call(ctx.member_ctx, ctx.member.id, booking.id)

      assert_visit_available!(ctx)

      assert bypass_rls(fn -> Notifications.list_for_user(ctx.owner.id) end)
             |> Enum.filter(&(to_string(&1.type) == "booking_pending")) == []
    end

    test "rejecting a pending booking returns the visit", ctx do
      booking = book!(ctx, ctx.slot.(%{auto_approve: false}))
      clear_session!()

      assert {:ok, %{status: :rejected}, :resolved} =
               ResolveBooking.call(ctx.owner_ctx, booking.id, %{action: "reject"})

      assert_visit_available!(ctx)
    end

    test "a waived no-show returns the visit", ctx do
      slot = ctx.slot.(%{})
      _booking = book!(ctx, slot)
      clear_session!()

      assert {:ok, %{status: "no_show"}} =
               AdminRecordAttendance.call(ctx.owner_ctx, slot.id, ctx.member.id, ctx.owner.id, %{
                 "status" => "no_show"
               })

      assert_visit_available!(ctx)
    end

    test "the reconcile job releases a reservation it is retried for", ctx do
      slot = ctx.slot.(%{})
      booking = book!(ctx, slot)
      clear_session!()

      assert :ok =
               ReconcileBookingReleaseJob.perform(%Oban.Job{
                 args: %{
                   "organization_id" => ctx.owner_ctx.organization_id,
                   "booking_id" => booking.id,
                   "user_id" => ctx.member.id,
                   "scheduled_class_id" => slot.id,
                   "allowance" => "class_visits",
                   "finalize" => false,
                   "reason" => "Booking withdrawn",
                   "idempotency_key" => "booking-withdrawn:#{booking.id}"
                 }
               })

      assert_visit_available!(ctx)
    end
  end

  defp book!(ctx, slot) do
    bypass_rls(fn ->
      {:ok, booking} = SubmitBooking.call(ctx.member_ctx, ctx.member, slot.id)
      booking
    end)
  end

  # With a one-visit package, a second booking only succeeds once the first
  # reservation was released.
  defp assert_visit_available!(ctx) do
    bypass_rls(fn ->
      later =
        ctx.slot.(%{
          scheduled_at:
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(72 * 3600, :second)
        })

      assert {:ok, _booking} = SubmitBooking.call(ctx.member_ctx, ctx.member, later.id)
    end)
  end

  describe "admin member search index rebuild (RebuildMemberSearchIndexJob)" do
    test "documents carry the member's gyms and finance summary" do
      {gym, member} =
        bypass_rls(fn ->
          owner = user_fixture()
          member = user_fixture()
          {:ok, gym} = Organizations.create_organization(%{name: "Search Gym"})
          add!(gym, owner, :owner)
          add!(gym, member, :member)

          {:ok, _membership} =
            Finance.upsert_membership(tenant!(owner, gym), member.id, %{
              user_type_snapshot: "member",
              status: "active",
              signup_source: "direct"
            })

          {gym, member}
        end)

      clear_session!()
      documents = AdminMemberSearchDocuments.build_all()
      document = Enum.find(documents, &(&1.id == member.id))

      assert document.organization_ids == [gym.id]
      assert document.membership_status == "active"
    end
  end

  describe "workout change fanout to assigned athletes" do
    test "deleting a workout tells the athletes it was assigned to" do
      {owner_ctx, athlete, workout} =
        bypass_rls(fn ->
          owner = user_fixture()
          athlete = user_fixture(%{role: :athlete})
          {:ok, gym} = Organizations.create_organization(%{name: "Fanout Gym"})
          add!(gym, owner, :owner)
          add!(gym, athlete, :athlete)
          owner_ctx = tenant!(owner, gym)
          workout = workout_fixture(owner, %{tenant_context: owner_ctx})

          {:ok, _assignment} =
            AssignWorkout.call(owner_ctx, %{
              master_workout_id: workout.id,
              athlete_ids: [athlete.id],
              scheduled_for: Date.utc_today()
            })

          {owner_ctx, athlete, workout}
        end)

      clear_session!()
      assert :ok = DeleteWorkout.call(owner_ctx, workout.id)

      types =
        bypass_rls(fn -> Notifications.list_for_user(athlete.id) end)
        |> Enum.map(&to_string(&1.type))

      assert "workout_deleted" in types
    end
  end

  describe "nickname propagation (PropagateNicknameJob)" do
    test "other users' notifications pick up a sender's new nickname" do
      suffix = System.unique_integer([:positive])
      old_nickname = "oldnick#{suffix}"
      new_nickname = "newnick#{suffix}"

      recipient =
        bypass_rls(fn ->
          sender = user_fixture(%{nickname: old_nickname})
          recipient = user_fixture()

          {:ok, _notification} =
            Notifications.create_notification(%{
              user_id: recipient.id,
              type: :athlete_message,
              payload: %{"sender_nickname" => old_nickname, "body" => "hi"}
            })

          {:ok, _renamed} =
            MilosTraining.Identity.update_profile(sender.id, %{nickname: new_nickname})

          recipient
        end)

      clear_session!()
      assert :ok = Notifications.propagate_nickname_change(old_nickname, new_nickname)

      assert [%{payload: %{"sender_nickname" => ^new_nickname}}] =
               bypass_rls(fn -> Notifications.list_for_user(recipient.id) end)
    end

    test "a nickname still held by an account is never rewritten" do
      held = "heldnick#{System.unique_integer([:positive])}"

      recipient =
        bypass_rls(fn ->
          _holder = user_fixture(%{nickname: held})
          other = user_fixture()
          recipient = user_fixture()

          {:ok, _notification} =
            Notifications.create_notification(%{
              user_id: recipient.id,
              type: :athlete_message,
              payload: %{"sender_nickname" => held, "body" => "hi"}
            })

          _ = other
          recipient
        end)

      clear_session!()
      other_nickname = bypass_rls(fn -> user_fixture().nickname end)
      assert :ok = Notifications.propagate_nickname_change(held, other_nickname)

      assert [%{payload: %{"sender_nickname" => ^held}}] =
               bypass_rls(fn -> Notifications.list_for_user(recipient.id) end)
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
