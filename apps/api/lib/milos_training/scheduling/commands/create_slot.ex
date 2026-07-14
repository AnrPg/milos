defmodule MilosTraining.Scheduling.Commands.CreateSlot do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(params), do: SchedulingStore.create_slot(params)
end
