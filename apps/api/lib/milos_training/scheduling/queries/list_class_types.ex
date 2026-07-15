defmodule MilosTraining.Scheduling.Queries.ListClassTypes do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(opts \\ []), do: SchedulingStore.list_class_types(opts)
end
