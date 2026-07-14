defmodule MilosTraining.Scheduling.Commands.SubmitBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(user_id, slot_id, timeout_minutes),
    do: SchedulingStore.create_booking(user_id, slot_id, timeout_minutes)
end
