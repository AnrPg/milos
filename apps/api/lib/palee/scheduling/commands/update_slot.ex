defmodule Palee.Scheduling.Commands.UpdateSlot do
  alias Palee.Scheduling.SchedulingStore

  def call(context, id, params), do: SchedulingStore.update_slot(context, id, params)
  def call(id, params), do: SchedulingStore.update_slot(id, params)
end
