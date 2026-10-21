defmodule Palee.Workers.ProcessWorkoutCompletionJob do
  @moduledoc """
  Durable completion projection handoff (ADR-029).

  Two completion sources share this job and its gamification pathway:

    * executions - `%{"execution_id" => id}`
    * standalone training-log entries (ADR-118) -
      `%{"source" => "training_log", "training_log_entry_id" => id,
      "organization_id" => org, "user_id" => user}`

  Uniqueness is per completion (`execution_id` / `training_log_entry_id`), so
  each completion is projected exactly once.
  """

  use Oban.Worker,
    queue: :gamification,
    max_attempts: 10,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:execution_id, :training_log_entry_id]
    ]

  alias Palee.Application.CompleteWorkout
  alias Palee.Execution
  alias Palee.Execution.ExecutionStore

  def training_log_job(%{id: id, organization_id: organization_id, user_id: user_id}) do
    new(%{
      "source" => "training_log",
      "training_log_entry_id" => id,
      "organization_id" => organization_id,
      "user_id" => user_id
    })
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "training_log_entry_id" => entry_id,
          "organization_id" => organization_id,
          "user_id" => user_id
        }
      }) do
    entry =
      Execution.with_training_log_context(
        %{organization_id: organization_id, user_id: user_id},
        fn -> Execution.get_training_log_entry_for_user(entry_id, user_id) end
      )

    case entry do
      %{status: "logged"} = entry -> CompleteWorkout.process_training_log_completion(entry)
      %{status: "voided"} -> {:cancel, :training_log_entry_voided}
      _missing -> {:cancel, :training_log_entry_not_found}
    end
  end

  def perform(%Oban.Job{args: %{"execution_id" => execution_id}}) do
    execution =
      ExecutionStore.with_authorization_context(%{}, fn ->
        Execution.get_execution(execution_id)
      end)

    case execution do
      %{completed_at_utc: %DateTime{}} = execution ->
        CompleteWorkout.process_completion(execution)

      nil ->
        {:cancel, :execution_not_found}

      _execution ->
        {:error, :execution_not_completed}
    end
  end
end
