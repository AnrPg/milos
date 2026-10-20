defmodule MilosTraining.Facility.Domain.DeskAssessment do
  @moduledoc """
  What the desk sees after scanning a member's code (ADR-155, decision 4):
  the scan decision (the same `ResolveScan` a door scan uses), the problems
  with the member's package, whether «auto» may check in on its own, and
  whether «Check-in παρ' όλα αυτά» is allowed.

  Problems, in the order the desk shows them:

    * `:frozen` - the membership is paused;
    * `:package_expired` - no package covers today (ended, cancelled, none);
    * `:unpaid` - an overdue invoice blocks access;
    * `:no_spots` - no booking now and the class starting now here is full;
    * `:nothing_to_check_in` - no booking now and no open gym.

  `:payment_due` (an open invoice inside its grace period) is a warning and
  never blocks. Auto check-in needs no problems and exactly one thing to
  check in to; an override needs the owner's `desk_override` and a problem.
  """

  alias MilosTraining.Facility.Domain.{CheckInRules, ResolveScan}

  @doc """
  `facts` are `ResolveScan`'s plus `entitlement` (the member's effective
  entitlement or nil when the box keeps no package for them).
  """
  def assess(facts, settings, %DateTime{} = now) do
    settings = CheckInRules.effective(settings)
    decision = ResolveScan.decide(Map.put(facts, :member?, true), settings, now)
    entitlement = Map.get(facts, :entitlement)

    problems =
      package_problems(entitlement) ++ availability_problems(decision, facts, settings, now)

    %{
      decision: decision,
      problems: problems,
      warnings: warnings(entitlement),
      can_auto_check_in: problems == [] and checkable?(decision),
      override_allowed: problems != [] and settings.desk_override and overridable?(decision)
    }
  end

  @doc "What an override checks in to: the booking in the window, or open gym."
  def override_target({:check_in_class, booking}), do: {:class, booking}
  def override_target({:choose, [booking | _rest]}), do: {:class, booking}
  def override_target({:nothing, _details}), do: :open_gym
  def override_target(:open_gym), do: :open_gym
  def override_target(_decision), do: nil

  defp package_problems(nil), do: []

  defp package_problems(entitlement) do
    [
      frozen?(entitlement) && :frozen,
      expired?(entitlement) && :package_expired,
      Map.get(entitlement, :status) == "blocked" && :unpaid
    ]
    |> Enum.filter(& &1)
  end

  defp frozen?(entitlement), do: not is_nil(Map.get(entitlement, :frozen_until))

  defp expired?(entitlement),
    do: Map.get(entitlement, :status) == "inactive" and not frozen?(entitlement)

  defp availability_problems({:nothing, %{classes: _}}, facts, settings, now) do
    if full_class_now?(facts, settings, now), do: [:no_spots], else: [:nothing_to_check_in]
  end

  defp availability_problems(_decision, _facts, _settings, _now), do: []

  defp full_class_now?(facts, settings, now) do
    facts
    |> Map.get(:classes, [])
    |> Enum.any?(fn class ->
      class.location_id in [nil, facts.location_id] and (class.spots_remaining || 0) <= 0 and
        CheckInRules.in_window?(settings, class.starts_at, now)
    end)
  end

  defp warnings(%{status: "grace"}), do: [:payment_due]
  defp warnings(_entitlement), do: []

  defp checkable?({:check_in_class, _booking}), do: true
  defp checkable?(:open_gym), do: true
  defp checkable?(_decision), do: false

  defp overridable?(decision), do: override_target(decision) != nil
end
