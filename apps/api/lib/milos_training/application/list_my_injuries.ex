defmodule MilosTraining.Application.ListMyInjuries do
  alias MilosTraining.Wellbeing

  def call(user_id), do: {:ok, %{injuries: Wellbeing.list_injuries_for_user(user_id)}}
end
