defmodule MilosTraining.Application.ListAdminInjuries do
  alias MilosTraining.Wellbeing

  def call(context, params),
    do:
      MilosTraining.Wellbeing.WellbeingStore.with_context(context, fn ->
        call(params)
      end)

  def call(params), do: {:ok, %{injuries: Wellbeing.list_injuries(params)}}
end
