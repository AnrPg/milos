defmodule MilosTraining.Scheduling.Commands.TimeoutBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(%{organization_id: _} = context, id),
    do: SchedulingStore.timeout_booking(context, id)

  def call(id), do: SchedulingStore.timeout_booking(id)
end
