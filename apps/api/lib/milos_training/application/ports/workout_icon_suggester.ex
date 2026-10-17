defmodule MilosTraining.Application.Ports.WorkoutIconSuggester do
  @moduledoc "Suggests a single emoji for a workout from its title, type and content."

  @type workout_summary :: %{
          title: String.t(),
          type: String.t() | nil,
          description: String.t() | nil,
          sections: [String.t()],
          movements: [String.t()]
        }

  @typedoc "Who the call is made for, so its model usage is metered (ADR-141)."
  @type metering :: %{
          optional(:organization_id) => String.t(),
          optional(:user_id) => String.t() | nil,
          optional(:operation_id) => String.t(),
          optional(:feature) => String.t()
        }

  @callback suggest(workout_summary(), metering()) :: {:ok, String.t()} | {:error, term()}
end
