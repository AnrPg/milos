defmodule MilosTraining.Scheduling.Queries.GetPendingBookings do
  alias MilosTraining.Scheduling.SchedulingStore

  def call, do: SchedulingStore.get_pending_bookings()
end
