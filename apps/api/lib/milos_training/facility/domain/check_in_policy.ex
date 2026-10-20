defmodule MilosTraining.Facility.Domain.CheckInPolicy do
  @moduledoc """
  Pure rules for open-gym check-ins (ADR-097): a check-in draws one
  `open_gym_visits` unit through the Facility channel, once per member and
  local day, at an active location.
  """

  @doc "Ledger request for one open-gym visit."
  def entitlement_request(location_id, %Date{} = occurred_on) do
    %{
      channel: :facility,
      capability: :open_gym,
      allowance: :open_gym_visits,
      quantity: 1,
      location_id: location_id,
      occurred_on: occurred_on
    }
  end

  @doc """
  Idempotency key of one check-in's visit. The day's single check-in is held
  by the `(user_id, checked_in_on)` unique index (a losing concurrent insert
  releases its reservation); the key is per check-in so a check-in undone
  within its minute (ADR-155) leaves the next one free to reserve again.
  """
  def idempotency_key(user_id, %Date{} = date, check_in_id),
    do: "open-gym:#{user_id}:#{Date.to_iso8601(date)}:#{check_in_id}"

  @doc "Self check-in when the actor is the member, otherwise staff."
  def source(actor_id, user_id) when actor_id == user_id, do: "self"
  def source(_actor_id, _user_id), do: "staff"

  def usable_location(nil), do: :ok
  def usable_location(%{archived_at: nil}), do: :ok
  def usable_location(%{archived_at: _archived}), do: {:error, :location_archived}

  @doc "The gym's local date for an instant, falling back to UTC."
  def local_date(%DateTime{} = now, timezone) when is_binary(timezone) do
    case DateTime.shift_zone(now, timezone) do
      {:ok, local} -> DateTime.to_date(local)
      _error -> DateTime.to_date(now)
    end
  end

  def local_date(%DateTime{} = now, _timezone), do: DateTime.to_date(now)
end
