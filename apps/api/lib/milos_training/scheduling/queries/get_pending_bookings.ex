defmodule MilosTraining.Scheduling.Queries.GetPendingBookings do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context), do: SchedulingStore.get_pending_bookings(context)
  def call, do: SchedulingStore.get_pending_bookings()
end
