defmodule MilosTraining.Scheduling.Queries.GetClassType do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(id, opts \\ []), do: SchedulingStore.get_class_type(id, opts)
end
