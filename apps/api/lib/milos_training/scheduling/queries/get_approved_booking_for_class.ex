defmodule MilosTraining.Scheduling.Queries.GetApprovedBookingForClass do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(user_id, scheduled_class_id),
    do: SchedulingStore.get_approved_booking_for_class(user_id, scheduled_class_id)
end
