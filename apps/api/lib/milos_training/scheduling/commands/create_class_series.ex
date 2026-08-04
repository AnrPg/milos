defmodule MilosTraining.Scheduling.Commands.CreateClassSeries do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, params), do: SchedulingStore.create_class_series(context, params)
  def call(params), do: SchedulingStore.create_class_series(params)
end
