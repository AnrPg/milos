defmodule MilosTraining.Execution.Commands.LogTrainingEntry do
  @moduledoc """
  Persists a standalone training-log entry for an already-authorized source.

  `source` is server-derived by the application layer (never client input):
  `%{source_type, source_reference_id, master_workout_id, booking_id, title,
  workout_type}`. Replaying the same `idempotency_key` returns the original
  entry instead of creating a duplicate.

  Options:
    * `:now` - reference time (required)
    * `:allowed_section_ids` - scoreable section ids of the source workout
    * `:completed_executions` - the user's executions, used to refuse logging a
      source that a completed execution already counted
    * `:job_builder` - `fn entry -> Oban.Job changeset end` enqueued in the
      same transaction as the insert (durable completion handoff, ADR-029)
  """

  alias MilosTraining.Execution.Domain.TrainingLogPolicy
  alias MilosTraining.Execution.TrainingLogStore

  def call(user_id, source, params, opts) do
    with {:ok, key} <- idempotency_key(params) do
      case TrainingLogStore.get_entry_by_idempotency_key(user_id, key) do
        nil ->
          create(source, key, params, opts)

        existing ->
          case TrainingLogPolicy.replay_decision(existing, source) do
            :replay -> {:ok, existing, :replayed}
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  defp create(source, key, params, opts) do
    freeform? = source.source_type == "freeform"

    with {:ok, details} <-
           TrainingLogPolicy.normalize_details(params,
             now: Keyword.fetch!(opts, :now),
             structured?: is_binary(source[:master_workout_id]),
             allowed_section_ids: Keyword.get(opts, :allowed_section_ids, []),
             freeform?: freeform?
           ),
         :ok <-
           ensure_not_double_counted(
             source,
             Keyword.get(opts, :completed_executions, []),
             details.performed_at_utc
           ) do
      attrs =
        details
        |> Map.put_new(:title, source[:title])
        |> Map.merge(%{
          source_type: source.source_type,
          source_reference_id: source[:source_reference_id],
          master_workout_id: source[:master_workout_id],
          booking_id: source[:booking_id],
          workout_type: source[:workout_type],
          idempotency_key: key,
          status: "logged",
          journal_visibility: Keyword.get(opts, :journal_visibility, "coach_can_view")
        })

      case TrainingLogStore.create_entry(attrs, Keyword.get(opts, :job_builder)) do
        {:ok, entry} -> {:ok, entry, :created}
        error -> error
      end
    end
  end

  defp ensure_not_double_counted(source, executions, performed_at) do
    if TrainingLogPolicy.double_counted?(source, executions, performed_at),
      do: {:error, :training_log_already_counted},
      else: :ok
  end

  defp idempotency_key(params) do
    case params["idempotency_key"] || params[:idempotency_key] do
      key when is_binary(key) and byte_size(key) >= 8 and byte_size(key) <= 128 ->
        {:ok, key}

      _invalid ->
        {:error, [idempotency_key: "must be between 8 and 128 characters"]}
    end
  end
end
