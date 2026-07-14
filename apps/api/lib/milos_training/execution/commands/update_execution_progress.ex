defmodule MilosTraining.Execution.Commands.UpdateExecutionProgress do
  alias MilosTraining.Execution.Domain.ProgressSnapshotter
  alias MilosTraining.Execution.ExecutionStore

  @allowed_statuses ["active", "paused"]

  def call(execution_id, user_id, params) do
    with {:ok, execution} <- fetch_owned_execution(execution_id, user_id),
         :ok <- ensure_mutable(execution),
         {:ok, progress_params} <- normalize_progress_params(params, execution) do
      ExecutionStore.update_execution(execution.id, progress_params)
    end
  end

  defp fetch_owned_execution(execution_id, user_id) do
    case ExecutionStore.get_execution(execution_id) do
      nil -> {:error, :not_found}
      %{user_id: ^user_id} = execution -> {:ok, execution}
      %{} -> {:error, :forbidden}
    end
  end

  defp ensure_mutable(%{completed_at_utc: nil, status: status}) when status != "completed",
    do: :ok

  defp ensure_mutable(_execution), do: {:error, :already_completed}

  defp normalize_progress_params(params, execution) do
    with {:ok, checked_exercise_ids} <- normalize_checked_exercise_ids(params),
         {:ok, status} <- normalize_status(params, execution),
         {:ok, current_segment_index} <- normalize_current_segment_index(params, execution),
         {:ok, paused_elapsed_ms} <- normalize_paused_elapsed_ms(params, execution),
         {:ok, total_elapsed_ms} <- normalize_total_elapsed_ms(params, execution),
         {:ok, section_elapsed_ms} <- normalize_int_map(params, execution, :section_elapsed_ms),
         {:ok, segment_cycle_counts} <-
           normalize_int_map(params, execution, :segment_cycle_counts),
         {:ok, segment_started_at_utc} <-
           normalize_segment_started_at_utc(params, execution, status),
         {:ok, resume_countdown_ends_at_utc} <-
           normalize_resume_countdown_ends_at_utc(params, execution, status) do
      section_scores =
        params
        |> Map.get(:segments, Map.get(params, "segments", []))
        |> ProgressSnapshotter.progress_snapshots(%{
          checked_exercise_ids: checked_exercise_ids,
          section_elapsed_ms: section_elapsed_ms,
          segment_cycle_counts: segment_cycle_counts
        })

      {:ok,
       %{
         checked_exercise_ids: checked_exercise_ids,
         status: String.to_existing_atom(status),
         current_segment_index: current_segment_index,
         paused_elapsed_ms: paused_elapsed_ms,
         total_elapsed_ms: total_elapsed_ms,
         section_elapsed_ms: section_elapsed_ms,
         segment_cycle_counts: segment_cycle_counts,
         segment_started_at_utc: segment_started_at_utc,
         resume_countdown_ends_at_utc: resume_countdown_ends_at_utc,
         section_scores: section_scores
       }}
    end
  end

  defp normalize_checked_exercise_ids(params) do
    checked_exercise_ids = params[:checked_exercise_ids] || params["checked_exercise_ids"] || []

    if is_list(checked_exercise_ids) and Enum.all?(checked_exercise_ids, &is_binary/1) do
      {:ok, Enum.uniq(checked_exercise_ids)}
    else
      {:error, :bad_request}
    end
  end

  defp normalize_status(params, execution) do
    status =
      params[:status] || params["status"] || execution.status || "active"

    if status in @allowed_statuses, do: {:ok, status}, else: {:error, :bad_request}
  end

  defp normalize_current_segment_index(params, execution) do
    case params[:current_segment_index] || params["current_segment_index"] ||
           execution.current_segment_index || 0 do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _other -> {:error, :bad_request}
    end
  end

  defp normalize_paused_elapsed_ms(params, execution) do
    case params[:paused_elapsed_ms] || params["paused_elapsed_ms"] || execution.paused_elapsed_ms ||
           0 do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _other -> {:error, :bad_request}
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

  defp normalize_segment_started_at_utc(params, execution, "active") do
    candidate =
      params[:segment_started_at_utc] ||
        params["segment_started_at_utc"] ||
        execution.segment_started_at_utc

    parse_datetime(candidate)
  end

  defp normalize_segment_started_at_utc(_params, _execution, "paused"), do: {:ok, nil}

  defp normalize_resume_countdown_ends_at_utc(params, _execution, "active") do
    case params[:resume_countdown_ends_at_utc] || params["resume_countdown_ends_at_utc"] do
      nil -> {:ok, nil}
      _value -> {:error, :bad_request}
    end
  end

  defp normalize_resume_countdown_ends_at_utc(params, execution, "paused") do
    candidate =
      params[:resume_countdown_ends_at_utc] ||
        params["resume_countdown_ends_at_utc"] ||
        execution.resume_countdown_ends_at_utc

    parse_optional_datetime(candidate)
  end

  defp parse_optional_datetime(nil), do: {:ok, nil}

  defp parse_optional_datetime(value) do
    case parse_datetime(value) do
      {:ok, %DateTime{} = datetime} -> {:ok, datetime}
      error -> error
    end
  end

  defp parse_datetime(%DateTime{} = datetime), do: {:ok, datetime}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _other -> {:error, :bad_request}
    end
  end

  defp parse_datetime(_value), do: {:error, :bad_request}
end
