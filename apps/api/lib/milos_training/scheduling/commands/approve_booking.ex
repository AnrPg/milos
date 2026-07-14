defmodule MilosTraining.Scheduling.Commands.ApproveBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id, admin_message), do: SchedulingStore.approve_booking(id, admin_message)
end
