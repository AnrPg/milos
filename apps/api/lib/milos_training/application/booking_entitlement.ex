defmodule MilosTraining.Application.BookingEntitlement do
  @moduledoc """
  Ledger allowance a booking reserved (class visits, event visits or guest
  passes, ADR-097). Release, finalize and late-cancellation flows use it so a
  guest or event booking never touches the member's class visits.
  """

  @allowances %{
    "class_visits" => :class_visits,
    "event_visits" => :event_visits,
    "guest_passes" => :guest_passes
  }

  def allowance(%{entitlement_allowance: value}) when is_binary(value),
    do: Map.get(@allowances, value, :class_visits)

  def allowance(%{entitlement_allowance: value}) when is_atom(value) and not is_nil(value),
    do: value

  def allowance(%{"entitlement_allowance" => value}) when is_binary(value),
    do: Map.get(@allowances, value, :class_visits)

  def allowance(_booking), do: :class_visits
end
