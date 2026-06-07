defmodule MilosTraining.Application.ReplaceScaleLevels do
  alias MilosTraining.Workouts

  def call(params) when is_list(params) do
    with {:ok, scale_levels} <- Workouts.replace_scale_levels(params) do
      {:ok, scale_levels}
    end
  end
end
