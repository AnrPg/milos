defmodule MilosTraining.Scheduling.Commands.ExtendClassSeries do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(series_id, horizon), do: SchedulingStore.extend_class_series(series_id, horizon)
end
