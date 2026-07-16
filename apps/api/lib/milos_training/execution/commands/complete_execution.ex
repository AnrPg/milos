defmodule MilosTraining.Execution.Commands.CompleteExecution do
  alias MilosTraining.Execution.Domain.{ProgressSnapshotter, ProgressValidator}
  alias MilosTraining.Execution.ExecutionStore

  def call(execution_id, user_id, params, opts \\ []) do
    case ExecutionStore.get_execution(execution_id) do
      nil ->
        {:error, :not_found}

      %{user_id: ^user_id} = execution ->
        with {:ok, checked_exercise_ids} <- normalize_checked_exercise_ids(params, execution),
             {:ok, total_elapsed_ms} <- normalize_total_elapsed_ms(params, execution),
             {:ok, section_elapsed_ms} <-
               normalize_int_map(params, execution, :section_elapsed_ms),
             {:ok, segment_cycle_counts} <-
               normalize_int_map(params, execution, :segment_cycle_counts),
             segments <- Map.get(params, :segments, Map.get(params, "segments", [])),
             manual_scores <- params[:section_scores] || params["section_scores"] || [],
             current_segment_index <-
               params[:current_segment_index] || params["current_segment_index"] ||
                 execution.current_segment_index || 0,
             :ok <-
               ProgressValidator.validate(
                 %{
                   checked_exercise_ids: checked_exercise_ids,
                   current_segment_index: current_segment_index,
                   paused_elapsed_ms: execution.paused_elapsed_ms || 0,
                   total_elapsed_ms: total_elapsed_ms,
                   section_elapsed_ms: section_elapsed_ms,
                   segment_cycle_counts: segment_cycle_counts
                 },
                 segments,
                 execution
               ),
             :ok <- validate_manual_scores(params, segments, manual_scores) do
          section_scores =
            segments
            |> ProgressSnapshotter.final_snapshots(
              %{
                checked_exercise_ids: checked_exercise_ids,
                section_elapsed_ms: section_elapsed_ms,
                segment_cycle_counts: segment_cycle_counts
              },
              manual_scores
            )

          completed_params = %{
            completed_at_utc: DateTime.utc_now(),
            completed_at_tz: params[:timezone] || params["timezone"] || "UTC",
            status: :completed,
            current_segment_index: current_segment_index,
            segment_started_at_utc: nil,
            paused_elapsed_ms: execution.paused_elapsed_ms || 0,
            resume_countdown_ends_at_utc: nil,
            total_elapsed_ms: total_elapsed_ms,
            section_elapsed_ms: section_elapsed_ms,
            segment_cycle_counts: segment_cycle_counts,
            checked_exercise_ids: checked_exercise_ids,
            section_scores: section_scores,
            exercise_notes: execution.exercise_notes || []
          }

          persist_completion(execution_id, completed_params, opts)
        end

      %{} ->
        {:error, :forbidden}
    end
  end

  defp persist_completion(execution_id, completed_params, opts) do
    case Keyword.get(opts, :completion_job) do
      %Ecto.Changeset{} = job_changeset ->
        ExecutionStore.complete_execution_with_job(
          execution_id,
          completed_params,
          job_changeset
        )

      nil ->
        ExecutionStore.complete_execution(execution_id, completed_params)
    end
  end

  defp validate_manual_scores(params, segments, manual_scores) do
    if Map.has_key?(params, :segments) or Map.has_key?(params, "segments") do
      ProgressSnapshotter.validate_manual_scores(segments, manual_scores)
    else
      :ok
    end
  end

  defp normalize_checked_exercise_ids(params, execution) do
    checked_exercise_ids =
      params[:checked_exercise_ids] ||
        params["checked_exercise_ids"] ||
        execution.checked_exercise_ids ||
        []

    if is_list(checked_exercise_ids) and Enum.all?(checked_exercise_ids, &is_binary/1) do
      {:ok, Enum.uniq(checked_exercise_ids)}
    else
      {:error, :bad_request}
    end
  end

  defp normalize_total_elapsed_ms(params, execution) do
    case params[:total_elapsed_ms] || params["total_elapsed_ms"] || execution.total_elapsed_ms ||
           0 do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _other -> {:error, :bad_request}
    end
  end

  defp normalize_int_map(params, execution, field) do
    candidate =
      params[field] ||
        params[Atom.to_string(field)] ||
        execution[field] ||
        execution[Atom.to_string(field)] ||
        %{}

    if is_map(candidate) do
      candidate
      |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
        normalized_key = to_string(key)

        case value do
          int when is_integer(int) and int >= 0 ->
            {:cont, {:ok, Map.put(acc, normalized_key, int)}}

          _other ->
            {:halt, {:error, :bad_request}}
        end
      end)
    else
      {:error, :bad_request}
    end
  end
end
