defmodule MilosTraining.Scheduling.Commands.CancelUserBookingsForRoleTransition do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, user_id),
    do: SchedulingStore.cancel_active_future_bookings_for_user(context, user_id)

  def call(user_id), do: SchedulingStore.cancel_active_future_bookings_for_user(user_id)
end
