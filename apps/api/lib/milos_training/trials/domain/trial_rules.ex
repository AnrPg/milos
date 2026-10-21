defmodule MilosTraining.Trials.Domain.TrialRules do
  @moduledoc """
  Whether a person may take a trial in a class, under the box's policy
  (ADR-144, plan D7). Pure: the application gathers the facts.

  Facts:

    * `:slot` - `%{scheduled_at, class_type_id, capacity, booked}` where
      `booked` counts the seats already taken (members, guests and trials);
    * `:trial_seats_taken` - active trial bookings in the class;
    * `:week_trials` - trials in classes of the same week at this box;
    * `:person` - `%{member?, ever_member?, consumed, open?}`;
    * `:now`.
  """

  @type reason ::
          :trials_disabled
          | :class_not_open_to_trials
          | :slot_in_past
          | :beyond_trial_horizon
          | :slot_full
          | :no_trial_seats
          | :weekly_trial_limit_reached
          | :already_member
          | :trial_for_first_timers_only
          | :trial_already_used
          | :trial_already_open

  @spec check(map(), map()) :: :ok | {:error, reason()}
  def check(policy, facts) do
    with :ok <- class_check(policy, facts),
         :ok <- person_check(policy, facts.person) do
      :ok
    end
  end

  @doc "The class-level part: whether the class can take a trial guest at all."
  def class_check(policy, %{slot: slot, now: now} = facts) do
    cond do
      not policy.enabled -> {:error, :trials_disabled}
      not open_type?(policy, slot) -> {:error, :class_not_open_to_trials}
      DateTime.compare(slot.scheduled_at, now) != :gt -> {:error, :slot_in_past}
      beyond_horizon?(policy, slot, now) -> {:error, :beyond_trial_horizon}
      full?(slot) -> {:error, :slot_full}
      seats_left(policy, slot, facts.trial_seats_taken) <= 0 -> {:error, :no_trial_seats}
      week_full?(policy, facts.week_trials) -> {:error, :weekly_trial_limit_reached}
      true -> :ok
    end
  end

  @doc "The person-level part, independent of the class."
  def person_check(policy, person) do
    cond do
      person.member? -> {:error, :already_member}
      policy.first_timers_only and person.ever_member? -> {:error, :trial_for_first_timers_only}
      person.open? -> {:error, :trial_already_open}
      person.consumed >= policy.per_person_limit -> {:error, :trial_already_used}
      true -> :ok
    end
  end

  @doc "Trial seats still free in a class: the owner's seats, never more than the class has."
  def seats_left(policy, slot, trial_seats_taken) do
    free = max(slot.capacity - slot.booked, 0)
    min(policy.seats_per_class - trial_seats_taken, free) |> max(0)
  end

  @doc "Whether a class type takes trials (an empty list means every type)."
  def open_type?(%{class_type_ids: []}, _slot), do: true
  def open_type?(%{class_type_ids: ids}, %{class_type_id: id}), do: id in ids

  @doc "The status a new trial starts in: booked at once, or waiting for staff."
  def initial_status(%{approval: "manual"}), do: "requested"
  def initial_status(_policy), do: "booked"

  @doc """
  The Monday-to-Sunday week (in the box's time zone) a class falls in, as
  UTC instants `{from, to}`; the weekly limit counts trials in it.
  """
  def week_of(%DateTime{} = at, time_zone) do
    local = shift(at, time_zone)
    monday = Date.add(DateTime.to_date(local), 1 - Date.day_of_week(local))

    {start_of(monday, time_zone), start_of(Date.add(monday, 7), time_zone)}
  end

  defp beyond_horizon?(%{horizon_days: nil}, _slot, _now), do: false

  defp beyond_horizon?(policy, slot, now),
    do: DateTime.compare(slot.scheduled_at, DateTime.add(now, policy.horizon_days, :day)) == :gt

  defp full?(%{capacity: capacity, booked: booked}), do: booked >= capacity

  defp week_full?(%{weekly_limit: nil}, _count), do: false
  defp week_full?(%{weekly_limit: limit}, count), do: count >= limit

  defp shift(at, zone) do
    case DateTime.shift_zone(at, zone || "Etc/UTC") do
      {:ok, local} -> local
      {:error, _} -> at
    end
  end

  defp start_of(date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone || "Etc/UTC") do
      {:ok, at} -> DateTime.shift_zone!(at, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:error, _} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end
  end
end
