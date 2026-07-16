defmodule MilosTraining.Scheduling.Commands.RejectBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id, admin_message), do: SchedulingStore.reject_booking(id, admin_message)

  def call(id, admin_message, reconciliation),
    do: SchedulingStore.reject_booking_with_reconciliation(id, admin_message, reconciliation)
end
