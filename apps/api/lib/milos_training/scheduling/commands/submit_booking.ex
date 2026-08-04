defmodule MilosTraining.Scheduling.Commands.SubmitBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, user_id, slot_id, timeout_minutes),
    do: SchedulingStore.create_booking(context, user_id, slot_id, timeout_minutes)

  def call(user_id, slot_id, timeout_minutes),
    do: SchedulingStore.create_booking(user_id, slot_id, timeout_minutes)
end
