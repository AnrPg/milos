defmodule MilosTraining.Application.ListMyInjuries do
  alias MilosTraining.Wellbeing

  def call(context, user_id),
    do:
      MilosTraining.Wellbeing.WellbeingStore.with_context(context, fn ->
        call(user_id)
      end)

  def call(user_id), do: {:ok, %{injuries: Wellbeing.list_injuries_for_user(user_id)}}
end
