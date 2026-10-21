defmodule Palee.Scheduling.Commands.ApproveBooking do
  alias Palee.Scheduling.SchedulingStore

  def call(context, id, admin_message),
    do: SchedulingStore.approve_booking(context, id, admin_message)

  def call(id, admin_message), do: SchedulingStore.approve_booking(id, admin_message)
end
