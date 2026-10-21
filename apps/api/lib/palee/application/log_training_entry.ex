defmodule Palee.Application.LogTrainingEntry do
  @moduledoc """
  Logs a workout performed outside a timer-backed execution (ADR-118).

  Orchestrates source authorization (Scheduling / Workouts public APIs),
  the no-double-counting check against the user's executions, persistence in
  the Execution context, and the durable completion handoff: the same
  `ProcessWorkoutCompletionJob` used for executions is enqueued in the insert
  transaction, flagged with `source: "training_log"`.

  Returns `{:ok, entry, :created | :replayed}`; a replayed idempotency key
  never re-enqueues projection work.
  """

  alias Palee.Application.{
    AuthorizeTrainingLogSource,
    CompleteWorkout,
    InjuryWarningEvaluation,
    JournalComments,
    TrackAnalyticsEvent
  }

  alias Palee.{Execution, Journal, Workouts}
  alias Palee.Workers.ProcessWorkoutCompletionJob

  def call(%{organization_id: _} = context, %{id: user_id}, params) when is_map(params) do
    now = DateTime.utc_now()

    Execution.with_training_log_context(context, fn ->
      # ADR-120: an offline replay of an already accepted submission returns
      # the original entry before source authorization is re-evaluated, so a
      # source that has since closed (class over, assignment rejected, entry
      # already logged) cannot turn an acknowledged write into a failure.
      case Execution.find_training_log_replay(user_id, params) do
        {:ok, entry} -> {:ok, entry, :replayed}
        {:error, reason} -> {:error, reason}
        :none -> log_new(context, user_id, params, now)
      end
      |> with_comments(context, params, now)
    end)
  end

  def call(_context, _actor, _params), do: {:error, :organization_context_required}

  # ADR-140 §1: comments written in the log form travel with the entry so
  # the offline outbox replays them together. They are upserted by their own
  # ids, so a replay converges too.
  defp with_comments({:ok, entry, outcome}, context, params, now) do
    comments = params["comments"] || params[:comments]

    with {:ok, _saved} <-
           JournalComments.save_for_entry(context, "training_log", entry.id, comments, now),
         do: {:ok, JournalComments.attach(entry, "training_log"), outcome}
  end

  defp with_comments(error, _context, _params, _now), do: error

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
             journal_visibility: Journal.initial_visibility(user_id, "training_log", true),
             job_builder: job_builder()
           ),
         :ok <- process_inline_if_needed(entry, outcome) do
      TrackAnalyticsEvent.call("training_log_entry_logged", context, entry, %{
        metadata:
          %{section_score_count: length(entry.section_scores || [])}
          |> Map.merge(injury_facts(context, user_id, source, entry))
      })

      {:ok, entry, outcome}
    end
  end

  # TD-088: the same organization-provenance segmentation facts as execution
  # completion, against the logged workout at the logged scale. A freeform
  # entry has no workout: only `had_active_injury` is meaningful there.
  defp injury_facts(%{organization_id: organization_id}, user_id, source, entry) do
    workout =
      case {Map.get(source, :workout), entry.scale_level_slug} do
        {nil, _scale} -> nil
        {workout, scale} when scale in [nil, ""] -> workout
        {workout, scale} -> Workouts.materialize_for_scale(workout, scale)
      end

    InjuryWarningEvaluation.completion_facts(
      %{organization_id: organization_id, user_id: user_id},
      workout
    )
  end

  defp allowed_section_ids(source) do
    source
    |> Map.get(:workout)
    |> Execution.training_log_scoreable_sections()
    |> Enum.map(& &1.id)
  end

  defp job_builder do
    if Application.get_env(:palee, :start_oban, true) do
      &ProcessWorkoutCompletionJob.training_log_job/1
    end
  end

  defp process_inline_if_needed(entry, :created) do
    if Application.get_env(:palee, :start_oban, true),
      do: :ok,
      else: CompleteWorkout.process_training_log_completion(entry)
  end

  defp process_inline_if_needed(_entry, :replayed), do: :ok
end
