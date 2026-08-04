defmodule MilosTraining.Scheduling.Commands.DeleteSlot do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, id), do: SchedulingStore.delete_slot(context, id)
  def call(id), do: SchedulingStore.delete_slot(id)
end
