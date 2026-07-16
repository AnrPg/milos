defmodule MilosTraining.Scheduling.Commands.WithdrawBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id), do: SchedulingStore.withdraw_booking(id)

  def call(id, reconciliation),
    do: SchedulingStore.withdraw_booking_with_reconciliation(id, reconciliation)
end
