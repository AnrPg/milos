defmodule Palee.Scheduling.Commands.ResolveBookingOperation do
  @moduledoc """
  Approves or rejects a pending booking under the ADR-120 idempotency policy:
  a replay of the operation that already resolved the booking returns
  `{:ok, booking, :replayed}` without side effects.
  """
  alias Palee.Scheduling.SchedulingStore

  def call(context, id, params, reconciliation),
    do: SchedulingStore.resolve_booking_operation(context, id, params, reconciliation)
end
