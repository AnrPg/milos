defmodule MilosTraining.Application.Ports.WorkoutIconSuggester do
  @moduledoc "Suggests a single emoji for a workout from its title, type and content."

  @type workout_summary :: %{
          title: String.t(),
          type: String.t() | nil,
          description: String.t() | nil,
          sections: [String.t()],
          movements: [String.t()]
        }

  @callback suggest(workout_summary()) :: {:ok, String.t()} | {:error, term()}
end
