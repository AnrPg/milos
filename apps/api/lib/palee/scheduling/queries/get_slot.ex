defmodule Palee.Scheduling.Queries.GetSlot do
  alias Palee.Scheduling.SchedulingStore

  def call(context, id), do: SchedulingStore.get_slot(context, id)
  def call(id), do: SchedulingStore.get_slot(id)
end
