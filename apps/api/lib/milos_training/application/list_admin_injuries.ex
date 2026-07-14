defmodule MilosTraining.Application.ListAdminInjuries do
  alias MilosTraining.Wellbeing

  def call(params), do: {:ok, %{injuries: Wellbeing.list_injuries(params)}}
end
