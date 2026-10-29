defmodule Palee.Infrastructure.Execution.EctoExecutionStore do
  @behaviour Palee.Execution.Ports.ExecutionStore

  import Ecto.Query

  alias Ecto.Multi
  alias Palee.Execution.{ExecutionPlanSet, ProgressOperation, WorkoutExecution}
  alias Palee.Execution.Domain.PlanActuals
  alias Palee.Infrastructure.Journal.{FeedBound, FeedScope}
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @impl true
  def start_execution(params) do
    params = put_current_user(params)

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
    {plan_sets, params} = Map.pop(params, :plan_sets, [])

    Repo.transaction(fn ->
      case WorkoutExecution
           |> scoped_to_user()
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
            {:ok, updated} ->
              updated
              |> normalize()
              |> Map.put(:plan_sets, json_sets(insert_plan_sets(Repo, updated, plan_sets)))

            {:error, %Ecto.Changeset{} = changeset} ->
              Repo.rollback(changeset)
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
    {plan_sets, params} = Map.pop(params, :plan_sets, [])

    Multi.new()
    |> Multi.run(:execution, fn repo, _changes ->
      case WorkoutExecution
           |> scoped_to_user()
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
    |> Multi.run(:plan_sets, fn repo, %{completed_execution: execution} ->
      {:ok, insert_plan_sets(repo, execution, plan_sets)}
    end)
    |> Oban.insert(:completion_job, job_changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{completed_execution: execution, plan_sets: sets}} ->
        {:ok, execution |> normalize() |> Map.put(:plan_sets, json_sets(sets))}

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
        case WorkoutExecution |> scoped_to_user() |> Repo.get(id) do
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
    case WorkoutExecution |> scoped_to_user() |> Repo.get(id) do
      nil ->
        nil

      %WorkoutExecution{} = execution ->
        execution |> normalize() |> Map.put(:plan_sets, json_sets(plan_sets_of(execution)))
    end
  end

  # ADR-270: the plan actuals of completed executions, in run order, for
  # consumers (training volume, PRs, planned-vs-done). Reads what the
  # session may see of the parent executions.
  @impl true
  def list_plan_sets(execution_ids) when is_list(execution_ids) do
    case Enum.filter(execution_ids, &is_binary/1) do
      [] ->
        []

      ids ->
        ExecutionPlanSet
        |> where([set], set.execution_id in ^ids)
        |> order_by([set], asc: set.execution_id, asc: set.inserted_at, asc: set.id)
        |> Repo.all()
        |> Enum.map(&plan_set_map/1)
    end
  end

  # The execution read model is JSON as is: decimals become numbers there;
  # `list_plan_sets/1` keeps them `Decimal` for consumers.
  defp json_sets(sets), do: Enum.map(sets, &PlanActuals.to_json/1)

  defp plan_sets_of(%WorkoutExecution{completed_at_utc: nil}), do: []

  defp plan_sets_of(%WorkoutExecution{id: id}),
    do: id |> List.wrap() |> list_plan_sets() |> Enum.map(&Map.delete(&1, :execution_id))

  defp plan_set_map(%ExecutionPlanSet{} = set),
    do: set |> ExecutionPlanSet.to_map() |> Map.put(:execution_id, set.execution_id)

  # Inserted in order, so `inserted_at` + id keep the run order the client sent.
  defp insert_plan_sets(_repo, _execution, []), do: []

  defp insert_plan_sets(repo, %WorkoutExecution{} = execution, records) do
    now = DateTime.utc_now()

    rows =
      records
      |> Enum.with_index()
      |> Enum.map(fn {record, index} ->
        record
        |> Map.take(ExecutionPlanSet.fields())
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          execution_id: execution.id,
          user_id: execution.user_id,
          organization_id: execution.organization_id,
          master_workout_id: execution.master_workout_id,
          inserted_at: DateTime.add(now, index, :microsecond)
        })
      end)

    rows
    |> Enum.chunk_every(1_000)
    |> Enum.each(&repo.insert_all(ExecutionPlanSet, &1))

    Enum.map(rows, fn row ->
      struct(ExecutionPlanSet, row) |> ExecutionPlanSet.to_map()
    end)
  end

  @impl true
  def list_executions_for_user(user_id) do
    WorkoutExecution
    |> scoped_to_user()
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.started_at_utc)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  # ADR-123 abandonment sweep: started, never-completed executions of the
  # session's tenant whose start falls in [started_after, started_before).
  # Fails closed (no rows) without a tenant in the session.
  @impl true
  def list_stale_executions(started_before, started_after, limit) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        WorkoutExecution
        |> where([e], e.organization_id == ^organization_id)
        |> where([e], is_nil(e.completed_at_utc) and e.status in [:active, :paused])
        |> where([e], e.started_at_utc < ^started_before and e.started_at_utc >= ^started_after)
        |> order_by([e], asc: e.started_at_utc)
        |> limit(^limit)
        |> Repo.all()
        |> Enum.map(&normalize/1)

      _missing_scope ->
        []
    end
  end

  # Progress operations are owner-scoped rows, so callers read this inside the
  # execution owner's session.
  @impl true
  def last_progress_at(execution_id) do
    ProgressOperation
    |> where([operation], operation.execution_id == ^execution_id)
    |> select([operation], max(operation.inserted_at))
    |> Repo.one()
    |> case do
      nil -> nil
      %NaiveDateTime{} = at -> DateTime.from_naive!(at, "Etc/UTC")
      %DateTime{} = at -> at
    end
  end

  @impl true
  def list_executions_for_coaching(user_id) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        WorkoutExecution
        |> where(
          [execution],
          execution.user_id == ^user_id and execution.organization_id == ^organization_id
        )
        # ADR-139 §6: a coach reads a member's executions only on a rung
        # that reaches the coach.
        |> where(
          [execution],
          fragment("palee_journal_visibility_reaches_coach(?)", execution.journal_visibility)
        )
        |> order_by([execution], desc: execution.started_at_utc)
        |> Repo.all()
        |> Enum.map(&normalize/1)

      _missing_scope ->
        []
    end
  end

  @impl true
  # ADR-186 §7: `user_ids` (the people of a branch filter) narrows the report.
  def list_executions_for_kpis(%DateTime{} = since, user_ids) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        WorkoutExecution
        |> where(
          [execution],
          execution.organization_id == ^organization_id and execution.started_at_utc >= ^since
        )
        |> then(fn query ->
          if is_list(user_ids),
            do: where(query, [execution], execution.user_id in ^user_ids),
            else: query
        end)
        |> select([execution], %{
          status: execution.status,
          completed_at_utc: execution.completed_at_utc,
          current_segment_index: execution.current_segment_index,
          section_scores: execution.section_scores,
          kpi_counters: execution.kpi_counters,
          duration_adjustments: execution.duration_adjustments,
          total_elapsed_ms: execution.total_elapsed_ms,
          source: execution.source,
          started_at_utc: execution.started_at_utc
        })
        |> Repo.all()
        |> Enum.map(fn row ->
          if row.completed_at_utc, do: %{row | status: :completed}, else: row
        end)

      _missing_scope ->
        []
    end
  end

  # Journal feed (ADR-139 §9): completed executions, newest first, after the
  # page bound, for the owner or for a coach of one gym.
  @impl true
  def list_execution_items(user_id, bound, limit, scope) do
    WorkoutExecution
    |> where([e], not is_nil(e.completed_at_utc))
    |> FeedScope.apply(user_id, scope,
      kind: "execution",
      at: :completed_at_utc,
      text_exists: :comments
    )
    |> FeedBound.apply(:completed_at_utc, bound)
    |> order_by([e], desc: e.completed_at_utc, desc: e.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def list_completed_for_workout(organization_id, workout_id, from, to) do
    WorkoutExecution
    |> where(
      [e],
      e.organization_id == ^organization_id and e.master_workout_id == ^workout_id and
        not is_nil(e.completed_at_utc) and e.completed_at_utc >= ^from and
        e.completed_at_utc < ^to
    )
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def set_execution_visibility(id, user_id, rung) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %WorkoutExecution{} = execution <-
           Repo.get_by(WorkoutExecution, id: id, user_id: user_id) do
      execution
      |> WorkoutExecution.visibility_changeset(rung)
      |> Repo.update()
      |> case do
        {:ok, updated} -> {:ok, normalize(updated)}
        error -> error
      end
    else
      _missing -> {:error, :not_found}
    end
  end

  @impl true
  def move_executions(user_id, from, to) do
    {count, _rows} =
      WorkoutExecution
      |> where([e], e.user_id == ^user_id and not is_nil(e.organization_id))
      |> where([e], e.journal_visibility in ^from)
      |> Repo.update_all(set: [journal_visibility: to])

    count
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
      organization_id: execution.organization_id,
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
      lock_version: execution.lock_version,
      kpi_counters: execution.kpi_counters || %{},
      duration_adjustments: execution.duration_adjustments || %{},
      journal_visibility: execution.journal_visibility,
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

  defp scoped_to_user(query) do
    cond do
      RepoContext.current_setting("app.admin_mode") == "true" ->
        query

      RepoContext.current_setting("app.execution_authorization_check") == "true" ->
        query

      user_id = RepoContext.current_setting("app.user_id") ->
        where(query, [row], row.user_id == ^user_id)

      true ->
        where(query, [row], false)
    end
  end

  defp put_current_user(params) do
    case RepoContext.current_setting("app.user_id") do
      user_id when is_binary(user_id) ->
        if Enum.any?(Map.keys(params), &is_binary/1),
          do: Map.put(params, "user_id", user_id),
          else: Map.put(params, :user_id, user_id)

      _no_user_context ->
        params
    end
  end
end
