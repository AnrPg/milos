defmodule Palee.Scheduling.Commands.CreateClassType do
  alias Palee.Scheduling.SchedulingStore

  def call(context, params), do: SchedulingStore.create_class_type(context, params)
  def call(params), do: SchedulingStore.create_class_type(params)
end
