defmodule MilosTraining.Scheduling.Queries.GetClassType do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(context, id, opts), do: SchedulingStore.get_class_type(context, id, opts)
  def call(%{organization_id: _} = context, id), do: call(context, id, [])
  def call(id, opts) when is_list(opts), do: SchedulingStore.get_class_type(id, opts)
  def call(id), do: SchedulingStore.get_class_type(id)
end
