defmodule Palee.Scheduling.Commands.SubmitBooking do
  alias Palee.Scheduling.SchedulingStore

  def call(context, user_id, slot_id, timeout_minutes, opts) when is_list(opts),
    do: SchedulingStore.create_booking(context, user_id, slot_id, timeout_minutes, opts)

  def call(context, user_id, slot_id, timeout_minutes),
    do: SchedulingStore.create_booking(context, user_id, slot_id, timeout_minutes)

  def call(user_id, slot_id, timeout_minutes),
    do: SchedulingStore.create_booking(user_id, slot_id, timeout_minutes)
end
