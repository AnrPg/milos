defmodule Palee.Scheduling.Commands.ExtendClassSeries do
  alias Palee.Scheduling.SchedulingStore

  def call(context, series_id, horizon),
    do: SchedulingStore.extend_class_series(context, series_id, horizon)

  def call(series_id, horizon), do: SchedulingStore.extend_class_series(series_id, horizon)
end
