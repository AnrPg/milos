defmodule MilosTraining.Scheduling.Commands.CreateClassType do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(params), do: SchedulingStore.create_class_type(params)
end
