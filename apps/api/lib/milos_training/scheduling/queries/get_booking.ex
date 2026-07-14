defmodule MilosTraining.Scheduling.Queries.GetBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id), do: SchedulingStore.get_booking(id)
end
