defmodule MilosTraining.Infrastructure.Execution.EctoExecutionStore do
  @behaviour MilosTraining.Execution.Ports.ExecutionStore

  import Ecto.Query

  alias Ecto.Multi
  alias MilosTraining.Execution.{ProgressOperation, WorkoutExecution}
  alias MilosTraining.Repo

  @impl true
  def start_execution(params) do
    %WorkoutExecution{}
    |> WorkoutExecution.start_changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, execution} -> {:ok, normalize(execution)}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @impl true
  def complete_execution(id, params) do
    Repo.transaction(fn ->
      case WorkoutExecution
           |> where([e], e.id == ^id)
           |> lock("FOR UPDATE")
           |> Repo.one() do
        nil ->
          Repo.rollback(:not_found)

        %WorkoutExecution{completed_at_utc: completed_at} when not is_nil(completed_at) ->
          Repo.rollback(:already_completed)

        %WorkoutExecution{} = execution ->
          execution
          |> WorkoutExecution.complete_changeset(params)
          |> Repo.update()
          |> case do
            {:ok, updated} -> normalize(updated)
            {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
          end
      end
    end)
    |> case do
      {:ok, execution} -> {:ok, execution}
      {:error, :not_found} -> {:error, :not_found}
      {:error, :already_completed} -> {:error, :already_completed}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @impl true
  def complete_execution_with_job(id, params, job_changeset) do
    Multi.new()
    |> Multi.run(:execution, fn repo, _changes ->
      case WorkoutExecution
           |> where([execution], execution.id == ^id)
           |> lock("FOR UPDATE")
           |> repo.one() do
        nil ->
          {:error, :not_found}

        %WorkoutExecution{completed_at_utc: completed_at} when not is_nil(completed_at) ->
          {:error, :already_completed}

        %WorkoutExecution{} = execution ->
          {:ok, execution}
      end
    end)
    |> Multi.update(:completed_execution, fn %{execution: execution} ->
      WorkoutExecution.complete_changeset(execution, params)
    end)
    |> Oban.insert(:completion_job, job_changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{completed_execution: execution}} ->
        {:ok, normalize(execution)}

      {:error, :execution, reason, _changes} ->
        {:error, reason}

      {:error, :completed_execution, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, :completion_job, _reason, _changes} ->
        {:error, :completion_processing_unavailable}
    end
  end

  @impl true
  def update_execution(id, params) do
    result =
      Repo.transaction(fn ->
        case Repo.get(WorkoutExecution, id) do
          nil -> Repo.rollback(:not_found)
          execution -> persist_versioned_update(execution, params)
        end
      end)

    case result do
      {:ok, execution} -> {:ok, execution}
      {:error, :stale_execution} -> recover_idempotent_retry(id, params)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def progress_operation_applied?(execution_id, user_id, operation_id) do
    ProgressOperation
    |> where(
      [operation],
      operation.execution_id == ^execution_id and operation.user_id == ^user_id and
        operation.operation_id == ^operation_id
    )
    |> Repo.exists?()
  end

  @impl true
  def get_execution(id) do
    case Repo.get(WorkoutExecution, id) do
      nil -> nil
      %WorkoutExecution{} = execution -> normalize(execution)
    end
  end

  @impl true
  def list_executions_for_user(user_id) do
    WorkoutExecution
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.started_at_utc)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  defp normalize(%WorkoutExecution{} = execution) do
    normalized_status =
      cond do
        execution.completed_at_utc -> "completed"
        is_nil(execution.status) -> "active"
        true -> to_string(execution.status)
      end

    segment_started_at_utc =
      cond do
        execution.segment_started_at_utc -> execution.segment_started_at_utc
        normalized_status == "active" -> execution.started_at_utc
        true -> nil
      end

    %{
      id: execution.id,
      user_id: execution.user_id,
      master_workout_id: execution.master_workout_id,
      scale_level_slug: execution.scale_level_slug,
      source: to_string(execution.source),
      source_reference_id: execution.source_reference_id,
      status: normalized_status,
      started_at_utc: execution.started_at_utc,
      started_at_tz: execution.started_at_tz,
      completed_at_utc: execution.completed_at_utc,
      completed_at_tz: execution.completed_at_tz,
      current_segment_index: execution.current_segment_index || 0,
      segment_started_at_utc: segment_started_at_utc,
      paused_elapsed_ms: execution.paused_elapsed_ms || 0,
      resume_countdown_ends_at_utc: execution.resume_countdown_ends_at_utc,
      total_elapsed_ms: execution.total_elapsed_ms || 0,
      section_elapsed_ms: execution.section_elapsed_ms || %{},
      segment_cycle_counts: execution.segment_cycle_counts || %{},
      checked_exercise_ids: execution.checked_exercise_ids || [],
      section_scores: execution.section_scores || [],
      exercise_notes: execution.exercise_notes || [],
      lock_version: execution.lock_version,
      inserted_at: execution.inserted_at
    }
  end

  defp persist_versioned_update(execution, params) do
    expected_version =
      params[:expected_version] || params["expected_version"] || execution.lock_version

    if execution.lock_version == expected_version do
      case execution
           |> WorkoutExecution.progress_changeset(params)
           |> Repo.update(stale_error_field: :lock_version) do
        {:ok, updated} ->
          persist_progress_operation(updated, params, expected_version)
          normalize(updated)

        {:error, %{errors: [lock_version: _error]}} ->
          Repo.rollback(:stale_execution)

        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback(changeset)
      end
    else
      Repo.rollback(:stale_execution)
    end
  end

  defp persist_progress_operation(updated, params, expected_version) do
    case params[:operation_id] || params["operation_id"] do
      nil ->
        :ok

      operation_id ->
        %ProgressOperation{}
        |> ProgressOperation.changeset(%{
          operation_id: operation_id,
          execution_id: updated.id,
          user_id: updated.user_id,
          base_version: expected_version,
          result_version: updated.lock_version
        })
        |> Repo.insert!()
    end
  end

  defp recover_idempotent_retry(id, params) do
    user_id = params[:user_id] || params["user_id"]
    operation_id = params[:operation_id] || params["operation_id"]

    if user_id && operation_id && progress_operation_applied?(id, user_id, operation_id) do
      {:ok, get_execution(id)}
    else
      {:error, :stale_execution}
    end
  end
end
