defmodule MilosTraining.Scheduling.Commands.UpdateSlot do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id, params), do: SchedulingStore.update_slot(id, params)
end
