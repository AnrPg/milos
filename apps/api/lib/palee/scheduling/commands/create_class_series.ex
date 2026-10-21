defmodule Palee.Scheduling.Commands.CreateClassSeries do
  alias Palee.Scheduling.SchedulingStore

  def call(context, params), do: SchedulingStore.create_class_series(context, params)
  def call(params), do: SchedulingStore.create_class_series(params)
end
