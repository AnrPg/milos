defmodule MilosTraining.Application.LogTrainingEntry do
  @moduledoc """
  Logs a workout performed outside a timer-backed execution (ADR-108).

  Orchestrates source authorization (Scheduling / Workouts public APIs),
  the no-double-counting check against the user's executions, persistence in
  the Execution context, and the durable completion handoff: the same
  `ProcessWorkoutCompletionJob` used for executions is enqueued in the insert
  transaction, flagged with `source: "training_log"`.

  Returns `{:ok, entry, :created | :replayed}`; a replayed idempotency key
  never re-enqueues projection work.
  """

  alias MilosTraining.Application.{
    AuthorizeTrainingLogSource,
    CompleteWorkout,
    TrackAnalyticsEvent
  }

  alias MilosTraining.Execution
  alias MilosTraining.Workers.ProcessWorkoutCompletionJob

  def call(%{organization_id: _} = context, %{id: user_id}, params) when is_map(params) do
    now = DateTime.utc_now()

    Execution.with_training_log_context(context, fn ->
      # ADR-110: an offline replay of an already accepted submission returns
      # the original entry before source authorization is re-evaluated, so a
      # source that has since closed (class over, assignment rejected, entry
      # already logged) cannot turn an acknowledged write into a failure.
      case Execution.find_training_log_replay(user_id, params) do
        {:ok, entry} -> {:ok, entry, :replayed}
        {:error, reason} -> {:error, reason}
        :none -> log_new(context, user_id, params, now)
      end
    end)
  end

  def call(_context, _actor, _params), do: {:error, :organization_context_required}

  defp log_new(context, user_id, params, now) do
    with {:ok, source} <-
           AuthorizeTrainingLogSource.call(
             context,
             user_id,
             params["source_type"] || params[:source_type],
             params["source_reference_id"] || params[:source_reference_id],
             now
           ),
         {:ok, entry, outcome} <-
           Execution.log_training_entry(user_id, Map.delete(source, :workout), params,
             now: now,
             allowed_section_ids: allowed_section_ids(source),
             completed_executions: Execution.list_executions_for_user(user_id),
             job_builder: job_builder()
           ),
         :ok <- process_inline_if_needed(entry, outcome) do
      TrackAnalyticsEvent.call("training_log_entry_logged", context, entry, %{
        metadata: %{section_score_count: length(entry.section_scores || [])}
      })

      {:ok, entry, outcome}
    end
  end

  defp allowed_section_ids(source) do
    source
    |> Map.get(:workout)
    |> Execution.training_log_scoreable_sections()
    |> Enum.map(& &1.id)
  end

  defp job_builder do
    if Application.get_env(:milos_training, :start_oban, true) do
      &ProcessWorkoutCompletionJob.training_log_job/1
    end
  end

  defp process_inline_if_needed(entry, :created) do
    if Application.get_env(:milos_training, :start_oban, true),
      do: :ok,
      else: CompleteWorkout.process_training_log_completion(entry)
  end

  defp process_inline_if_needed(_entry, :replayed), do: :ok
end
