defmodule MilosTraining.Scheduling.Commands.RejectBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id, admin_message), do: SchedulingStore.reject_booking(id, admin_message)
end
