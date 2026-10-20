defmodule MilosTraining.Trials.TrialDomainTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Trials.TrialPolicy
  alias MilosTraining.Trials.Domain.{TrialLifecycle, TrialRules}

  @now ~U[2026-10-20 10:00:00Z]

  defp policy(attrs \\ %{}),
    do: struct(%TrialPolicy{organization_id: Ecto.UUID.generate(), enabled: true}, attrs)

  defp facts(overrides \\ %{}) do
    Map.merge(
      %{
        slot: %{
          scheduled_at: DateTime.add(@now, 1, :day),
          class_type_id: "strength",
          capacity: 10,
          booked: 3
        },
        trial_seats_taken: 0,
        week_trials: 0,
        person: %{member?: false, ever_member?: false, consumed: 0, open?: false},
        now: @now
      },
      overrides
    )
  end

  describe "TrialRules.check/2" do
    test "a first-timer may try an open class" do
      assert :ok = TrialRules.check(policy(), facts())
    end

    test "class limits" do
      assert {:error, :trials_disabled} = TrialRules.check(policy(%{enabled: false}), facts())

      assert {:error, :class_not_open_to_trials} =
               TrialRules.check(policy(%{class_type_ids: ["yoga"]}), facts())

      past = put_in(facts().slot.scheduled_at, DateTime.add(@now, -1, :hour))
      assert {:error, :slot_in_past} = TrialRules.check(policy(), past)

      far = put_in(facts().slot.scheduled_at, DateTime.add(@now, 10, :day))
      assert {:error, :beyond_trial_horizon} = TrialRules.check(policy(%{horizon_days: 7}), far)
      assert :ok = TrialRules.check(policy(), far)

      full = put_in(facts().slot.booked, 10)
      assert {:error, :slot_full} = TrialRules.check(policy(), full)

      assert {:error, :no_trial_seats} =
               TrialRules.check(policy(%{seats_per_class: 2}), facts(%{trial_seats_taken: 2}))

      assert {:error, :weekly_trial_limit_reached} =
               TrialRules.check(policy(%{weekly_limit: 5}), facts(%{week_trials: 5}))
    end

    test "person limits" do
      person = &facts(%{person: Map.merge(facts().person, &1)})

      assert {:error, :already_member} = TrialRules.check(policy(), person.(%{member?: true}))
      assert :ok = TrialRules.check(policy(), person.(%{ever_member?: true}))

      assert {:error, :trial_for_first_timers_only} =
               TrialRules.check(
                 policy(%{first_timers_only: true}),
                 person.(%{ever_member?: true})
               )

      assert {:error, :trial_already_open} = TrialRules.check(policy(), person.(%{open?: true}))
      assert {:error, :trial_already_used} = TrialRules.check(policy(), person.(%{consumed: 1}))
      assert :ok = TrialRules.check(policy(%{per_person_limit: 2}), person.(%{consumed: 1}))
    end

    test "trial seats never exceed the class's free seats" do
      assert TrialRules.seats_left(policy(%{seats_per_class: 5}), %{capacity: 10, booked: 8}, 0) ==
               2

      assert TrialRules.seats_left(policy(%{seats_per_class: 2}), %{capacity: 10, booked: 0}, 3) ==
               0
    end

    test "weeks run Monday to Sunday in the box's time zone" do
      # Sunday 23:30 in Athens is still that week; Monday 00:30 is the next.
      {from, to} = TrialRules.week_of(~U[2026-10-25 21:30:00Z], "Europe/Athens")
      assert from == ~U[2026-10-18 21:00:00Z]
      assert to == ~U[2026-10-25 22:00:00Z]
    end
  end

  describe "TrialLifecycle" do
    test "an undone check-in takes back the attend step, never a conversion" do
      assert {:ok, %{status: "booked", attended_at: nil}} =
               TrialLifecycle.undo_attend(%{status: "attended"}, "booked")

      assert {:ok, %{status: "no_show"}} =
               TrialLifecycle.undo_attend(%{status: "attended"}, "no_show")

      assert {:error, :invalid_trial_transition} =
               TrialLifecycle.undo_attend(%{status: "converted"}, "booked")

      assert {:error, :invalid_trial_transition} =
               TrialLifecycle.undo_attend(%{status: "attended"}, "requested")
    end

    test "allowed steps stamp the change; others are refused" do
      assert {:ok, %{status: "booked", decided_by_id: "staff"}} =
               TrialLifecycle.transition(%{status: "requested"}, :accept, @now, by: "staff")

      assert {:ok, %{status: "attended", attended_at: @now}} =
               TrialLifecycle.transition(%{status: "no_show"}, :attend, @now)

      assert {:ok, %{status: "converted"}} =
               TrialLifecycle.transition(%{status: "booked"}, :convert, @now)

      assert {:error, :invalid_trial_transition} =
               TrialLifecycle.transition(%{status: "declined"}, :accept, @now)

      assert {:error, :invalid_trial_transition} =
               TrialLifecycle.transition(%{status: "attended"}, :cancel, @now)
    end

    test "which outcomes use up a trial" do
      assert TrialLifecycle.consumes?("attended", false)
      refute TrialLifecycle.consumes?("no_show", false)
      assert TrialLifecycle.consumes?("no_show", true)
      refute TrialLifecycle.consumes?("cancelled", true)
      refute TrialLifecycle.consumes?("declined", true)
    end
  end
end
