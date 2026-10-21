defmodule MilosTraining.Seasons.DomainTest do
  @moduledoc "ADR-167: season rules and the enrollment lifecycle are pure."

  use ExUnit.Case, async: true

  alias MilosTraining.Seasons.Domain.{EnrollmentLifecycle, SeasonRules}

  @start ~D[2026-11-02]
  @offering %{status: "published", starts_on: @start, weeks: 2}

  describe "dates and status" do
    test "a season runs for whole weeks from its start" do
      assert SeasonRules.ends_on(@start, 2) == ~D[2026-11-15]
      assert SeasonRules.ends_on(@offering) == ~D[2026-11-15]
    end

    test "running and completed follow from the dates" do
      assert SeasonRules.effective_status(@offering, ~D[2026-11-01]) == "published"
      assert SeasonRules.effective_status(@offering, @start) == "running"
      assert SeasonRules.effective_status(@offering, ~D[2026-11-15]) == "running"
      assert SeasonRules.effective_status(@offering, ~D[2026-11-16]) == "completed"
    end

    test "drafts and cancelled seasons keep their status and take no requests" do
      for status <- ~w(draft cancelled) do
        offering = %{@offering | status: status}
        assert SeasonRules.effective_status(offering, @start) == status
        assert SeasonRules.request_check(offering, @start) == {:error, :season_not_open}
      end

      assert SeasonRules.request_check(@offering, ~D[2026-11-10]) == :ok
      assert SeasonRules.request_check(@offering, ~D[2026-11-16]) == {:error, :season_not_open}
    end
  end

  describe "places" do
    test "requests and participants hold places; a full season waitlists" do
      assert SeasonRules.request_status(2, 1) == "requested"
      assert SeasonRules.request_status(2, 2) == "waitlisted"
      assert SeasonRules.can_confirm?(2, 1)
      refute SeasonRules.can_confirm?(2, 2)
    end

    test "the schedule locks once someone is confirmed" do
      refute SeasonRules.schedule_locked?(0)
      assert SeasonRules.schedule_locked?(1)
    end
  end

  describe "programme" do
    test "orders items and keeps days inside the season" do
      a = Ecto.UUID.generate()
      b = Ecto.UUID.generate()

      assert {:ok, [%{"day" => 0, "workout_id" => ^b}, %{"day" => 13, "workout_id" => ^a}]} =
               SeasonRules.normalize_programme(
                 [%{"day" => 13, "workout_id" => a}, %{day: "0", workout_id: b}],
                 2
               )

      assert {:error, _} = SeasonRules.normalize_programme([%{day: 14, workout_id: a}], 2)
      assert {:error, _} = SeasonRules.normalize_programme([%{day: 1}], 2)

      assert {:error, _} =
               SeasonRules.normalize_programme(
                 [%{day: 1, workout_id: a}, %{day: 1, workout_id: a}],
                 2
               )
    end

    test "schedules dated workouts from the later of the start and today" do
      a = Ecto.UUID.generate()
      programme = [%{"day" => 0, "workout_id" => a}, %{"day" => 3, "workout_id" => a}]

      assert SeasonRules.schedule(programme, @start, @start) == [
               {@start, a},
               {~D[2026-11-05], a}
             ]

      assert SeasonRules.schedule(programme, @start, ~D[2026-11-04]) == [{~D[2026-11-05], a}]
    end
  end

  describe "enrollment lifecycle" do
    @now ~U[2026-11-01 10:00:00Z]

    test "a request is confirmed or declined; a waitlist place is promoted first" do
      assert {:ok, %{status: "active", decided_by_id: "staff"}} =
               EnrollmentLifecycle.transition(%{status: "requested"}, :confirm, @now, by: "staff")

      assert {:ok, %{status: "declined", decline_reason: "Γεμάτο"}} =
               EnrollmentLifecycle.transition(%{status: "waitlisted"}, :decline, @now,
                 reason: "Γεμάτο"
               )

      assert {:ok, %{status: "requested"}} =
               EnrollmentLifecycle.transition(%{status: "waitlisted"}, :promote, @now)

      assert {:error, :invalid_season_transition} =
               EnrollmentLifecycle.transition(%{status: "declined"}, :confirm, @now)

      assert {:ok, %{status: "completed"}} =
               EnrollmentLifecycle.transition(%{status: "active"}, :complete, @now)
    end

    test "only a new, declined or cancelled member may ask again" do
      assert EnrollmentLifecycle.can_request?(nil)
      assert EnrollmentLifecycle.can_request?("declined")
      assert EnrollmentLifecycle.can_request?("cancelled")
      refute EnrollmentLifecycle.can_request?("requested")
      refute EnrollmentLifecycle.can_request?("active")

      assert %{status: "waitlisted", decided_at: nil, cancelled_at: nil} =
               EnrollmentLifecycle.request("waitlisted", @now)
    end
  end
end
