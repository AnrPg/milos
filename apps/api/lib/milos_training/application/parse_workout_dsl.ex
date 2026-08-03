defmodule MilosTraining.Application.ParseWorkoutDsl do
  @moduledoc """
  Builds an authoritative canonical preview from Quick Text workout source.
  """

  alias MilosTraining.Workouts

  def call(source) do
    with {:ok, parsed} <- Workouts.parse_dsl(source) do
      {:ok,
       %{
         version: parsed.version,
         workout: parsed.workout,
         formatted_source: Workouts.format_dsl(parsed.workout, version: parsed.version),
         vocabulary: Workouts.dsl_vocabulary(),
         diagnostics: parsed.diagnostics
       }}
    end
  end
end
