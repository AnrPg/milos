defmodule MilosTraining.Workouts.Domain.WorkoutDsl do
  @moduledoc """
  Pure facade for the versioned canonical workout DSL.

  Parsing is deterministic and bounded. Formatting emits the canonical v1
  representation consumed by Beautify, mode switching, documentation
  fixtures, and round-trip verification.
  """

  alias MilosTraining.Workouts.Domain.WorkoutDsl.{Formatter, Parser}

  @type diagnostic :: %{
          code: atom(),
          severity: :error | :warning,
          line: pos_integer(),
          column: pos_integer(),
          params: map()
        }

  @spec parse(binary()) :: {:ok, map()} | {:error, [diagnostic()]}
  defdelegate parse(source), to: Parser

  @spec format(map(), keyword()) :: binary()
  defdelegate format(workout, opts \\ []), to: Formatter
end
