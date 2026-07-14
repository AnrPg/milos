defmodule MilosTraining.Scheduling.Commands.SubmitAutoApprovedBooking do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(user_id, slot_id), do: SchedulingStore.create_approved_booking(user_id, slot_id)
end
