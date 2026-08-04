defmodule MilosTraining.Scheduling.Commands.RejectBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(%{organization_id: _} = context, id, admin_message),
    do: SchedulingStore.reject_booking(context, id, admin_message)

  def call(id, admin_message, reconciliation),
    do: SchedulingStore.reject_booking_with_reconciliation(id, admin_message, reconciliation)

  def call(context, id, admin_message, reconciliation),
    do:
      SchedulingStore.reject_booking_with_reconciliation(
        context,
        id,
        admin_message,
        reconciliation
      )

  def call(id, admin_message), do: SchedulingStore.reject_booking(id, admin_message)
end
