defmodule Palee.Scheduling.Queries.GetBooking do
  alias Palee.Scheduling.SchedulingStore

  def call(context, id), do: SchedulingStore.get_booking(context, id)
  def call(id), do: SchedulingStore.get_booking(id)
end
