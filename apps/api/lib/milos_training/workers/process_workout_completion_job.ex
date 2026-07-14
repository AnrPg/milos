defmodule MilosTraining.Workers.ProcessWorkoutCompletionJob do
  use Oban.Worker,
    queue: :gamification,
    max_attempts: 10,
    unique: [period: :infinity, fields: [:worker, :args], keys: [:execution_id]]

  alias MilosTraining.Application.CompleteWorkout
  alias MilosTraining.Execution

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => execution_id}}) do
    case Execution.get_execution(execution_id) do
      %{completed_at_utc: %DateTime{}} = execution ->
        CompleteWorkout.process_completion(execution)

      nil ->
        {:cancel, :execution_not_found}

      _execution ->
        {:error, :execution_not_completed}
    end
  end
end
