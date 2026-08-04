defmodule MilosTraining.Scheduling.Commands.WithdrawBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(%{organization_id: _} = context, id),
    do: SchedulingStore.withdraw_booking(context, id)

  def call(id, reconciliation),
    do: SchedulingStore.withdraw_booking_with_reconciliation(id, reconciliation)

  def call(context, id, reconciliation),
    do: SchedulingStore.withdraw_booking_with_reconciliation(context, id, reconciliation)

  def call(id), do: SchedulingStore.withdraw_booking(id)
end
