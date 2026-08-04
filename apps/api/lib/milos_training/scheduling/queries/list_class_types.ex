defmodule MilosTraining.Scheduling.Queries.ListClassTypes do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, opts), do: SchedulingStore.list_class_types(context, opts)
  def call(%{organization_id: _} = context), do: call(context, [])
  def call(opts) when is_list(opts), do: SchedulingStore.list_class_types(opts)
  def call(), do: SchedulingStore.list_class_types()
end
