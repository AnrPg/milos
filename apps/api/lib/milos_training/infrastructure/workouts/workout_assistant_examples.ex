defmodule MilosTraining.Infrastructure.Workouts.WorkoutAssistantExamples do
  @moduledoc """
  Curated few-shot examples for the workout assistant: real-style coach text
  and the canonical answer it should produce (see
  `priv/workout_assistant/examples/README.md`).

  Examples are read at compile time; adding, changing or removing a file
  recompiles this module and therefore the prompts.
  """

  @directory Path.expand("../../../../priv/workout_assistant/examples", __DIR__)
  @paths @directory |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()

  for path <- @paths, do: @external_resource(path)

  @examples Enum.map(@paths, fn path ->
              path
              |> File.read!()
              |> Jason.decode!()
              |> Map.put("file", Path.basename(path))
            end)

  @doc "All examples, in file-name order."
  def all, do: @examples

  def __mix_recompile__? do
    @directory |> Path.join("*.json") |> Path.wildcard() |> Enum.sort() != @paths
  end
end
