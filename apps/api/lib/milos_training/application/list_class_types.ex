defmodule MilosTraining.Application.ListClassTypes do
  alias MilosTraining.Scheduling

  def call(context, opts), do: {:ok, Scheduling.list_class_types(context, opts)}
  def call(%{organization_id: _} = context), do: call(context, [])
  def call(opts) when is_list(opts), do: {:ok, Scheduling.list_class_types(opts)}
  def call(), do: call([])
end
