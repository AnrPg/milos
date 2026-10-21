defmodule Palee.Application.BookingEntitlement do
  @moduledoc """
  Ledger allowance a booking reserved (class visits, event visits or guest
  passes, ADR-097), or none at all for a trial seat (ADR-144). Release,
  finalize and late-cancellation flows go through `release/6` and
  `finalize/6`, so a guest or event booking never touches the member's class
  visits and a trial never touches the ledger.
  """

  alias Palee.Finance

  @allowances %{
    "class_visits" => :class_visits,
    "event_visits" => :event_visits,
    "guest_passes" => :guest_passes,
    "none" => :none
  }

  def allowance(%{entitlement_allowance: value}) when is_binary(value),
    do: Map.get(@allowances, value, :class_visits)

  def allowance(%{entitlement_allowance: value}) when is_atom(value) and not is_nil(value),
    do: value

  def allowance(%{"entitlement_allowance" => value}) when is_binary(value),
    do: Map.get(@allowances, value, :class_visits)

  def allowance(_booking), do: :class_visits

  @doc "Returns a scheduling reservation to the member's package (no-op for :none)."
  def release(_context, _user_id, _scheduled_class_id, :none, _params), do: {:ok, :no_allowance}

  def release(context, user_id, scheduled_class_id, allowance, params),
    do:
      Finance.release_entitlement_source(
        context,
        user_id,
        "scheduling",
        scheduled_class_id,
        allowance,
        params
      )

  @doc "Consumes a scheduling reservation (no-op for :none)."
  def finalize(_context, _user_id, _scheduled_class_id, :none, _params), do: {:ok, :no_allowance}

  def finalize(context, user_id, scheduled_class_id, allowance, params),
    do:
      Finance.finalize_entitlement_source(
        context,
        user_id,
        "scheduling",
        scheduled_class_id,
        allowance,
        params
      )
end
