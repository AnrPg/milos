defmodule MilosTraining.Scheduling.Queries.GetBookingByClientOperation do
  @moduledoc "Finds the booking a member's client operation id created (ADR-110)."
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, user_id, client_operation_id),
    do: SchedulingStore.get_booking_by_client_operation(context, user_id, client_operation_id)
end
