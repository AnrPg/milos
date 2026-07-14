defmodule MilosTraining.Scheduling.Commands.DeleteSlot do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id), do: SchedulingStore.delete_slot(id)
end
