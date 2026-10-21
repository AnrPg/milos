defmodule Palee.Scheduling.Commands.SubmitAutoApprovedBooking do
  alias Palee.Scheduling.SchedulingStore

  def call(context, user_id, slot_id, opts) when is_list(opts),
    do: SchedulingStore.create_approved_booking(context, user_id, slot_id, opts)

  def call(context, user_id, slot_id),
    do: SchedulingStore.create_approved_booking(context, user_id, slot_id)

  def call(user_id, slot_id), do: SchedulingStore.create_approved_booking(user_id, slot_id)
end
