defmodule MilosTraining.Scheduling.Queries.GetSlot do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, id), do: SchedulingStore.get_slot(context, id)
  def call(id), do: SchedulingStore.get_slot(id)
end
