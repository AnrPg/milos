defmodule MilosTraining.Scheduling.Commands.UpdateClassType do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id, params), do: SchedulingStore.update_class_type(id, params)
end
